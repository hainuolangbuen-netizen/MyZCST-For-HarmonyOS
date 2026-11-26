import { common, Want } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Ui } from './Ui';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-link';

/**
 * 网页里的站外链接 / 支付 Scheme 处理。
 *
 * 学校水电缴费页点「微信支付」后，页面会跳到一个 `weixin://...` 或
 * `intent://...` 地址（部分版本是 `window.open` 弹出支付窗）。ArkWeb 无法渲染
 * 这类地址，直接放行就会得到"整页空白、点不动"的表现。这里统一拦截：
 *   - http/https/file/about/data/blob 继续交给 Web 组件；
 *   - 微信/支付宝/云闪付等 Scheme 交给系统 openLink / startAbility 拉起对应 App；
 *   - 拉不起来时复制链接并提示用户去对应 App 打开，避免页面被导航成空白。
 */
export class WebLink {
  /** 这些前缀是 Web 组件自己能渲染的地址，不要拦截。 */
  static isWebUrl(url: string): boolean {
    if (url.length === 0) {
      return false;
    }
    const lower: string = url.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://') ||
      lower.startsWith('file://') || lower.startsWith('about:') ||
      lower.startsWith('data:') || lower.startsWith('blob:') ||
      lower.startsWith('javascript:');
  }

  /** 空白页：支付弹窗常用 about:blank 占位，导航到它会留下整页白色。 */
  static isBlank(url: string): boolean {
    return url === '' || url.toLowerCase() === 'about:blank';
  }

  /** 支付类/外部 App Scheme。 */
  static isExternalScheme(url: string): boolean {
    const lower: string = url.toLowerCase();
    return lower.startsWith('weixin://') || lower.startsWith('wechat://') ||
      lower.startsWith('alipays://') || lower.startsWith('alipay://') ||
      lower.startsWith('unionpay://') || lower.startsWith('upwallet://') ||
      lower.startsWith('intent://') || lower.startsWith('tel:') ||
      lower.startsWith('sms:') || lower.startsWith('mailto:');
  }

  /**
   * 收银台页面：这类页面在普通 WebView 中经常依赖微信/支付宝 App 的 JSAPI，
   * 直接加载会白屏或卡在"正在跳转"。命中时交给系统浏览器/对应 App。
   */
  static isPaymentUrl(url: string): boolean {
    const lower: string = url.toLowerCase();
    return lower.indexOf('wx.tenpay.com') >= 0 ||
      lower.indexOf('tenpay.com') >= 0 ||
      lower.indexOf('pay.weixin.qq.com') >= 0 ||
      lower.indexOf('mclient.alipay.com') >= 0 ||
      lower.indexOf('wappaygw.alipay.com') >= 0 ||
      lower.indexOf('cashier.alipay.com') >= 0 ||
      lower.indexOf('unionpay.com') >= 0 ||
      lower.indexOf('95516.com') >= 0;
  }

  /**
   * 处理站外地址。
   *
   * 关键区别（参考掌上猪科的实现）：
   *   - `weixin://` / `alipays://` 是**拉起 App 的 Scheme**，交给系统 startAbility，
   *     不要先走 openLink —— 部分系统会把 weixin:// 当普通链接丢给浏览器，
   *     微信收到后就会报「商家格式有误」；
   *   - `https://wx.tenpay.com/...` 等 H5 收银台才交给浏览器/系统 openLink。
   */
  static openExternal(ui: UIContext, url: string): void {
    if (url.length === 0) {
      return;
    }
    const lower: string = url.toLowerCase();
    const ctx: common.UIAbilityContext | undefined =
      Ui.context(ui) as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      WebLink.copy(ui, url);
      return;
    }
    if (lower.startsWith('intent://')) {
      // Android Intent 语法鸿蒙不能直接解析，复制给用户在浏览器/对应 App 打开。
      WebLink.copy(ui, url);
      return;
    }
    if (lower.startsWith('weixin://') || lower.startsWith('wechat://')) {
      WebLink.openScheme(ui, ctx, url, '微信');
      return;
    }
    if (lower.startsWith('alipays://') || lower.startsWith('alipay://')) {
      WebLink.openScheme(ui, ctx, url, '支付宝');
      return;
    }
    if (lower.startsWith('unionpay://') || lower.startsWith('upwallet://')) {
      WebLink.openScheme(ui, ctx, url, '云闪付');
      return;
    }
    if (!WebLink.isWebUrl(url)) {
      WebLink.copy(ui, url);
      return;
    }
    WebLink.openBrowser(ui, ctx, url);
  }

  /** 自定义 Scheme：直接 startAbility 拉起对应支付 App。 */
  private static openScheme(ui: UIContext, ctx: common.UIAbilityContext,
    url: string, label: string): void {
    const want: Want = { action: 'ohos.want.action.viewData', uri: url };
    Ui.toast(ui, '正在打开' + label + '…');
    ctx.startAbility(want).then(() => {
      hilog.info(DOMAIN, TAG, 'scheme %{public}s opened', label);
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'scheme %{public}s failed: %{public}d %{public}s',
        label, err.code, err.message);
      // 有些支付页把 H5 收银台放在 scheme 的 url= 参数里，尝试再转浏览器。
      const inner: string = WebLink.queryParam(url, 'url');
      if (inner.length > 0 && WebLink.isWebUrl(inner)) {
        WebLink.openBrowser(ui, ctx, inner);
        return;
      }
      Ui.toast(ui, '未能拉起' + label + '，请在系统浏览器完成支付或重试');
    });
  }

  /** H5 收银台：openLink 优先，失败再用隐式 Want + browsable 打开浏览器。 */
  private static openBrowser(ui: UIContext, ctx: common.UIAbilityContext, url: string): void {
    ctx.openLink(url, { appLinkingOnly: false }).then(() => {
      hilog.info(DOMAIN, TAG, 'openLink ok: %{public}s', WebLink.shortUrl(url));
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'openLink failed: %{public}d %{public}s',
        err.code, err.message);
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url,
        entities: ['entity.system.browsable']
      };
      ctx.startAbility(want).then(() => {
        hilog.info(DOMAIN, TAG, 'browser startAbility ok: %{public}s', WebLink.shortUrl(url));
      }).catch((err2: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'browser startAbility failed: %{public}d %{public}s',
          err2.code, err2.message);
        WebLink.copy(ui, url);
      });
    });
  }

  /** 从 URL 查询串里取参数（用于 weixin://...?url=https%3A... 的兜底）。 */
  private static queryParam(url: string, key: string): string {
    const marker: string = key + '=';
    const at: number = url.indexOf(marker);
    if (at < 0) {
      return '';
    }
    let value: string = url.substring(at + marker.length);
    const amp: number = value.indexOf('&');
    if (amp >= 0) {
      value = value.substring(0, amp);
    }
    try {
      return decodeURIComponent(value);
    } catch (err) {
      return value;
    }
  }

  /** 复制链接，并提示用户在对应 App 内打开。 */
  static copy(ui: UIContext, url: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        Ui.toast(ui, '已复制链接，请到微信/支付宝中打开');
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'clipboard failed: %{public}s', err.message);
        Ui.toast(ui, '无法拉起外部应用，请手动复制支付链接');
      });
    } catch (err) {
      Ui.toast(ui, '无法拉起外部应用，请手动复制支付链接');
    }
  }

  private static shortUrl(url: string): string {
    return url.length > 80 ? url.substring(0, 80) + '…' : url;
  }
}
