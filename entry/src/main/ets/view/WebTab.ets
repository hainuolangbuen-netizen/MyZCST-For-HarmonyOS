import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';

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
        .onErrorReceive((event) => {
          hilog.error(DOMAIN, TAG, 'onErrorReceive url=%{public}s err=%{public}s',
            event.request.getRequestUrl(), event.error.getErrorInfo());
        })
        .onHttpErrorReceive((event) => {
          hilog.error(DOMAIN, TAG, 'onHttpErrorReceive url=%{public}s code=%{public}d',
            event.request.getRequestUrl(), event.response.getResponseCode());
        })
        .onWindowNew((event) => {
          // 门户 H5 里有多处 window.open / target=_blank。
          // 把"新窗口"的内容接管到同一个 Web 组件里，否则用户点了链接会没反应。
          hilog.info(DOMAIN, TAG, 'onWindowNew -> %{public}s', event.targetUrl);
          if (event.targetUrl.length > 0) {
            event.handler.setWebController(this.controller);
          }
        })
        .onDownloadStart((event) => {
          // TODO: 接 @ohos.request 下载到 filesDir 并 startAbility 打开。
          // 第一版只记录，附件下载仍是待办项。
          hilog.info(DOMAIN, TAG, 'download start: %{public}s (%{public}s)', event.url, event.mimetype);
        })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topPad() })
    .backgroundColor($r('app.color.card_bg'))
  }
}
