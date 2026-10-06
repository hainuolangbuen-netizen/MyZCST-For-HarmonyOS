import { common } from '@kit.AbilityKit';
import {
  AppSettings,
  GLASS_STANDARD,
  GLASS_STRONG,
  GLASS_THIN,
  THEME_DARK,
  THEME_LIGHT,
  THEME_SYSTEM
} from '../common/AppSettings';
import { MaterialGate } from '../common/MaterialGate';
import { Ui } from '../common/Ui';

/**
 * 单选项。
 *
 * 注意：这里必须做成独立的 @Component，**不能用带参数的 @Builder** ——
 * @Builder 的参数是按值传入的，父组件状态变化时不会重新执行 builder，
 * 实测表现为"点了「浅色」页面确实变浅了，但 ✓ 还留在「深色」上"。
 * @Prop 才是能跟着父组件状态刷新的通道。
 */
@Component
struct OptionRow {
  @Prop title: string = '';
  @Prop hint: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(16)
          .fontColor(this.selected ? $r('app.color.brand_blue') : $r('app.color.text_primary'))
        Text(this.hint)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.selected) {
        Text('✓')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand_blue'))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      this.onTap();
    })
  }
}

/**
 * 设置页：外观两项。
 *
 *   深色模式   —— 跟随系统 / 浅色 / 深色，立即调用 UIAbilityContext.setColorMode，
 *                 取色走 resources/dark/element/color.json。
 *   沉浸光感   —— 轻 / 标准 / 强，改变底部悬浮页签的 ImmersiveStyle 与底色。
 *
 * 两项都写在 AppStorage 里（AppSettings.setXxx 负责持久化 + 广播），
 * 所以这页用 @StorageLink 就能即时回显，返回后其它页也已经是新值。
 */
@Entry
@Component
struct SettingsPage {
  @StorageProp('topAvoidPx') topAvoidPx: number = 0;
  @StorageLink('themeMode') themeMode: string = THEME_SYSTEM;
  @StorageLink('glassLevel') glassLevel: string = GLASS_STANDARD;

  private themeOptions: string[] = [THEME_SYSTEM, THEME_LIGHT, THEME_DARK];
  private glassOptions: string[] = [GLASS_THIN, GLASS_STANDARD, GLASS_STRONG];

  private topPad(): number {
    return this.getUIContext().px2vp(this.topAvoidPx);
  }

  private hostContext(): common.Context | undefined {
    return Ui.context(this.getUIContext());
  }

  private themeHint(mode: string): string {
    if (mode === THEME_LIGHT) {
      return '始终使用浅色';
    }
    if (mode === THEME_DARK) {
      return '始终使用深色';
    }
    return '随系统的深色模式自动切换';
  }

  private glassHint(level: string): string {
    if (level === GLASS_THIN) {
      return '最通透，文字自动取背景补色';
    }
    if (level === GLASS_STRONG) {
      return '模糊最重，观感最厚重';
    }
    return '默认档，通透与模糊兼顾';
  }

  private pickTheme(mode: string): void {
    const ctx: common.Context | undefined = this.hostContext();
    if (ctx === undefined) {
      this.themeMode = mode;
      return;
    }
    AppSettings.setTheme(ctx, mode);
  }

  private pickGlass(level: string): void {
    const ctx: common.Context | undefined = this.hostContext();
    if (ctx === undefined) {
      this.glassLevel = level;
      return;
    }
    AppSettings.setGlass(ctx, level);
  }

  private glassNote(): string {
    if (!MaterialGate.supported()) {
      return '当前设备不支持沉浸光感（uiMaterial.isImmersiveMaterialSupported 返回 false），此设置不会生效。';
    }
    const level: number = MaterialGate.level();
    const levelText: string = level === 0 ? '高' : (level === 1 ? '中' : '低');
    return '沉浸光感作用在底部悬浮页签上：材质会拾取页签背后的内容与光线。'
      + '本机算力档位为「' + levelText + '」。';
  }

  @Builder
  topBar() {
    Row() {
      Text('‹ 返回')
        .fontSize(16)
        .fontColor($r('app.color.brand_blue'))
        .onClick(() => {
          Ui.back(this.getUIContext());
        })
      Blank()
      Text('设置')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text('返回')
        .fontSize(16)
        .fontColor(Color.Transparent)
    }
    .width('100%')
    .height(48 + this.topPad())
    .padding({ left: 16, right: 16, top: this.topPad() })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.page_bg'))
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .margin({ left: 28, top: 18, bottom: 8 })
      .width('100%')
  }

  build() {
    Column() {
      this.topBar()

      Scroll() {
        Column() {
          this.sectionTitle('深色模式')
          Column() {
            ForEach(this.themeOptions, (mode: string, index: number) => {
              OptionRow({
                title: AppSettings.themeLabel(mode),
                hint: this.themeHint(mode),
                selected: this.themeMode === mode,
                onTap: () => {
                  this.pickTheme(mode);
                }
              })
              if (index < this.themeOptions.length - 1) {
                Divider()
                  .strokeWidth(0.5)
                  .color($r('app.color.divider'))
                  .margin({ left: 16 })
              }
            }, (mode: string) => 'theme_' + mode)
          }
          .width('100%')
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(16)
          .margin({ left: 12, right: 12 })
          .clip(true)

          this.sectionTitle('沉浸光感')
          Column() {
            ForEach(this.glassOptions, (level: string, index: number) => {
              OptionRow({
                title: AppSettings.glassLabel(level),
                hint: this.glassHint(level),
                selected: this.glassLevel === level,
                onTap: () => {
                  this.pickGlass(level);
                }
              })
              if (index < this.glassOptions.length - 1) {
                Divider()
                  .strokeWidth(0.5)
                  .color($r('app.color.divider'))
                  .margin({ left: 16 })
              }
            }, (level: string) => 'glass_' + level)
          }
          .width('100%')
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(16)
          .margin({ left: 12, right: 12 })
          .clip(true)

          Text(this.glassNote())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 28, right: 28, top: 10 })
            .lineHeight(18)

          // 给底部留白
          Row().height(40)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
