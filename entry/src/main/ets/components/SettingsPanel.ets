import { getUiStrings, UiStrings } from '../core/I18n';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { AppearanceConfig, SystemSettings, defaultAppearance, defaultSystemSettings } from '../core/Models';
import { SystemMotion } from '../core/SystemMotion';
import { KelivoNavTitleBar } from './KelivoChrome';

interface SettingsNavItem {
  id: string;
  section: string;
  title: string;
  symbolRes: Resource;
  route: string;
  detailText?: string;
  keywords: string;
}

@Component
export struct SettingsPanel {
  @Prop systemSettings: SystemSettings = defaultSystemSettings();
  @Prop appearance: AppearanceConfig = defaultAppearance();
  @Prop language: string = 'zh-Hans';
  @Prop immersiveLightEnabled: boolean = true;
  @Prop hasAnyKey: boolean = false;
  @Prop storageText: string = '';

  onChangeThemeMode: (mode: 'system' | 'light' | 'dark') => Promise<void> = async () => {};
  onNavigateRoute: (route: string) => void = () => {};
  onOpenUrl: (url: string) => void = () => {};
  onDismissOverlay: () => boolean = () => false;
  onClose: () => void = () => {};

  @State searchOpen: boolean = false;
  @State searchQuery: string = '';
  @State showThemeSheet: boolean = false;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('windowLeftInsetVp') winLeftInset: number = 0;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('themeSurfaceHex') themeSurfaceHex: string = '#FFFFFF';
  @StorageProp('themeCanvasHex') themeCanvasHex: string = '#F7F7F7';
  @StorageProp('effectiveDarkMode') isDark: boolean = false;
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;
  private listScroller: Scroller = new Scroller();

  private labels(): UiStrings {
    return getUiStrings(this.language);
  }

  private themeModeLabel(): string {
    if (this.appearance.themeMode === 'light') return '浅色';
    if (this.appearance.themeMode === 'dark') return '深色';
    return '跟随系统';
  }

  private toggleSearch(open: boolean): void {
    SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.searchOpen = open;
      if (!open) {
        this.searchQuery = '';
      }
    });
    if (open) {
      this.listScroller.scrollEdge(Edge.Top);
    }
  }

  private allNavItems(): SettingsNavItem[] {
    return [
      {
        id: 'themeMode',
        section: '通用设置',
        title: '颜色模式',
        symbolRes: $r('sys.symbol.moon'),
        route: '__themeMode__',
        detailText: this.themeModeLabel(),
        keywords: 'color mode dark light system theme 色彩 颜色 浅色 深色'
      },
      {
        id: 'appearance',
        section: '通用设置',
        title: '偏好设置',
        symbolRes: $r('sys.symbol.display'),
        route: 'appearance',
        keywords: 'preferences display theme palette immersive light markdown behavior 偏好 外观 主题 语言'
      },
      {
        id: 'personas',
        section: '通用设置',
        title: '助手',
        symbolRes: $r('sys.symbol.person'),
        route: 'personas',
        keywords: 'assistant persona avatar regex prompt binding 助手 角色 提示词'
      },
      {
        id: 'defaultModel',
        section: '模型与服务',
        title: '默认模型',
        symbolRes: $r('sys.symbol.heart'),
        route: 'defaultModel',
        keywords: 'default model title summary translate ocr memory compress 默认 模型'
      },
      {
        id: 'providers',
        section: '模型与服务',
        title: '供应商',
        symbolRes: $r('sys.symbol.square_grid_2x2'),
        route: 'providers',
        keywords: 'provider model api key oauth openai claude gemini ollama 供应商 服务商 导入'
      },
      {
        id: 'search',
        section: '模型与服务',
        title: '搜索服务',
        symbolRes: $r('sys.symbol.globe_badge_message'),
        route: 'search',
        keywords: 'search web tavily brave bing google exa 联网 搜索'
      },
      {
        id: 'voice',
        section: '模型与服务',
        title: '语音服务',
        symbolRes: $r('sys.symbol.speaker_wave_2'),
        route: 'voice',
        keywords: 'voice tts asr speech microphone 语音 朗读 识别'
      },
      {
        id: 'tools',
        section: '模型与服务',
        title: 'MCP',
        symbolRes: $r('sys.symbol.wrench_and_screwdriver'),
        route: 'tools',
        keywords: 'mcp sse streamable http tool fetch 工具'
      },
      {
        id: 'workspace',
        section: '模型与服务',
        title: '工作区与环境',
        symbolRes: $r('sys.symbol.folder'),
        route: 'workspace',
        keywords: 'workspace file diff env grep 工作区 环境'
      },
      {
        id: 'schedules',
        section: '模型与服务',
        title: '定时任务',
        symbolRes: $r('sys.symbol.clock'),
        route: 'schedules',
        keywords: 'schedule timer automation task 定时 任务'
      },
      {
        id: 'skills',
        section: '模型与服务',
        title: '技能',
        symbolRes: $r('sys.symbol.wand_and_stars'),
        route: 'skills',
        keywords: 'skills skill.md github agent 技能'
      },
      {
        id: 'worldBook',
        section: '模型与服务',
        title: '世界书',
        symbolRes: $r('sys.symbol.book'),
        route: 'promptTools',
        keywords: 'worldbook lorebook sillytavern trigger 世界书'
      },
      {
        id: 'memory',
        section: '模型与服务',
        title: '记忆',
        symbolRes: $r('sys.symbol.lightbulb'),
        route: 'memory',
        keywords: 'memory profile auto extract long term 记忆 画像'
      },
      {
        id: 'quickPhrases',
        section: '模型与服务',
        title: '快捷短语',
        symbolRes: $r('sys.symbol.bolt'),
        route: 'quickPhrases',
        keywords: 'quick phrase snippet prompt 快捷 短语'
      },
      {
        id: 'instructionCards',
        section: '模型与服务',
        title: '指令注入',
        symbolRes: $r('sys.symbol.rectangle_stack'),
        route: 'instructionCards',
        keywords: 'instruction card prompt injection template 指令 注入'
      },
      {
        id: 'networkProxy',
        section: '模型与服务',
        title: '网络代理',
        symbolRes: $r('sys.symbol.compass'),
        route: 'providers_proxy',
        keywords: 'network proxy http socks5 网络 代理'
      },
      {
        id: 'webdav',
        section: '数据设置',
        title: '数据备份',
        symbolRes: $r('sys.symbol.cloud'),
        route: 'webdav',
        keywords: 'webdav s3 backup restore import snapshot 备份 恢复 同步'
      },
      {
        id: 'chatStorage',
        section: '数据设置',
        title: '聊天记录存储',
        symbolRes: $r('sys.symbol.externaldrive'),
        route: 'diagnostics_storage',
        detailText: this.storageText,
        keywords: 'storage cleanup database cache 聊天记录 存储 空间'
      },
      {
        id: 'about',
        section: '关于',
        title: '关于',
        symbolRes: $r('sys.symbol.info_circle'),
        route: 'about',
        keywords: 'about version kelivo 关于 版本'
      },
      {
        id: 'stats',
        section: '关于',
        title: '统计',
        symbolRes: $r('sys.symbol.list_bullet'),
        route: 'stats',
        keywords: 'stats token usage heatmap analytics 统计 用量'
      },
      {
        id: 'docs',
        section: '关于',
        title: '使用文档',
        symbolRes: $r('sys.symbol.book'),
        route: '__docs__',
        keywords: 'docs documentation help 使用 文档'
      },
      {
        id: 'logs',
        section: '关于',
        title: '日志',
        symbolRes: $r('sys.symbol.doc_text'),
        route: 'diagnostics_logs',
        keywords: 'logs request context debug 日志 调试'
      },
      {
        id: 'toolSchema',
        section: '关于',
        title: '工具描述',
        symbolRes: $r('sys.symbol.slider_horizontal_2'),
        route: 'diagnostics_tools',
        keywords: 'tool schema override description 工具 描述'
      }
    ];
  }

  private sectionNames(): string[] {
    return ['通用设置', '模型与服务', '数据设置', '关于'];
  }

  private itemsForSection(sec: string): SettingsNavItem[] {
    const q = this.searchQuery.trim().toLowerCase();
    return this.allNavItems().filter((it: SettingsNavItem): boolean => {
      if (it.section !== sec) return false;
      if (q.length === 0) return true;
      return (
        it.title.toLowerCase().indexOf(q) >= 0 ||
        it.section.toLowerCase().indexOf(q) >= 0 ||
        it.keywords.indexOf(q) >= 0
      );
    });
  }

  private warningBannerBg(): string {
    return this.isDark ? '#2BFF6B6B' : '#18E5484D';
  }

  @Builder
  private navTitleBar() {
    KelivoNavTitleBar({
      titleText: this.labels().settings,
      showBack: true,
      rightSymbol: this.searchOpen ? $r('sys.symbol.xmark') : $r('sys.symbol.magnifyingglass'),
      onBack: () => { this.onClose(); },
      onRightAction: () => { this.toggleSearch(!this.searchOpen); }
    })
  }

  @Builder
  private navRow(item: SettingsNavItem, showDivider: boolean) {
    Column() {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph(item.symbolRes)
            .fontSize(20)
            .fontColor([$r('app.color.ink')])
        }
        .width(28)
        .alignItems(HorizontalAlign.Center)

        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (item.detailText && item.detailText.length > 0) {
          Text(item.detailText)
            .fontSize(13)
            .fontColor($r('app.color.muted'))
        }

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([$r('app.color.muted')])
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 13, bottom: 13 })
      .onClick(() => {
        if (item.route === '__themeMode__') {
          this.showThemeSheet = true;
        } else if (item.route === '__docs__') {
          this.onOpenUrl('https://kelivo.psycheas.top/');
        } else {
          this.onNavigateRoute(item.route);
        }
      })

      if (showDivider) {
        Divider()
          .strokeWidth(0.6)
          .color($r('app.color.line'))
          .margin({ left: 54, right: 12 })
      }
    }
    .width('100%')
  }

  @Builder
  private themeModeOverlay() {
    Column() {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.display'))
          .fontSize(19)
          .fontColor([$r('app.color.ink')])
        Text('跟随系统')
          .fontSize(15)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        if (this.appearance.themeMode === 'system') {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(17)
            .fontColor([$r('app.color.accent')])
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => {
        this.showThemeSheet = false;
        this.onChangeThemeMode('system').catch(() => {});
      })

      Divider().strokeWidth(0.6).color($r('app.color.line')).margin({ left: 48, right: 16 })

      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.sun_max'))
          .fontSize(19)
          .fontColor([$r('app.color.ink')])
        Text('浅色')
          .fontSize(15)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        if (this.appearance.themeMode === 'light') {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(17)
            .fontColor([$r('app.color.accent')])
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => {
        this.showThemeSheet = false;
        this.onChangeThemeMode('light').catch(() => {});
      })

      Divider().strokeWidth(0.6).color($r('app.color.line')).margin({ left: 48, right: 16 })

      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.moon'))
          .fontSize(19)
          .fontColor([$r('app.color.ink')])
        Text('深色')
          .fontSize(15)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        if (this.appearance.themeMode === 'dark') {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(17)
            .fontColor([$r('app.color.accent')])
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => {
        this.showThemeSheet = false;
        this.onChangeThemeMode('dark').catch(() => {});
      })
    }
    .width('100%')
    .padding({ top: 4, bottom: 20 })
  }

  build() {
    NavDestination() {
      Column() {
        Scroll(this.listScroller) {
          Column() {
            if (this.searchOpen) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(17)
                  .fontColor([$r('app.color.muted')])
                TextInput({ text: this.searchQuery, placeholder: '搜索设置项...' })
                  .id('settingsSearchInput')
                  .layoutWeight(1)
                  .height(36)
                  .padding(0)
                  .fontSize(14)
                  .backgroundColor(Color.Transparent)
                  .onChange((v: string) => { this.searchQuery = v; })
                if (this.searchQuery.length > 0) {
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontSize(13)
                      .fontColor([$r('app.color.muted')])
                  }
                  .width(26)
                  .height(26)
                  .padding(0)
                  .backgroundColor(Color.Transparent)
                  .onClick(() => { this.searchQuery = ''; })
                }
              }
              .width('100%')
              .height(44)
              .padding({ left: 14, right: 10 })
              .borderRadius(22)
              .backgroundColor($r('app.color.surface'))
              .margin({ bottom: 10 })
              .transition(SystemMotion.inlineBarTransition(this.reduceMotion))
            }

            if (!this.hasAnyKey && !this.searchOpen) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                  .fontSize(18)
                  .fontColor([$r('app.color.warning')])
                Text('部分服务未配置，某些功能可能不可用')
                  .fontSize(12)
                  .fontColor($r('app.color.ink'))
                  .maxLines(2)
                  .layoutWeight(1)
              }
              .width('100%')
              .padding(12)
              .borderRadius(12)
              .backgroundColor(this.warningBannerBg())
              .margin({ bottom: 8 })
              .onClick(() => { this.onNavigateRoute('providers'); })
            }

            ForEach(this.sectionNames(), (sec: string, secIdx: number) => {
              if (this.itemsForSection(sec).length > 0) {
                Text(sec)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.muted'))
                  .width('100%')
                  .padding({ left: 12, right: 12, top: secIdx === 0 ? 2 : 14, bottom: 6 })
                Column() {
                  ForEach(this.itemsForSection(sec), (item: SettingsNavItem, idx: number) => {
                    this.navRow(item, idx < this.itemsForSection(sec).length - 1)
                  }, (item: SettingsNavItem) => `${item.id}_${item.detailText || ''}_${this.storageText}`)
                }
                .width('100%')
                .borderRadius(14)
                .backgroundColor($r('app.color.surface'))
              }
            }, (sec: string) => sec)
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 56 + this.winTopInset + 4,
            bottom: Math.max(36, this.winBottomInset + 20)
          })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.winLeftInset, right: this.winRightInset })
      .backgroundColor(Color.Transparent)
      .bindSheet(
        $$this.showThemeSheet,
        this.themeModeOverlay(),
        ImmersiveMaterialStyle.sheetOptions(
          this.immersiveLightEnabled,
          this.themeSurfaceHex,
          '颜色模式',
          () => { this.showThemeSheet = false; },
          true
        )
      )
    }
    .hideBackButton(true)
    .backgroundColor(this.themeCanvasHex)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .title(
      { builder: () => { this.navTitleBar(); }, height: 56 + this.winTopInset },
      ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightEnabled, true)
    )
    .systemTransition(SystemMotion.navTransition(this.reduceMotion))
    .onBackPressed(() => {
      if (this.onDismissOverlay()) {
        return true;
      }
      if (this.searchOpen) {
        this.toggleSearch(false);
        return true;
      }
      return false;
    })
  }
}
