/**
 * 全校各系统地址集中配置。
 *
 * ===== 实测结论（2026-10-02，走校园网 + 已登录 Cookie 逐个验证过）=====
 *
 * ❌ 不要再把首页/资讯/消息/应用指到 https://mapp.zcst.edu.cn/index.jsp?domainId=1&act=1
 *    或 https://mapp.zcst.edu.cn/ —— 那两个地址返回的是**南京苏迪「LightApp 轻应用
 *    管理平台」的桌面版管理控制台**（4974 字节，title「欢迎使用LightApp轻应用管理平台！」）。
 *    它对普通学生账号只暴露一个菜单「应用配置 > 调查问卷」，而那个菜单项指向管理页
 *    /_web/_apps/eform/manage/surveyManage.jsp，普通账号一打开就被服务端拒绝，于是整页
 *    显示「您当前访问的页面出错 / 提示：无创建操作权限」。这就是"登录后什么都没有"的原因。
 *
 * ✅ 真正可用的东西：
 *    - 学校官网 https://www.zcst.edu.cn/ —— 200 / 102 KB，<meta viewport width=device-width>，
 *      手机上是响应式的，是资讯最合适的现实来源。
 *    - 苏迪轻应用页面 /_web/_apps/lightapp/<app>/mobile/permit/app/pub/index.html ——
 *      已确认 studentSchedule（课程表-新版）存在，未登录会 302 到 CAS。
 *    - PC 融合门户（树维 SOPPlus）https://my.zcst.edu.cn/_web/sopplus/sopplus/index.html ——
 *      200 / 673 字节的 SPA 空壳，**没有服务端移动端适配**，手机上就是缩小版桌面页，
 *      只能当兜底入口，不能当主界面。
 *    - CAS 统一身份认证 https://sos.zcst.edu.cn/login。
 *
 * ✅✅ 重大发现（2026-10-02 补充）：**苏迪 iPortal 移动接口其实部署在 my.zcst.edu.cn 上**，
 *    前缀是 https://my.zcst.edu.cn/mobile/*.mo —— 官方 iOS/安卓「我的珠科」的应用列表
 *    就是从这里取的。实测：
 *      - GET /mobile/getAppCategorys.mo         → 200，返回 12 个真实分类（新生服务/教工服务/
 *        调查问卷/人事服务/系统直通车/学生服务/网络服务/工会服务/车辆服务/迎新离校/疫情防控/生活服务）
 *      - GET /mobile/queryCategoryApps.mo       → 302 到 CAS（**分类下的应用列表需要登录态**）
 *      - GET /mobile/listAnonNavigation15.mo    → 200，返回「重要提示」(columnId 7)、「通知公告」(columnId 9)
 *      - GET /mobile/queryIndexApps.mo          → 302（需要登录态）
 *    注意：这些接口在 mapp.zcst.edu.cn 上才是 404，别搞混主机。
 *
 * ❌ 已排除（都验证过）：mapp.zcst.edu.cn 上的 /mobile/*.mo 全部 404；
 *    my.zcst.edu.cn/_web/sopplus/mobile.jsp 403「缺少请求参数」；
 *    work.zcst.edu.cn 是 OA 工作流系统；lib/mail/news/m/jwc/ecard 等子域全部解析失败。
 *
 * 法律与技术背景：官方安卓版「我的珠科」(com.jluzh.iportal) 里写死的生产域名
 * https://mapp.jluzh.com 已经失效（现在是 4.cn 的域名停放页），学校现役域名是 zcst.edu.cn。
 */
export class PortalConfig {
  /** 学校官网（响应式，资讯来源）。 */
  static readonly SCHOOL_SITE: string = 'https://www.zcst.edu.cn/';

  /** 苏迪轻应用平台所在主机。 */
  static readonly MAPP_HOST: string = 'https://mapp.zcst.edu.cn';

  /**
   * 登录入口。未登录访问会被 CAS 过滤器 302 到 https://sos.zcst.edu.cn/login，
   * 登录成功后回到这里，登录态以 JSESSIONID 的形式落在 WebCookieManager 里，
   * 全 App 的 Web 组件共享，所以只需要登录一次。
   */
  static readonly LOGIN_ENTRY: string = 'https://mapp.zcst.edu.cn/index.jsp?domainId=1&act=1';

  /** CAS 统一身份认证入口。 */
  static readonly CAS: string = 'https://sos.zcst.edu.cn/login';

  /** 我的课表（苏迪轻应用，需登录态；未登录会 302 到 CAS）。 */
  static readonly LIGHT_SCHEDULE: string =
    'https://mapp.zcst.edu.cn/_web/_apps/lightapp/studentSchedule/mobile/permit/app/pub/index.html';

  /** PC 融合门户（树维 SOPPlus，无移动适配，兜底）。 */
  static readonly PC_PORTAL: string = 'https://my.zcst.edu.cn/_web/sopplus/sopplus/index.html';

  /** PC 融合门户根（CAS 登录后跳回）。 */
  static readonly PC_PORTAL_ROOT: string = 'https://my.zcst.edu.cn/';

  /**
   * 苏迪 iPortal 移动接口主机与入口。官方 App 的应用列表来自这里：
   * 分类列表是公开的，分类下的应用列表需要登录态（未登录 302 到 CAS）。
   * 本 App 的做法：用一个隐藏 Web 组件直接打开这些 .mo 地址（同源，Cookie 自动带上），
   * 再读 document.body.innerText 拿 JSON —— 既不用手工搬 Cookie，也由 WebView 自己完成 SSO。
   */
  static readonly MOBILE_HOST: string = 'https://my.zcst.edu.cn';
  static readonly CATEGORY_API: string = 'https://my.zcst.edu.cn/mobile/getAppCategorys.mo';
  /** 首页/收藏应用接口（需登录态）。 */
  static readonly INDEX_APPS_API: string = 'https://my.zcst.edu.cn/mobile/queryIndexApps.mo';

  /** 首页轮播/公告类栏目接口。 */
  static readonly ANON_NOTICE_API: string = 'https://my.zcst.edu.cn/mobile/listAnonNavigation15.mo';

  /** 某个分类下的应用列表接口。 */
  static categoryAppsApi(categoryId: number): string {
    return 'https://my.zcst.edu.cn/mobile/queryCategoryApps.mo?categoryId=' + categoryId;
  }

  /** 判断一个 URL 是不是本 App 要抓取的移动接口。 */
  static isMobileApiUrl(url: string): boolean {
    return url.indexOf('/mobile/') >= 0 && url.indexOf('my.zcst.edu.cn') >= 0;
  }

  /** CAS 判断：URL 落在这个域上说明还没登录完。 */
  static isCasUrl(url: string): boolean {
    return url.indexOf('sos.zcst.edu.cn') >= 0;
  }

  /** 登录成功判断：URL 回到轻应用平台主域，说明 CAS 已经把票据换成会话了。 */
  static isPortalUrl(url: string): boolean {
    return url.indexOf('mapp.zcst.edu.cn') >= 0;
  }
}
