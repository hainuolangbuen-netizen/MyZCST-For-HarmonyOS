import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardData } from './CardData';
import { CardStore } from './CardStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-water';

interface ScrapedItem {
  label: string;
  balance: number;
  unit: string;
  used: number;
}

/**
 * 「智能水电」页面 → 桌面水电卡片 的桥。
 *
 * 完美校园 SWAEServlet 在部分网络/账号上会被风控（405/未绑定），所以再加一条
 * **应用内页面取数**的兜底：打开学校「智能水电」轻应用后，注入脚本读取页面
 * 上已经渲染出来的余额，调用 `window.__myzcstWater.save(...)` 写进 CardStore。
 *
 * 这条路径不猜接口、不抓 Cookie，只复用用户眼前已经看到的数据。
 */
export class WaterBridge {
  private context: common.Context | undefined = undefined;
  private last: string = '';

  attach(context: common.Context): void {
    this.context = context;
  }

  /** JS 侧调用：payload = {room, items:[{label,balance,unit,used}]} */
  save(payload: string): void {
    if (this.context === undefined || payload.length === 0 || payload === this.last) {
      return;
    }
    try {
      const root: Record<string, Object> = JSON.parse(payload) as Record<string, Object>;
      const rawItems: Object | undefined = root['items'];
      if (!Array.isArray(rawItems)) {
        return;
      }
      const items: ScrapedItem[] = [];
      for (const raw of rawItems as Object[]) {
        if (raw === null || raw === undefined || typeof raw !== 'object') {
          continue;
        }
        const rec: Record<string, Object> = raw as Record<string, Object>;
        const label: string = WaterBridge.str(rec['label']);
        const balance: number = WaterBridge.num(rec['balance']);
        if (label.length === 0 || isNaN(balance)) {
          continue;
        }
        const unit: string = WaterBridge.str(rec['unit']).length > 0
          ? WaterBridge.str(rec['unit']) : (label.indexOf('电') >= 0 ? '度' : '吨');
        items.push({
          label: label,
          balance: balance,
          unit: unit,
          used: WaterBridge.num(rec['used'])
        });
      }
      if (items.length === 0) {
        return;
      }
      const lines: string[] = [];
      let hasNewPower: boolean = false;
      let hasNewWater: boolean = false;
      for (const item of items.slice(0, 8)) {
        const urgent: boolean = item.balance < (item.unit === '度' ? 20 : (item.unit === '吨' ? 1 : 10));
        const line: string = item.label + '|' + item.balance.toFixed(2) + '|' + item.unit + '|'
          + item.used.toFixed(2) + '|' + (urgent ? '1' : '0');
        lines.push(line);
        if (item.label.indexOf('电') >= 0) {
          hasNewPower = true;
        }
        if (item.label.indexOf('水') >= 0) {
          hasNewWater = true;
        }
      }
      const room: string = WaterBridge.str(root['room']);
      this.commit(room, lines, hasNewPower, hasNewWater);
      this.last = payload;
      hilog.info(DOMAIN, TAG, 'saved from page items=%{public}d', items.length);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'save failed');
    }
  }

  /**
   * 页面 XHR/fetch 响应兜底：有些 H5 的余额在 JSON 里、DOM 只有图表/画布，
   * 此时从响应原文里提取带「度/吨」的单位值或 water 字段。
   */
  saveRaw(source: string, text: string): void {
    if (this.context === undefined || text.length === 0 || text.length > 200000) {
      return;
    }
    const all: string = (source + ' ' + text).toLowerCase();
    if (all.indexOf('water') < 0 && all.indexOf('fee') < 0 && all.indexOf('吨') < 0
      && all.indexOf('度') < 0 && all.indexOf('kwh') < 0) {
      return;
    }
    const normalized: string = text.replace(/\\"/g, '"');
    const items: ScrapedItem[] = [];
    WaterBridge.addMatch(items, normalized,
      /(?:electricity|electric|elec)(?:Balance|Value|Num|Amount)?["']?\s*[:=]\s*["']?(-?\d+(?:\.\d+)?)/i,
      '剩余电量', '度');
    WaterBridge.addMatch(items, normalized,
      /(?:coldWater|cold_water|coldwater)(?:Balance|Value|Num|Amount)?["']?\s*[:=]\s*["']?(-?\d+(?:\.\d+)?)(?:\s*(?:吨|m³|m3|t))?/i,
      '剩余冷水', '吨');
    WaterBridge.addMatch(items, normalized,
      /(?:hotWater|hot_water|hotwater)(?:Balance|Value|Num|Amount)?["']?\s*[:=]\s*["']?(-?\d+(?:\.\d+)?)(?:\s*(?:吨|m³|m3|t))?/i,
      '剩余热水', '吨');
    WaterBridge.addMatch(items, normalized,
      /(?:冷水|冷水量|热水|热水量|剩余水量|水量)[^0-9-]{0,24}(-?\d+(?:\.\d+)?)\s*(?:吨|m³|m3)/i,
      '剩余水量', '吨');
    if (items.length === 0) {
      return;
    }
    const roomMatch: RegExpMatchArray | null = normalized.match(/[A-Za-z]\d+-\d+/);
    const room: string = roomMatch === null ? '' : roomMatch[0];
    const filled: ScrapedItem[] = [];
    const seen: string[] = [];
    for (const item of items) {
      if (seen.indexOf(item.label) >= 0) {
        continue;
      }
      seen.push(item.label);
      filled.push(item);
    }
    this.save(JSON.stringify({ room: room, items: filled }));
  }

  private static addMatch(items: ScrapedItem[], text: string, pattern: RegExp,
    label: string, unit: string): void {
    const m: RegExpMatchArray | null = text.match(pattern);
    if (m === null) {
      return;
    }
    const value: number = Number(m[1]);
    if (isNaN(value)) {
      return;
    }
    items.push({ label: label, balance: value, unit: unit, used: 0 });
  }

  private commit(room: string, lines: string[], hasNewPower: boolean, hasNewWater: boolean): void {
    if (this.context === undefined) {
      return;
    }
    const ctx: common.Context = this.context;
    const existing: string = CardStore.getSync(ctx, CardStore.KEY_FEE_LINES);
    const merged: string[] = [];
    for (const oldLine of existing.split('\n')) {
      if (oldLine.indexOf('|') <= 0) {
        continue;
      }
      const label: string = oldLine.split('|')[0];
      const unit: string = oldLine.split('|').length > 2 ? oldLine.split('|')[2] : '';
      if (unit === '元') {
        continue;
      }
      if (hasNewPower && label.indexOf('电') >= 0) {
        continue;
      }
      if (hasNewWater && label.indexOf('水') >= 0) {
        continue;
      }
      merged.push(oldLine);
    }
    for (const line of lines) {
      merged.push(line);
    }
    const oldRoom: string = CardStore.getSync(ctx, CardStore.KEY_FEE_ROOM);
    CardStore.put(ctx, CardStore.KEY_FEE_ROOM, room.length > 0 ? room : oldRoom).then(() => {
      CardStore.put(ctx, CardStore.KEY_FEE_LINES, merged.join('\n')).then(() => {
        const d = new Date();
        const p = (n: number): string => (n < 10 ? '0' + n : String(n));
        const stamp: string = p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' '
          + p(d.getHours()) + ':' + p(d.getMinutes()) + ' 已同步';
        CardStore.put(ctx, CardStore.KEY_FEE_UPDATED, stamp).then(() => {
          CardStore.put(ctx, CardStore.KEY_FEE_SYNC_AT, String(Date.now())).then(() => {
            CardData.updateAll(ctx);
          });
        });
      });
    });
  }

  private static str(value: Object | undefined): string {
    return typeof value === 'string' ? (value as string).trim() : '';
  }

  private static num(value: Object | undefined): number {
    if (typeof value === 'number') {
      return value as number;
    }
    if (typeof value === 'string') {
      const n: number = Number((value as string).trim());
      return isNaN(n) ? NaN : n;
    }
    return NaN;
  }
}

/** 注入到智能水电页面的脚本：每 1.5s 扫一次可见文本，找到余额就回调原生桥。 */
export const WATER_SCRAPE_JS: string = `
(function () {
  if (window.__myzcstWaterHooked) return;
  window.__myzcstWaterHooked = true;
  function sendRaw(url, text) {
    try {
      if (window.__myzcstWater && window.__myzcstWater.saveRaw) {
        window.__myzcstWater.saveRaw(String(url || ''), String(text || ''));
      }
    } catch (e) {}
  }
  try {
    var of = window.fetch;
    if (of) {
      window.fetch = function () {
        var args = arguments;
        var p = of.apply(this, args);
        try {
          p.then(function (r) {
            try {
              r.clone().text().then(function (t) { sendRaw(args[0], t); });
            } catch (e) {}
          });
        } catch (e) {}
        return p;
      };
    }
  } catch (e) {}
  try {
    var op = XMLHttpRequest.prototype.open;
    var os = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (m, u) {
      this.__myzcstUrl = u;
      return op.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function () {
      var xhr = this;
      xhr.addEventListener('load', function () {
        try { if (xhr.responseText) sendRaw(xhr.__myzcstUrl, xhr.responseText); } catch (e) {}
      });
      return os.apply(this, arguments);
    };
  } catch (e) {}
  function clean(s) { return String(s || '').replace(/\\s+/g, ' ').trim(); }
  function numberIn(s) {
    var m = String(s || '').match(/-?\\d+(?:\\.\\d+)?/);
    return m ? parseFloat(m[0]) : null;
  }
  function scan() {
    var body = document.body ? document.body.innerText : '';
    if (!body) return;
    var lines = body.split('\\n').map(clean).filter(function (x) { return x.length > 0; });
    var room = '';
    var rm = body.match(/[A-Za-z]\\d+-\\d+/);
    if (rm) room = rm[0];
    var defs = [
      ['剩余电量', /电费|电量|电表|剩余电/, '度', /(-?\\d+(?:\\.\\d+)?)\\s*(?:度|kWh)/i],
      ['剩余冷水', /冷水|冷水量/, '吨', /(-?\\d+(?:\\.\\d+)?)\\s*(?:吨|m³|m3)/i],
      ['剩余热水', /热水|热水量/, '吨', /(-?\\d+(?:\\.\\d+)?)\\s*(?:吨|m³|m3)/i],
      ['剩余水量', /剩余水量|水表|水量/, '吨', /(-?\\d+(?:\\.\\d+)?)\\s*(?:吨|m³|m3)/i]
    ];
    var out = [];
    var hasWater = false;
    for (var d = 0; d < defs.length; d++) {
      var label = defs[d][0], re = defs[d][1], unit = defs[d][2], unitRe = defs[d][3];
      if (label === '剩余水量' && hasWater) continue;
      for (var i = 0; i < lines.length; i++) {
        if (!re.test(lines[i])) continue;
        var v = matchUnit(lines[i], unitRe);
        if (v === null) {
          for (var k = 1; k <= 2 && i + k < lines.length; k++) {
            v = matchUnit(lines[i + k], unitRe);
            if (v !== null) break;
          }
        }
        if (v !== null) {
          out.push({ label: label, balance: v, unit: unit, used: 0 });
          if (label !== '剩余电量') hasWater = true;
          break;
        }
      }
    }
    if (out.length > 0 && window.__myzcstWater) {
      window.__myzcstWater.save(JSON.stringify({ room: room, items: out }));
    }
  }
  function matchUnit(s, re) {
    var m = String(s || '').match(re);
    return m ? parseFloat(m[1]) : null;
  }
  setInterval(scan, 1500);
  setTimeout(scan, 500);
})();
`;

export function isWaterUrl(url: string): boolean {
  const lower: string = url.toLowerCase();
  return lower.indexOf('watercharges') >= 0 || lower.indexOf('watermanage') >= 0
    || lower.indexOf('wanxiao') >= 0 || lower.indexOf('water') >= 0
    || lower.indexOf('electric') >= 0 || lower.indexOf('hydro') >= 0
    || lower.indexOf('/water') >= 0;
}
