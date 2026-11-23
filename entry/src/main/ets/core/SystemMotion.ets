import { curves, UIContext } from '@kit.ArkUI';

export class SystemMotion {
  static navTransition(reduceMotion: boolean, modal: boolean = false): NavigationSystemTransitionType {
    if (reduceMotion) {
      return NavigationSystemTransitionType.FADE;
    }
    return modal ? NavigationSystemTransitionType.SLIDE_BOTTOM : NavigationSystemTransitionType.DEFAULT;
  }

  static drawerScrimTransition(reduceMotion: boolean): TransitionEffect {
    return TransitionEffect.OPACITY.animation({
      duration: reduceMotion ? 100 : 220,
      curve: Curve.EaseOut
    });
  }

  static drawerPanelTransition(reduceMotion: boolean): TransitionEffect {
    if (reduceMotion) {
      return TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.Linear });
    }
    return TransitionEffect.move(TransitionEdge.START).animation({
      curve: curves.springMotion(0.32, 0.92)
    });
  }

  static overlayModalTransition(reduceMotion: boolean): TransitionEffect {
    if (reduceMotion) {
      return TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.Linear });
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.move(TransitionEdge.BOTTOM)
        .combine(TransitionEffect.OPACITY)
        .animation({ curve: curves.springMotion(0.34, 0.90) }),
      TransitionEffect.move(TransitionEdge.BOTTOM)
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: 220, curve: Curve.FastOutLinearIn })
    );
  }

  static startSlideTransition(reduceMotion: boolean): TransitionEffect {
    if (reduceMotion) {
      return TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.Linear });
    }
    return TransitionEffect.move(TransitionEdge.START)
      .combine(TransitionEffect.OPACITY)
      .animation({ curve: curves.springMotion(0.32, 0.92) });
  }

  static endSlideTransition(reduceMotion: boolean): TransitionEffect {
    if (reduceMotion) {
      return TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.Linear });
    }
    return TransitionEffect.move(TransitionEdge.END)
      .combine(TransitionEffect.OPACITY)
      .animation({ curve: curves.springMotion(0.32, 0.92) });
  }

  static subViewTransition(reduceMotion: boolean): TransitionEffect {
    if (reduceMotion) {
      return TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.Linear });
    }
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: 24 }))
      .animation({ curve: curves.responsiveSpringMotion(0.28, 0.90) });
  }

  static inlineBarTransition(reduceMotion: boolean): TransitionEffect {
    if (reduceMotion) {
      return TransitionEffect.OPACITY.animation({ duration: 100, curve: Curve.Linear });
    }
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.move(TransitionEdge.TOP))
      .animation({ curve: curves.responsiveSpringMotion(0.24, 0.92) });
  }

  static reasoningRevealTransition(reduceMotion: boolean): TransitionEffect {
    if (reduceMotion) return TransitionEffect.IDENTITY;
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: -6 }))
        .animation({ duration: 180, curve: Curve.EaseOut }),
      TransitionEffect.IDENTITY
    );
  }

  static springAnimate(uiCtx: UIContext | undefined, reduceMotion: boolean, fn: () => void): void {
    if (!uiCtx) {
      fn();
      return;
    }
    try {
      uiCtx.animateTo(
        reduceMotion
          ? { duration: 120, curve: Curve.Linear }
          : { curve: curves.springMotion(0.30, 0.90) },
        fn
      );
    } catch (_) {
      fn();
    }
  }

  static quickAnimate(uiCtx: UIContext | undefined, reduceMotion: boolean, fn: () => void): void {
    if (!uiCtx) {
      fn();
      return;
    }
    try {
      uiCtx.animateTo(
        reduceMotion
          ? { duration: 100, curve: Curve.Linear }
          : { curve: curves.responsiveSpringMotion(0.24, 0.92) },
        fn
      );
    } catch (_) {
      fn();
    }
  }
}
