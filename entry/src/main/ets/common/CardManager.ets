import { common, Want } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { formInfo, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Ui } from './Ui';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-cardmgr';

/** 与 AppScope/app.json5、module.json5 保持一致。 */
const BUNDLE_NAME: string = 'com.zcst.myzcst';
const MODULE_NAME: string = 'entry';
const FORM_ABILITY: string = 'EntryFormAbility';
const SCHEDULE_FORM: string = 'schedule_card';
const TODO_FORM: string = 'todo_card';
const FEE_FORM: string = 'fee_card';

/**
 * 卡片管理入口。
 *
 * 鸿蒙不允许应用直接往桌面「钉」卡片（没有 requestPinForm 这类 API），
 * 官方给应用提供的是 `formProvider.openFormManager(want)`：拉起系统的
 * 「卡片管理」页，用户在那里选尺寸并添加到桌面。之前「我的卡片 → 管理」
 * 没有任何动作，所以用户反馈"创建课表卡片功能失效"；这里接上系统入口。
 */
export class CardManager {
  /** 打开「今日课程」的卡片管理页。 */
  static openScheduleManager(ui: UIContext): void {
    CardManager.openManager(ui, SCHEDULE_FORM, '今日课程', formInfo.FormDimension.Dimension_2_4);
  }

  /** 打开「我的待办」的卡片管理页。 */
  static openTodoManager(ui: UIContext): void {
    CardManager.openManager(ui, TODO_FORM, '我的待办', formInfo.FormDimension.Dimension_2_4);
  }

  /** 打开「宿舍水电」的卡片管理页。 */
  static openFeeManager(ui: UIContext): void {
    CardManager.openManager(ui, FEE_FORM, '智能水电', formInfo.FormDimension.Dimension_2_2);
  }

  private static openManager(ui: UIContext, formName: string, label: string,
    dimension: formInfo.FormDimension): void {
    // bundleName 优先从运行上下文取，避免以后改包名后这里忘记同步。
    const ctx: common.UIAbilityContext | undefined =
      Ui.context(ui) as common.UIAbilityContext | undefined;
    const bundleName: string = ctx === undefined ? BUNDLE_NAME : ctx.applicationInfo.name;
    const want: Want = {
      bundleName: bundleName,
      abilityName: FORM_ABILITY,
      parameters: {
        'ohos.extra.param.key.form_dimension': dimension,
        'ohos.extra.param.key.form_name': formName,
        'ohos.extra.param.key.module_name': MODULE_NAME
      }
    };
    try {
      formProvider.openFormManager(want);
      Ui.toast(ui, '请在卡片管理页添加「' + label + '」');
      hilog.info(DOMAIN, TAG, 'openFormManager requested for %{public}s', formName);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'openFormManager failed: %{public}d %{public}s', e.code, e.message);
      // 系统不支持时给出可执行的替代路径，避免用户点了没反应。
      Ui.toast(ui, '请长按桌面/应用图标 → 服务卡片 → ' + label);
    }
  }
}
