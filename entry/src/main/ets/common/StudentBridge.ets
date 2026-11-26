import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardStore } from './CardStore';
import { FeeSync } from './FeeSync';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-user';

/**
 * 从 CAS 登录表单里自动识别学号。
 *
 * 水电查询需要学号，但让用户再去设置里抄一遍很容易找不到入口。CAS 登录页
 * 本来就要输入学号，这里在登录页注入一个监听器：检测到 6~20 位纯数字的
 * 账号输入后写入 CardStore，登录返回后 FeeSync 就能直接查询。
 *
 * 只保存账号，不碰密码；密码输入框（type=password）永远跳过。
 */
export class StudentBridge {
  private context: common.Context | undefined = undefined;
  private last: string = '';

  attach(context: common.Context): void {
    this.context = context;
  }

  save(value: string): void {
    if (this.context === undefined) {
      return;
    }
    const no: string = value.trim();
    if (no.length < 6 || no.length > 20 || no === this.last) {
      return;
    }
    if (!/^\d+$/.test(no)) {
      return;
    }
    this.last = no;
    const ctx: common.Context = this.context;
    CardStore.put(ctx, CardStore.KEY_STUDENT_NO, no).then(() => {
      // 学号是登录时自动识别出来的，顺手触发一次水电查询；失败不影响登录。
      FeeSync.sync(ctx);
    });
    hilog.info(DOMAIN, TAG, 'student no captured (%{public}d digits)', no.length);
  }
}

/** 注入 CAS 登录页：监听账号输入框，数字账号自动回传原生。 */
export const STUDENT_SCRAPE_JS: string = `
(function () {
  if (window.__myzcstUserHooked) return;
  window.__myzcstUserHooked = true;
  function scan() {
    var inputs = document.querySelectorAll('input');
    for (var i = 0; i < inputs.length; i++) {
      var el = inputs[i];
      var type = String(el.type || '').toLowerCase();
      if (type === 'password' || type === 'hidden') continue;
      var hint = String((el.name || '') + ' ' + (el.id || '') + ' '
        + (el.placeholder || '') + ' ' + (el.autocomplete || '')).toLowerCase();
      if (hint.indexOf('captcha') >= 0 || hint.indexOf('code') >= 0) continue;
      var value = String(el.value || '').trim();
      if (!/^\\d{6,20}$/.test(value)) continue;
      if (window.__myzcstUser && window.__myzcstUser.save) {
        window.__myzcstUser.save(value);
      }
    }
  }
  document.addEventListener('input', scan, true);
  document.addEventListener('change', scan, true);
  setInterval(scan, 1000);
  scan();
})();
`;
