import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardStore } from './CardStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst-set';

/** 深色模式：跟随系统 / 浅色 / 深色。 */
export const THEME_SYSTEM: string = 'system';
export const THEME_LIGHT: string = 'light';
export const THEME_DARK: string = 'dark';

/** 沉浸光感强度：轻 / 标准 / 强。 */
export const GLASS_THIN: string = 'thin';
export const GLASS_STANDARD: string = 'standard';
export const GLASS_STRONG: string = 'strong';

/**
 * 应用偏好设置（持久化在 CardStore 的 preferences 里）。
 *
 * 目前两项：
 *   1. 深色模式 —— 靠 @ohos.app.ability.ConfigurationConstant.ColorMode 切换，
 *      真正取色的是 resources/dark/element/color.json（同名资源覆盖 base）。
 *   2. 沉浸光感强度 —— 交给 MaterialGate 决定用哪种 ImmersiveStyle。
 *
 * 明暗切换用的是 **UIAbilityContext.setColorMode**（@since 18，
 * application/UIAbilityContext.d.ts:1253）。优先级是
 * UIAbility > ApplicationContext > 系统，取最高那档就只用它。
 * 官方约束：**必须在 windowStage.loadContent 之后再调**，否则抛 16000011，
 * 所以冷启动时在 EntryAbility 的 loadContent 回调里应用一次，用户在设置页
 * 改动时再立即应用一次（那时页面早已加载完成）。
 */
export class AppSettings {
  /** preferences 键名：深色模式。 */
  static readonly KEY_THEME: string = 'theme_mode';
  /** preferences 键名：沉浸光感强度。 */
  static readonly KEY_GLASS: string = 'glass_strength';

  static theme(context: common.Context): string {
    const v: string = CardStore.getSync(context, AppSettings.KEY_THEME);
    if (v === THEME_LIGHT || v === THEME_DARK) {
      return v;
    }
    return THEME_SYSTEM;
  }

  static glass(context: common.Context): string {
    const v: string = CardStore.getSync(context, AppSettings.KEY_GLASS);
    if (v === GLASS_THIN || v === GLASS_STRONG) {
      return v;
    }
    return GLASS_STANDARD;
  }

  static themeLabel(mode: string): string {
    if (mode === THEME_LIGHT) {
      return '浅色';
    }
    if (mode === THEME_DARK) {
      return '深色';
    }
    return '跟随系统';
  }

  static glassLabel(level: string): string {
    if (level === GLASS_THIN) {
      return '轻';
    }
    if (level === GLASS_STRONG) {
      return '强';
    }
    return '标准';
  }

  /** 冷启动时把两项设置读进 AppStorage，页面用 @StorageProp / @StorageLink 订阅。 */
  static publish(context: common.Context): void {
    AppStorage.setOrCreate<string>('themeMode', AppSettings.theme(context));
    AppStorage.setOrCreate<string>('glassLevel', AppSettings.glass(context));
  }

  static setTheme(context: common.Context, mode: string): void {
    AppStorage.setOrCreate<string>('themeMode', mode);
    CardStore.put(context, AppSettings.KEY_THEME, mode);
    // 注意：CardStore.put 是异步的，这里不能再用 AppSettings.theme(context) 回读
    // （preferences 还没落盘，会读到旧值），必须直接把用户选的那档传下去。
    AppSettings.applyMode(context, mode);
  }

  static setGlass(context: common.Context, level: string): void {
    AppStorage.setOrCreate<string>('glassLevel', level);
    CardStore.put(context, AppSettings.KEY_GLASS, level);
  }

  static colorMode(mode: string): ConfigurationConstant.ColorMode {
    if (mode === THEME_DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    if (mode === THEME_LIGHT) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }

  /** 立即应用明暗模式。调用方保证页面已经加载完成。 */
  static applyTheme(context: common.Context): void {
    AppSettings.applyMode(context, AppSettings.theme(context));
  }

  /** 按指定档位切换明暗（不读存储，给"用户刚点完"的场合用）。 */
  static applyMode(context: common.Context, mode: string): void {
    try {
      const ability: common.UIAbilityContext = context as common.UIAbilityContext;
      ability.setColorMode(AppSettings.colorMode(mode));
      hilog.info(DOMAIN, TAG, 'setColorMode(%{public}s) ok', mode);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setColorMode(%{public}s) failed: %{public}s',
        mode, JSON.stringify(err));
    }
  }
}
