import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { AppCatalog, Favorites } from '../common/AppData';
import { AppCategory, PortalApi, PortalApp, PortalResult } from '../common/PortalApi';
import { PortalConfig } from '../common/PortalConfig';
import { Session } from '../common/Session';
import { WebPageParams } from '../common/RouteParams';
import { Ui } from '../common/Ui';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-app';
const LOGIN_NOTE: string = '分类下的应用需要登录后才能读取，请先到「我的」完成统一身份认证。';

/** 兜底宫格项（接口拿不到数据时用）。 */
class AppItem {
  readonly label: string;
  readonly icon: Resource;
  readonly url: string;
  readonly action: string;

  constructor(label: string, icon: Resource, url: string, action: string) {
    this.label = label;
    this.icon = icon;
    this.url = url;
    this.action = action;
  }
}

class AppGroup {
  readonly title: string;
  readonly items: AppItem[];

  constructor(title: string, items: AppItem[]) {
    this.title = title;
    this.items = items;
  }
}

/**
 * 「应用」页。
 *
 * 数据来源与官方 iOS/安卓版一致：苏迪 iPortal 移动接口
 *   GET https://my.zcst.edu.cn/mobile/getAppCategorys.mo     （分类，公开）
 *   GET https://my.zcst.edu.cn/mobile/queryCategoryApps.mo   （分类下的应用，需登录态）
 *
 * 实现方式：用原生 HTTP（@ohos.net.http）直接 GET 这些 .mo 地址，cookie 由
 * WebCookieManager 提供（在「我的」登录过一次即可，CAS 单点登录那一步在 Web 组件里完成）。
 * 早期版本用"1×1 隐藏 Web 组件 + runJavaScript"取数据，在 ArkWeb 网络线程上会
 * SIGTRAP 崩溃，已废弃。
 * 接口拿不到数据时，退回本地维护的宫格（每项都指向实测存在的地址），保证页面不为空。
 */
@Component
export struct AppPage {
  /** 登录态由 Index 下发；refreshTick 每次切页签递增，用它重读（见 Index 的注释）。 */
  @Prop @Watch('onVisible') refreshTick: number = 0;
  @State loggedIn: boolean = false;
  @State userName: string = '';
  @StorageProp('topAvoidPx') topAvoidPx: number = 0;

  /** 服务端返回的 12 个真实分类。 */
  @State categories: AppCategory[] = [];
  /** 接口一次性返回的全部应用（本地按分类过滤）。 */
  @State allApps: PortalApp[] = [];
  /**
   * 「我的收藏」里存的应用名（按顺序）。
   *
   * 实测：门户的 queryCategoryApps.mo / queryIndexApps.mo 都返回整份应用目录
   * （data 下只有 recommends / tops / ranks，没有个人收藏），所以收藏由客户端
   * 维护、存在 preferences 里，默认与官方 App 一致（日程 / 我的待办 / 学生课表）。
   */
  @State favoriteNames: string[] = [];
  /** 「添加应用」选择面板是否展开。 */
  @State showPicker: boolean = false;
  /** 当前分类下的应用。 */
  @State apps: PortalApp[] = [];
  @State activeId: number = -1;
  @State activeName: string = '';
  @State appsLoading: boolean = false;
  @State note: string = '';
  @State needLogin: boolean = false;
  @State loaded: boolean = false;
  /** 需要借 Web 组件跑一次 CAS 单点登录（原生 HTTP 不会自己完成 SSO 跳转）。 */
  @State ssoNeeded: boolean = false;

  private ssoTried: boolean = false;
  @State ssoUrl: string = '';
  private ssoController: webview.WebviewController = new webview.WebviewController();

  /** 兜底宫格项（接口拿不到数据时用）。 */
  private groups: AppGroup[] = [
    new AppGroup('常用', [
      new AppItem('课程表', $r('app.media.ic_app_schedule'), PortalConfig.LIGHT_SCHEDULE, 'web'),
      new AppItem('我的卡片', $r('app.media.ic_card'), '', 'soon'),
      new AppItem('我的待办', $r('app.media.ic_qe_todo'), PortalConfig.PC_PORTAL, 'web'),
      new AppItem('学校官网', $r('app.media.ic_app_web'), PortalConfig.SCHOOL_SITE, 'web')
    ]),
    new AppGroup('门户与认证', [
      new AppItem('融合门户', $r('app.media.ic_app_portal'), PortalConfig.PC_PORTAL, 'web'),
      new AppItem('统一认证', $r('app.media.ic_app_auth'), '', 'login'),
      new AppItem('意见反馈', $r('app.media.ic_feedback'), '', 'soon'),
      new AppItem('更多', $r('app.media.ic_qe_add'), '', 'soon')
    ])
  ];

  /** 状态栏高度转 vp，避免顶部提示条被状态栏压住。 */
  private topInset(): number {
    return this.getUIContext().px2vp(this.topAvoidPx) + 8;
  }

  aboutToAppear(): void {
    this.onVisible();
  }

  /**
   * 页签露脸时重读登录态与收藏。
   *
   * 登录态刚变成"已登录"（例如刚从登录页返回）时要重新拉一次应用列表——之前
   * 拿不到数据就是因为没有会话。已经拉到的目录缓存在 AppCatalog 里，切页签不会重发请求。
   */
  onVisible(): void {
    const logged: boolean = Session.isLoggedIn();
    const justLoggedIn: boolean = logged && !this.loggedIn;
    this.loggedIn = logged;
    this.userName = Session.userName();
    this.loadFavoriteNames();

    if (this.allApps.length === 0 && AppCatalog.isLoaded()) {
      this.allApps = AppCatalog.all();
    }
    if (!this.loaded || justLoggedIn) {
      this.ssoTried = false;
      this.loadCategories();
    } else if (this.apps.length === 0) {
      this.selectInitial();
    }
  }

  private loadFavoriteNames(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      this.favoriteNames = Favorites.DEFAULT.slice();
      return;
    }
    this.favoriteNames = Favorites.load(ctx);
  }

  /** 把收藏里的应用名解析成接口返回的真实应用（图标/地址都来自服务端）。 */
  private resolvedFavorites(): PortalApp[] {
    const out: PortalApp[] = [];
    for (const name of this.favoriteNames) {
      for (const app of this.allApps) {
        if (app.name === name) {
          out.push(app);
          break;
        }
      }
    }
    return out;
  }

  /** 长按分类里的应用 → 收藏 / 取消收藏。 */
  private toggleFavorite(app: PortalApp): void {
    const list: string[] = this.favoriteNames.slice();
    const at: number = list.indexOf(app.name);
    if (at >= 0) {
      list.splice(at, 1);
      Ui.toast(this.getUIContext(), '已取消收藏「' + app.name + '」');
    } else {
      if (list.length >= Favorites.MAX) {
        Ui.toast(this.getUIContext(), '「我的收藏」最多放 ' + Favorites.MAX + ' 个，请先长按移除一个');
        return;
      }
      list.push(app.name);
      Ui.toast(this.getUIContext(), '已收藏「' + app.name + '」');
    }
    this.favoriteNames = list;
    const ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      Favorites.save(ctx, list);
    }
  }

  /** 拉分类列表（公开接口，不需要登录）。 */
  private async loadCategories(): Promise<void> {
    try {
      const result: PortalResult = await PortalApi.fetchText(PortalConfig.CATEGORY_API);
      if (result.needLogin || result.text.length === 0) {
        this.loaded = true;
        this.needLogin = result.needLogin;
        this.note = result.needLogin ? LOGIN_NOTE : '读取应用分类失败，请稍后重试。';
        return;
      }
      const list: AppCategory[] = PortalApi.parseCategories(result.text);
      if (list.length === 0) {
        this.loaded = true;
        this.note = '没能解析出应用分类（接口返回为空）。';
        return;
      }
      this.loaded = true;
      this.needLogin = false;
      this.categories = list;
      this.note = '';
      await this.loadAllApps();
      this.selectInitial();
    } catch (err) {
      this.loaded = true;
      this.note = '读取应用分类失败：' + (err as BusinessError).message;
    }
  }

  /** 默认选中第一个"真的有应用"的分类（接口里排第一的「新生服务」通常是空的）。 */
  private selectInitial(): void {
    for (const category of this.categories) {
      for (const app of this.allApps) {
        if (app.belongsTo(category.id)) {
          this.selectCategory(category);
          return;
        }
      }
    }
    if (this.categories.length > 0) {
      this.selectCategory(this.categories[0]);
    }
  }

  /**
   * 拉取全部应用（需要登录态）。
   *
   * 实测：`queryCategoryApps.mo` 不管传哪个 categoryId 都返回同一份完整列表（42KB），
   * 每个应用自带 `categoryIds`（形如 ",13,17,"），所以只请求一次、本地按分类过滤。
   */
  private async loadAllApps(): Promise<void> {
    this.appsLoading = true;
    try {
      const result: PortalResult = await PortalApi.fetchText(PortalConfig.categoryAppsApi(this.categories[0].id));
      this.appsLoading = false;
      if (result.needLogin || result.text.length === 0) {
        // 已登录但 my.zcst.edu.cn 上还没有会话：借 Web 组件跑一次 CAS 单点登录，成功后重试。
        if (this.loggedIn && !this.ssoTried) {
          this.ssoTried = true;
          this.ssoUrl = PortalConfig.categoryAppsApi(this.categories[0].id);
          this.ssoNeeded = true;
          return;
        }
        this.needLogin = true;
        this.note = LOGIN_NOTE;
        return;
      }
      this.needLogin = false;
      this.allApps = PortalApi.parseApps(result.text);
      // 发布到共享缓存，首页的「我的收藏」直接复用，避免重复请求。
      AppCatalog.set(this.allApps);
      this.note = '';
      hilog.info(DOMAIN, TAG, 'all apps -> %{public}d (%{public}s)',
        this.allApps.length, PortalApi.countGroups(result.text));
    } catch (err) {
      this.appsLoading = false;
      this.note = '读取应用列表失败：' + (err as BusinessError).message;
      hilog.error(DOMAIN, TAG, 'loadAllApps failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 本地按分类过滤（不发请求）。 */
  private selectCategory(category: AppCategory): void {
    this.activeId = category.id;
    this.activeName = category.name;
    const filtered: PortalApp[] = [];
    for (const app of this.allApps) {
      if (app.belongsTo(category.id)) {
        filtered.push(app);
      }
    }
    this.apps = filtered;
    if (filtered.length === 0 && this.allApps.length > 0 && !this.needLogin) {
      this.note = '这个分类下暂时没有应用。';
    } else if (!this.needLogin) {
      this.note = '';
    }
  }

  /** SSO 跳转完成后重试一次原生请求。 */
  private onSsoDone(): void {
    this.loadAllApps();
    this.selectInitial();
  }

  /** 接口里的地址可能是 '/_web/...' 这种相对路径。 */
  private absolute(url: string): string {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('/')) {
      return PortalConfig.MOBILE_HOST + url;
    }
    return url;
  }

  /**
   * 应用图标的 iconUrl 是 http 明文地址（如 http://my.zcst.edu.cn/_upload/...），
   * 应用未开 cleartextTraffic，所以统一改写成 https 再加载；学校站点 https 可用。
   */
  private httpsIcon(url: string): string {
    if (url.startsWith('http://')) {
      return 'https://' + url.substring(7);
    }
    return this.absolute(url);
  }

  private openLogin(): void {
    Ui.push(this.getUIContext(), 'pages/LoginPage');
  }

  private openApp(app: PortalApp): void {
    if (app.url.length === 0) {
      return;
    }
    Ui.pushWith(this.getUIContext(), 'pages/WebViewPage',
      new WebPageParams(app.name, this.absolute(app.url)));
  }

  private open(item: AppItem): void {
    if (item.action === 'login') {
      Ui.push(this.getUIContext(), 'pages/LoginPage');
      return;
    }
    if (item.action === 'soon' || item.url.length === 0) {
      Ui.toast(this.getUIContext(), item.label + '：功能开发中');
      return;
    }
    Ui.pushWith(this.getUIContext(), 'pages/WebViewPage', new WebPageParams(item.label, item.url));
  }

  @Builder
  categoryItem(category: AppCategory) {
    Row() {
      Text(category.name)
        .fontSize(14)
        .fontColor(this.activeId === category.id ? Color.White : $r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 14, bottom: 14 })
    .backgroundColor(this.activeId === category.id ? $r('app.color.brand_navy') : Color.Transparent)
    .onClick(() => {
      this.selectCategory(category);
    })
  }

  @Builder
  appCell(app: PortalApp) {
    Column() {
      if (app.icon.length > 0) {
        Image(this.httpsIcon(app.icon))
          .width(40)
          .height(40)
          .objectFit(ImageFit.Contain)
          .borderRadius(10)
          .alt($r('app.media.ic_app_web'))
      } else {
        Text(app.name.length > 0 ? app.name.substring(0, 1) : '?')
          .fontSize(18)
          .fontColor(Color.White)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .borderRadius(12)
          .backgroundColor($r('app.color.brand_blue'))
      }
      Text(app.name)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
    }
    .width('33%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.openApp(app);
    })
    .gesture(LongPressGesture().onAction(() => {
      this.toggleFavorite(app);
    }))
  }

  @Builder
  gridCell(item: AppItem) {
    Column() {
      Image(item.icon)
        .width(34)
        .height(34)
        .objectFit(ImageFit.Contain)
      Text(item.label)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
        .maxLines(1)
    }
    .width('25%')
    .padding({ top: 14, bottom: 14 })
    .onClick(() => {
      this.open(item);
    })
  }

  @Builder
  hintBar() {
    Row() {
      Image(this.loggedIn ? $r('app.media.ic_app_auth') : $r('app.media.ic_avatar'))
        .width(18)
        .height(18)
        .objectFit(ImageFit.Contain)
      Text(this.loggedIn
        ? ('已登录' + (this.userName.length > 0 ? '：' + this.userName : '') + ' · 应用可直接打开')
        : '未登录时，分类下的应用需要先登录')
        .fontSize(12)
        .fontColor(this.loggedIn ? $r('app.color.ok_text') : $r('app.color.text_secondary'))
        .margin({ left: 8 })
        .layoutWeight(1)
      if (!this.loggedIn) {
        Text('去登录')
          .fontSize(12)
          .fontColor($r('app.color.brand_blue'))
          .onClick(() => {
            Ui.push(this.getUIContext(), 'pages/LoginPage');
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInset(), bottom: 10 })
    .backgroundColor(this.loggedIn ? $r('app.color.ok_bg') : $r('app.color.info_bg'))
  }

  @Builder
  fallbackGroups() {
    ForEach(this.groups, (group: AppGroup) => {
      Column() {
        Text(group.title)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 4, bottom: 8 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(group.items, (item: AppItem) => {
            this.gridCell(item)
          }, (item: AppItem) => group.title + item.label)
        }
        .width('100%')
        .padding({ top: 4, bottom: 8 })
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(16)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 14 })
    }, (group: AppGroup) => group.title)
  }

  @Builder
  favoritesRow() {
    Column() {
      Row() {
        Row()
          .width(3)
          .height(14)
          .backgroundColor($r('app.color.brand_brick'))
          .borderRadius(2)
        Text('我的收藏')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 6 })
      }
      .width('100%')
      .padding({ left: 4, top: 10, bottom: 6 })

      Row() {
        if (this.resolvedFavorites().length > 0) {
          ForEach(this.resolvedFavorites(), (app: PortalApp) => {
            this.favoriteCell(app)
          }, (app: PortalApp) => 'fav-' + app.name)
        } else {
          ForEach(this.groups[0].items, (item: AppItem) => {
            this.fallbackFavoriteCell(item)
          }, (item: AppItem) => 'fb-' + item.label)
        }
        this.addAppCell()
      }
      .width('100%')
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(14)
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
  }

  @Builder
  favoriteCell(app: PortalApp) {
    Column() {
      if (app.icon.length > 0) {
        Image(this.httpsIcon(app.icon))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
          .alt($r('app.media.ic_app_web'))
      } else {
        Text(app.name.length > 0 ? app.name.substring(0, 1) : '?')
          .fontSize(14)
          .fontColor(Color.White)
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .borderRadius(8)
          .backgroundColor($r('app.color.brand_blue'))
      }
      Text(app.name)
        .fontSize(11)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 6 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .onClick(() => {
      this.openApp(app);
    })
  }

  @Builder
  fallbackFavoriteCell(item: AppItem) {
    Column() {
      Image(item.icon)
        .width(28)
        .height(28)
        .objectFit(ImageFit.Contain)
      Text(item.label)
        .fontSize(11)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 6 })
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .onClick(() => {
      this.open(item);
    })
  }

  @Builder
  addAppCell() {
    Column() {
      Image($r('app.media.ic_qe_add'))
        .width(28)
        .height(28)
        .objectFit(ImageFit.Contain)
      Text('添加应用')
        .fontSize(11)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 6 })
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .onClick(() => {
      this.showPicker = true;
    })
  }

  /** 「添加应用」面板：点一下加入，再点一下移出。 */
  @Builder
  pickerSheet() {
    Column() {
      Text('点应用即可加入或移出「我的收藏」，最多 ' + Favorites.MAX + ' 个')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 10 })

      List() {
        ForEach(this.allApps, (app: PortalApp) => {
          ListItem() {
            Row() {
              if (app.icon.length > 0) {
                Image(this.httpsIcon(app.icon))
                  .width(32)
                  .height(32)
                  .objectFit(ImageFit.Contain)
                  .borderRadius(8)
                  .alt($r('app.media.ic_app_web'))
              } else {
                Text(app.name.length > 0 ? app.name.substring(0, 1) : '?')
                  .fontSize(14)
                  .fontColor(Color.White)
                  .width(32)
                  .height(32)
                  .textAlign(TextAlign.Center)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.brand_blue'))
              }
              Text(app.name)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .margin({ left: 12 })
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.favoriteNames.indexOf(app.name) >= 0 ? '已收藏' : '添加')
                .fontSize(13)
                .fontColor(this.favoriteNames.indexOf(app.name) >= 0
                  ? $r('app.color.ok_text') : $r('app.color.brand_blue'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .onClick(() => {
              this.toggleFavorite(app);
            })
          }
        }, (app: PortalApp) => 'pick-' + app.name)
      }
      .layoutWeight(1)
      .width('100%')
      .divider({ strokeWidth: 1, color: $r('app.color.divider') })
    }
    .width('100%')
    .height(520)
  }

  build() {
    Column() {
      this.hintBar()

      // SSO 引导：只借 Web 组件跑一次 CAS 跳转；页面加载回调里只做原生 HTTP，不再 loadUrl（那会崩）
      if (this.ssoNeeded) {
        Web({ src: this.ssoUrl, controller: this.ssoController })
          .width(1)
          .height(1)
          .opacity(0)
          .domStorageAccess(true)
          .databaseAccess(true)
          .mixedMode(MixedMode.Compatible)
          .zoomAccess(false)
          .onPageEnd((event) => {
            hilog.info(DOMAIN, TAG, 'sso page end: %{public}s', event.url);
            this.ssoNeeded = false;
            this.onSsoDone();
          })
      }

      if (!this.loaded) {
        Column() {
          LoadingProgress().width(32).height(32)
          Text('正在读取学校移动门户的应用列表…')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 10 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.categories.length > 0) {
        this.favoritesRow()

        Row() {
          // 左侧：服务端返回的真实分类
          List() {
            ForEach(this.categories, (category: AppCategory) => {
              ListItem() {
                this.categoryItem(category)
              }
            }, (category: AppCategory) => category.id.toString())
          }
          .width(104)
          .height('100%')
          .backgroundColor($r('app.color.cell_bg'))
          .divider({ strokeWidth: 0.5, color: $r('app.color.divider') })

          // 右侧：该分类下的应用
          Scroll() {
            Column() {
              Text(this.activeName)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .padding({ left: 12, top: 12, bottom: 4 })

              if (this.appsLoading) {
                Row() {
                  LoadingProgress().width(24).height(24)
                  Text('读取中…')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ left: 8 })
                }
                .padding({ top: 24, bottom: 24 })
                .justifyContent(FlexAlign.Center)
                .width('100%')
              } else if (this.apps.length > 0) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.apps, (app: PortalApp) => {
                    this.appCell(app)
                  }, (app: PortalApp) => app.name)
                }
                .width('100%')
                .padding({ top: 4, bottom: 8 })
              } else {
                Text(this.note)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .lineHeight(18)
                  .padding({ left: 12, right: 12, top: 16 })

                if (this.needLogin) {
                  Button('立即登录')
                    .fontSize(13)
                    .height(34)
                    .backgroundColor($r('app.color.brand_blue'))
                    .margin({ left: 12, top: 14 })
                    .onClick(() => {
                      this.openLogin();
                    })
                }
              }

              // 给底部悬浮页签让位
              Row().height(96)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .height('100%')
          .align(Alignment.Top)
          .backgroundColor($r('app.color.page_bg'))
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Scroll() {
          Column() {
            this.fallbackGroups()

            Text(this.note.length > 0 ? this.note
              : '说明：以上入口由客户端维护，每一项都指向实测存在的地址。')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(16)
              .padding({ left: 16, right: 16, top: 16 })

            Row().height(96)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .backgroundColor($r('app.color.page_bg'))
      }

      // 页面底部的说明
      Row().height(96)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .bindSheet($$this.showPicker, this.pickerSheet(), {
      height: 520,
      dragBar: true,
      showClose: true,
      blurStyle: BlurStyle.COMPONENT_THICK,
      onDisappear: () => {
        this.showPicker = false;
      }
    })
  }
}
