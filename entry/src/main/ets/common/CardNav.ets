import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-card-nav';
/** AppStorage 键：桌面卡片点击后希望主应用打开的页面（schedule / todo）。 */
export const KEY_CARD_TARGET: string = 'cardTarget';

/**
 * 桌面卡片的点击路由。
 *
 * 卡片里的 `postCardAction({ action: 'router', abilityName: 'EntryAbility',
 * params: { target: 'schedule' | 'todo' } })` 只会把 Want 交给 EntryAbility，
 * 主应用原来没有消费这个参数，所以点击卡片只是"打开 App"，并没有进到对应页面。
 *
 * 这里把 target 暂存到 AppStorage：EntryAbility（冷启动 onCreate / 热启动
 * onNewWant）写入，Index 用 @StorageProp + @Watch 消费并真正 push 页面。
 */
export class CardNav {
  /** 从 Want 里取出 target 并写入 AppStorage；没有则忽略。 */
  static capture(want: Want): void {
    // 先保证键存在：Index 的 @StorageProp 需要 AppStorage 里已有同名键才能订阅到后续变化。
    const current: string | undefined = AppStorage.get<string>(KEY_CARD_TARGET);
    if (current === undefined) {
      AppStorage.setOrCreate<string>(KEY_CARD_TARGET, '');
    }
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return;
    }
    const target: Object | undefined = params['target'];
    if (typeof target !== 'string') {
      return;
    }
    const value: string = target as string;
    if (value.length === 0) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'card target -> %{public}s', value);
    AppStorage.setOrCreate<string>(KEY_CARD_TARGET, value);
  }

  /** 读取并清空待处理 target，避免重复跳转。 */
  static take(): string {
    const value: string | undefined = AppStorage.get<string>(KEY_CARD_TARGET);
    if (value === undefined || value.length === 0) {
      return '';
    }
    AppStorage.setOrCreate<string>(KEY_CARD_TARGET, '');
    return value;
  }
}
