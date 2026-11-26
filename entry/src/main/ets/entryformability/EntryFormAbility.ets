import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CardData } from '../common/CardData';
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
 *
 * 另外在 onAddForm 里登记 formId：主 App 登录后同步完课程时，用 formId 主动
 * updateForm，卡片无需等 30 分钟就能显示当天课程。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    // onAddForm 必须同步返回且不能抛异常，否则卡片添加会失败；任何 preferences
    // 读写的异常都在这里兜住，退回一份占位数据保证卡片一定能创建出来。
    try {
      const formId: string = CardData.formId(want);
      const formName: string = CardData.formName(want);
      const key: string = formName === 'todo_card'
        ? CardStore.KEY_FORM_TODO
        : CardStore.KEY_FORM_SCHEDULE;
      CardStore.appendFormId(this.context, key, formId);
      hilog.info(DOMAIN, TAG, 'onAddForm name=%{public}s id=%{public}s', formName, formId);
      return CardData.build(this.context);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'onAddForm fallback: %{public}s', JSON.stringify(err));
      const data: Record<string, string> = {
        'scheduleTitle': '今日课程',
        'scheduleLines': '打开「我的珠科」并登录后自动同步',
        'todoTitle': '我的待办',
        'todoLines': '打开「我的珠科」并登录后自动同步',
        'updatedText': ''
      };
      return formBindingData.createFormBindingData(data);
    }
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onCastToNormalForm %{public}s', formId);
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm %{public}s', formId);
    formProvider.updateForm(formId, CardData.build(this.context)).catch((err: BusinessError) => {
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
    CardStore.removeFormId(this.context, formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
