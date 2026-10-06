import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE_NAME: string = 'myzcst_card_store';

/**
 * 桌面小组件的数据中转站。
 *
 * 卡片自己不能联网（ArkTS 卡片的接口白名单里没有网络能力），所以数据流是：
 *   主 App（Web 组件里登录 → 拿到 cookie → 调轻应用接口）→ 写这里 → 卡片读这里
 * preferences 是应用级存储，FormExtensionAbility 与主 App 共享同一个实例。
 */
export class CardStore {
  /** 今日课表，多行文本，每行一节课。 */
  static readonly KEY_SCHEDULE: string = 'schedule_text';
  /** 我的待办，多行文本，每行一条。 */
  static readonly KEY_TODO: string = 'todo_text';
  /** 最近一次同步时间，展示用。 */
  static readonly KEY_UPDATED: string = 'updated_text';
  /** 登录态 cookie（JSESSIONID 等），主 App 写入，供后续同步复用。 */
  static readonly KEY_COOKIE: string = 'session_cookie';

  private static options(): preferences.Options {
    const opt: preferences.Options = { name: STORE_NAME };
    return opt;
  }

  static async put(context: common.Context, key: string, value: string): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, CardStore.options());
      await store.put(key, value);
      await store.flush();
    } catch (err) {
      hilog.error(0x0000, 'myzcst-store', 'put %{public}s failed: %{public}s', key, JSON.stringify(err));
    }
  }

  static async get(context: common.Context, key: string): Promise<string> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, CardStore.options());
      const value: preferences.ValueType = await store.get(key, '');
      return typeof value === 'string' ? value : '';
    } catch (err) {
      hilog.error(0x0000, 'myzcst-store', 'get %{public}s failed: %{public}s', key, JSON.stringify(err));
      return '';
    }
  }

  /** 同步读，给 FormExtensionAbility.onAddForm 这种必须同步返回的场合用。 */
  static getSync(context: common.Context, key: string): string {
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, CardStore.options());
      const value: preferences.ValueType = store.getSync(key, '');
      return typeof value === 'string' ? value : '';
    } catch (err) {
      return '';
    }
  }
}
