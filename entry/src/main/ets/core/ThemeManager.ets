import { AppearanceConfig, defaultAppearance } from './Models';

export interface PaletteTokens {
  canvas: string;
  surface: string;
  panel: string;
  ink: string;
  muted: string;
  accent: string;
  onAccent: string;
  tint: string;
  line: string;
  warning: string;
}

export interface ThemePalette {
  id: string;
  name: string;
  light: PaletteTokens;
  dark: PaletteTokens;
}

export interface WallpaperPreset {
  id: string;
  name: string;
  cssGradient: string;
  solidFallback: string;
}

export const BUILTIN_PALETTES: ThemePalette[] = [
  {
    id: 'default',
    name: '默认',
    light: {
      canvas: '#F7F7F7',
      surface: '#FFFFFF',
      panel: '#EFEFF3',
      ink: '#202020',
      muted: '#646464',
      accent: '#4D5C92',
      onAccent: '#FFFFFF',
      tint: '#DCE1FF',
      line: '#1A000000',
      warning: '#BB0947'
    },
    dark: {
      canvas: '#121213',
      surface: '#1D1E22',
      panel: '#27292F',
      ink: '#F9F9F9',
      muted: '#CECECE',
      accent: '#B6C4FF',
      onAccent: '#1D2D61',
      tint: '#354479',
      line: '#24FFFFFF',
      warning: '#FCB4BD'
    }
  },
  {
    id: 'blue',
    name: '以太蓝',
    light: {
      canvas: '#FDFBFF',
      surface: '#FFFFFF',
      panel: '#EFF3FA',
      ink: '#1B1B1D',
      muted: '#44464E',
      accent: '#3E5E98',
      onAccent: '#FFFFFF',
      tint: '#D6E2FF',
      line: '#1A000000',
      warning: '#BB0947'
    },
    dark: {
      canvas: '#1B1B1D',
      surface: '#25262A',
      panel: '#2F3136',
      ink: '#E3E1E6',
      muted: '#C4C6D0',
      accent: '#ACC7FF',
      onAccent: '#032F67',
      tint: '#24457F',
      line: '#24FFFFFF',
      warning: '#FCB4BD'
    }
  },
  {
    id: 'green',
    name: '翠竹绿',
    light: {
      canvas: '#FBFDF8',
      surface: '#FFFFFF',
      panel: '#EEF5F0',
      ink: '#191C1A',
      muted: '#404942',
      accent: '#166C47',
      onAccent: '#FFFFFF',
      tint: '#A3F4C5',
      line: '#1A000000',
      warning: '#A63B00'
    },
    dark: {
      canvas: '#191C1A',
      surface: '#232724',
      panel: '#2C322E',
      ink: '#E1E3DF',
      muted: '#C0C9C0',
      accent: '#87D7AA',
      onAccent: '#003921',
      tint: '#005232',
      line: '#24FFFFFF',
      warning: '#FEB69A'
    }
  },
  {
    id: 'purple',
    name: '暮色紫',
    light: {
      canvas: '#FFFBFF',
      surface: '#FFFFFF',
      panel: '#F4EFFA',
      ink: '#1C1B1F',
      muted: '#47464F',
      accent: '#5D5698',
      onAccent: '#FFFFFF',
      tint: '#E5DEFF',
      line: '#1A000000',
      warning: '#BB0947'
    },
    dark: {
      canvas: '#1C1B1F',
      surface: '#26242B',
      panel: '#312F38',
      ink: '#E6E1E6',
      muted: '#C9C4CF',
      accent: '#C8BFFF',
      onAccent: '#2E2766',
      tint: '#453E7F',
      line: '#24FFFFFF',
      warning: '#FCB4BD'
    }
  },
  {
    id: 'yellow',
    name: '琥珀金',
    light: {
      canvas: '#FFFBF9',
      surface: '#FFFFFF',
      panel: '#F7F1E8',
      ink: '#1F1B16',
      muted: '#4F4539',
      accent: '#855304',
      onAccent: '#FFFFFF',
      tint: '#FFDDB6',
      line: '#1A000000',
      warning: '#A63B00'
    },
    dark: {
      canvas: '#1F1B16',
      surface: '#2A241E',
      panel: '#352E27',
      ink: '#EBE0D9',
      muted: '#B8ABA0',
      accent: '#FDB967',
      onAccent: '#482A00',
      tint: '#663D00',
      line: '#24FFFFFF',
      warning: '#FEB69A'
    }
  },
  {
    id: 'smoky_rose',
    name: '烟熏玫瑰',
    light: {
      canvas: '#FFFBFF',
      surface: '#FFFFFF',
      panel: '#F7EEF3',
      ink: '#201A1D',
      muted: '#504349',
      accent: '#824E6C',
      onAccent: '#FFFFFF',
      tint: '#FFD8EA',
      line: '#1A000000',
      warning: '#BB0947'
    },
    dark: {
      canvas: '#201A1D',
      surface: '#2B2327',
      panel: '#362D32',
      ink: '#ECDFE3',
      muted: '#D4C2C9',
      accent: '#F5B3D6',
      onAccent: '#4E203C',
      tint: '#673754',
      line: '#24FFFFFF',
      warning: '#FCB4BD'
    }
  },
  {
    id: 'terracotta',
    name: '赤陶陶土',
    light: {
      canvas: '#FFFBFF',
      surface: '#FFFFFF',
      panel: '#F7EFEC',
      ink: '#221A18',
      muted: '#53433E',
      accent: '#8B4E3B',
      onAccent: '#FFFFFF',
      tint: '#FFDBD0',
      line: '#1A000000',
      warning: '#B91F01'
    },
    dark: {
      canvas: '#221A18',
      surface: '#2D2320',
      panel: '#382D29',
      ink: '#EFDFDB',
      muted: '#D9C2BB',
      accent: '#FFB59E',
      onAccent: '#522211',
      tint: '#6E3725',
      line: '#24FFFFFF',
      warning: '#FFB5A5'
    }
  },
  {
    id: 'monochrome',
    name: '霜灰极简',
    light: {
      canvas: '#F7F7F7',
      surface: '#FFFFFF',
      panel: '#EFEFEF',
      ink: '#202020',
      muted: '#646464',
      accent: '#000000',
      onAccent: '#FFFFFF',
      tint: '#EFEFEF',
      line: '#1A000000',
      warning: '#000000'
    },
    dark: {
      canvas: '#121213',
      surface: '#1D1E20',
      panel: '#2B2B2B',
      ink: '#F9F9F9',
      muted: '#CECECE',
      accent: '#FFFFFF',
      onAccent: '#000000',
      tint: '#2B2B2B',
      line: '#24FFFFFF',
      warning: '#FFFFFF'
    }
  },
  {
    id: 'doc_theme',
    name: '青柠薄荷',
    light: {
      canvas: '#F7F7F7',
      surface: '#FFFFFF',
      panel: '#ECF5F0',
      ink: '#202020',
      muted: '#646464',
      accent: '#00B96B',
      onAccent: '#FFFFFF',
      tint: '#D7F5E6',
      line: '#1A000000',
      warning: '#FF0000'
    },
    dark: {
      canvas: '#121213',
      surface: '#1C1E1D',
      panel: '#252A27',
      ink: '#F9F9F9',
      muted: '#CECECE',
      accent: '#00B96B',
      onAccent: '#FFFFFF',
      tint: '#0F3E2A',
      line: '#24FFFFFF',
      warning: '#FF5252'
    }
  }
];

export const WALLPAPER_PRESETS: WallpaperPreset[] = [
  { id: 'none', name: '纯净无壁纸', cssGradient: '', solidFallback: '' },
  { id: 'mist', name: '晨雾蓝调', cssGradient: 'linear-gradient(#EFF6FF, #F8FAFC)', solidFallback: '#EEF4FD' },
  { id: 'sage', name: '薄荷青苔', cssGradient: 'linear-gradient(#ECFDF5, #F0FDF4)', solidFallback: '#ECF8F1' },
  { id: 'sunset', name: '落日微光', cssGradient: 'linear-gradient(#FFF7ED, #FFF1F2)', solidFallback: '#FDF3EC' },
  { id: 'dusk', name: '暮光柔紫', cssGradient: 'linear-gradient(#F5F3FF, #EFF6FF)', solidFallback: '#F4F1FC' }
];

export function normalizePaletteId(id: string): string {
  switch (id) {
    case 'kelivo-indigo':
      return 'default';
    case 'azure':
      return 'blue';
    case 'emerald':
      return 'green';
    case 'violet':
      return 'purple';
    case 'amber':
      return 'yellow';
    case 'rose':
      return 'smoky_rose';
    case 'slate':
      return 'monochrome';
    default:
      return id || 'default';
  }
}

export function defaultAppearanceConfig(): AppearanceConfig {
  const base = defaultAppearance();
  base.wallpaperValue = 'none';
  base.wallpaperOpacity = 0.35;
  return base;
}

export function findPalette(id: string): ThemePalette {
  const normalized = normalizePaletteId(id);
  for (let i = 0; i < BUILTIN_PALETTES.length; i++) {
    if (BUILTIN_PALETTES[i].id === normalized) {
      return BUILTIN_PALETTES[i];
    }
  }
  return BUILTIN_PALETTES[0];
}

function isHexColor(v: Object | undefined): boolean {
  return typeof v === 'string' && /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(v.trim());
}

export function parseCustomThemeJson(rawJson: string, fallback: PaletteTokens): PaletteTokens | undefined {
  const clean = rawJson.trim();
  if (clean.length === 0) {
    return undefined;
  }
  try {
    const obj = JSON.parse(clean) as Record<string, Object>;
    return {
      canvas: isHexColor(obj['canvas']) ? String(obj['canvas']) : fallback.canvas,
      surface: isHexColor(obj['surface']) ? String(obj['surface']) : fallback.surface,
      panel: isHexColor(obj['panel']) ? String(obj['panel']) : fallback.panel,
      ink: isHexColor(obj['ink']) ? String(obj['ink']) : fallback.ink,
      muted: isHexColor(obj['muted']) ? String(obj['muted']) : fallback.muted,
      accent: isHexColor(obj['accent']) ? String(obj['accent']) : fallback.accent,
      onAccent: isHexColor(obj['onAccent']) ? String(obj['onAccent']) : fallback.onAccent,
      tint: isHexColor(obj['tint']) ? String(obj['tint']) : fallback.tint,
      line: isHexColor(obj['line']) ? String(obj['line']) : fallback.line,
      warning: isHexColor(obj['warning']) ? String(obj['warning']) : fallback.warning
    };
  } catch (_) {
    return undefined;
  }
}

export function resolveEffectiveDark(mode: 'system' | 'light' | 'dark', isSystemDark: boolean): boolean {
  if (mode === 'dark') {
    return true;
  }
  if (mode === 'light') {
    return false;
  }
  return isSystemDark;
}

export function resolveThemeTokens(config: AppearanceConfig, isSystemDark: boolean): PaletteTokens {
  const palette = findPalette(config.paletteId);
  const useDark = resolveEffectiveDark(config.themeMode, isSystemDark);
  const base = useDark ? palette.dark : palette.light;
  let resolved = base;
  if (config.customThemeJson && config.customThemeJson.trim().length > 0) {
    const parsed = parseCustomThemeJson(config.customThemeJson, base);
    if (parsed) {
      resolved = parsed;
    }
  }
  if (config.pureBackground) {
    return {
      canvas: useDark ? '#000000' : '#FFFFFF',
      surface: resolved.surface,
      panel: resolved.panel,
      ink: resolved.ink,
      muted: resolved.muted,
      accent: resolved.accent,
      onAccent: resolved.onAccent,
      tint: resolved.tint,
      line: resolved.line,
      warning: resolved.warning
    };
  }
  return resolved;
}

export function resolveWallpaperColor(config: AppearanceConfig, isDark: boolean): string {
  if (config.wallpaperKind === 'none' || !config.wallpaperValue || config.wallpaperValue === 'none') {
    return '';
  }
  if (isDark) {
    return '';
  }
  for (let i = 0; i < WALLPAPER_PRESETS.length; i++) {
    if (WALLPAPER_PRESETS[i].id === config.wallpaperValue) {
      return WALLPAPER_PRESETS[i].solidFallback;
    }
  }
  return isHexColor(config.wallpaperValue) ? config.wallpaperValue : '';
}
