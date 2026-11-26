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
   * 处理站外地址：先尝试系统 openLink，失败再用 startAbility 兜底，
   * 仍失败则复制到剪贴板并提示。
   */
  static openExternal(ui: UIContext, url: string): void {
    if (url.length === 0) {
      return;
    }
    const ctx: common.UIAbilityContext | undefined =
      Ui.context(ui) as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      WebLink.copy(ui, url);
      return;
    }
    if (url.toLowerCase().startsWith('intent://')) {
      // Android Intent 语法鸿蒙不能直接解析，复制给用户在浏览器/对应 App 打开。
      WebLink.copy(ui, url);
      return;
    }
    ctx.openLink(url, { appLinkingOnly: false }).then(() => {
      hilog.info(DOMAIN, TAG, 'openLink ok: %{public}s', WebLink.shortUrl(url));
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'openLink failed: %{public}d %{public}s',
        err.code, err.message);
      // 部分系统版本 openLink 只认 http(s)，用隐式 Want 再试一次自定义 Scheme。
      const want: Want = { action: 'ohos.want.action.viewData', uri: url };
      ctx.startAbility(want).then(() => {
        hilog.info(DOMAIN, TAG, 'startAbility ok: %{public}s', WebLink.shortUrl(url));
      }).catch((err2: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'startAbility failed: %{public}d %{public}s',
          err2.code, err2.message);
        WebLink.copy(ui, url);
      });
    });
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
