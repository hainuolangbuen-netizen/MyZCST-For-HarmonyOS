import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardStore } from './CardStore';
import { PortalApi, PortalApp, PortalResult } from './PortalApi';
import { PortalConfig } from './PortalConfig';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-data';

/**
 * 「我的收藏」。
 *
 * 实测：门户的 queryCategoryApps.mo / queryIndexApps.mo 返回的都是整份应用目录
 * （data 下只有 recommends / tops / ranks，没有个人收藏字段），所以收藏只能由
 * 客户端维护、存在 preferences 里。默认三项与官方 App 一致（日程 / 我的待办 /
 * 学生课表）。
 *
 * 存的是应用的 name（服务端显示名），图标和跳转地址在渲染时去 AppCatalog 里解析。
 */
export class Favorites {
  static readonly KEY: string = 'favorite_apps';
  static readonly DEFAULT: string[] = ['日程', '我的待办', '学生课表'];
  static readonly MAX: number = 4;

  static load(context: common.Context): string[] {
    const raw: string = CardStore.getSync(context, Favorites.KEY);
    return raw.length > 0 ? raw.split('\n') : Favorites.DEFAULT.slice();
  }

  static save(context: common.Context, names: string[]): void {
    CardStore.put(context, Favorites.KEY, names.join('\n'));
  }
}

/**
 * 服务端应用目录的内存缓存。
 *
 * 「应用」页拉到目录后放进来，「首页」直接读，避免重复请求；首页在没有缓存时
 * 用 ensure() 自己拉一次。注意 CAS 单点登录那一步只能在 Web 组件里完成
 * （见 AppPage 里的隐藏 Web），所以 ensure() 在会话还没建立时返回 false，
 * 调用方需要自己决定是提示登录还是等下次刷新。
 */
export class AppCatalog {
  /** 服务端会忽略 categoryId（实测每个 id 都返回同一份完整目录），任取一个有效分类即可。 */
  static readonly ANY_CATEGORY: number = 39;

  private static apps: PortalApp[] = [];
  private static loaded: boolean = false;

  static set(list: PortalApp[]): void {
    AppCatalog.apps = list;
    AppCatalog.loaded = list.length > 0;
  }

  static all(): PortalApp[] {
    return AppCatalog.apps;
  }

  static isLoaded(): boolean {
    return AppCatalog.loaded;
  }

  static find(name: string): PortalApp | undefined {
    for (const app of AppCatalog.apps) {
      if (app.name === name) {
        return app;
      }
    }
    return undefined;
  }

  /** 解析一组收藏名 → 服务端返回的真实应用（图标/地址都来自接口），解析不到的跳过。 */
  static resolve(names: string[]): PortalApp[] {
    const out: PortalApp[] = [];
    for (const name of names) {
      const hit: PortalApp | undefined = AppCatalog.find(name);
      if (hit !== undefined) {
        out.push(hit);
      }
    }
    return out;
  }

  /** 没有缓存时自己拉一次全量目录（服务端会忽略 categoryId）。 */
  static async ensure(categoryId: number): Promise<boolean> {
    if (AppCatalog.loaded) {
      return true;
    }
    try {
      const result: PortalResult = await PortalApi.fetchText(PortalConfig.categoryAppsApi(categoryId));
      if (result.needLogin || result.text.length === 0) {
        return false;
      }
      const list: PortalApp[] = PortalApi.parseApps(result.text);
      AppCatalog.set(list);
      hilog.info(DOMAIN, TAG, 'catalog ensure -> %{public}d 项', list.length);
      return AppCatalog.loaded;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'catalog ensure failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }
}
