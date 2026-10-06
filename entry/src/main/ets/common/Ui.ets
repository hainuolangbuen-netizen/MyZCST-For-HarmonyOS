import { UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-ui';

/**
 * UI 辅助层。
 *
 * 模块级的 router / promptAction / getContext 在 API 18 起全部标记 @deprecated
 * （官方 @useinstead 指向 UIContext 上的同名方法）。这里把跳转、参数读取、
 * Toast、Context 获取集中封装一次，页面里不再直接碰那些废弃入口。
 */
export class Ui {
  /** 无参跳转。 */
  static push(ui: UIContext, url: string): void {
    ui.getRouter().pushUrl({ url: url }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'pushUrl %{public}s failed: %{public}s', url, JSON.stringify(err));
    });
  }

  /** 带参跳转。 */
  static pushWith(ui: UIContext, url: string, params: Object): void {
    ui.getRouter().pushUrl({ url: url, params: params }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'pushUrl %{public}s failed: %{public}s', url, JSON.stringify(err));
    });
  }

  static back(ui: UIContext): void {
    try {
      ui.getRouter().back();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'back failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 读取上一页传来的参数；失败返回 undefined。 */
  static params(ui: UIContext): Object | undefined {
    try {
      return ui.getRouter().getParams();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getParams failed: %{public}s', JSON.stringify(err));
      return undefined;
    }
  }

  static toast(ui: UIContext, message: string): void {
    try {
      ui.getPromptAction().showToast({ message: message, duration: 1600 });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'toast failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 取组件所在 Ability 的 Context（替代已废弃的 getContext(this)）。 */
  static context(ui: UIContext): common.Context | undefined {
    try {
      return ui.getHostContext();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getHostContext failed: %{public}s', JSON.stringify(err));
      return undefined;
    }
  }
}
