import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-watch';
/**
 * 手机端发数据用的自定义公共事件。
 * 手机同步完成后 publish，手表在 onCreate 里订阅；两边用同一个字符串，
 * 改名字时 CONTEXT.md 与手机端 WatchSync 要一起改。
 */
const EVENT_SYNC: string = 'com.zcst.myzcst.WATCH_SYNC';

export default class EntryAbility extends UIAbility {
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    this.subscribeSync();
  }

  onDestroy(): void {
    this.unsubscribeSync();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/WatchHome', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
      }
    });
  }

  /**
   * 订阅手机推来的同步事件。
   *
   * 手表上没有输入密码的场景，账号与 Cookie 都不进手表；数据由手机侧
   * 通过公共事件（跨端下发时由 Wear Engine 转发）送过来，这里只负责落盘，
   * 页面在 onPageShow 或收到事件后重新读 WatchPrefs 即可。
   */
  private subscribeSync(): void {
    if (this.subscriber !== null) {
      return;
    }
    try {
      const info: commonEventManager.CommonEventSubscribeInfo = {
        events: [EVENT_SYNC]
      };
      commonEventManager.createSubscriber(info, (err, sub) => {
        if (err) {
          hilog.warn(DOMAIN, TAG, 'createSubscriber failed: %{public}d', err.code);
          return;
        }
        this.subscriber = sub;
        commonEventManager.subscribe(sub, (err2, data) => {
          if (err2) {
            hilog.warn(DOMAIN, TAG, 'subscribe failed: %{public}d', err2.code);
            return;
          }
          const payload: string = data.data === undefined ? '' : data.data;
          hilog.info(DOMAIN, TAG, 'sync event %{public}d bytes', payload.length);
        });
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'subscribe exception');
    }
  }

  private unsubscribeSync(): void {
    if (this.subscriber === null) {
      return;
    }
    try {
      commonEventManager.unsubscribe(this.subscriber);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'unsubscribe failed');
    }
    this.subscriber = null;
  }
}