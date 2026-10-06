import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { PortalConfig } from '../common/PortalConfig';
import { Session } from '../common/Session';
import { Ui } from '../common/Ui';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-login';

/**
 * 统一身份认证登录页。
 *
 * 流程：Web 打开 PortalConfig.LOGIN_ENTRY →（未登录时）302 到 CAS 登录页 →
 * 用户输学号密码 → CAS 带票据跳回轻应用平台 → 我们检测到 URL 回到
 * mapp.zcst.edu.cn，顺手把页面上的显示名抠出来存进 preferences，然后自动返回。
 *
 * 登录态是 Cookie，落在 WebCookieManager 里，全 App 的 Web 组件共享，
 * 所以这里登录一次，资讯/应用/课程表等所有需要登录的页面都跟着生效。
 */
@Entry
@Component
struct LoginPage {
  @StorageProp('topAvoidPx') topAvoidPx: number = 0;
  @State progress: number = 0;
  @State hint: string = '正在跳转统一身份认证…';
  @State done: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  /** 防止 onPageEnd 反复触发导致重复保存 / 重复返回。 */
  private handled: boolean = false;

  private topPad(): number {
    return this.getUIContext().px2vp(this.topAvoidPx);
  }

  /**
   * 从登录落地页上抠显示名。
   *
   * 轻应用平台控制台的配置脚本里，右上角用户名长这样：
   *     href:'', title: '张三', img: ..., className: 'core-user',
   * 所以用 `title: '...'` + 150 字符内出现 core-user 来定位。150 这个窗口是量过的：
   * 「应用配置」那个 title 距离 core-user 约 300 字符，不会被误匹配。
   */
  private probeUser(): void {
    const js: string =
      '(function(){try{' +
      'var h=document.documentElement.outerHTML;' +
      "var m=h.match(/title:\\s*'([^']{1,20})'[\\s\\S]{0,150}?core-user/);" +
      "if(m) return 'N:'+m[1];" +
      "var t=(document.title||'').replace(/\\s+/g,'');" +
      "if(t.indexOf('LightApp')>=0) return 'N:';" +
      "return 'N:';" +
      "}catch(e){return 'N:';}})()";
    this.controller.runJavaScript(js)
      .then((res: string) => {
        // runJavaScript 回传的是 JSON 文本：字符串结果会带外层双引号（"N:张三"），
        // 直接 startsWith('N:') 会判不中，必须先剥掉。
        let s: string = res === undefined || res === null ? '' : res;
        if (s.length > 1 && s.startsWith('"') && s.endsWith('"')) {
          s = s.substring(1, s.length - 1);
        }
        const name: string = s.startsWith('N:') ? s.substring(2) : '';
        hilog.info(DOMAIN, TAG, 'probeUser -> "%{public}s" (raw=%{public}s)', name, res);
        this.finish(name);
      })
      .catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'probeUser failed: %{public}s', JSON.stringify(err));
        this.finish('');
      });
  }

  private finish(name: string): void {
    if (this.handled) {
      return;
    }
    this.handled = true;
    this.done = true;
    this.hint = name.length > 0 ? ('登录成功：' + name) : '登录成功';
    const ctx: common.Context | undefined = Ui.context(this.getUIContext());
    const goBack: () => void = () => {
      setTimeout(() => {
        Ui.back(this.getUIContext());
      }, 900);
    };
    if (ctx === undefined) {
      goBack();
      return;
    }
    Session.saveName(ctx, name)
      .then(() => {
        goBack();
      })
      .catch(() => {
        goBack();
      });
  }

  build() {
    Column() {
      // 顶部条
      Row() {
        Text('‹  返回')
          .fontSize(16)
          .fontColor($r('app.color.brand_navy'))
          .onClick(() => {
            Ui.back(this.getUIContext());
          })
        Blank()
        Text('统一身份认证')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('完成')
          .fontSize(16)
          .fontColor(this.handled ? $r('app.color.text_secondary') : $r('app.color.brand_blue'))
          .onClick(() => {
            if (!this.handled) {
              this.probeUser();
            }
          })
      }
      .width('100%')
      .height(48 + this.topPad())
      .padding({ left: 12, right: 12, top: this.topPad() })
      .backgroundColor($r('app.color.card_bg'))

      Row() {
        Text(this.hint)
          .fontSize(12)
          .fontColor(this.done ? $r('app.color.ok_text') : $r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.done ? $r('app.color.ok_bg') : $r('app.color.info_bg'))

      if (this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color($r('app.color.brand_blue'))
      }

      Web({ src: PortalConfig.LOGIN_ENTRY, controller: this.controller })
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
          hilog.info(DOMAIN, TAG, 'login onPageEnd url=%{public}s', event.url);
          if (this.handled) {
            return;
          }
          if (PortalConfig.isPortalUrl(event.url) && !PortalConfig.isCasUrl(event.url)) {
            // 已经跳回平台 = CAS 票据换成功，抠名字并返回。
            this.probeUser();
          } else {
            this.hint = PortalConfig.isCasUrl(event.url) ? '请在下方输入学号与密码' : '正在跳转…';
          }
        })
        .onErrorReceive((event) => {
          hilog.error(DOMAIN, TAG, 'login onErrorReceive %{public}s', event.error.getErrorInfo());
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
