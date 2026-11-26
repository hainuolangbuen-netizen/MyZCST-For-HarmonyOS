import { common } from '@kit.AbilityKit';
import { WatchPrefs } from './WatchPrefs';

/** Wear Engine 的 payload 根字段名，与手机端 WatchSync 内保持一致。 */
const KEY_SCHEDULE: string = 'schedule_text';
const KEY_SUBTITLE: string = 'subtitle_text';
const KEY_UPDATED: string = 'updated_text';
const KEY_FEE_ROOM: string = 'fee_room';
const KEY_FEE_LINES: string = 'fee_lines';
const KEY_FEE_UPDATED: string = 'fee_updated_text';

/**
 * 手机 → 手表的数据落盘。
 *
 * 手表自己不登录、不联网拉学校接口：学校的接口要 CAS 会话，而手表上没有输入
 * 密码的合适场景。数据流是：
 *
 *   手机（已登录）同步课程/水电 → 组装一份与桌面卡片同构的 JSON
 *     → 通过 Wear Engine `sendMessage` 发给手表
 *     → 手表 EntryAbility.onCreate 里注册的监听收到 → 写进 WatchPrefs → 页面刷新
 *
 * 这样做的好处：手表端没有账号密码、没有 Cookie，丢了也只是少一份课表；
 * 手机没同步过时手表显示「等待手机同步」。
 */
export class WatchSync {
  /** 把一条消息写进首选项。返回是否有变化。 */
  static apply(context: common.Context, payload: string): boolean {
    if (payload.length === 0) {
      return false;
    }
    let parsed: Record<string, Object> | null = null;
    try {
      parsed = JSON.parse(payload) as Record<string, Object>;
    } catch (err) {
      return false;
    }
    if (parsed === null) {
      return false;
    }
    const rec: Record<string, Object> = parsed as Record<string, Object>;
    WatchPrefs.init(context);
    const fields: string[] = [
      KEY_SCHEDULE, KEY_SUBTITLE, KEY_UPDATED,
      KEY_FEE_ROOM, KEY_FEE_LINES, KEY_FEE_UPDATED
    ];
    let changed: boolean = false;
    for (const key of fields) {
      const raw: Object | undefined = rec[key];
      if (raw === undefined || typeof raw !== 'string') {
        continue;
      }
      const value: string = raw as string;
      if (WatchPrefs.str(key, '') !== value) {
        WatchPrefs.putStr(key, value);
        changed = true;
      }
    }
    return changed;
  }

  static scheduleText(): string {
    return WatchPrefs.str(KEY_SCHEDULE, '');
  }

  static subtitle(): string {
    return WatchPrefs.str(KEY_SUBTITLE, '');
  }

  static updated(): string {
    return WatchPrefs.str(KEY_UPDATED, '');
  }

  static feeRoom(): string {
    return WatchPrefs.str(KEY_FEE_ROOM, '');
  }

  static feeLines(): string {
    return WatchPrefs.str(KEY_FEE_LINES, '');
  }

  static feeUpdated(): string {
    return WatchPrefs.str(KEY_FEE_UPDATED, '');
  }
}