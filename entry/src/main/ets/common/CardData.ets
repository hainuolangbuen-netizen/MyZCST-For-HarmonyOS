import { common, Want } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardStore } from './CardStore';
import { WatchSync } from './WatchSync';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-carddata';

/**
 * 卡片的 FormBindingData 构建与主动刷新。
 *
 * 内容与 EntryFormAbility 原来内联的 buildBindingData 完全一致，抽出来是为了
 * 让主 App 在「登录后同步课程」完成时也能构造同一份数据，并通过 formId 主动
 * 刷新已经添加的桌面卡片（卡片自己不能联网，只能靠主 App 推送）。
 */
export class CardData {
  /** 卡片展示数据：优先 CardStore，没有数据时给登录引导占位。 */
  static build(context: common.Context): formBindingData.FormBindingData {
    const schedule: string = CardStore.getSync(context, CardStore.KEY_SCHEDULE);
    const todo: string = CardStore.getSync(context, CardStore.KEY_TODO);
    const updated: string = CardStore.getSync(context, CardStore.KEY_UPDATED);
    const subtitle: string = CardStore.getSync(context, CardStore.KEY_SUBTITLE);
    const todoUpdated: string = CardStore.getSync(context, CardStore.KEY_TODO_UPDATED);
    const feeRoom: string = CardStore.getSync(context, CardStore.KEY_FEE_ROOM);
    const rawFee: string = CardStore.getSync(context, CardStore.KEY_FEE_LINES);
    // 1.0.5 之前可能把「冷水费 1.00 元」这种金额当成余额写进卡片；
    // 用户要的是吨数/度数，元为单位的行不再展示。
    const feeKept: string[] = [];
    for (const line of rawFee.split('\n')) {
      if (line.indexOf('|元|') >= 0) {
        continue;
      }
      if (line.length > 0) {
        feeKept.push(line);
      }
    }
    const feeLines: string = feeKept.join('\n');
    const feeUpdated: string = CardStore.getSync(context, CardStore.KEY_FEE_UPDATED);
    const data: Record<string, string> = {
      'scheduleTitle': '今日课程',
      'scheduleSubtitle': subtitle,
      'scheduleLines': schedule.length > 0 ? schedule : '打开「我的珠科」并登录后自动同步',
      'todoTitle': '我的待办',
      'todoLines': todo.length > 0 ? todo : '暂无待办',
      'todoUpdatedText': todoUpdated,
      'feeTitle': '智能水电',
      'feeRoom': feeRoom,
      'feeLines': feeLines.length > 0 ? feeLines : '尚未获取水电数据',
      'feeUpdatedText': feeUpdated,
      'updatedText': updated
    };
    return formBindingData.createFormBindingData(data);
  }

  /** 从 onAddForm 的 Want 里取 formId（系统分配，用于后续 updateForm）。 */
  static formId(want: Want): string {
    return CardData.param(want, 'ohos.extra.param.key.form_identity');
  }

  /** 卡片名称（schedule_card / todo_card）。 */
  static formName(want: Want): string {
    return CardData.param(want, 'ohos.extra.param.key.form_name');
  }

  private static param(want: Want, key: string): string {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return '';
    }
    const value: Object | undefined = params[key];
    return typeof value === 'string' ? value as string : '';
  }

  /** 主动刷新所有已登记的卡片；卡片被删除后 updateForm 会失败，忽略即可。 */
  static async updateAll(context: common.Context): Promise<void> {
    const data: formBindingData.FormBindingData = CardData.build(context);
    const ids: string[] = [];
    for (const id of CardStore.formIds(context, CardStore.KEY_FORM_SCHEDULE)) {
      ids.push(id);
    }
    for (const id of CardStore.formIds(context, CardStore.KEY_FORM_TODO)) {
      if (ids.indexOf(id) < 0) {
        ids.push(id);
      }
    }
    for (const id of CardStore.formIds(context, CardStore.KEY_FORM_FEE)) {
      if (ids.indexOf(id) < 0) {
        ids.push(id);
      }
    }
    for (const formId of ids) {
      try {
        await formProvider.updateForm(formId, data);
        hilog.info(DOMAIN, TAG, 'updateForm ok: %{public}s', formId);
      } catch (err) {
        const e = err as BusinessError;
        hilog.warn(DOMAIN, TAG, 'updateForm %{public}s failed: %{public}d %{public}s',
          formId, e.code, e.message);
      }
    }
    // 桌面卡片刷新完，顺手把同一份数据推给手表（没有配对设备时静默失败）。
    WatchSync.push(context);
  }
}
