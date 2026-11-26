import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Downloader } from '../common/Downloader';
import { WebLink } from '../common/WebLink';
import { WebPageParams } from '../common/RouteParams';
import { Ui } from '../common/Ui';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-web';

/**
 * 内嵌 H5 栏目的容器。
 *
 * 现役移动门户 https://mapp.zcst.edu.cn 只是苏迪 LightApp 的**管理台**（见
 * PortalConfig 里的实测结论），所以本组件只用于打开确定可用的页面：
 * 学校官网（响应式）和各个轻应用页面。
 * CAS 登录态在 Web 组件里自然建立并保持。
 */
@Component
export struct WebTab {
  @Prop url: string = '';
  @StorageProp('topAvoidPx') topAvoidPx: number = 0;
  @State progress: number = 100;
  private controller: webview.WebviewController = new webview.WebviewController();

  /**
   * 窗口是 setWindowLayoutFullScreen(true) 的全屏布局，网页从 y=0 开始画，
   * 学校官网那条约 76vp 高的红色页头会被状态栏和挖孔压住，所以把 Web 整体下移
   * 一个状态栏高度。
   */
  private topPad(): number {
    return this.getUIContext().px2vp(this.topAvoidPx);
  }

  build() {
    Column() {
      if (this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color($r('app.color.brand_blue'))
      }
      Web({ src: this.url, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .domStorageAccess(true)
        .databaseAccess(true)
        .mixedMode(MixedMode.Compatible)
        .zoomAccess(false)
        .multiWindowAccess(true)
        .onProgressChange((event) => {
          this.progress = event.newProgress;
        })
        .onPageBegin((event) => {
          hilog.info(DOMAIN, TAG, 'onPageBegin url=%{public}s', event.url);
        })
        .onPageEnd((event) => {
          this.progress = 100;
          hilog.info(DOMAIN, TAG, 'onPageEnd url=%{public}s', event.url);
        })
        .onLoadIntercept((event) => {
          const url: string = event.data.getRequestUrl();
          if (!event.data.isMainFrame()) {
            return false;
          }
          if (WebLink.isWebUrl(url) && !WebLink.isPaymentUrl(url)) {
            return false;
          }
          hilog.info(DOMAIN, TAG, 'intercept url: %{public}s', url.substring(0, 80));
          WebLink.openExternal(this.getUIContext(), url);
          return true;
        })
        .onErrorReceive((event) => {
          hilog.error(DOMAIN, TAG, 'onErrorReceive url=%{public}s err=%{public}s',
            event.request.getRequestUrl(), event.error.getErrorInfo());
        })
        .onHttpErrorReceive((event) => {
          hilog.error(DOMAIN, TAG, 'onHttpErrorReceive url=%{public}s code=%{public}d',
            event.request.getRequestUrl(), event.response.getResponseCode());
        })
        .onWindowNew((event) => {
          // 同 WebViewPage：不要用当前 controller 接管新窗口，否则 target 为空或
          // 支付 Scheme 时会把原页面换成空白页。
          hilog.info(DOMAIN, TAG, 'onWindowNew -> %{public}s', event.targetUrl);
          const target: string = event.targetUrl;
          event.handler.setWebController(null);
          if (target.length === 0) {
            Ui.toast(this.getUIContext(), '已拦截空白弹窗');
            return;
          }
          if (!WebLink.isWebUrl(target)) {
            WebLink.openExternal(this.getUIContext(), target);
            return;
          }
          if (WebLink.isPaymentUrl(target)) {
            WebLink.openExternal(this.getUIContext(), target);
            return;
          }
          Ui.pushWith(this.getUIContext(), 'pages/WebViewPage',
            new WebPageParams('详情', target));
        })
        .onDownloadStart((event) => {
          hilog.info(DOMAIN, TAG, 'download start: %{public}s (%{public}s)', event.url, event.mimetype);
          Downloader.start(this.getUIContext(), event.url, event.contentDisposition, event.mimetype);
        })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topPad() })
    .backgroundColor($r('app.color.card_bg'))
  }
}
