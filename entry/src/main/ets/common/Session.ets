import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { CardStore } from './CardStore';

/** AppStorage 里存放当前登录用户名的键（供各页面用 @StorageProp 订阅）。 */
export const KEY_USER_NAME: string = 'userName';
/** AppStorage 里存放"是否已登录"的键。用户名可能取不到，登录态必须单独存。 */
export const KEY_LOGGED_IN: string = 'loggedIn';

/**
 * 登录态。
 *
 * 真实登录发生在 Web 组件里（CAS 统一身份认证），会话以 Cookie 的形式存在
 * WebCookieManager 中，全 App 的 Web 组件自动共享——所以「登录」这件事本身
 * 不需要我们自己保存密码或 token。
 *
 * 这里只额外记住两件事，用于「我的」页显示状态：
 *   - 显示名（从登录落地页上取）；
 *   - 上次登录时间。
 * 两者都写进 preferences，冷启动由 EntryAbility 回填到 AppStorage。
 */
export class Session {
  private static readonly KEY_NAME: string = 'user_name';
  private static readonly KEY_TIME: string = 'login_time';

  /** 当前显示名；取不到时返回空串（此时用 isLoggedIn() 判断登录态）。 */
  static userName(): string {
    const v: string | undefined = AppStorage.get<string>(KEY_USER_NAME);
    return v === undefined ? '' : v;
  }

  static isLoggedIn(): boolean {
    const v: boolean | undefined = AppStorage.get<boolean>(KEY_LOGGED_IN);
    return v === true;
  }

  /** 冷启动时调用：把持久化的登录态回填进 AppStorage。 */
  static restore(context: common.Context): void {
    const name: string = CardStore.getSync(context, Session.KEY_NAME);
    const time: string = CardStore.getSync(context, Session.KEY_TIME);
    if (name.length > 0) {
      AppStorage.setOrCreate<string>(KEY_USER_NAME, name);
    }
    if (name.length > 0 || time.length > 0) {
      AppStorage.setOrCreate<boolean>(KEY_LOGGED_IN, true);
    }
  }

  /**
   * 登录成功后调用。
   *
   * name 可能为空——平台控制台只有在登录落地页里能抠到显示名，抠不到时
   * 我们只知道"会话有效"，此时仍标记为已登录，只是不显示具体姓名。
   */
  static async saveName(context: common.Context, name: string): Promise<void> {
    AppStorage.setOrCreate<string>(KEY_USER_NAME, name);
    AppStorage.setOrCreate<boolean>(KEY_LOGGED_IN, true);
    await CardStore.put(context, Session.KEY_NAME, name);
    await CardStore.put(context, Session.KEY_TIME, new Date().toLocaleString());
    // 会话 Cookie 立刻落盘，避免杀进程后丢登录态。
    try {
      await webview.WebCookieManager.saveCookieAsync();
    } catch (err) {
      // 保存失败不影响本次登录，下次访问站点会重新写盘。
    }
  }

  /** 退出登录：清 UI 状态 + 清偏好 + 清 Web Cookie。 */
  static async logout(context: common.Context): Promise<void> {
    AppStorage.setOrCreate<string>(KEY_USER_NAME, '');
    AppStorage.setOrCreate<boolean>(KEY_LOGGED_IN, false);
    await CardStore.put(context, Session.KEY_NAME, '');
    await CardStore.put(context, Session.KEY_TIME, '');
    await CardStore.put(context, CardStore.KEY_COOKIE, '');
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (err) {
      // 忽略：乐观清除，失败也只是下次访问仍带旧 Cookie。
    }
  }
}
