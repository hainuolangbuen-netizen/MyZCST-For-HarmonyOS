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
  /** 卡片副标题（第几周 / 日期），展示用。 */
  static readonly KEY_SUBTITLE: string = 'subtitle_text';
  /** 登录态 cookie（JSESSIONID 等），主 App 写入，供后续同步复用。 */
  static readonly KEY_COOKIE: string = 'session_cookie';
  /** 上次课程同步成功的时间戳（毫秒），用于避免重复同步。 */
  static readonly KEY_SYNC_AT: string = 'sync_at';
  /** 已添加到桌面的卡片 formId（按卡片分开存，换行分隔）。 */
  static readonly KEY_FORM_SCHEDULE: string = 'schedule_form_ids';
  static readonly KEY_FORM_TODO: string = 'todo_form_ids';

  /** 读取某类卡片已添加到桌面的 formId 列表。 */
  static formIds(context: common.Context, key: string): string[] {
    const raw: string = CardStore.getSync(context, key);
    if (raw.length === 0) {
      return [];
    }
    const out: string[] = [];
    for (const part of raw.split('\n')) {
      const id: string = part.trim();
      if (id.length > 0 && out.indexOf(id) < 0) {
        out.push(id);
      }
    }
    return out;
  }

  /** 卡片创建时登记 formId；主 App 同步完课程后用它主动刷新已添加的卡片。 */
  static appendFormId(context: common.Context, key: string, formId: string): void {
    if (formId.length === 0) {
      return;
    }
    const ids: string[] = CardStore.formIds(context, key);
    if (ids.indexOf(formId) >= 0) {
      return;
    }
    ids.push(formId);
    CardStore.putSync(context, key, ids.join('\n'));
  }

  /** 卡片删除时移除 formId，避免后续 updateForm 报错。 */
  static removeFormId(context: common.Context, formId: string): void {
    if (formId.length === 0) {
      return;
    }
    for (const key of [CardStore.KEY_FORM_SCHEDULE, CardStore.KEY_FORM_TODO]) {
      const ids: string[] = CardStore.formIds(context, key);
      const at: number = ids.indexOf(formId);
      if (at >= 0) {
        ids.splice(at, 1);
        CardStore.putSync(context, key, ids.join('\n'));
      }
    }
  }

  /** 同步写：FormExtensionAbility 的 onAddForm/onRemoveForm 返回后进程可能很快回收。 */
  static putSync(context: common.Context, key: string, value: string): void {
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, CardStore.options());
      store.putSync(key, value);
      store.flushSync();
    } catch (err) {
      hilog.error(0x0000, 'myzcst-store', 'putSync %{public}s failed: %{public}s', key, JSON.stringify(err));
    }
  }

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
