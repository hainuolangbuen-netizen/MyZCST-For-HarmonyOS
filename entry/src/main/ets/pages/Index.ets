import { hilog } from '@kit.PerformanceAnalysisKit';
import { MaterialGate } from '../common/MaterialGate';
import { PortalConfig } from '../common/PortalConfig';
import { Session } from '../common/Session';
import { AppPage } from '../view/AppPage';
import { HomePage } from '../view/HomePage';
import { MessagePage } from '../view/MessagePage';
import { MinePage } from '../view/MinePage';
import { WebTab } from '../view/WebTab';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst';

/**
 * 应用外壳：底部 5 个页签（资讯 / 消息 / 首页 / 应用 / 我的）。
 *
 * 形态对齐官方安卓 / iOS 版：底部页签是**悬浮胶囊**，内容从它下面穿过，
 * 所以给它挂上沉浸光感材质（FloatingTabBarStyle.systemMaterial）。
 * 注意 barOverlap(true) + barPosition(BarPosition.End) 必须同时给，否则
 * 页签不会浮在内容上，材质也就没有东西可以透出来。
 *
 * 页签内容的分工（改之前先读 PortalConfig 里的实测结论）：
 *   资讯 = 学校官网（响应式，真实校园新闻）
 *   消息 = 原生页（学校移动端没有消息接口，只做登录引导 + 通知入口）
 *   首页 = 原生页（轮播 + 快捷入口，形态对齐官方版）
 *   应用 = 原生宫格（平台没有可用的应用列表页，入口由客户端维护）
 *   我的 = 原生页（真实 CAS 登录入口）
 */
@Entry
@Component
struct Index {
  @State currentIndex: number = 2;
  @State materialReady: boolean = false;
  /**
   * 登录态在壳这一层集中同步，再通过 @Prop 下发给所有页签。
   *
   * 早前各页自己写 @StorageProp('loggedIn')，实测从登录页 router.back() 回来后
   * 兄弟页签不会刷新（要杀进程重启才认）。现在改成：@Entry 页在 onPageShow /
   * aboutToAppear / 每次切页签时重新读 Session，并递增 refreshTick；子组件用
   * @Prop @Watch 接这个 tick 重读，页签一露脸状态就是新的。
   */
  @State loggedIn: boolean = false;
  @State userName: string = '';
  @State refreshTick: number = 0;
  /**
   * 沉浸光感强度，由「设置」页写入 AppStorage（AppSettings.setGlass），
   * 用 @StorageProp 订阅后 barFloatingStyle 会自动重建、立即生效。
   */
  @StorageProp('glassLevel') @Watch('onGlassChange') glassLevel: string = 'standard';
  private tabsController: TabsController = new TabsController();

  aboutToAppear(): void {
    this.materialReady = MaterialGate.supported();
    this.syncLogin();
    hilog.info(DOMAIN, TAG,
      'immersive supported=%{public}s level=%{public}d appState=%{public}d glass=%{public}s',
      this.materialReady, MaterialGate.level(), MaterialGate.state(), this.glassLevel);
  }

  onGlassChange(): void {
    hilog.info(DOMAIN, TAG, 'glass level -> %{public}s', this.glassLevel);
  }

  /** 从登录页 router.back() 回来、或从后台切回前台都会走这里。 */
  onPageShow(): void {
    this.syncLogin();
  }

  private syncLogin(): void {
    this.loggedIn = Session.isLoggedIn();
    this.userName = Session.userName();
    this.refreshTick = this.refreshTick + 1;
    hilog.info(DOMAIN, TAG, 'syncLogin loggedIn=%{public}s user=%{public}s tick=%{public}d',
      this.loggedIn, this.userName.length > 0 ? this.userName : '-', this.refreshTick);
  }

  /** 悬浮页签样式；设备不支持光感时就不挂材质，形态本身仍然是悬浮胶囊。 */
  private floatingStyle(): FloatingTabBarStyle {
    const style: FloatingTabBarStyle = {
      barSideMargin: 16,
      barBottomMargin: 14,
      adaptToHandedness: true
    };
    if (this.materialReady) {
      style.systemMaterial = MaterialGate.tabMaterial(this.glassLevel);
    }
    return style;
  }

  /** 供内部页（首页快捷入口）切换页签用。 */
  private switchTab(index: number): void {
    this.currentIndex = index;
    this.tabsController.changeIndex(index);
  }

  @Builder
  tabItem(index: number, label: string, iconOff: Resource, iconOn: Resource) {
    Column() {
      Image(this.currentIndex === index ? iconOn : iconOff)
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
      Text(label)
        .fontSize(10)
        .margin({ top: 3 })
        .fontColor(this.currentIndex === index ? $r('app.color.tab_active') : $r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
        TabContent() {
          WebTab({ url: PortalConfig.SCHOOL_SITE })
        }
        .tabBar(this.tabItem(0, '资讯', $r('app.media.tab_news_off'), $r('app.media.tab_news_on')))

        TabContent() {
          MessagePage({
            loggedIn: this.loggedIn,
            userName: this.userName,
            refreshTick: this.refreshTick
          })
        }
        .tabBar(this.tabItem(1, '消息', $r('app.media.tab_msg_off'), $r('app.media.tab_msg_on')))

        TabContent() {
          HomePage({
            loggedIn: this.loggedIn,
            refreshTick: this.refreshTick,
            onOpenTab: (index: number) => this.switchTab(index)
          })
        }
        .tabBar(this.tabItem(2, '首页', $r('app.media.tab_home_off'), $r('app.media.tab_home_on')))

        TabContent() {
          AppPage({
            loggedIn: this.loggedIn,
            userName: this.userName,
            refreshTick: this.refreshTick
          })
        }
        .tabBar(this.tabItem(3, '应用', $r('app.media.tab_app_off'), $r('app.media.tab_app_on')))

        TabContent() {
          MinePage({
            loggedIn: this.loggedIn,
            userName: this.userName,
            refreshTick: this.refreshTick
          })
        }
        .tabBar(this.tabItem(4, '我的', $r('app.media.tab_mine_off'), $r('app.media.tab_mine_on')))
      }
      .barHeight(56)
      .barOverlap(true)
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barFloatingStyle(this.floatingStyle())
      .scrollable(false)
      .animationDuration(200)
      .onChange((index: number) => {
        this.currentIndex = index;
        // 页签一露面就把登录态重新读一遍下发给子组件。
        this.syncLogin();
      })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
