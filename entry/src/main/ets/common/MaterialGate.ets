import { uiMaterial } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GLASS_STRONG, GLASS_THIN } from './AppSettings';

const DOMAIN: number = 0x0000;
const TAG: string = 'myzcst';

/**
 * 沉浸光感（uiMaterial）能力的统一入口。
 *
 * 分支选择：本机 SDK 是 HarmonyOS 26.0.0（apiVersion 26），对应的是
 * `@kit.ArkUI` 里的 `uiMaterial` 命名空间。网上 HDS 分支的
 * `@kit.UIDesignKit` / `hdsMaterial` / `HdsNavigation` 在本机 SDK 里**不存在**，
 * 照抄会编译不过。
 *
 * 生效条件（四个变量相乘）：
 *   1. 系统档位 + 2. 设备算力（getGlobalMaterialLevel）+ 3. 应用开关
 *   （module.json5 里 metadata 的 `ohos.arkui.UIMaterial.state` = enable）
 *   + 4. 组件参数（本文这两个工厂方法）。
 *
 * 组件级入口有两种，别搞混：
 *   - 专用属性：Navigation.title 的 systemMaterial、Tabs 的
 *     FloatingTabBarStyle.systemMaterial —— 语义强、参数定型（页签走这里）。
 *   - 通用属性：CommonMethod.systemMaterial(material)（common.d.ts:22642，
 *     since 26.0.0）—— 任意组件都能挂，Search 之类的走这里。
 *   MaterialState.ENABLE 下材质会**盖过组件自身的 backgroundColor /
 *   backgroundBlurStyle / shadow / border**，所以挂了材质就别指望背景色还起作用。
 */
export class MaterialGate {
  /** 设备是否支持沉浸光感。false 时把 ImmersiveMaterial 传进去也不会有任何效果。 */
  static supported(): boolean {
    try {
      return uiMaterial.isImmersiveMaterialSupported();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'isImmersiveMaterialSupported threw: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /** 设备算力档位：EXQUISITE(0) / GENTLE(1) / SMOOTH(2)。只读，改不了。 */
  static level(): number {
    try {
      return uiMaterial.getGlobalMaterialLevel() as number;
    } catch (err) {
      return -1;
    }
  }

  /** 应用级开关状态：DEFAULT(0) / ENABLE(1) / DISABLE(2)。 */
  static state(): number {
    try {
      return uiMaterial.getMaterialInfo().state as number;
    } catch (err) {
      return -1;
    }
  }

  /**
   * 底部悬浮页签用的沉浸材质，按用户设置的强度分三档：
   *
   *   轻   ULTRA_THIN  #1AFFFFFF  —— 最通透，几乎只剩一点点磨砂，并打开 colorInvert
   *   标准 REGULAR     #33FFFFFF  —— 默认档
   *   强   ULTRA_THICK #59FFFFFF  —— 模糊最重、底色最实
   *
   * colorInvert 是"光感"里最能被感知的一环：它让材质子树里的文字/图标
   * 自动取背景补色（uiMaterial.d.ts:342 的说明），但**只有 THIN / ULTRA_THIN
   * 且应用沉浸光感强度足够时才会触发**，所以放在"轻"档，而不是"强"档
   * —— 强档用 ULTRA_THICK，带上 colorInvert 也不会生效。
   *
   * materialColor 必须带透明度，否则会把背后内容完全挡住，滤镜也就看不出来了。
   * lightEffect 就是"光随指动"的那层高光反馈。
   */
  static tabMaterial(strength: string): uiMaterial.ImmersiveMaterial {
    let style: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.REGULAR;
    // 材质底色按主题取资源：浅色模式用「淡淡的黑」、深色模式用「淡淡的白」，
    // 否则纯白叠在纯白页面上完全看不出来（这正是「感觉光感有点弱」的主因）。
    let color: ResourceColor = $r('app.color.bar_frost_standard');
    let invert: boolean = false;
    if (strength === GLASS_THIN) {
      style = uiMaterial.ImmersiveStyle.ULTRA_THIN;
      color = $r('app.color.bar_frost_thin');
      invert = true;
    } else if (strength === GLASS_STRONG) {
      style = uiMaterial.ImmersiveStyle.ULTRA_THICK;
      color = $r('app.color.bar_frost_strong');
    }
    const light: uiMaterial.LightEffectOptions = { color: '#FFFFFF' };
    const options: uiMaterial.ImmersiveOptions = {
      style: style,
      materialColor: color,
      colorInvert: invert,
      applyShadow: true,
      interactive: true,
      lightEffect: light
    };
    return new uiMaterial.ImmersiveMaterial(options);
  }

  /**
   * 首页搜索框用的沉浸材质。
   * 比页签更薄（THIN）、更透（#26FFFFFF），因为它是叠在轮播图上的一小块，
   * 厚了会把底下那张图糊死。
   *
   * ⚠️ 实测结论（API 26 模拟器）：通用属性 `CommonMethod.systemMaterial`
   *   挂在 Search / Stack 上**编译通过但不产生任何渲染效果** —— 把 materialColor
   *   从 '#26FFFFFF' 换成 '#CCFF0000'（80% 不透明红），整屏像素差 bbox 只有状态栏
   *   时钟那几个字，搜索框区域零差异；去掉 backgroundColor 后胶囊消失但依然不见红色。
   *   真正生效的只有"专用属性"：Tabs 的 FloatingTabBarStyle.systemMaterial（已用
   *   开关 A/B 逐像素证明）、Navigation.title 的 systemMaterial。
   *   所以搜索框的玻璃观感靠 backgroundBlurStyle + 半透明底色兜底，本方法保留是
   *   为了将来系统把通用属性接通后自动生效。
   */
  static searchMaterial(): uiMaterial.ImmersiveMaterial {
    const light: uiMaterial.LightEffectOptions = { color: '#FFFFFF' };
    const options: uiMaterial.ImmersiveOptions = {
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: '#26FFFFFF',
      colorInvert: false,
      applyShadow: true,
      interactive: true,
      lightEffect: light
    };
    return new uiMaterial.ImmersiveMaterial(options);
  }
}
