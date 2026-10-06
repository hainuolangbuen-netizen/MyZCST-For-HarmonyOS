import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CardStore } from '../common/CardStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-form';

/**
 * 卡片（小组件）提供方。
 *
 * 卡片渲染服务负责画，桌面负责显示，我们只负责在 onAddForm / onUpdateForm 时
 * 把数据塞进 formBindingData。数据来自 CardStore（preferences），
 * 由主 App 在用户登录并成功拉取门户接口后写入。
 *
 * form_config.json 里两张卡片都开了 updateEnabled，updateDuration=1
 * 表示每 30 分钟由系统回调一次 onUpdateForm。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  private buildBindingData(): formBindingData.FormBindingData {
    const context = this.context;
    const schedule: string = CardStore.getSync(context, CardStore.KEY_SCHEDULE);
    const todo: string = CardStore.getSync(context, CardStore.KEY_TODO);
    const updated: string = CardStore.getSync(context, CardStore.KEY_UPDATED);

    const data: Record<string, string> = {
      'scheduleTitle': '今日课表',
      'scheduleLines': schedule.length > 0 ? schedule : '打开「我的珠科」并登录后自动同步',
      'todoTitle': '我的待办',
      'todoLines': todo.length > 0 ? todo : '打开「我的珠科」并登录后自动同步',
      'updatedText': updated
    };
    return formBindingData.createFormBindingData(data);
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onAddForm');
    return this.buildBindingData();
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onCastToNormalForm %{public}s', formId);
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm %{public}s', formId);
    formProvider.updateForm(formId, this.buildBindingData()).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'updateForm failed: %{public}s', JSON.stringify(err));
    });
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    hilog.info(DOMAIN, TAG, 'onChangeFormVisibility %{public}s', JSON.stringify(newStatus));
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'onFormEvent %{public}s %{public}s', formId, message);
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm %{public}s', formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
