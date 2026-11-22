import { accessibility } from '@kit.AccessibilityKit';
import { KeyboardAvoidMode, UIContext, window } from '@kit.ArkUI';
import {
  AvoidRectLike,
  SafeAreaInsets,
  computeCutoutSafeInsets,
  emptySafeAreaInsets,
  mergeSafeAreaInsets,
  normalizeHexColor
} from './ImmersiveUtils';

let sharedWindowController: AppWindowController | undefined = undefined;

export function syncWindowSystemBars(isDark: boolean): void {
  if (sharedWindowController) {
    sharedWindowController.syncSystemBarAppearance(isDark);
  }
}

export function syncWindowBackgroundColor(hexColor: string): void {
  if (sharedWindowController) {
    sharedWindowController.syncWindowBackground(hexColor);
  }
}

export class AppWindowController {
  private mainWindow?: window.Window;
  private uiContext?: UIContext;
  private originalBarProps?: window.SystemBarProperties;
  private lastBarThemeKey: string = '';
  private lastWindowBgHex: string = '';

  private readonly handleAvoidAreaChange = (data: window.AvoidAreaOptions): void => {
    if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
      AppStorage.setOrCreate('windowKeyboardHeightVp', this.pxToVpVal(data.area.bottomRect.height));
      return;
    }
    this.refreshAvoidAreas();
  };

  private readonly handleKeyboardHeightChange = (heightPx: number): void => {
    AppStorage.setOrCreate('windowKeyboardHeightVp', this.pxToVpVal(heightPx));
  };

  private readonly handleWindowSizeChange = (_size: window.Size): void => {
    this.refreshAvoidAreas();
    this.refreshWindowStatus();
    this.refreshTitleButtonRect();
  };

  private readonly handleWindowStatusChange = (status: window.WindowStatusType): void => {
    AppStorage.setOrCreate('windowIsFloating', status === window.WindowStatusType.FLOATING);
    this.refreshAvoidAreas();
    this.refreshTitleButtonRect();
  };

  private readonly handleTitleButtonRectChange = (rect: window.TitleButtonRect): void => {
    this.publishTitleButtonRect(rect);
  };

  private readonly handleAnimationReduceChange = (enabled: boolean): void => {
    AppStorage.setOrCreate('reduceMotionEnabled', enabled);
  };

  async attach(win: window.Window, initialDark: boolean): Promise<void> {
    this.detach();
    this.mainWindow = win;
    sharedWindowController = this;

    try {
      this.uiContext = win.getUIContext();
    } catch (_) {}

    try {
      this.uiContext?.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (_) {}

    AppStorage.setOrCreate('windowKeyboardHeightVp', 0);

    try {
      this.originalBarProps = win.getWindowSystemBarProperties();
    } catch (_) {}

    try {
      await win.setWindowLayoutFullScreen(true);
    } catch (_) {}

    this.refreshAvoidAreas();
    this.refreshWindowStatus();
    this.refreshTitleButtonRect();
    this.syncSystemBarAppearance(initialDark);
    this.syncWindowBackground(initialDark ? '#121213' : '#F7F7F7');

    try {
      const reduced = accessibility.isAnimationReduceEnabledSync();
      AppStorage.setOrCreate('reduceMotionEnabled', reduced);
    } catch (_) {
      AppStorage.setOrCreate('reduceMotionEnabled', false);
    }

    try {
      accessibility.onAnimationReduceStateChange(this.handleAnimationReduceChange);
    } catch (_) {}

    try {
      win.on('avoidAreaChange', this.handleAvoidAreaChange);
    } catch (_) {}

    try {
      win.on('windowSizeChange', this.handleWindowSizeChange);
    } catch (_) {}

    try {
      win.on('windowStatusDidChange', this.handleWindowStatusChange);
    } catch (_) {}

    try {
      win.on('windowTitleButtonRectChange', this.handleTitleButtonRectChange);
    } catch (_) {}

    try {
      win.on('keyboardHeightChange', this.handleKeyboardHeightChange);
    } catch (_) {}
  }

  detach(): void {
    const win = this.mainWindow;
    try {
      accessibility.offAnimationReduceStateChange(this.handleAnimationReduceChange);
    } catch (_) {}

    if (win) {
      try { win.off('avoidAreaChange', this.handleAvoidAreaChange); } catch (_) {}
      try { win.off('windowSizeChange', this.handleWindowSizeChange); } catch (_) {}
      try { win.off('windowStatusDidChange', this.handleWindowStatusChange); } catch (_) {}
      try { win.off('windowTitleButtonRectChange', this.handleTitleButtonRectChange); } catch (_) {}
      try { win.off('keyboardHeightChange', this.handleKeyboardHeightChange); } catch (_) {}
      if (this.originalBarProps) {
        try {
          win.setWindowSystemBarProperties(this.originalBarProps).catch(() => {});
        } catch (_) {}
      }
    }

    if (sharedWindowController === this) {
      sharedWindowController = undefined;
    }
    this.mainWindow = undefined;
    this.uiContext = undefined;
    this.originalBarProps = undefined;
    this.lastBarThemeKey = '';
    this.lastWindowBgHex = '';
    AppStorage.setOrCreate('windowKeyboardHeightVp', 0);
  }

  syncWindowBackground(hexColor: string): void {
    const win = this.mainWindow;
    if (!win) {
      return;
    }
    const clean = normalizeHexColor(hexColor, '#F7F7F7');
    if (this.lastWindowBgHex === clean) {
      return;
    }
    this.lastWindowBgHex = clean;
    try {
      win.setWindowBackgroundColor(clean);
    } catch (_) {
      this.lastWindowBgHex = '';
    }
  }

  syncSystemBarAppearance(isDark: boolean): void {
    const win = this.mainWindow;
    if (!win) {
      return;
    }
    const key = isDark ? 'dark' : 'light';
    if (this.lastBarThemeKey === key) {
      return;
    }
    this.lastBarThemeKey = key;
    const props: window.SystemBarProperties = {
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: isDark ? '#F3F4F6' : '#111827',
      navigationBarContentColor: isDark ? '#F3F4F6' : '#111827'
    };
    try {
      win.setWindowSystemBarProperties(props).catch(() => {
        this.lastBarThemeKey = '';
      });
    } catch (_) {
      this.lastBarThemeKey = '';
    }
  }

  private pxToVpVal(px: number): number {
    if (px <= 0) {
      return 0;
    }
    if (this.uiContext) {
      try {
        return Math.round(this.uiContext.px2vp(px) * 10) / 10;
      } catch (_) {}
    }
    return Math.round((px / 3) * 10) / 10;
  }

  private refreshWindowStatus(): void {
    const win = this.mainWindow;
    if (!win) {
      return;
    }
    try {
      const status = win.getWindowStatus();
      AppStorage.setOrCreate('windowIsFloating', status === window.WindowStatusType.FLOATING);
    } catch (_) {}
  }

  private refreshTitleButtonRect(): void {
    const win = this.mainWindow;
    if (!win) {
      return;
    }
    try {
      const rect = win.getTitleButtonRect();
      this.publishTitleButtonRect(rect);
    } catch (_) {}
  }

  private publishTitleButtonRect(rect: window.TitleButtonRect | undefined): void {
    if (!rect || rect.width <= 0) {
      AppStorage.setOrCreate('windowTitleRightAvoidVp', 0);
      return;
    }
    // TitleButtonRect width and right are already measured in vp.
    const avoidVp = Math.max(0, rect.width + Math.max(0, rect.right));
    AppStorage.setOrCreate('windowTitleRightAvoidVp', avoidVp);
  }

  private toAvoidRect(rect: window.Rect): AvoidRectLike {
    return { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
  }

  private areaInsets(winW: number, winH: number, area: window.AvoidArea): SafeAreaInsets {
    return computeCutoutSafeInsets(
      winW,
      winH,
      this.toAvoidRect(area.topRect),
      this.toAvoidRect(area.bottomRect),
      this.toAvoidRect(area.leftRect),
      this.toAvoidRect(area.rightRect)
    );
  }

  private refreshAvoidAreas(): void {
    const win = this.mainWindow;
    if (!win) {
      return;
    }
    try {
      const props = win.getWindowProperties();
      const winW = props.windowRect.width;
      const winH = props.windowRect.height;

      const sysArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const cutArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const gesArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM_GESTURE);

      const sysInsets = this.areaInsets(winW, winH, sysArea);
      const navInsets = this.areaInsets(winW, winH, navArea);
      const cutInsets = this.areaInsets(winW, winH, cutArea);
      const gesInsets = this.areaInsets(winW, winH, gesArea);

      let merged: SafeAreaInsets = mergeSafeAreaInsets(sysInsets, navInsets);
      merged = mergeSafeAreaInsets(merged, cutInsets);
      // Merge only horizontal side-swipe gesture zones cleanly; bottom keeps nav indicator height.
      merged = mergeSafeAreaInsets(merged, {
        top: 0,
        bottom: 0,
        left: gesInsets.left > 0 ? Math.min(gesInsets.left, 16) : 0,
        right: gesInsets.right > 0 ? Math.min(gesInsets.right, 16) : 0
      });

      AppStorage.setOrCreate('windowTopInsetVp', this.pxToVpVal(merged.top));
      AppStorage.setOrCreate('windowBottomInsetVp', this.pxToVpVal(merged.bottom));
      AppStorage.setOrCreate('windowLeftInsetVp', this.pxToVpVal(merged.left));
      AppStorage.setOrCreate('windowRightInsetVp', this.pxToVpVal(merged.right));
      AppStorage.setOrCreate('windowNavIndicatorVp', this.pxToVpVal(navInsets.bottom));
    } catch (_) {
      const fallback = emptySafeAreaInsets();
      AppStorage.setOrCreate('windowTopInsetVp', fallback.top);
      AppStorage.setOrCreate('windowBottomInsetVp', fallback.bottom);
      AppStorage.setOrCreate('windowLeftInsetVp', fallback.left);
      AppStorage.setOrCreate('windowRightInsetVp', fallback.right);
    }
  }
}
