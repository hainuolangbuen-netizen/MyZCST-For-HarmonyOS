import { common } from '@kit.AbilityKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardStore } from './CardStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-watchsync';
/**
 * 与手表端 EntryAbility 共用的事件名。
 * 两边各写一份常量而不是抽公共包，是为了让手表模块完全不依赖手机模块
 * （手表产品单独打包时不必把 entry 编进去）。
 */
const EVENT_SYNC: string = 'com.zcst.myzcst.WATCH_SYNC';

/**
 * 手机 → 手表的数据推送。
 *
 * 手表没有登录态（没有能舒服输密码的场景，也不该把 Cookie 放到第二台设备），
 * 所以课表与水电由手机同步完成后推给手表：
 *
 *   1. 从 CardStore 取出与桌面卡片同构的字段；
 *   2. 组装成一份 JSON（键名与手表端 WatchPrefs 完全一致）；
 *   3. publish 一个公共事件。同一台设备上装了两端时手表直接收到；
 *      Wear Engine 可用时由它的跨端通道转发到手表设备。
 *
 * 推送是"尽力而为"的：失败只记日志，不影响手机端的同步结果。
 */
export class WatchSync {
  /** 把当前卡片数据推给手表。 */
  static push(context: common.Context): boolean {
    return WatchSync.pushSync(context);
  }

  /** 组装 payload。字段与 `wearable/common/WatchSync.ets` 的读取键一对应。 */
  static buildPayload(context: common.Context): string {
    const data: Record<string, string> = {
      'schedule_text': CardStore.getSync(context, CardStore.KEY_SCHEDULE),
      'subtitle_text': CardStore.getSync(context, CardStore.KEY_SUBTITLE),
      'updated_text': CardStore.getSync(context, CardStore.KEY_UPDATED),
      'fee_room': CardStore.getSync(context, CardStore.KEY_FEE_ROOM),
      'fee_lines': CardStore.getSync(context, CardStore.KEY_FEE_LINES),
      'fee_updated_text': CardStore.getSync(context, CardStore.KEY_FEE_UPDATED)
    };
    return JSON.stringify(data);
  }

  private static publish(payload: string): boolean {
    if (payload.length === 0) {
      return false;
    }
    const options: commonEventManager.CommonEventPublishData = {
      data: payload,
      code: 0
    };
    // 用回调形式：SDK 里 publish 只有 callback 重载，没有 Promise 版本。
    // 回调里不能再 await，所以这里同步返回"已发出"，真实结果写日志。
    try {
      commonEventManager.publish(EVENT_SYNC, options, (err: BusinessError) => {
        if (err) {
          hilog.warn(DOMAIN, TAG, 'publish failed: %{public}d', err.code);
        } else {
          hilog.info(DOMAIN, TAG, 'publish %{public}d bytes', payload.length);
        }
      });
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'publish exception');
      return false;
    }
  }

  static pushSync(context: common.Context): boolean {
    return WatchSync.publish(WatchSync.buildPayload(context));
  }
}