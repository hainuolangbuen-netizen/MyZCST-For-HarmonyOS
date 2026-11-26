import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'myzcst_watch';

/**
 * 手表端首选项。
 *
 * 手表与手机是两台设备，沙箱不互通，所以这里读的是「手机通过
 * Wear Engine 发过来并落盘」的那份快照，键名与手机端 CardStore 保持一致，
 * 方便两边对同一份 payload 用同一套解析逻辑。
 */
export class WatchPrefs {
  private static store: preferences.Preferences | null = null;

  static init(context: common.Context): void {
    if (WatchPrefs.store === null) {
      const options: preferences.Options = { name: STORE_NAME };
      WatchPrefs.store = preferences.getPreferencesSync(context, options);
    }
  }

  private static get(): preferences.Preferences {
    if (WatchPrefs.store === null) {
      throw new Error('WatchPrefs not initialized');
    }
    return WatchPrefs.store;
  }

  static str(key: string, def: string): string {
    const v: preferences.ValueType = WatchPrefs.get().getSync(key, def);
    return typeof v === 'string' ? v as string : def;
  }

  static putStr(key: string, value: string): void {
    WatchPrefs.get().putSync(key, value);
    WatchPrefs.get().flushSync();
  }

  static clear(): void {
    WatchPrefs.putStr('schedule_text', '');
    WatchPrefs.putStr('fee_lines', '');
    WatchPrefs.putStr('fee_room', '');
    WatchPrefs.putStr('updated_text', '');
    WatchPrefs.putStr('fee_updated_text', '');
    WatchPrefs.putStr('subtitle_text', '');
  }
}