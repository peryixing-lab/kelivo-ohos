import { CustomTheme, LengthMetrics, promptAction, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial } from '@kit.UIDesignKit';
import { hexWithAlpha, normalizeHexColor } from './ImmersiveUtils';
import { PaletteTokens } from './ThemeManager';

export class ImmersiveMaterialStyle {
  private static api26Cache: boolean | undefined = undefined;
  private static supportedCache: boolean | undefined = undefined;
  private static hdsImmersiveCache: boolean | undefined = undefined;
  private static ultraThinCache: Map<string, uiMaterial.ImmersiveMaterial> =
    new Map<string, uiMaterial.ImmersiveMaterial>();
  private static thinCache: Map<string, uiMaterial.ImmersiveMaterial> =
    new Map<string, uiMaterial.ImmersiveMaterial>();
  private static thickCache?: uiMaterial.ImmersiveMaterial = undefined;
  private static ultraThickCache?: uiMaterial.ImmersiveMaterial = undefined;

  static isApi26Available(): boolean {
    if (ImmersiveMaterialStyle.api26Cache === undefined) {
      let ok = false;
      try {
        if (typeof deviceInfo.apiAvailable === 'function') {
          ok = deviceInfo.apiAvailable('26.0.0');
        } else {
          ok = deviceInfo.sdkApiVersion >= 26;
        }
      } catch (_) {
        ok = false;
      }
      ImmersiveMaterialStyle.api26Cache = ok;
    }
    return ImmersiveMaterialStyle.api26Cache;
  }

  static isSupported(): boolean {
    if (ImmersiveMaterialStyle.supportedCache === undefined) {
      if (!ImmersiveMaterialStyle.isApi26Available()) {
        ImmersiveMaterialStyle.supportedCache = false;
      } else {
        try {
          ImmersiveMaterialStyle.supportedCache = uiMaterial.isImmersiveMaterialSupported();
        } catch (_) {
          ImmersiveMaterialStyle.supportedCache = false;
        }
      }
    }
    return ImmersiveMaterialStyle.supportedCache;
  }

  static hasHdsImmersive(): boolean {
    if (ImmersiveMaterialStyle.hdsImmersiveCache === undefined) {
      try {
        const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
        ImmersiveMaterialStyle.hdsImmersiveCache = types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0;
      } catch (_) {
        ImmersiveMaterialStyle.hdsImmersiveCache = false;
      }
    }
    return ImmersiveMaterialStyle.hdsImmersiveCache;
  }

  static isActive(enabled: boolean): boolean {
    return enabled && ImmersiveMaterialStyle.isSupported();
  }

  static capabilitySummary(): string {
    if (!ImmersiveMaterialStyle.isApi26Available()) {
      const hdsTag = ImmersiveMaterialStyle.hasHdsImmersive() ? '（支持 HDS 23+）' : '';
      return `当前运行 API < 26.0.0${hdsTag}，已自动启用标准清晰模糊降级`;
    }
    if (!ImmersiveMaterialStyle.isSupported()) {
      return '当前设备不支持 ImmersiveMaterial，已使用标准主题实体背景';
    }
    try {
      const lvl = uiMaterial.getGlobalMaterialLevel();
      const info = uiMaterial.getMaterialInfo();
      const tier = lvl === uiMaterial.MaterialLevel.EXQUISITE
        ? '高算力(EXQUISITE)'
        : (lvl === uiMaterial.MaterialLevel.GENTLE ? '中算力(GENTLE)' : '低算力自适应(SMOOTH)');
      const stateLabel = info.state === uiMaterial.MaterialState.ENABLE
        ? 'ENABLE'
        : (info.state === uiMaterial.MaterialState.DISABLE ? 'DISABLE' : 'DEFAULT');
      return `已就绪 · ${tier} · 状态 ${stateLabel}`;
    } catch (_) {
      return 'API 26.0.0 沉浸光感已就绪';
    }
  }

  private static thickMaterial(): uiMaterial.ImmersiveMaterial {
    if (!ImmersiveMaterialStyle.thickCache) {
      ImmersiveMaterialStyle.thickCache = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THICK,
        applyShadow: true
      });
    }
    return ImmersiveMaterialStyle.thickCache;
  }

  private static ultraThickMaterial(): uiMaterial.ImmersiveMaterial {
    if (!ImmersiveMaterialStyle.ultraThickCache) {
      ImmersiveMaterialStyle.ultraThickCache = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THICK,
        applyShadow: true
      });
    }
    return ImmersiveMaterialStyle.ultraThickCache;
  }

  private static cachedUltraThin(tint: string, lightHex: string, invert: boolean): uiMaterial.ImmersiveMaterial {
    const key = `${tint}_${lightHex}_${invert ? '1' : '0'}`;
    const existing = ImmersiveMaterialStyle.ultraThinCache.get(key);
    if (existing !== undefined) {
      return existing;
    }
    if (ImmersiveMaterialStyle.ultraThinCache.size >= 24) {
      ImmersiveMaterialStyle.ultraThinCache.clear();
    }
    const created = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: tint,
      colorInvert: invert,
      interactive: true,
      applyShadow: false,
      lightEffect: { color: lightHex }
    });
    ImmersiveMaterialStyle.ultraThinCache.set(key, created);
    return created;
  }

  private static cachedThin(tint: string, lightHex: string, invert: boolean): uiMaterial.ImmersiveMaterial {
    const key = `${tint}_${lightHex}_${invert ? '1' : '0'}`;
    const existing = ImmersiveMaterialStyle.thinCache.get(key);
    if (existing !== undefined) {
      return existing;
    }
    if (ImmersiveMaterialStyle.thinCache.size >= 24) {
      ImmersiveMaterialStyle.thinCache.clear();
    }
    const created = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: tint,
      colorInvert: invert,
      interactive: false,
      applyShadow: true,
      lightEffect: { color: lightHex }
    });
    ImmersiveMaterialStyle.thinCache.set(key, created);
    return created;
  }

  static composerBackground(fallbackColor: ResourceColor, enabled: boolean): ResourceColor {
    if (ImmersiveMaterialStyle.isActive(enabled)) {
      return Color.Transparent;
    }
    return fallbackColor;
  }

  static sheetCardBackground(
    enabled: boolean,
    fallbackColor: ResourceColor = $r('app.color.panel')
  ): ResourceColor {
    if (ImmersiveMaterialStyle.isActive(enabled)) {
      return $r('sys.color.comp_background_tertiary');
    }
    return fallbackColor;
  }

  static composerMaterial(
    palette: PaletteTokens,
    isDark: boolean,
    enabled: boolean
  ): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialStyle.isApi26Available()) {
      return undefined;
    }
    if (!enabled || !ImmersiveMaterialStyle.isSupported()) {
      return uiMaterial.Material.empty;
    }
    const tint = hexWithAlpha(palette.surface, isDark ? '88' : '4A');
    const lightHex = normalizeHexColor(palette.accent, '#2563EB');
    return ImmersiveMaterialStyle.cachedThin(tint, lightHex, true);
  }

  static titleButtonBackground(palette: PaletteTokens, enabled: boolean, active: boolean = false): ResourceColor {
    if (ImmersiveMaterialStyle.isActive(enabled)) {
      return Color.Transparent;
    }
    return active ? palette.tint : palette.surface;
  }

  static titleButtonMaterial(
    palette: PaletteTokens,
    isDark: boolean,
    enabled: boolean,
    active: boolean = false
  ): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialStyle.isApi26Available()) {
      return undefined;
    }
    if (!enabled || !ImmersiveMaterialStyle.isSupported()) {
      return uiMaterial.Material.empty;
    }
    const baseHex = active ? palette.accent : palette.surface;
    const tint = hexWithAlpha(baseHex, active ? (isDark ? 'B0' : '42') : (isDark ? '96' : '58'));
    const lightHex = normalizeHexColor(palette.accent, '#2563EB');
    return ImmersiveMaterialStyle.cachedUltraThin(tint, lightHex, !active);
  }

  static titlePillMaterial(
    palette: PaletteTokens,
    isDark: boolean,
    enabled: boolean
  ): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialStyle.isApi26Available()) {
      return undefined;
    }
    if (!enabled || !ImmersiveMaterialStyle.isSupported()) {
      return uiMaterial.Material.empty;
    }
    const tint = hexWithAlpha(palette.surface, isDark ? '8C' : '52');
    const lightHex = normalizeHexColor(palette.accent, '#2563EB');
    return ImmersiveMaterialStyle.cachedUltraThin(tint, lightHex, true);
  }

  static controlMaterial(enabled: boolean): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialStyle.isApi26Available()) {
      return undefined;
    }
    if (!enabled || !ImmersiveMaterialStyle.isSupported()) {
      return uiMaterial.Material.empty;
    }
    return undefined;
  }

  static selectMenuMaterial(enabled: boolean): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialStyle.isApi26Available()) {
      return undefined;
    }
    if (!enabled || !ImmersiveMaterialStyle.isSupported()) {
      return uiMaterial.Material.empty;
    }
    return ImmersiveMaterialStyle.thickMaterial();
  }

  static alertDialogMaterial(enabled: boolean): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialStyle.isApi26Available()) {
      return undefined;
    }
    if (!enabled || !ImmersiveMaterialStyle.isSupported()) {
      return uiMaterial.Material.empty;
    }
    return ImmersiveMaterialStyle.ultraThickMaterial();
  }

  static headerActionBackground(
    surfaceHex: string,
    tintHex: string,
    enabled: boolean,
    active: boolean = false
  ): ResourceColor {
    if (ImmersiveMaterialStyle.isActive(enabled)) {
      return Color.Transparent;
    }
    return active ? normalizeHexColor(tintHex, '#DCE1FF') : normalizeHexColor(surfaceHex, '#FFFFFF');
  }

  static headerActionMaterial(
    surfaceHex: string,
    accentHex: string,
    isDark: boolean,
    enabled: boolean,
    active: boolean = false
  ): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialStyle.isApi26Available()) {
      return undefined;
    }
    if (!enabled || !ImmersiveMaterialStyle.isSupported()) {
      return uiMaterial.Material.empty;
    }
    const baseHex = active ? normalizeHexColor(accentHex, '#4D5C92') : normalizeHexColor(surfaceHex, '#FFFFFF');
    const tint = hexWithAlpha(baseHex, active ? (isDark ? 'B0' : '42') : (isDark ? '96' : '58'));
    const lightHex = normalizeHexColor(accentHex, '#4D5C92');
    return ImmersiveMaterialStyle.cachedUltraThin(tint, lightHex, !active);
  }

  static menuOptions(enabled: boolean): MenuOptions {
    if (ImmersiveMaterialStyle.isActive(enabled)) {
      return {
        systemMaterial: ImmersiveMaterialStyle.thickMaterial()
      };
    }
    if (ImmersiveMaterialStyle.isApi26Available() && !enabled) {
      return {
        systemMaterial: uiMaterial.Material.empty
      };
    }
    return {};
  }

  static toastOptions(message: string, enabled: boolean): promptAction.ShowToastOptions {
    if (ImmersiveMaterialStyle.isActive(enabled)) {
      return {
        message,
        systemMaterial: ImmersiveMaterialStyle.thickMaterial()
      };
    }
    if (ImmersiveMaterialStyle.isApi26Available() && !enabled) {
      return {
        message,
        systemMaterial: uiMaterial.Material.empty
      };
    }
    return { message };
  }

  static sheetOptions(
    enabled: boolean,
    pageHex: string,
    titleText: string,
    onDisappear: () => void,
    fitContent: boolean = false
  ): SheetOptions {
    const titleObj: SheetTitleOptions = { title: titleText };
    if (ImmersiveMaterialStyle.isActive(enabled)) {
      if (fitContent) {
        return {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          title: titleObj,
          systemMaterial: ImmersiveMaterialStyle.ultraThickMaterial(),
          onDisappear
        };
      }
      return {
        height: SheetSize.MEDIUM,
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        showClose: true,
        title: titleObj,
        systemMaterial: ImmersiveMaterialStyle.ultraThickMaterial(),
        onDisappear
      };
    }
    if (fitContent) {
      return {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: true,
        title: titleObj,
        backgroundColor: normalizeHexColor(pageHex, '#F6F8FB'),
        blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
        onDisappear
      };
    }
    const fallbackOpts: SheetOptions = {
      height: SheetSize.MEDIUM,
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      showClose: true,
      title: titleObj,
      backgroundColor: normalizeHexColor(pageHex, '#F6F8FB'),
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      onDisappear
    };
    return fallbackOpts;
  }

  static actionSheetOptions(
    enabled: boolean,
    pageHex: string,
    onDisappear: () => void
  ): SheetOptions {
    if (ImmersiveMaterialStyle.isActive(enabled)) {
      return {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        systemMaterial: ImmersiveMaterialStyle.ultraThickMaterial(),
        onDisappear
      };
    }
    return {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: normalizeHexColor(pageHex, '#FFFFFF'),
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      onDisappear
    };
  }

  static pageTheme(pageHex: string): CustomTheme {
    return {
      colors: {
        compBackgroundGray: normalizeHexColor(pageHex, '#F6F8FB')
      }
    };
  }

  static titleBarOptions(enabled: boolean, scrollUnderTitle: boolean): NavigationTitleOptions {
    if (!ImmersiveMaterialStyle.isApi26Available()) {
      return {
        barStyle: BarStyle.STACK,
        backgroundColor: Color.Transparent,
        backgroundBlurStyle: scrollUnderTitle ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE
      };
    }
    const useScrollEffect = enabled && scrollUnderTitle && ImmersiveMaterialStyle.isSupported();
    return {
      barStyle: BarStyle.STACK,
      backgroundColor: Color.Transparent,
      scrollEffectOptions: useScrollEffect
        ? {
            scrollEffectType: ScrollEffectType.GRADUAL_BLUR,
            blurEffectiveStartOffset: LengthMetrics.vp(0),
            blurEffectiveEndOffset: LengthMetrics.vp(8)
          }
        : undefined,
      systemMaterial: useScrollEffect ? undefined : uiMaterial.Material.empty
    };
  }
}
