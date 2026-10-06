import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebPageParams } from '../common/RouteParams';
import { Ui } from '../common/Ui';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-webview';

/**
 * 通用内嵌浏览页。
 *
 * 「应用」「首页快捷入口」「消息」里点开的具体页面都走这里：带一个返回按钮 +
 * 标题栏，其余屏幕给 ArkWeb。窗口新开（门户 H5 里大量 target=_blank / window.open）
 * 会被接管回同一个 Web 组件，否则用户点了链接没有反应。
 */
@Entry
@Component
struct WebViewPage {
  @StorageProp('topAvoidPx') topAvoidPx: number = 0;
  @State title: string = '';
  @State progress: number = 0;
  @State currentUrl: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private initialUrl: string = '';

  aboutToAppear(): void {
    const params: WebPageParams | undefined =
      Ui.params(this.getUIContext()) as WebPageParams | undefined;
    if (params !== undefined) {
      this.title = params.title;
      this.initialUrl = params.url;
      this.currentUrl = params.url;
    }
  }

  private topPad(): number {
    return this.getUIContext().px2vp(this.topAvoidPx);
  }

  build() {
    Column() {
      Row() {
        Text('‹  返回')
          .fontSize(16)
          .fontColor($r('app.color.brand_navy'))
          .onClick(() => {
            Ui.back(this.getUIContext());
          })
        Blank()
        Text(this.title.length > 0 ? this.title : '详情')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank()
        Text('刷新')
          .fontSize(15)
          .fontColor($r('app.color.brand_blue'))
          .onClick(() => {
            this.controller.refresh();
          })
      }
      .width('100%')
      .height(48 + this.topPad())
      .padding({ left: 12, right: 12, top: this.topPad() })
      .backgroundColor($r('app.color.card_bg'))

      if (this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color($r('app.color.brand_blue'))
      }

      Web({ src: this.initialUrl, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .domStorageAccess(true)
        .databaseAccess(true)
        .mixedMode(MixedMode.Compatible)
        .zoomAccess(true)
        .multiWindowAccess(true)
        .onProgressChange((event) => {
          this.progress = event.newProgress;
        })
        .onPageEnd((event) => {
          this.progress = 100;
          this.currentUrl = event.url;
          hilog.info(DOMAIN, TAG, 'onPageEnd %{public}s', event.url);
        })
        .onWindowNew((event) => {
          if (event.targetUrl.length > 0) {
            event.handler.setWebController(this.controller);
          }
        })
        .onDownloadStart((event) => {
          hilog.info(DOMAIN, TAG, 'download start: %{public}s', event.url);
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
