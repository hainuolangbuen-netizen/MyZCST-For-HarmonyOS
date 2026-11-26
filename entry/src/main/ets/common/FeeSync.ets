import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardData } from './CardData';
import { CardStore } from './CardStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-fee';
const ENDPOINT: string = 'https://xqh5.17wanxiao.com/smartWaterAndElectricityService/SWAEServlet';
const REFERER: string = 'https://xqh5.17wanxiao.com/userwaterelecmini/index.html';
const CUSTOMERCODE: string = '1399';
const COMMAND: string = 'JBSWaterElecService';
const TTL_MS: number = 15 * 60 * 1000;
const UA: string = 'Mozilla/5.0 (Linux; Android 14; REP-AN00 Build/HONORREP-AN00; wv) '
  + 'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/127.0.6533.103 '
  + 'Mobile Safari/537.36 Wanxiao/5.8.6';

interface FeeItem {
  label: string;
  balance: number;
  unit: string;
  used: number;
  urgent: boolean;
}

/**
 * 宿舍水电数据同步。
 *
 * 数据源是「完美校园」的 SWAEServlet（学校宿舍水电实际接入方，见 ZCSTFeeApp
 * 的实测协议）：POST 学号即可查询，不需要登录态；学号必须保留前导零。
 * 响应是双层 JSON：外层 {code_, body}，body 本身是 JSON 字符串。
 *
 * 学号从「设置 → 卡片与同步 → 水电查询学号」读取。没有学号时卡片显示引导，
 * 不拿登录显示名（姓名）去冒充学号。
 */
export class FeeSync {
  private static syncing: boolean = false;
  private static lastAttempt: number = 0;

  static async ensureFresh(context: common.Context): Promise<void> {
    if (CardStore.getSync(context, CardStore.KEY_STUDENT_NO).trim().length === 0) {
      return;
    }
    const last: number = Number(CardStore.getSync(context, CardStore.KEY_FEE_SYNC_AT));
    if (!isNaN(last) && last > 0 && Date.now() - last < TTL_MS) {
      return;
    }
    if (Date.now() - FeeSync.lastAttempt < 60 * 1000) {
      return;
    }
    await FeeSync.sync(context);
  }

  static async sync(context: common.Context): Promise<boolean> {
    if (FeeSync.syncing) {
      return false;
    }
    FeeSync.syncing = true;
    FeeSync.lastAttempt = Date.now();
    try {
      return await FeeSync.doSync(context);
    } finally {
      FeeSync.syncing = false;
    }
  }

  private static async doSync(context: common.Context): Promise<boolean> {
    const studentNo: string = CardStore.getSync(context, CardStore.KEY_STUDENT_NO).trim();
    if (studentNo.length === 0) {
      hilog.info(DOMAIN, TAG, 'skip: no student_no');
      return false;
    }

    const param: string = '{"cmd":"getbindroom","account":"' + studentNo
      + '","timestamp":"' + FeeSync.stamp() + '"}';
    const body: string = 'param=' + encodeURIComponent(param)
      + '&customercode=' + CUSTOMERCODE
      + '&method=getbindroom&command=' + COMMAND;

    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(ENDPOINT, {
        method: http.RequestMethod.POST,
        header: {
          'Accept': '*/*',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer': REFERER,
          'User-Agent': UA,
          'X-Requested-With': 'com.newcapec.mobile.ncp'
        },
        extraData: body,
        connectTimeout: 15000,
        readTimeout: 20000
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        hilog.warn(DOMAIN, TAG, 'http %{public}d', response.responseCode);
        return false;
      }
      const text: string = response.result as string;
      const outer: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      if (FeeSync.str(outer['code_']) !== '0') {
        hilog.warn(DOMAIN, TAG, 'code_=%{public}s', FeeSync.str(outer['code_']));
        return false;
      }
      const bodyValue: Object | undefined = outer['body'];
      const innerText: string = typeof bodyValue === 'string'
        ? bodyValue as string : JSON.stringify(bodyValue);
      const inner: Record<string, Object> = JSON.parse(innerText) as Record<string, Object>;

      const rooms: Object[] = [];
      const roomList: Object | undefined = inner['roomlist'];
      if (Array.isArray(roomList)) {
        for (const room of roomList as Object[]) {
          rooms.push(room);
        }
      } else if (inner['roomfullname'] !== undefined) {
        rooms.push(inner);
      }

      let roomName: string = '';
      let feeLines: string[] = [];
      for (const obj of rooms) {
        if (obj === null || obj === undefined || typeof obj !== 'object') {
          continue;
        }
        const room: Record<string, Object> = obj as Record<string, Object>;
        const verify: string = FeeSync.str(room['roomverify']);
        if (verify.length === 0) {
          continue;
        }
        roomName = FeeSync.str(room['roomfullname']);
        if (roomName.length === 0) {
          roomName = '未知房间';
        }
        roomName = FeeSync.shortRoom(roomName);
        feeLines = FeeSync.parseItems(room);
        break;
      }

      if (roomName.length === 0) {
        const flag: string = FeeSync.str(inner['existflag']);
        if (flag === '0') {
          roomName = '未绑定宿舍';
          feeLines = [];
        } else {
          hilog.warn(DOMAIN, TAG, 'no room parsed');
          return false;
        }
      }

      await CardStore.put(context, CardStore.KEY_FEE_ROOM, roomName);
      await CardStore.put(context, CardStore.KEY_FEE_LINES, feeLines.join('\n'));
      await CardStore.put(context, CardStore.KEY_FEE_UPDATED, FeeSync.timeStamp());
      await CardStore.put(context, CardStore.KEY_FEE_SYNC_AT, String(Date.now()));
      await CardData.updateAll(context);
      hilog.info(DOMAIN, TAG, 'sync ok room=%{public}s items=%{public}d', roomName, feeLines.length);
      return true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'sync failed: %{public}d %{public}s', e.code, e.message);
      return false;
    } finally {
      request.destroy();
    }
  }

  private static parseItems(room: Record<string, Object>): string[] {
    const out: string[] = [];
    const list: Object | undefined = room['detaillist'];
    if (Array.isArray(list)) {
      for (let i = 0; i < (list as Object[]).length; i++) {
        const raw: Object = (list as Object[])[i];
        if (raw === null || raw === undefined || typeof raw !== 'object') {
          continue;
        }
        const item: Record<string, Object> = raw as Record<string, Object>;
        const type: string = FeeSync.str(item['businesstype']);
        const label: string = FeeSync.label(type, i);
        const balance: number = FeeSync.num(item['odd']);
        const used: number = FeeSync.num(item['use']);
        const unit: string = type === '0' ? '度' : ((type === '1' || type === '2') ? '元' : (i === 0 ? '度' : '元'));
        const urgent: boolean = balance < (unit === '度' ? 20 : 10);
        out.push(label + '|' + balance.toFixed(2) + '|' + unit + '|' + used.toFixed(2)
          + '|' + (urgent ? '1' : '0'));
      }
    }
    if (out.length === 0 && room['odd'] !== undefined) {
      const balance: number = FeeSync.num(room['odd']);
      const used: number = FeeSync.num(room['use']);
      out.push('电费|' + balance.toFixed(2) + '|度|' + used.toFixed(2)
        + '|' + (balance < 20 ? '1' : '0'));
    }
    return out;
  }

  /** 完美校园房间名形如「珠海科技学院_康园2栋_K2-5层_K2-516」，卡片只显示后两段。 */
  private static shortRoom(full: string): string {
    const parts: string[] = full.split('_');
    if (parts.length >= 2) {
      return parts[parts.length - 2] + ' · ' + parts[parts.length - 1];
    }
    return full;
  }

  private static label(type: string, index: number): string {    if (type === '0') {
      return '电费';
    }
    if (type === '1') {
      return '冷水费';
    }
    if (type === '2') {
      return '热水费';
    }
    return index === 0 ? '电费' : ('水费' + (index + 1));
  }

  private static num(value: Object | undefined): number {
    if (typeof value === 'number') {
      return value as number;
    }
    if (typeof value === 'string') {
      const n: number = Number((value as string).trim());
      return isNaN(n) ? 0 : n;
    }
    return 0;
  }

  private static str(value: Object | undefined): string {
    if (typeof value === 'string') {
      return (value as string).trim();
    }
    if (typeof value === 'number') {
      return String(value);
    }
    return '';
  }

  /** 完美校园要求 YYYYMMDDHHmmssSSS（本地时区，毫秒必须补足 3 位）。 */
  private static stamp(): string {
    const d = new Date();
    const p = (n: number): string => (n < 10 ? '0' + n : String(n));
    const ms: number = d.getMilliseconds();
    const msText: string = ms < 10 ? '00' + ms : (ms < 100 ? '0' + ms : String(ms));
    return String(d.getFullYear()) + p(d.getMonth() + 1) + p(d.getDate())
      + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds()) + msText;
  }

  private static timeStamp(): string {
    const d = new Date();
    const p = (n: number): string => (n < 10 ? '0' + n : String(n));
    return p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes()) + ' 已同步';
  }
}
