import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-api';

/** 一次接口请求的结果。needLogin 表示服务端把请求重定向到了统一身份认证。 */
export class PortalResult {
  readonly needLogin: boolean;
  readonly text: string;

  constructor(needLogin: boolean, text: string) {
    this.needLogin = needLogin;
    this.text = text;
  }
}

/** 应用分类（来自 /mobile/getAppCategorys.mo）。 */
export class AppCategory {
  readonly id: number;
  readonly name: string;

  constructor(id: number, name: string) {
    this.id = id;
    this.name = name;
  }
}

/**
 * 一个可打开的应用。
 *
 * 字段名来自 2026-10-02 在模拟器上登录后抓到的真实响应（`queryCategoryApps.mo`）：
 *   {"name":"日程","appName":"com.sudytech.appricheng",
 *    "mainUrl":"https://mapp.zcst.edu.cn/_web/_apps/lightapp/calendar/mobile/permit/app/pub/index.html",
 *    "iconUrl":"http://my.zcst.edu.cn/_upload/appstore/<uuid>/res/icon/05.png",
 *    "categoryId":17,"categoryIds":",17,","sort":1,"type":4,...}
 * 注意：`appName` 是包名（com.sudytech.xxx），`name` 才是显示名；地址在 `mainUrl`。
 */
export class PortalApp {
  readonly name: string;
  readonly url: string;
  readonly icon: string;
  readonly categoryIds: string;

  constructor(name: string, url: string, icon: string, categoryIds: string) {
    this.name = name;
    this.url = url;
    this.icon = icon;
    this.categoryIds = categoryIds;
  }

  /** 该应用是否属于某个分类（categoryIds 形如 ",13,17,"）。 */
  belongsTo(categoryId: number): boolean {
    if (this.categoryIds.length === 0) {
      return false;
    }
    const parts: string[] = this.categoryIds.split(',');
    for (const part of parts) {
      if (part.length > 0 && Number(part) === categoryId) {
        return true;
      }
    }
    return false;
  }
}

/**
 * 苏迪 iPortal 移动接口的响应解析。
 *
 * 为什么要写"宽松解析"：`queryCategoryApps.mo` 需要登录态才能拿到真实数据，
 * 而官方 App 的 JSON 字段名没有公开文档（安卓包里被 R8 混淆过）。所以这里不写死
 * 某个 schema，而是递归遍历 JSON，把"同时具备名字字段和 URL 字段"的对象认成应用。
 * 这样服务端换版本、字段改名（name/appName/title、url/appUrl/linkUrl…）都能兜住。
 */
export class PortalApi {
  // `mainUrl` 必须排第一：它才是应用的入口地址（downloadUrl/installUrl 是离线包，不能用）
  private static readonly URL_KEYS: string[] =
    ['mainUrl', 'url', 'appUrl', 'linkUrl', 'href', 'openUrl', 'mAppUrl', 'appLink'];
  // `appName` 是包名（com.sudytech.xxx），放最后兜底；`name`/`title` 才是显示名
  private static readonly NAME_KEYS: string[] =
    ['name', 'title', 'appTitle', 'label', 'description', 'appName'];
  private static readonly ICON_KEYS: string[] =
    ['iconUrl', 'icon', 'appIconPath', 'logo', 'imgUrl'];
  private static readonly CATEGORY_KEYS: string[] =
    ['categoryIds', 'categoryId', 'categoryIdsStr'];

  /**
   * 用原生 HTTP 拉接口文本。
   *
   * 为什么不用隐藏的 Web 组件取数据：ArkWeb 的网络线程（NetworkService）在
   * "页面加载回调里再次 loadUrl" 这种重入场景下会 SIGTRAP 崩溃（实测 faultlog
   * cppcrash-...-20261002032234929.log，栈全在 libarkweb_engine.so）。
   * 改成原生 HTTP 后，cookie 由 WebCookieManager 共享（登录页登过一次就够），
   * 302 到 CAS 时我们按"响应不是 JSON"判定需要登录，不再让 Web 引擎参与。
   */
  static async fetchText(url: string): Promise<PortalResult> {
    const request = http.createHttp();
    try {
      let cookie: string = '';
      try {
        cookie = webview.WebCookieManager.fetchCookieSync(url);
      } catch (err) {
        cookie = '';
      }
      const header: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 ' +
          '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
      };
      if (cookie.length > 0) {
        header['Cookie'] = cookie;
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000
      };
      const response = await request.request(url, options);
      const code: number = response.responseCode as number;
      let body: string = '';
      if (typeof response.result === 'string') {
        body = response.result as string;
      }
      const trimmed: string = body.replace(/^\s+/, '');
      const isJson: boolean = trimmed.startsWith('{') || trimmed.startsWith('[');
      hilog.info(DOMAIN, TAG, 'fetch %{public}s -> code=%{public}d len=%{public}d json=%{public}s',
        url, code, body.length, isJson ? 'Y' : 'N');
      return new PortalResult(!isJson, body);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'fetch failed %{public}s code=%{public}d', url, e.code);
      return new PortalResult(false, '');
    } finally {
      request.destroy();
    }
  }

  /** 解析分类列表。 */
  static parseCategories(text: string): AppCategory[] {
    const out: AppCategory[] = [];
    try {
      const root = JSON.parse(text) as Record<string, Object>;
      const data = root.data as Object[];
      if (data) {
        for (const item of data) {
          const rec = item as Record<string, Object>;
          const idObj = rec.id;
          const nameObj = rec.name;
          if (typeof nameObj === 'string' && (nameObj as string).length > 0) {
            const id: number = typeof idObj === 'number' ? idObj as number : -1;
            out.push(new AppCategory(id, nameObj as string));
          }
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'parseCategories failed: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, 'parseCategories -> %{public}d 项', out.length);
    return out;
  }

  /** 解析某分类下的应用列表。 */
  static parseApps(text: string): PortalApp[] {
    const out: PortalApp[] = [];
    try {
      const root = JSON.parse(text) as Object;
      PortalApi.collect(root, out, 0);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'parseApps failed: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, 'parseApps -> %{public}d 项', out.length);
    if (out.length === 0 && text.length > 0) {
      // 解析不出来时把响应开头打出来，便于按真实字段名调整（不打印全部，避免日志过长）
      hilog.info(DOMAIN, TAG, 'parseApps raw head: %{public}s', text.substring(0, 400));
    }
    return out;
  }

  /**
   * 解析接口响应里 recommend/tops/ranks 这类数组的项数，只用于日志排查。
   * 实测结论：门户这几个应用接口都返回整份目录（27 个），没有个人收藏列表，
   * 所以「我的收藏」由客户端维护（见 AppPage.favoriteNames）。
   */
  static countGroups(text: string): string {
    try {
      const root = JSON.parse(text) as Record<string, Object>;
      const data = root['data'];
      if (data !== undefined && data !== null) {
        const rec = data as Record<string, Object>;
        const parts: string[] = [];
        for (const key of Object.keys(rec)) {
          const value = rec[key];
          if (Array.isArray(value)) {
            parts.push(key + '=' + (value as Object[]).length);
          }
        }
        return parts.join(' ');
      }
    } catch (err) {
      return 'parse failed';
    }
    return '';
  }

  private static collect(node: Object, out: PortalApp[], depth: number): void {
    if (depth > 6 || node === null || node === undefined) {
      return;
    }
    if (Array.isArray(node)) {
      for (const item of node as Object[]) {
        PortalApi.collect(item as Object, out, depth + 1);
      }
      return;
    }
    if (typeof node !== 'object') {
      return;
    }
    const rec = node as Record<string, Object>;
    const name: string = PortalApi.pick(rec, PortalApi.NAME_KEYS);
    let url: string = PortalApi.pick(rec, PortalApi.URL_KEYS);
    if (name.length > 0 && url.length === 0) {
      // 有的服务端把地址放在子对象里（如 {name:.., app:{url:..}}），向下找一层
      url = PortalApi.pickChildUrl(rec);
    }
    if (name.length > 0 && url.length > 0 && !PortalApi.duplicated(out, name)) {
      const icon: string = PortalApi.pick(rec, PortalApi.ICON_KEYS);
      const categoryIds: string = PortalApi.pick(rec, PortalApi.CATEGORY_KEYS);
      out.push(new PortalApp(name, url, icon, categoryIds));
    }
    for (const key of Object.keys(rec)) {
      const child: Object = rec[key];
      if (child !== null && child !== undefined && typeof child === 'object') {
        PortalApi.collect(child, out, depth + 1);
      }
    }
  }

  /** 在直接子对象里找一个地址字段。 */
  private static pickChildUrl(rec: Record<string, Object>): string {
    for (const key of Object.keys(rec)) {
      const child: Object = rec[key];
      if (child !== null && child !== undefined && typeof child === 'object' && !Array.isArray(child)) {
        const u: string = PortalApi.pick(child as Record<string, Object>, PortalApi.URL_KEYS);
        if (u.length > 0) {
          return u;
        }
      }
    }
    return '';
  }

  private static pick(rec: Record<string, Object>, keys: string[]): string {    for (const key of keys) {
      const v: Object = rec[key];
      if (typeof v === 'string') {
        const s: string = (v as string).trim();
        if (s.length > 0) {
          return s;
        }
      }
    }
    return '';
  }

  private static duplicated(list: PortalApp[], name: string): boolean {
    for (const item of list) {
      if (item.name === name) {
        return true;
      }
    }
    return false;
  }
}
