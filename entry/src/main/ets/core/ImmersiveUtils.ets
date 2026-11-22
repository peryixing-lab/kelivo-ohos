export interface SafeAreaInsets {
  top: number;
  bottom: number;
  left: number;
  right: number;
}

export interface AvoidRectLike {
  left: number;
  top: number;
  width: number;
  height: number;
}

export function emptySafeAreaInsets(): SafeAreaInsets {
  return { top: 0, bottom: 0, left: 0, right: 0 };
}

/**
 * Computes pixel insets from window.AvoidArea directional rects inside the window coordinate frame.
 */
export function computeCutoutSafeInsets(
  winWidthPx: number,
  winHeightPx: number,
  topRect?: AvoidRectLike,
  bottomRect?: AvoidRectLike,
  leftRect?: AvoidRectLike,
  rightRect?: AvoidRectLike
): SafeAreaInsets {
  const top = topRect && topRect.height > 0 && topRect.width > 0
    ? Math.max(0, topRect.top + topRect.height)
    : 0;
  const left = leftRect && leftRect.width > 0 && leftRect.height > 0
    ? Math.max(0, leftRect.left + leftRect.width)
    : 0;
  const right = rightRect && rightRect.width > 0 && rightRect.height > 0 && winWidthPx > 0
    ? Math.max(0, winWidthPx - rightRect.left)
    : 0;
  const bottom = bottomRect && bottomRect.height > 0 && bottomRect.width > 0 && winHeightPx > 0
    ? Math.max(0, winHeightPx - bottomRect.top)
    : 0;
  return { top, bottom, left, right };
}

export function mergeSafeAreaInsets(a: SafeAreaInsets, b: SafeAreaInsets): SafeAreaInsets {
  return {
    top: Math.max(a.top, b.top),
    bottom: Math.max(a.bottom, b.bottom),
    left: Math.max(a.left, b.left),
    right: Math.max(a.right, b.right)
  };
}

/**
 * Normalizes #RGB/#RRGGBB/#AARRGGBB (with or without leading '#') to uppercase #RRGGBB.
 */
export function normalizeHexColor(input: string, fallback: string = '#F6F8FB'): string {
  const raw = (input || '').trim().replace(/^#/, '');
  if (/^[0-9A-Fa-f]{3}$/.test(raw)) {
    const u = raw.toUpperCase();
    return `#${u[0]}${u[0]}${u[1]}${u[1]}${u[2]}${u[2]}`;
  }
  if (/^[0-9A-Fa-f]{6}$/.test(raw)) {
    return `#${raw.toUpperCase()}`;
  }
  if (/^[0-9A-Fa-f]{8}$/.test(raw)) {
    return `#${raw.slice(2).toUpperCase()}`;
  }
  return fallback;
}

/**
 * Combines a #RRGGBB base color with a 2-digit translucent hex alpha (#AARRGGBB).
 * Guarantees non-FF transparency so ImmersiveMaterial optical filters remain visible.
 */
export function hexWithAlpha(hexColor: string, alphaHex: string): string {
  const rgb = normalizeHexColor(hexColor, '#FFFFFF');
  const cleanAlpha = /^[0-9A-Fa-f]{2}$/.test(alphaHex) ? alphaHex.toUpperCase() : '48';
  const clampedAlpha = cleanAlpha === 'FF' ? 'CC' : cleanAlpha;
  return `#${clampedAlpha}${rgb.slice(1)}`;
}

/**
 * Adjusts bottom safe-area inset when entering FLOATING mini-window mode on phone vs tablet.
 */
export function computeFloatingBottomInsetVp(
  rawBottomInsetVp: number,
  isFloatingWindow: boolean,
  isWide: boolean
): number {
  if (!isFloatingWindow) {
    return Math.max(0, rawBottomInsetVp);
  }
  if (!isWide) {
    // Phone floating window removes fullscreen navigation-indicator lift.
    return 0;
  }
  return Math.min(8, Math.max(0, rawBottomInsetVp));
}
