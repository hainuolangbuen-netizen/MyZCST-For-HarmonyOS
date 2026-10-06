import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppCatalog, Favorites } from '../common/AppData';
import { MaterialGate } from '../common/MaterialGate';
import { PortalConfig } from '../common/PortalConfig';
import { PortalApp } from '../common/PortalApi';
import { Session } from '../common/Session';
import { WebPageParams } from '../common/RouteParams';
import { Ui } from '../common/Ui';

/** 顶部轮播（含悬浮搜索框）的总高度，同时决定快捷入口卡片向上叠压的量。 */
const BANNER_H: number = 240;
/** 搜索框高度。 */
const SEARCH_H: number = 40;
/** 轮播文案距轮播底边的距离。 */
const BANNER_TEXT_BOTTOM: number = 48;

class QuickEntry {
  readonly label: string;
  /** 本地兜底图标。 */
  readonly icon: Resource;
  /** 服务端图标 URL（非空时优先用它）。 */
  readonly iconUrl: string;
  /** 非空则在应用内 Web 页打开；为空表示跳页签（看 tab）。 */
  readonly url: string;
  /** url 为空时切到哪个页签。 */
  readonly tab: number;

  constructor(label: string, icon: Resource, iconUrl: string, url: string, tab: number) {
    this.label = label;
    this.icon = icon;
    this.iconUrl = iconUrl;
    this.url = url;
    this.tab = tab;
  }
}

class BannerItem {
  readonly title: string;
  readonly subtitle: string;
  readonly from: string;
  readonly to: string;

  constructor(title: string, subtitle: string, from: string, to: string) {
    this.title = title;
    this.subtitle = subtitle;
    this.from = from;
    this.to = to;
  }
}

/**
 * 首页（原生 ArkUI，对齐官方 iOS/安卓版的形态）：
 * 顶部轮播 + 悬浮搜索框（沉浸光感）+ 悬浮快捷入口卡片 + 「我的卡片」条带。
 *
 * 排版约束（改动时请一并满足，否则会重现"文案被搜索框压住"的问题）：
 *   搜索框占 [statusBar + 8, statusBar + 8 + SEARCH_H]；
 *   轮播文案贴轮播底边对齐（justifyContent(End) + padding.bottom），
 *   上沿 = BANNER_H - BANNER_TEXT_BOTTOM - 文案高度，必须大于搜索框底边。
 *   轮播 240vp、文案下留 48vp 时：搜索框底边约 87vp，文案约 138~192vp，
 *   快捷卡顶边 208vp —— 三者的间隙都在 16vp 以上。
 *
 * 说明：轮播位暂时是渐变色占位，等拿到学校的真实焦点图 URL 再换成 Image。
 */
@Component
export struct HomePage {
  /** 状态栏高度（px），由 EntryAbility 在 onWindowStageCreate 里写入 AppStorage。 */
  @StorageProp('topAvoidPx') topAvoidPx: number = 0;
  /** 登录态由 Index 下发；refreshTick 每次切页签递增，用它重读（见 Index 的注释）。 */
  @Prop @Watch('onVisible') refreshTick: number = 0;
  @State loggedIn: boolean = false;
  /** 「我的收藏」解析出的真实应用（图标/地址都来自服务端）。 */
  @State favApps: PortalApp[] = [];
  @State bannerIndex: number = 0;
  /** 由 Index 注入：切到指定页签（"添加应用"用）。 */
  onOpenTab: (index: number) => void = (index: number) => {};

  aboutToAppear(): void {
    this.onVisible();
  }

  /**
   * 页签露脸时重读登录态与收藏。
   *
   * 收藏名存在 preferences 里（在「应用」页维护），这里把它解析成服务端返回的真实
   * 应用。目录由 AppCatalog 缓存：「应用」页已经拉过就直接用，没拉过（用户没进过
   * 应用页）就自己拉一次；拉不到（未登录）时退回本地默认入口，保证首屏不为空。
   */
  onVisible(): void {
    this.loggedIn = Session.isLoggedIn();
    this.loadFavorites();
    hilog.info(0x0000, 'myzcst-home', 'onVisible tick=%{public}d loggedIn=%{public}s fav=%{public}d',
      this.refreshTick, this.loggedIn, this.favApps.length);
  }

  private loadFavorites(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      this.favApps = [];
      return;
    }
    this.favApps = AppCatalog.resolve(Favorites.load(ctx));
    if (this.favApps.length === 0 && !AppCatalog.isLoaded()) {
      this.fetchCatalog();
    }
  }

  private async fetchCatalog(): Promise<void> {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    const names: string[] = Favorites.load(ctx);
    const ok: boolean = await AppCatalog.ensure(AppCatalog.ANY_CATEGORY);
    if (ok) {
      this.favApps = AppCatalog.resolve(names);
    }
  }

  /** 接口里的地址可能是 '/_web/...' 相对路径，图标是 http 明文，统一规范化。 */
  private absolute(url: string): string {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return url.startsWith('/') ? PortalConfig.MOBILE_HOST + url : url;
  }

  private httpsIcon(url: string): string {
    if (url.startsWith('http://')) {
      return 'https://' + url.substring(7);
    }
    return this.absolute(url);
  }

  /** 首屏快捷入口 = 我的收藏（服务端解析）+「添加应用」。 */
  private homeEntries(): QuickEntry[] {
    const out: QuickEntry[] = [];
    for (const app of this.favApps) {
      out.push(new QuickEntry(app.name, $r('app.media.ic_app_web'),
        this.httpsIcon(app.icon), this.absolute(app.url), -1));
    }
    if (out.length === 0) {
      for (const item of this.defaultEntries) {
        out.push(item);
      }
    }
    out.push(new QuickEntry('添加应用', $r('app.media.ic_qe_add'), '', '', 3));
    return out;
  }

  private onQuickEntry(item: QuickEntry): void {
    if (item.url.length === 0) {
      if (item.tab >= 0) {
        this.onOpenTab(item.tab);
      }
      return;
    }
    Ui.pushWith(this.getUIContext(), 'pages/WebViewPage',
      new WebPageParams(item.label, item.url));
  }

  /** 搜索框离屏顶的距离（vp）= 状态栏高度 + 8。 */
  private searchTop(): number {
    return this.getUIContext().px2vp(this.topAvoidPx) + 8;
  }

  private banners: BannerItem[] = [
    new BannerItem('珠海科技学院', '厚德 博学 唯实 创新', '#1B3A6B', '#0A1E3F'),
    new BannerItem('移动门户已上线', '一站式办理校内业务', '#8C2F2A', '#4A1512'),
    new BannerItem('我的珠科', '鸿蒙版', '#0A4A6B', '#062B3F')
  ];

  /** 收藏还没同步到（未登录 / 目录没拉到）时的本地兜底入口。 */
  private defaultEntries: QuickEntry[] = [
    new QuickEntry('课程表', $r('app.media.ic_app_schedule'), '', PortalConfig.LIGHT_SCHEDULE, -1),
    new QuickEntry('我的待办', $r('app.media.ic_qe_todo'), '', PortalConfig.PC_PORTAL, -1),
    new QuickEntry('学校官网', $r('app.media.ic_app_web'), '', PortalConfig.SCHOOL_SITE, -1)
  ];

  /**
   * 轮播单页。文案**贴底对齐**而不是垂直居中：垂直居中会让文案正好落在
   * 悬浮搜索框的高度带里，被压住一半。
   */
  @Builder
  bannerSlide(item: BannerItem) {
    Column() {
      Text(item.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textShadow({ radius: 6, color: '#40000000', offsetX: 0, offsetY: 2 })
      Text(item.subtitle)
        .fontSize(12)
        .fontColor('#CCFFFFFF')
        .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .padding({ bottom: BANNER_TEXT_BOTTOM, left: 24, right: 24 })
    .linearGradient({
      angle: 135,
      colors: [[item.from, 0.0], [item.to, 1.0]]
    })
  }

  @Builder
  quickEntryCell(item: QuickEntry) {
    Column() {
      if (item.iconUrl.length > 0) {
        Image(item.iconUrl)
          .width(30)
          .height(30)
          .objectFit(ImageFit.Contain)
          .alt(item.icon)
      } else {
        Image(item.icon)
          .width(30)
          .height(30)
          .objectFit(ImageFit.Contain)
      }
      Text(item.label)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onQuickEntry(item);
    })
  }

  build() {
    Scroll() {
      Column() {
        // 顶部轮播 + 悬浮搜索框（搜索框走通用属性 systemMaterial 上沉浸光感）
        Stack({ alignContent: Alignment.Top }) {
          Swiper() {
            ForEach(this.banners, (item: BannerItem) => {
              this.bannerSlide(item)
            }, (item: BannerItem) => item.title)
          }
          .autoPlay(true)
          .interval(4000)
          .loop(true)
          .indicator(
            new DotIndicator()
              .itemWidth(6)
              .itemHeight(6)
              .selectedItemWidth(14)
              .color('#66FFFFFF')
              .selectedColor(Color.White)
          )
          .width('100%')
          .height(BANNER_H)
          .onChange((index: number) => {
            this.bannerIndex = index;
          })

          Search({ placeholder: '搜索应用、资讯' })
            .width('92%')
            .height(SEARCH_H)
            .margin({ top: this.searchTop() })
            .borderRadius(SEARCH_H / 2)
            // 沉浸光感（官方 API）：ENABLE 且系统白名单支持时，材质会盖过下面的底色。
            // 实测 API 26 模拟器上通用属性 systemMaterial 对 Search 不生效，故下面用
            // backgroundBlurStyle + 半透明底色保证"玻璃"观感，两者不冲突（材质生效时优先）。
            .systemMaterial(MaterialGate.searchMaterial())
            .backgroundColor('#33FFFFFF')
            .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
            .fontColor(Color.White)
            .placeholderColor('#B3FFFFFF')
            .searchIcon({ size: 18, color: '#E6FFFFFF' })
        }
        .width('100%')
        .height(BANNER_H)

        // 快捷入口卡片（= 我的收藏，向上叠压轮播）
        Row() {
          ForEach(this.homeEntries(), (item: QuickEntry) => {
            this.quickEntryCell(item)
          }, (item: QuickEntry) => item.label)
        }
        .width('100%')
        .height(88)
        .padding({ left: 8, right: 8 })
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(18)
        .shadow({ radius: 16, color: '#14000000', offsetX: 0, offsetY: 4 })
        .margin({ left: 12, right: 12, top: -32 })

        // 我的卡片
        Row() {
          Image($r('app.media.ic_card'))
            .width(20)
            .height(20)
            .objectFit(ImageFit.Contain)
          Text('我的卡片')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand_navy'))
            .margin({ left: 8 })
          Blank()
          Text('管理')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 14 })
        .backgroundColor($r('app.color.cell_bg'))
        .borderRadius(12)
        .margin({ left: 12, right: 12, top: 12 })

        Text('资讯来自学校官网，卡片与应用入口在「应用」页维护')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 16 })

        // 给底部悬浮页签让位
        Row().height(96)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }
}
