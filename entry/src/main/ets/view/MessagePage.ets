import { PortalConfig } from '../common/PortalConfig';
import { Session } from '../common/Session';
import { WebPageParams } from '../common/RouteParams';
import { Ui } from '../common/Ui';

class MsgRow {
  readonly label: string;
  readonly note: string;
  readonly icon: Resource;
  readonly url: string;

  constructor(label: string, note: string, icon: Resource, url: string) {
    this.label = label;
    this.note = note;
    this.icon = icon;
    this.url = url;
  }
}

/**
 * 「消息」页（原生 ArkUI）。
 *
 * 说明：学校的苏迪 LightApp 平台在 mapp.zcst.edu.cn 上**没有部署移动消息接口**
 * （/mobile/*.mo 一族全部 404），官方安卓版用的是它自带的服务端，学校这边没有。
 * 所以这一页目前只做两件真事：引导登录 + 打开学校官网的通知栏目。
 * 不做假的"未读红点"。
 */
@Component
export struct MessagePage {
  /**
   * 登录态由 Index 通过 @Prop 下发；refreshTick 每次切页签都会递增，
   * 用它触发重读，避免"登录完了别的页还显示未登录"。
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

  /** 状态栏高度转 vp：全屏布局下标题要自己避开状态栏与挖孔。 */
  private topInset(): number {
    return this.getUIContext().px2vp(this.topAvoidPx) + 8;
  }

  private rows: MsgRow[] = [
    new MsgRow('学校通知公告', '打开珠海科技学院官网查看最新通知', $r('app.media.ic_app_web'),
      PortalConfig.SCHOOL_SITE),
    new MsgRow('融合门户待办', '在 PC 融合门户里查看待办事项', $r('app.media.ic_qe_todo'),
      PortalConfig.PC_PORTAL)
  ];

  @Builder
  row(item: MsgRow, isLast: boolean) {
    Column() {
      Row() {
        Image(item.icon)
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
        Column() {
          Text(item.label)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text(item.note)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        Image($r('app.media.ic_chevron'))
          .width(14)
          .height(14)
          .objectFit(ImageFit.Contain)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onClick(() => {
        Ui.pushWith(this.getUIContext(), 'pages/WebViewPage',
          new WebPageParams(item.label, item.url));
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
        Text('消息')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .padding({ left: 16, top: this.topInset() + 12, bottom: 12 })

        // 登录引导
        if (!this.loggedIn) {
          Column() {
            Image($r('app.media.tab_msg_on'))
              .width(40)
              .height(40)
              .objectFit(ImageFit.Contain)
            Text('登录后同步消息与待办')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 12 })
            Text('登录统一身份认证后，课程表、融合门户等页面无需再次输入密码')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 6 })
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24 })
            Button('立即登录')
              .fontSize(15)
              .height(40)
              .width(160)
              .margin({ top: 16 })
              .backgroundColor($r('app.color.brand_blue'))
              .onClick(() => {
                Ui.push(this.getUIContext(), 'pages/LoginPage');
              })
          }
          .width('100%')
          .padding({ top: 28, bottom: 28 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(16)
          .margin({ left: 12, right: 12 })
        } else {
          Column() {
            Text(this.userName.length > 0 ? ('已登录：' + this.userName) : '已登录统一身份认证')
              .fontSize(13)
              .fontColor($r('app.color.ok_text'))
            Text('当前没有未读消息')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 6 })
          }
          .width('100%')
          .padding({ top: 18, bottom: 18 })
          .backgroundColor($r('app.color.ok_bg'))
          .borderRadius(16)
          .margin({ left: 12, right: 12 })
        }

        // 可打开的入口
        Column() {
          ForEach(this.rows, (item: MsgRow, index: number) => {
            this.row(item, index === this.rows.length - 1)
          }, (item: MsgRow) => item.label)
        }
        .width('100%')
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(16)
        .margin({ left: 12, right: 12, top: 12 })

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
