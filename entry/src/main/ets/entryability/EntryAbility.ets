import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { Session } from '../common/Session';
import { AppSettings } from '../common/AppSettings';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    // 把上次登录的用户名从 preferences 回填到 AppStorage，
    // 页面用 @StorageProp('userName') 订阅，冷启动后也能显示登录态。
    Session.restore(this.context);
    // 把「深色模式 / 沉浸光感强度」两项设置读进 AppStorage，
    // 页面用 @StorageProp 订阅；真正切换明暗在 loadContent 之后做。
    AppSettings.publish(this.context);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    // 沉浸式：让内容延伸到状态栏 / 导航条之下，由页面自行留出安全区。
    // 沉浸光感（ImmersiveMaterial）要求组件与系统 UI 重叠才有意义。
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        const avoid: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        AppStorage.setOrCreate<number>('topAvoidPx', avoid.topRect.height);
        AppStorage.setOrCreate<number>('bottomAvoidPx', avoid.bottomRect.height);
        hilog.info(DOMAIN, TAG, 'avoid top=%{public}d bottom=%{public}d',
          avoid.topRect.height, avoid.bottomRect.height);
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', JSON.stringify(err));
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'window setup failed: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'Succeeded in loading the content.');
      // UIAbilityContext.setColorMode 官方要求页面已加载，所以放在这里。
      AppSettings.applyTheme(this.context);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
