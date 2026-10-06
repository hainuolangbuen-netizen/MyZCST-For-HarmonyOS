import { common } from '@kit.AbilityKit';
import { PortalConfig } from '../common/PortalConfig';
import { Session } from '../common/Session';
import { WebPageParams } from '../common/RouteParams';
import { Ui } from '../common/Ui';

class MineRow {
  readonly label: string;
  readonly icon: Resource;
  readonly url: string;
  /** 站内路由（如 pages/SettingsPage）；与 url 二选一。 */
  readonly page: string;

  /** url / page 都为空表示本地动作（由 label 决定）。 */
  constructor(label: string, icon: Resource, url: string, page: string = '') {
    this.label = label;
    this.icon = icon;
    this.url = url;
    this.page = page;
  }
}

/**
 * 「我的」页（原生 ArkUI，对齐官方 iOS 版的形态）：
 * 深蓝渐变头部 + 登录入口 + 一组列表行。
 *
 * 登录不再是本地布尔开关：点头部会打开 pages/LoginPage，在 Web 里走真实的
 * CAS 统一身份认证；登录态通过 AppStorage('userName') 全局广播，本页用
 * @StorageProp 订阅，登录返回后立刻刷新。
 */
@Component
export struct MinePage {
  /**
   * 登录态由 Index 通过 @Prop 下发；refreshTick 每次切页签/回到前台都会递增，
   * 用它触发重读（登录页返回后本页与其它页签一起刷新）。
   */
  @Prop @Watch('onVisible') refreshTick: number = 0;
  @State loggedIn: boolean = false;
  @State userName: string = '';
  @StorageProp('topAvoidPx') topAvoidPx: number = 0;

  aboutToAppear(): void {
    this.onVisible();
  }

  onVisible(): void {
    this.loggedIn = Session.isLoggedIn();
    this.userName = Session.userName();
  }

  /** 头部主标题：登录后优先显示姓名，姓名拿不到时只显示"已登录"。 */
  private headerTitle(): string {
    if (!this.loggedIn) {
      return '登录';
    }
    return this.userName.length > 0 ? this.userName : '已登录';
  }

  private rows: MineRow[] = [
    new MineRow('融合门户', $r('app.media.ic_app_portal'), PortalConfig.PC_PORTAL),
    new MineRow('学校官网', $r('app.media.ic_app_web'), PortalConfig.SCHOOL_SITE),
    new MineRow('意见反馈', $r('app.media.ic_feedback'), ''),
    new MineRow('关于我们', $r('app.media.ic_about'), ''),
    new MineRow('使用帮助', $r('app.media.ic_help'), ''),
    new MineRow('设置', $r('app.media.ic_settings'), '', 'pages/SettingsPage')
  ];

  private onRow(item: MineRow): void {
    if (item.page.length > 0) {
      Ui.push(this.getUIContext(), item.page);
      return;
    }
    if (item.url.length > 0) {
      Ui.pushWith(this.getUIContext(), 'pages/WebViewPage',
        new WebPageParams(item.label, item.url));
      return;
    }
    Ui.toast(this.getUIContext(), item.label + '：功能开发中');
  }

  private async doLogout(): Promise<void> {
    const ctx: common.Context | undefined = Ui.context(this.getUIContext());
    if (ctx !== undefined) {
      await Session.logout(ctx);
    }
    this.onVisible();
    Ui.toast(this.getUIContext(), '已退出登录');
  }

  @Builder
  listRow(item: MineRow, isLast: boolean) {
    Column() {
      Row() {
        Image(item.icon)
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
        Text(item.label)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 12 })
        Blank()
        Image($r('app.media.ic_chevron'))
          .width(14)
          .height(14)
          .objectFit(ImageFit.Contain)
      }
      .width('100%')
      .height(54)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.onRow(item);
      })

      if (!isLast) {
        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.divider'))
          .margin({ left: 48 })
      }
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column() {
        // 深蓝渐变头部：点击进入统一身份认证
        Row() {
          Stack() {
            Image($r('app.media.ic_avatar'))
              .width(30)
              .height(30)
              .objectFit(ImageFit.Contain)
          }
          .width(56)
          .height(56)
          .borderRadius(28)
          .backgroundColor('#3A5691')

          Column() {
            Text(this.headerTitle())
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
            Text(this.loggedIn ? '已登录统一身份认证' : '登录后体验更多功能')
              .fontSize(12)
              .fontColor('#B3C2DC')
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 14 })
          .layoutWeight(1)

          Image($r('app.media.ic_chevron'))
            .width(16)
            .height(16)
            .objectFit(ImageFit.Contain)
        }
        .width('100%')
        .height(150)
        .padding({ left: 20, right: 20, top: this.getUIContext().px2vp(this.topAvoidPx) })
        .alignItems(VerticalAlign.Center)
        .linearGradient({
          angle: 160,
          colors: [['#0A2A63', 0.0], ['#011F5B', 1.0]]
        })
        .onClick(() => {
          if (this.loggedIn) {
            Ui.toast(this.getUIContext(),
              this.userName.length > 0 ? ('已登录：' + this.userName) : '已登录统一身份认证');
          } else {
            Ui.push(this.getUIContext(), 'pages/LoginPage');
          }
        })

        // 列表
        Column() {
          ForEach(this.rows, (item: MineRow, index: number) => {
            this.listRow(item, index === this.rows.length - 1)
          }, (item: MineRow) => item.label)
        }
        .width('100%')
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(16)
        .margin({ left: 12, right: 12, top: 12 })

        // 退出登录
        if (this.loggedIn) {
          Row() {
            Text('退出登录')
              .fontSize(16)
              .fontColor($r('app.color.brand_brick'))
          }
          .width('100%')
          .height(54)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(16)
          .margin({ left: 12, right: 12, top: 12 })
          .onClick(() => {
            this.doLogout();
          })
        }

        Text('我的珠科 · 鸿蒙版 1.0.0')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 20 })

        // 给底部悬浮页签让位
        Row().height(96)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .align(Alignment.Top)
  }
}
