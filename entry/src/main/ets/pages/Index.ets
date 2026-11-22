import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import {
  AppearanceConfig,
  AsrConfig,
  Attachment,
  BackupPreferencesConfig,
  BrowserBookmark,
  ChatItemDisplayConfig,
  ChatMessage,
  ContextLogEntry,
  Conversation,
  EnvVar,
  GenerationParams,
  InstructionCard,
  LocalSnapshotMeta,
  LocalWorkspace,
  McpServerConfig,
  MemoryEntry,
  MemorySettings,
  ModelDefaults,
  ModelSpec,
  OAuthProviderKind,
  Persona,
  Provider,
  QuickPhrase,
  QuoteRef,
  ReasoningEffort,
  RequestLogEntry,
  S3BackupConfig,
  ScheduledTask,
  SearchConfig,
  SearchHit,
  SearchServiceConfig,
  SkillRecord,
  SystemSettings,
  TokenUsage,
  ToolCallRecord,
  ToolPermissionMode,
  ToolSchemaOverride,
  TtsConfig,
  UsageStatRow,
  UserProfileField,
  MemoryTrace,
  WorldBook,
  Workspace,
  defaultAppearance,
  defaultChatItemDisplay,
  defaultGenerationParams,
  defaultInstructionCards,
  defaultQuickPhrases,
  defaultSearchServices,
  defaultSystemSettings,
  findProviderModelSpec,
  getAllAttachments,
  initialWorkspace,
  isProviderConfigured,
  normalizeAppearanceConfig,
  normalizeBackupConfig,
  resolveActiveModel
} from '../core/Models';
import { ChatCall, ChatCallOptions, RichFragment, makeAdvancedChatCall } from '../core/Protocol';
import { ChatStream, completeOnce, generateImages } from '../core/ChatClient';
import { WorkspaceStore, exportChats, forgetKey, importChats, newId, readKey, storeKey } from '../core/Storage';
import { ImportedProvider } from '../core/ProviderLink';
import {
  computeStorageBreakdown,
  hydrateAttachmentData,
  pickMultipleAttachments,
  pickPhotoAttachments,
  takePhotoAttachment
} from '../core/AttachmentStore';
import { BrandIconId, resolveBrandIconId, splitAssistantParagraphs } from '../core/BrandIcons';
import { selectApiKey, markKeyError, markKeySuccess } from '../core/KeyPool';
import {
  appendMessageVersion,
  applyContextCompression,
  buildCompressionPrompt,
  deleteMessageVersion,
  exportMessagesAsMarkdown,
  exportMessagesAsPlainText,
  sliceContextMessages,
  switchMessageVersion,
  undoContextCompression,
  updateActiveMessageVersionText,
  updateActiveMessageVersionTranslation
} from '../core/ContextUtils';
import { Narration } from '../core/Narration';
import { SpeechInputController } from '../core/SpeechInput';
import { McpManager, McpTool } from '../core/RemoteTools';
import { McpDiscoveredDescriptor, RegisteredTool, assembleToolRegistry, defaultMaxToolSteps } from '../core/ToolRegistry';
import { ToolExecutionOutput, runAgentToolLoop } from '../core/ToolLoop';
import { PromptTemplateContext, applyRegexRules, buildAssembledPrompt } from '../core/PromptEngine';
import {
  buildMemoryInjectionBlock,
  buildMemoryRulesSystemPrompt,
  normalizeMemorySettings,
  resolveMemoryPromptLang
} from '../core/MemoryLogic';
import {
  buildMemoryTools,
  buildMemoryOrganizeBatch,
  executeMemoryToolCall,
  runMemoryPipeline
} from '../core/MemoryEngine';
import { PaletteTokens, resolveEffectiveDark, resolveThemeTokens, resolveWallpaperColor } from '../core/ThemeManager';
import { createLocalSnapshot } from '../core/BackupManager';
import { UiStrings, getUiStrings } from '../core/I18n';
import {
  applyKeepScreenOn,
  applySystemColorMode,
  ensureNotificationPermission,
  notifyGenerationComplete,
  sharePlainText,
  triggerHapticFeedback
} from '../core/SystemBridge';
import { MessageBody } from '../components/MessageBody';
import { PersonaEditor } from '../components/PersonaEditor';
import { ProviderEditor } from '../components/ProviderEditor';
import { SearchEditor } from '../components/SearchEditor';
import { ToolsPanel } from '../components/ToolsPanel';
import { WebDavPanel } from '../components/WebDavPanel';
import { ContextSheet } from '../components/ContextSheet';
import { VoiceSettingsPanel } from '../components/VoiceSettingsPanel';
import { RichPreviewKind, RichPreviewSheet } from '../components/RichPreviewSheet';
import { ImageViewerSheet } from '../components/ImageViewerSheet';
import { PromptToolsPanel } from '../components/PromptToolsPanel';
import { MemoryPanel } from '../components/MemoryPanel';
import { TranslatePanel } from '../components/TranslatePanel';
import { StatsPanel } from '../components/StatsPanel';
import { DiagnosticsPanel, ToolSchemaCandidate } from '../components/DiagnosticsPanel';
import { AppearancePanel } from '../components/AppearancePanel';
import { SettingsPanel } from '../components/SettingsPanel';
import { DefaultModelPanel } from '../components/DefaultModelPanel';
import { AboutPanel } from '../components/AboutPanel';
import { KelivoAvatarBadge, KelivoNavTitleBar } from '../components/KelivoChrome';
import { BottomToolsSheet } from '../components/BottomToolsSheet';
import { ModelSelectSheet } from '../components/ModelSelectSheet';
import { ChatToolsSheet, ReasoningLevelSheet, SearchQuickSheet } from '../components/ChatQuickSheets';
import { OAuthLoginSheet } from '../components/OAuthLoginSheet';
import { WorkspacePanel } from '../components/WorkspacePanel';
import { SkillsPanel } from '../components/SkillsPanel';
import { BrowserPanel } from '../components/BrowserPanel';
import { ScheduledTasksPanel } from '../components/ScheduledTasksPanel';
import { buildWorkspaceTools, executeWorkspaceTool } from '../core/WorkspaceTools';
import { buildSkillsPromptSummary, defaultBuiltinSkills } from '../core/SkillsParser';
import { buildSkillTools, executeSkillTool } from '../core/SkillsManager';
import { BrowserAgentManager, buildBrowserTools } from '../core/BrowserAgent';
import { AskUserPromptRequest, DeviceToolBridge, buildDeviceTools, executeDeviceTool } from '../core/DeviceTools';
import { ScheduledTaskRunner } from '../core/ScheduledTasks';
import { WebSearch, fetchWebPage } from '../core/WebSearch';
import { computeFloatingBottomInsetVp, hexWithAlpha } from '../core/ImmersiveUtils';
import { syncWindowBackgroundColor, syncWindowSystemBars } from '../core/WindowController';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { SystemMotion } from '../core/SystemMotion';

interface ComposerDraftData {
  text: string;
  attachments: Attachment[];
}

interface ResolvedProviderAuth {
  key: string;
  keyEntryId: string;
  proxyPass: string;
}

interface ResolvedRoleTarget {
  prov: Provider;
  model: string;
}

interface MemoryQueueJob {
  workspace: Workspace;
  chatId: string;
  personaId: string;
  fallback: ResolvedRoleTarget;
  manual: boolean;
  fromEditor?: boolean;
}

@Entry
@Component
struct Index {
  @State workspace: Workspace = initialWorkspace();
  @State activeRoute: string = 'chat';
  @State ready: boolean = false;
  @State loadError: string = '';
  @State wide: boolean = false;
  @State notice: string = '';
  @State renameId: string = '';
  @State renameText: string = '';
  @State query: string = '';
  @State draft: string = '';
  @State attachedList: Attachment[] = [];
  @State quoteDraft?: QuoteRef = undefined;
  @State draftPersona: string = 'default';
  @State working: boolean = false;
  @State picking: boolean = false;
  @State liveText: string = '';
  @State liveReasoning: string = '';
  @State searchOn: boolean = false;
  @State imageGenMode: boolean = false;
  @State ephemeralMode: boolean = false;
  @State fetchingSources: boolean = false;
  @State expandedSources: string = '';
  @State expandedReasoning: string = '';
  @State expandedToolId: string = '';
  @State readingId: string = '';
  @State ttsPaused: boolean = false;
  @State recording: boolean = false;
  @State liveToolCalls: ToolCallRecord[] = [];
  @State pendingApprovalTool: string = '';
  @State pendingApprovalArgs: string = '';
  @State fullAccessMode: boolean = false;
  // In-conversation search & minimap & selection export
  @State inChatSearchOpen: boolean = false;
  @State inChatQuery: string = '';
  @State inChatMatchPos: number = 0;
  @State showMiniMap: boolean = false;
  @State multiSelectMode: boolean = false;
  @State selectedMsgIds: string[] = [];
  // Message edit / select-copy / export dialogs
  @State editingMsgId: string = '';
  @State editingMsgText: string = '';
  @State selectCopyText: string = '';
  @State showModelQuickSheet: boolean = false;
  // Rich preview & Image viewer overlays
  @State previewVisible: boolean = false;
  @State previewKind: RichPreviewKind = 'html';
  @State previewTitle: string = '';
  @State previewCode: string = '';
  @State imageViewerSrc: string = '';
  @State imageViewerTitle: string = '';
  @State requestLogs: RequestLogEntry[] = [];
  @State contextLogs: ContextLogEntry[] = [];
  @State usageStats: UsageStatRow[] = [];
  @State translateInitialText: string = '';
  @State showPromptQuickBar: boolean = false;
  @State isSystemDark: boolean = false;
  @State filesDirPath: string = '';
  @State dbDirPath: string = '';
  @State oauthModalVisible: boolean = false;
  @State oauthKind: OAuthProviderKind = 'chatgpt';
  @State sidePanelMode: '' | 'browser' | 'workspace' = '';
  @State wideSide: boolean = false;
  @State askQuestionText: string = '';
  @State askQuestionOptions: string[] = [];
  @State askQuestionPlaceholder: string = '';
  @State askQuestionAnswer: string = '';
  @State drawerOpen: boolean = false;
  @State drawerAssistantsExpanded: boolean = false;
  @State drawerGlobalSearch: boolean = false;
  @State drawerEditingUser: boolean = false;
  @State drawerUserNameDraft: string = '';
  @State promptTabInit: number = 0;
  @State diagTabInit: number = 0;
  @State providerOpenProxy: boolean = false;
  @State personaEditTargetId: string = '';
  @State preferencesSubView: string = '';
  @State storageSizeLabel: string = '0 B';
  @State showBottomToolsSheet: boolean = false;
  @State showSearchQuickSheet: boolean = false;
  @State showReasoningSheet: boolean = false;
  @State showChatToolsSheet: boolean = false;
  @State showMessageActionSheet: boolean = false;
  @State messageActionTargetId: string = '';
  @State regeneratingMsgId: string = '';
  @State composerBarHeightVp: number = 136;
  @State chatScrollNavVisible: boolean = false;
  @State chatScrollNavSide: 'left' | 'right' = 'right';
  @State lastSendError: string = '';
  @State lastSendErrorChatId: string = '';
  @State expandedLongMsgIds: string[] = [];
  @State organizingMemoryChatId: string = '';
  @State organizingMemoryAssistantId: string = '';
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('windowKeyboardHeightVp') @Watch('onKeyboardHeightChanged') winKeyboardHeight: number = 0;
  @StorageProp('windowLeftInsetVp') winLeftInset: number = 0;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('windowTitleRightAvoidVp') winTitleRightAvoid: number = 0;
  @StorageProp('windowIsFloating') winIsFloating: boolean = false;
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;
  @StorageProp('systemIsDark') @Watch('onSystemDarkChanged') sysDarkFromAbility: boolean = false;

  private store?: WorkspaceStore;
  private stream?: ChatStream;
  private searcher?: WebSearch;
  private mcpManager: McpManager = new McpManager();
  private browserManager: BrowserAgentManager = new BrowserAgentManager();
  private scheduler: ScheduledTaskRunner = new ScheduledTaskRunner();
  private speechInput: SpeechInputController = new SpeechInputController();
  private approvalResolver?: (choice: 'allow_once' | 'allow_all' | 'deny') => void;
  private askUserResolver?: (val: string) => void;
  private stopped: boolean = false;
  private scrollView: Scroller = new Scroller();
  private memoryQueue: MemoryQueueJob[] = [];
  private memoryQueueRunning: boolean = false;
  private memoryWindowFailures: Map<string, number> = new Map<string, number>();
  private drafts: Map<string, ComposerDraftData> = new Map<string, ComposerDraftData>();
  private speaker: Narration = new Narration();
  private followBottom: boolean = true;
  private chatScrollNavHideTimer: number = -1;
  private chatFirstVisibleIdx: number = 0;
  private chatLastVisibleIdx: number = 0;
  private chatNavTargetIdx: number = -1;
  private holdingHandSubscribed: boolean = false;
  private navPathStack: NavPathStack = new NavPathStack();

  private readonly handleHoldingHandChanged = (status: motion.HoldingHandStatus): void => {
    let nextSide: 'left' | 'right' = this.chatScrollNavSide;
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
      nextSide = 'left';
    } else if (
      status === motion.HoldingHandStatus.RIGHT_HAND_HELD ||
      status === motion.HoldingHandStatus.BOTH_HANDS_HELD
    ) {
      nextSide = 'right';
    }
    if (nextSide !== this.chatScrollNavSide) {
      SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
        this.chatScrollNavSide = nextSide;
      });
    }
  };

  private startHoldingHandMonitor(): void {
    if (this.holdingHandSubscribed || !canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      return;
    }
    try {
      const recent = motion.getRecentOperatingHandStatus();
      if (recent === motion.OperatingHandStatus.LEFT_HAND_OPERATED) {
        this.chatScrollNavSide = 'left';
      } else if (recent === motion.OperatingHandStatus.RIGHT_HAND_OPERATED) {
        this.chatScrollNavSide = 'right';
      }
    } catch (_) {}
    try {
      motion.on('holdingHandChanged', this.handleHoldingHandChanged);
      this.holdingHandSubscribed = true;
    } catch (_) {}
  }

  private stopHoldingHandMonitor(): void {
    if (!this.holdingHandSubscribed) {
      return;
    }
    this.holdingHandSubscribed = false;
    try {
      motion.off('holdingHandChanged', this.handleHoldingHandChanged);
    } catch (_) {}
  }

  aboutToAppear(): void {
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (_) {}
    this.startHoldingHandMonitor();
    this.navPathStack.setInterception({
      didShow: (_from: NavDestinationContext | NavBar, _to: NavDestinationContext | NavBar, _op: NavigationOperation, _animated: boolean) => {
        this.syncActiveRouteFromStack();
      }
    });
    this.loadWorkspace();
  }
  onPageShow(): void {
    this.startHoldingHandMonitor();
    this.consumePendingShareText();
  }
  onPageHide(): void {
    this.stopHoldingHandMonitor();
  }
  aboutToDisappear(): void {
    this.stopHoldingHandMonitor();
    this.hideChatScrollNavImmediate();
    this.stopReply();
    this.scheduler.stop();
    this.speaker.stop();
    this.speechInput.stopSystemDictation().catch(() => {});
  }

  private onKeyboardHeightChanged(): void {
    if (this.winKeyboardHeight > 0 && this.activeRoute === 'chat' && this.followBottom && (this.activeChat()?.messages.length || 0) > 0) {
      setTimeout(() => {
        if (this.followBottom) {
          this.scrollView.scrollEdge(Edge.Bottom);
        }
      }, 60);
    }
  }

  private updateComposerBarHeight(h: number): void {
    const rounded = Math.round(h);
    if (rounded > 40 && Math.abs(rounded - this.composerBarHeightVp) >= 2) {
      this.composerBarHeightVp = rounded;
    }
  }

  private hideChatScrollNavImmediate(): void {
    if (this.chatScrollNavHideTimer >= 0) {
      clearTimeout(this.chatScrollNavHideTimer);
      this.chatScrollNavHideTimer = -1;
    }
    this.chatScrollNavVisible = false;
    this.chatNavTargetIdx = -1;
  }

  private scheduleChatScrollNavHide(): void {
    if (this.chatScrollNavHideTimer >= 0) {
      clearTimeout(this.chatScrollNavHideTimer);
      this.chatScrollNavHideTimer = -1;
    }
    this.chatScrollNavHideTimer = setTimeout(() => {
      this.chatScrollNavHideTimer = -1;
      SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
        this.chatScrollNavVisible = false;
      });
    }, 2600);
  }

  private showChatScrollNav(): void {
    if ((this.activeChat()?.messages.length || 0) === 0) {
      return;
    }
    if (!this.chatScrollNavVisible) {
      SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
        this.chatScrollNavVisible = true;
      });
    }
    this.scheduleChatScrollNavHide();
  }

  private jumpChatTop(): void {
    const msgs = this.activeChat()?.messages || [];
    if (msgs.length === 0) {
      return;
    }
    this.followBottom = false;
    this.chatNavTargetIdx = 0;
    this.scrollView.scrollToIndex(0, !this.reduceMotion, ScrollAlign.START);
    this.scheduleChatScrollNavHide();
  }

  private jumpChatPrev(): void {
    const msgs = this.activeChat()?.messages || [];
    if (msgs.length === 0) {
      return;
    }
    this.followBottom = false;
    const maxIdx = msgs.length - 1;
    const baseIdx = (this.chatNavTargetIdx >= 0 && this.chatNavTargetIdx <= maxIdx)
      ? this.chatNavTargetIdx
      : Math.max(0, Math.min(maxIdx, this.chatFirstVisibleIdx));
    const target = Math.max(0, baseIdx - 1);
    this.chatNavTargetIdx = target;
    this.scrollView.scrollToIndex(target, !this.reduceMotion, ScrollAlign.START);
    this.scheduleChatScrollNavHide();
  }

  private jumpChatNext(): void {
    const msgs = this.activeChat()?.messages || [];
    if (msgs.length === 0) {
      return;
    }
    const maxIdx = msgs.length - 1;
    const baseIdx = (this.chatNavTargetIdx >= 0 && this.chatNavTargetIdx <= maxIdx)
      ? this.chatNavTargetIdx
      : Math.max(0, Math.min(maxIdx, this.chatFirstVisibleIdx));
    if (baseIdx >= maxIdx) {
      this.followBottom = true;
      this.chatNavTargetIdx = maxIdx;
      this.scrollView.scrollEdge(Edge.Bottom);
    } else {
      const target = baseIdx + 1;
      this.chatNavTargetIdx = target;
      this.scrollView.scrollToIndex(target, !this.reduceMotion, ScrollAlign.START);
    }
    this.scheduleChatScrollNavHide();
  }

  private jumpChatBottom(): void {
    const msgs = this.activeChat()?.messages || [];
    if (msgs.length === 0) {
      return;
    }
    this.followBottom = true;
    this.chatNavTargetIdx = msgs.length - 1;
    this.scrollView.scrollEdge(Edge.Bottom);
    this.scheduleChatScrollNavHide();
  }

  private composerInactiveIconColor(): Resource {
    return ImmersiveMaterialStyle.isActive(this.immersiveLightOn())
      ? $r('sys.color.icon_secondary')
      : $r('app.color.muted');
  }

  private composerPillBg(): Resource {
    return ImmersiveMaterialStyle.isActive(this.immersiveLightOn())
      ? $r('sys.color.comp_background_tertiary')
      : $r('app.color.panel');
  }

  private consumePendingShareText(): void {
    const shared = AppStorage.get<string>('pendingShareText');
    if (shared && shared.trim().length > 0) {
      this.draft = this.draft.trim().length > 0 ? `${this.draft}\n\n${shared.trim()}` : shared.trim();
      AppStorage.setOrCreate('pendingShareText', '');
      this.navigateTo('chat');
      this.toast('已填入系统分享文本');
    }
  }

  private syncImmersiveStorage(): void {
    const tokens = this.themeTokens();
    AppStorage.setOrCreate('immersiveLightEnabled', this.immersiveLightOn());
    AppStorage.setOrCreate('effectiveDarkMode', this.effectiveDark());
    AppStorage.setOrCreate('themeAccentHex', tokens.accent);
    AppStorage.setOrCreate('themeSurfaceHex', tokens.surface);
    AppStorage.setOrCreate('themeTintHex', tokens.tint);
    AppStorage.setOrCreate('themeCanvasHex', tokens.canvas);
  }

  private syncActiveRouteFromStack(): void {
    const names = this.navPathStack.getAllPathName();
    this.activeRoute = names.length > 0 ? names[names.length - 1] : 'chat';
  }

  private navigateTo(route: string): void {
    if (this.drawerOpen) {
      this.drawerOpen = false;
    }
    if (route === 'chat') {
      if (this.navPathStack.size() > 0) {
        this.navPathStack.clear(true);
      }
      this.activeRoute = 'chat';
      return;
    }
    const names = this.navPathStack.getAllPathName();
    const top = names.length > 0 ? names[names.length - 1] : 'chat';
    if (top === route) {
      return;
    }
    this.navPathStack.pushPathByName(route, route, true);
    this.activeRoute = route;
  }

  private navigateBack(): void {
    if (this.navPathStack.size() > 0) {
      this.navPathStack.pop(true);
      this.syncActiveRouteFromStack();
    } else {
      this.activeRoute = 'chat';
    }
  }

  private setDrawerOpen(open: boolean): void {
    if (this.drawerOpen === open) {
      return;
    }
    SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.drawerOpen = open;
    });
  }

  private setSidePanelMode(mode: '' | 'browser' | 'workspace'): void {
    if (this.sidePanelMode === mode) {
      return;
    }
    SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.sidePanelMode = mode;
    });
  }

  private dismissTopOverlay(): boolean {
    if (this.oauthModalVisible) {
      SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
        this.oauthModalVisible = false;
      });
      return true;
    }
    if (this.previewVisible) {
      SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
        this.previewVisible = false;
      });
      return true;
    }
    if (this.imageViewerSrc) {
      SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
        this.imageViewerSrc = '';
      });
      return true;
    }
    if (this.selectCopyText) {
      SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
        this.selectCopyText = '';
      });
      return true;
    }
    if (this.editingMsgId) {
      SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
        this.editingMsgId = '';
      });
      return true;
    }
    return false;
  }

  onBackPress(): boolean {
    if (this.dismissTopOverlay()) { return true; }
    if (this.showChatToolsSheet) { this.showChatToolsSheet = false; return true; }
    if (this.showReasoningSheet) { this.showReasoningSheet = false; return true; }
    if (this.showSearchQuickSheet) { this.showSearchQuickSheet = false; return true; }
    if (this.showBottomToolsSheet) { this.showBottomToolsSheet = false; return true; }
    if (this.showMiniMap) { this.showMiniMap = false; return true; }
    if (this.showModelQuickSheet) { this.showModelQuickSheet = false; return true; }
    if (this.drawerOpen) { this.setDrawerOpen(false); return true; }
    if (this.navPathStack.size() > 0) { this.navigateBack(); return true; }
    return false;
  }

  host(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  async loadWorkspace(): Promise<void> {
    this.loadError = '';
    try {
      const ctx = this.host();
      this.filesDirPath = ctx.filesDir;
      this.dbDirPath = ctx.databaseDir || ctx.filesDir;
      const cfgDark = ctx.config?.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      this.isSystemDark = cfgDark;
      if (AppStorage.get<boolean>('systemIsDark') === undefined) {
        AppStorage.setOrCreate('systemIsDark', cfgDark);
      }
      this.store = new WorkspaceStore(ctx);
      this.workspace = await this.store.load();
      if (!this.workspace.instructionCards || this.workspace.instructionCards.length === 0) {
        this.workspace.instructionCards = defaultInstructionCards();
      }
      if (!this.workspace.quickPhrases || this.workspace.quickPhrases.length === 0) {
        this.workspace.quickPhrases = defaultQuickPhrases();
      }
      if (!this.workspace.appearance) {
        this.workspace.appearance = defaultAppearance();
      } else {
        this.workspace.appearance = normalizeAppearanceConfig(this.workspace.appearance);
      }
      if (!this.workspace.favoriteModels) {
        this.workspace.favoriteModels = [];
      }
      if (!this.workspace.userName) {
        this.workspace.userName = '用户';
      }
      if (!this.workspace.memorySettings) {
        this.workspace.memorySettings = { autoExtract: false, injectGlobal: true, maxInjectCount: 10 };
      }
      if (!this.workspace.systemSettings) {
        this.workspace.systemSettings = defaultSystemSettings();
      }
      if (!this.workspace.backupConfig) {
        this.workspace.backupConfig = normalizeBackupConfig();
        if (this.workspace.systemSettings.autoSnapshotEnabled === false) {
          this.workspace.backupConfig.localCopiesEnabled = false;
        }
      } else {
        this.workspace.backupConfig = normalizeBackupConfig(this.workspace.backupConfig);
      }
      if (!this.workspace.skills || this.workspace.skills.length === 0) {
        this.workspace.skills = defaultBuiltinSkills();
      }
      if ((this.workspace.version || 1) < 2) {
        if (this.workspace.generationParams && this.workspace.generationParams.reasoningEffort === 'medium') {
          this.workspace.generationParams.reasoningEffort = 'off';
        }
        if (this.workspace.systemSettings) {
          this.workspace.systemSettings.chatSuggestionsEnabled = false;
          this.workspace.systemSettings.enabledDeviceTools = [];
        }
        if (this.workspace.modelDefaults) {
          const chatProv = this.workspace.providers.find((p: Provider): boolean => p.id === this.workspace.modelDefaults?.chatProviderId);
          if (chatProv && !isProviderConfigured(chatProv)) {
            this.workspace.modelDefaults.chatProviderId = '';
            this.workspace.modelDefaults.chatModelId = '';
          }
        }
        this.workspace.version = 2;
        this.store.save(this.workspace).catch(() => {});
      }
      this.followBottom = true;
      this.searchOn = this.workspace.systemSettings?.searchEnabled === true;
      applySystemColorMode(ctx, this.workspace.appearance.themeMode);
      syncWindowSystemBars(this.effectiveDark());
      syncWindowBackgroundColor(this.themeTokens().canvas);
      this.syncImmersiveStorage();
      this.refreshStorageSize().catch(() => {});
      const active = this.activeChat();
      if (active?.draftText) this.draft = active.draftText;
      this.draftPersona = active?.personaId || (this.workspace.personas[0]?.id || 'default');
      this.ready = true;
      this.scrollDown(true);
      this.consumePendingShareText();
      this.scheduler.start({
        getWorkspace: (): Workspace => this.workspace,
        getContext: (): common.UIAbilityContext | undefined => this.host(),
        onTaskResult: (updatedTask: ScheduledTask, newConv?: Conversation) => this.handleScheduledResult(updatedTask, newConv)
      });
      this.maybeAutoLocalCopy().catch(() => {});
    } catch (e) { this.loadError = '无法读取本地数据。' + ((e as Error).message || '请重试'); }
  }

  private async maybeAutoLocalCopy(): Promise<void> {
    const ctx = this.host();
    if (!ctx || !this.ready) return;
    const cfg = normalizeBackupConfig(this.workspace.backupConfig);
    if (!cfg.localCopiesEnabled) return;
    const hasContent = this.workspace.conversations.some((c: Conversation): boolean => !c.ephemeral && c.messages.length > 0);
    if (!hasContent) return;
    const days = cfg.localCopiesIntervalDays > 0 ? cfg.localCopiesIntervalDays : 1;
    const dueMs = days * 24 * 3600 * 1000;
    const snaps = this.workspace.snapshots || [];
    const lastAt = cfg.localCopiesLastSuccessAt || (snaps.length > 0 ? snaps[0].createdAt : 0);
    if (lastAt > 0 && Date.now() - lastAt < dueMs) return;
    try {
      await createLocalSnapshot(ctx.filesDir, this.workspace, 'auto');
      cfg.localCopiesLastSuccessAt = Date.now();
      cfg.localCopiesLastError = undefined;
      this.workspace.backupConfig = cfg;
      await this.persist();
      await this.refreshStorageSize().catch(() => {});
    } catch (e) {
      cfg.localCopiesLastError = (e as Error).message || '自动保存副本失败';
      this.workspace.backupConfig = cfg;
    }
  }

  persist(): Promise<void> {
    if (!this.ready || !this.store) return Promise.reject(new Error('工作区尚未就绪'));
    return this.store.save(this.workspace);
  }

  persistAction(): void { this.persist().catch(() => { this.notice = '保存到设备失败，请检查剩余空间'; }); }
  toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast(
        ImmersiveMaterialStyle.toastOptions(message, this.immersiveLightOn())
      );
    } catch (_) {}
  }

  private immersiveLightOn(): boolean {
    return this.appearanceCfg().immersiveLightEnabled !== false;
  }

  private systemDarkNow(): boolean {
    return this.sysDarkFromAbility;
  }

  private effectiveDark(): boolean {
    return resolveEffectiveDark(this.appearanceCfg().themeMode, this.systemDarkNow());
  }

  private onSystemDarkChanged(): void {
    if (!this.ready) {
      return;
    }
    syncWindowSystemBars(this.effectiveDark());
    syncWindowBackgroundColor(this.themeTokens().canvas);
    this.syncImmersiveStorage();
  }

  private chatCanScrollUnderTitle(): boolean {
    return !this.inChatSearchOpen && !this.multiSelectMode && (Boolean(this.activeChat()) || this.working);
  }

  private chatTitleBarHeight(): number {
    return 56 + this.winTopInset;
  }

  private effectiveBottomInset(): number {
    return computeFloatingBottomInsetVp(this.winBottomInset, this.winIsFloating, this.wide);
  }

  activeChat(): Conversation | undefined {
    return this.workspace.conversations.find((c: Conversation): boolean => c.id === this.workspace.activeConversation);
  }

  provider(): Provider {
    const res = resolveActiveModel(this.workspace, this.activeChat(), this.persona());
    return res.provider;
  }

  activeModelId(): string {
    const res = resolveActiveModel(this.workspace, this.activeChat(), this.persona());
    return res.modelId || res.provider.model;
  }

  selectedPersonaId(): string {
    if (this.workspace.personas.some((p: Persona): boolean => p.id === this.draftPersona)) {
      return this.draftPersona;
    }
    const chatPid = this.activeChat()?.personaId;
    if (chatPid && this.workspace.personas.some((p: Persona): boolean => p.id === chatPid)) {
      return chatPid;
    }
    return this.workspace.personas[0]?.id || 'default';
  }

  persona(): Persona {
    const id = this.selectedPersonaId();
    return this.workspace.personas.find((p: Persona): boolean => p.id === id) || this.workspace.personas[0];
  }

  effectiveParams(): GenerationParams {
    return this.persona().params || this.workspace.generationParams || defaultGenerationParams();
  }

  chatRows(): Conversation[] {
    const q = this.query.trim().toLowerCase();
    const pid = this.selectedPersonaId();
    return this.workspace.conversations.filter((c: Conversation): boolean => {
      const assistantMatch = this.drawerGlobalSearch || c.personaId === pid ||
        (this.workspace.personas.length <= 1 && !c.personaId);
      if (!assistantMatch) return false;
      return !q || c.title.toLowerCase().includes(q) || c.messages.some((m: ChatMessage): boolean => m.text.toLowerCase().includes(q));
    }).sort((a: Conversation, b: Conversation): number => Number(!!b.pinned) - Number(!!a.pinned) || b.updated - a.updated);
  }

  private dateGroupLabel(c: Conversation): string {
    if (c.pinned) return '置顶';
    const d = new Date(c.updated || Date.now());
    const now = new Date();
    const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const dayStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    const diffDays = Math.round((startToday - dayStart) / 86400000);
    if (diffDays <= 0) return '今天';
    if (diffDays === 1) return '昨天';
    if (diffDays <= 7) return '近 7 天';
    return '更早';
  }

  private isDrawerGroupStart(rows: Conversation[], idx: number): boolean {
    if (idx <= 0) return true;
    return this.dateGroupLabel(rows[idx]) !== this.dateGroupLabel(rows[idx - 1]);
  }

  private async refreshStorageSize(): Promise<void> {
    if (!this.filesDirPath) return;
    const stats = await computeStorageBreakdown(this.filesDirPath, this.dbDirPath || this.filesDirPath);
    const total = stats.totalBytes;
    if (total < 1024) {
      this.storageSizeLabel = `${total} B`;
    } else if (total < 1024 * 1024) {
      this.storageSizeLabel = `${(total / 1024).toFixed(1)} KB`;
    } else {
      this.storageSizeLabel = `${(total / (1024 * 1024)).toFixed(1)} MB`;
    }
  }

  private selectModelQuick(providerId: string, modelId: string): void {
    this.workspace.activeProvider = providerId;
    const prov = this.workspace.providers.find((p: Provider): boolean => p.id === providerId);
    if (prov && modelId) {
      prov.model = modelId;
    }
    const perChat = this.workspace.modelDefaults?.perChatModel === true;
    const c = this.activeChat();
    if (c && perChat) {
      c.overrideProviderId = providerId;
      c.overrideModel = modelId;
    } else {
      if (c) {
        c.overrideProviderId = undefined;
        c.overrideModel = undefined;
      }
      if (!perChat && this.persona()) {
        const curPersona = this.persona();
        curPersona.providerId = providerId;
        curPersona.modelId = modelId;
      }
    }
    this.showModelQuickSheet = false;
    this.persistAction();
  }

  private toggleFavoriteModel(providerId: string, modelId: string): void {
    const key = `${providerId}::${modelId}`;
    const list = this.workspace.favoriteModels || [];
    this.workspace.favoriteModels = list.includes(key)
      ? list.filter((item: string): boolean => item !== key)
      : [...list, key];
    this.persistAction();
  }

  private duplicateChat(c: Conversation): void {
    const copy: Conversation = {
      id: newId(),
      title: `${c.title} (副本)`,
      updated: Date.now(),
      pinned: false,
      messages: c.messages.slice(),
      personaId: c.personaId
    };
    this.putChat(copy);
    this.workspace.activeConversation = copy.id;
    this.persistAction();
    this.scrollDown(true);
    this.toast('已复制对话');
  }

  private moveChatToNextPersona(c: Conversation): void {
    const list = this.workspace.personas;
    if (list.length <= 1) return;
    const curIdx = list.findIndex((p: Persona): boolean => p.id === c.personaId);
    const next = list[(curIdx + 1) % list.length];
    this.putChat({
      id: c.id,
      title: c.title,
      updated: c.updated,
      pinned: c.pinned,
      messages: c.messages,
      personaId: next.id
    });
    this.persistAction();
    this.toast(`已移至「${next.name}」`);
  }

  private resetChatContextWindow(): void {
    const c = this.activeChat();
    if (!c) return;
    c.contextStartIndex = c.messages.length;
    c.updated = Date.now();
    this.workspace.conversations = this.workspace.conversations.slice();
    this.showBottomToolsSheet = false;
    if (!c.ephemeral) {
      this.persistAction();
    }
    this.toast('已重置上下文窗口');
  }

  private setSearchEnabled(enabled: boolean, save: boolean = true): void {
    this.searchOn = enabled;
    const sys = this.workspace.systemSettings || defaultSystemSettings();
    sys.searchEnabled = enabled;
    this.workspace.systemSettings = sys;
    if (save) {
      this.persistAction();
    }
  }

  private selectSearchServiceQuick(id: string): void {
    this.workspace.activeSearchId = id;
    this.setSearchEnabled(true);
  }

  private toggleChatMcp(id: string, on: boolean): void {
    const servers = this.workspace.mcpServers || [];
    this.workspace.mcpServers = servers.map((s: McpServerConfig): McpServerConfig => {
      if (s.id === id) {
        return {
          id: s.id,
          name: s.name,
          transport: s.transport,
          endpoint: s.endpoint,
          bearerSecretRef: s.bearerSecretRef,
          customHeaders: s.customHeaders,
          oauthAccessTokenRef: s.oauthAccessTokenRef,
          enabled: on,
          disabledTools: s.disabledTools,
          autoApproveTools: s.autoApproveTools
        };
      }
      return s;
    });
    this.persistAction();
  }

  private toggleQuickDeviceTool(id: string, on: boolean): void {
    const cfg = this.workspace.systemSettings || defaultSystemSettings();
    const cur = cfg.enabledDeviceTools ? cfg.enabledDeviceTools.slice() : [];
    const nextList = on
      ? (cur.includes(id) ? cur : [...cur, id])
      : cur.filter((item: string): boolean => item !== id);
    cfg.enabledDeviceTools = nextList;
    this.workspace.systemSettings = cfg;
    this.persistAction();
  }

  private selectChatWorkspace(id: string): void {
    const c = this.activeChat();
    if (c) {
      c.workspaceId = id || undefined;
      this.workspace.conversations = this.workspace.conversations.slice();
    } else {
      this.toast('开始对话后将自动绑定该工作区');
    }
    this.persistAction();
  }

  private setChatFullAccess(full: boolean): void {
    this.fullAccessMode = full;
    const c = this.activeChat();
    if (c) {
      c.toolPermissionMode = full ? 'full' : 'ask';
      this.workspace.conversations = this.workspace.conversations.slice();
    }
    this.persistAction();
  }

  private activeEnabledMcpIds(): string[] {
    return (this.workspace.mcpServers || [])
      .filter((s: McpServerConfig): boolean => s.enabled)
      .map((s: McpServerConfig): string => s.id);
  }

  private enabledDeviceToolsList(): string[] {
    return this.workspace.systemSettings?.enabledDeviceTools || [];
  }

  private selectAssistant(personaId: string, closeDrawer: boolean = true): void {
    this.draftPersona = personaId;
    this.drawerGlobalSearch = false;
    this.drawerAssistantsExpanded = false;
    const candidates = this.workspace.conversations
      .filter((c: Conversation): boolean => !c.ephemeral && c.personaId === personaId)
      .sort((a: Conversation, b: Conversation): number => Number(!!b.pinned) - Number(!!a.pinned) || b.updated - a.updated);
    const cur = this.activeChat();
    if (candidates.length > 0) {
      if (!cur || cur.personaId !== personaId) {
        this.activate(candidates[0].id);
      }
    } else if (cur && cur.personaId !== personaId) {
      this.activate('');
    }
    if (closeDrawer) {
      this.setDrawerOpen(false);
    }
  }

  activate(chatId: string, createEphemeral: boolean = false): void {
    if (this.working || this.picking) return;
    const prevId = this.workspace.activeConversation;
    this.drafts.set(prevId, { text: this.draft, attachments: this.attachedList.slice() });
    const prevChat = this.activeChat();
    if (prevChat && !prevChat.ephemeral) {
      prevChat.draftText = this.draft;
    }
    const stored = this.drafts.get(chatId);
    this.workspace.activeConversation = chatId;
    const nextChat = this.activeChat();
    if (nextChat && this.workspace.personas.some((p: Persona): boolean => p.id === nextChat.personaId)) {
      this.draftPersona = nextChat.personaId;
    }
    this.draft = stored?.text ?? nextChat?.draftText ?? '';
    this.attachedList = stored?.attachments?.slice() || [];
    this.quoteDraft = undefined;
    this.ephemeralMode = createEphemeral || !!nextChat?.ephemeral;
    this.imageGenMode = !!nextChat?.imageGenMode;
    this.fullAccessMode = nextChat?.toolPermissionMode === 'full';
    this.inChatSearchOpen = false;
    this.inChatQuery = '';
    this.multiSelectMode = false;
    this.selectedMsgIds = [];
    this.lastSendError = '';
    this.lastSendErrorChatId = '';
    this.notice = '';
    this.hideChatScrollNavImmediate();
    this.navigateTo('chat');
    this.followBottom = true;
    this.persistAction();
    this.scrollDown(true);
  }

  putChat(chat: Conversation): void {
    const prev = this.workspace.conversations.find((c: Conversation): boolean => c.id === chat.id);
    if (chat.pinned === undefined) chat.pinned = prev?.pinned;
    if (chat.ephemeral === undefined) chat.ephemeral = prev?.ephemeral;
    if (chat.contextStartIndex === undefined) chat.contextStartIndex = prev?.contextStartIndex;
    if (chat.personaId === prev?.personaId && chat.memoryOrganizedThrough === undefined) {
      chat.memoryOrganizedThrough = prev.memoryOrganizedThrough;
    }
    if (chat.overrideProviderId === undefined) chat.overrideProviderId = prev?.overrideProviderId;
    if (chat.overrideModel === undefined) chat.overrideModel = prev?.overrideModel;
    if (chat.overridePrompt === undefined) chat.overridePrompt = prev?.overridePrompt;
    if (chat.suggestions === undefined) chat.suggestions = prev?.suggestions;
    this.workspace.conversations = [chat, ...this.workspace.conversations.filter((c: Conversation): boolean => c.id !== chat.id)];
  }

  scrollDown(force: boolean = false): void {
    if (force) {
      this.followBottom = true;
      const jumpToLatest = () => {
        const count = this.activeChat()?.messages.length || 0;
        if (count > 0) {
          this.scrollView.scrollToIndex(count - 1, false, ScrollAlign.END);
        }
        this.scrollView.scrollEdge(Edge.Bottom);
      };
      jumpToLatest();
      setTimeout(jumpToLatest, 24);
      setTimeout(jumpToLatest, 80);
      setTimeout(jumpToLatest, 180);
      return;
    }
    if (this.followBottom) {
      setTimeout(() => {
        if (this.followBottom) {
          this.scrollView.scrollEdge(Edge.Bottom);
        }
      }, 30);
    }
  }

  async applyProvider(p: Provider, key: string, reuse: boolean, setActive: boolean = false): Promise<Provider[]> {
    const previous = this.workspace.providers;
    const priorId = this.workspace.activeProvider;
    const oldRef = p.secretRef;
    let ref = reuse ? oldRef : '';
    if (key) {
      ref = newId();
      try { await storeKey(ref, key); } catch (_) { throw new Error('系统密钥库写入失败，请检查设备是否已解锁'); }
    }
    p.secretRef = ref;
    this.workspace.providers = previous.some((v: Provider): boolean => v.id === p.id) ?
      previous.map((v: Provider): Provider => v.id === p.id ? p : v) : [p, ...previous];
    const priorActiveProv = previous.find((v: Provider): boolean => v.id === priorId);
    const curIsConfigured = priorActiveProv ? isProviderConfigured(priorActiveProv) : false;
    if (setActive || (!curIsConfigured && isProviderConfigured(p))) {
      this.workspace.activeProvider = p.id;
      if (setActive && this.workspace.modelDefaults && p.model.trim()) {
        this.workspace.modelDefaults.chatProviderId = p.id;
        this.workspace.modelDefaults.chatModelId = p.model.trim();
      }
    }
    try { await this.persist(); }
    catch (e) {
      this.workspace.providers = previous;
      this.workspace.activeProvider = priorId;
      if (key) await forgetKey(ref);
      throw e as Error;
    }
    if (oldRef && oldRef !== ref) await forgetKey(oldRef).catch(() => {});
    this.notice = '';
    return this.workspace.providers.slice();
  }

  async importProviders(items: ImportedProvider[]): Promise<Provider[]> {
    const previous = this.workspace.providers.slice();
    const priorActiveId = this.workspace.activeProvider;
    const hadAnyKey = this.hasAnyConfiguredKey();
    const createdRefs: string[] = [];
    const importedList: Provider[] = [];
    try {
      for (let i = 0; i < items.length; i++) {
        const entry = items[i];
        const cloned: Provider = {
          id: entry.provider.id,
          name: entry.provider.name,
          family: entry.provider.family,
          baseUrl: entry.provider.baseUrl,
          model: entry.provider.model,
          secretRef: entry.provider.secretRef,
          models: entry.provider.models ? entry.provider.models.slice() : [],
          apiKeys: entry.provider.apiKeys ? entry.provider.apiKeys.slice() : [],
          keyStrategy: entry.provider.keyStrategy || 'round_robin',
          groupName: entry.provider.groupName,
          oauth: entry.provider.oauth,
          enabled: entry.provider.enabled !== false
        };
        const cleanKey = entry.key.trim();
        if (cleanKey.length > 0) {
          const ref = newId();
          try {
            await storeKey(ref, cleanKey);
          } catch (_) {
            throw new Error('系统密钥库写入失败，请检查设备是否已解锁');
          }
          createdRefs.push(ref);
          cloned.secretRef = ref;
        }
        importedList.push(cloned);
      }
      this.workspace.providers = [...importedList, ...previous];
      const curActiveProv = previous.find((p: Provider): boolean => p.id === priorActiveId);
      if ((!hadAnyKey || !curActiveProv?.secretRef) && importedList.length > 0 && importedList[0].secretRef) {
        this.workspace.activeProvider = importedList[0].id;
      }
      await this.persist();
      this.notice = '';
      this.toast(`已导入 ${importedList.length} 个供应商`);
      return this.workspace.providers.slice();
    } catch (e) {
      this.workspace.providers = previous;
      this.workspace.activeProvider = priorActiveId;
      for (let i = 0; i < createdRefs.length; i++) {
        await forgetKey(createdRefs[i]).catch(() => {});
      }
      throw e as Error;
    }
  }

  async deleteProvider(id: string): Promise<Provider[]> {
    if (this.workspace.providers.length <= 1) return this.workspace.providers.slice();
    const target = this.workspace.providers.find((p: Provider): boolean => p.id === id);
    if (target?.secretRef) await forgetKey(target.secretRef).catch(() => {});
    this.workspace.providers = this.workspace.providers.filter((p: Provider): boolean => p.id !== id);
    if (this.workspace.activeProvider === id) this.workspace.activeProvider = this.workspace.providers[0].id;
    this.persistAction();
    return this.workspace.providers.slice();
  }

  async savePersona(p: Persona, setActive: boolean): Promise<void> {
    const previous = this.workspace.personas;
    this.workspace.personas = previous.some((v: Persona): boolean => v.id === p.id)
      ? previous.map((v: Persona): Persona => (v.id === p.id ? p : v))
      : [...previous, p];
    if (setActive) {
      this.selectAssistant(p.id, false);
    }
    try {
      await this.persist();
    } catch (e) {
      this.workspace.personas = previous;
      throw e as Error;
    }
  }

  async deletePersonaById(id: string): Promise<void> {
    if (this.workspace.personas.length <= 1) return;
    const next = this.workspace.personas.filter((v: Persona): boolean => v.id !== id);
    if (next.length === 0) return;
    this.workspace.personas = next;
    if (this.draftPersona === id) {
      this.draftPersona = next[0].id;
    }
    this.persistAction();
  }

  async applyPersona(p: Persona): Promise<void> {
    await this.savePersona(p, true);
  }

  private appearanceCfg(): AppearanceConfig {
    return this.workspace.appearance || defaultAppearance();
  }

  private themeTokens(): PaletteTokens {
    return resolveThemeTokens(this.appearanceCfg(), this.systemDarkNow());
  }

  private uiLabels(): UiStrings {
    return getUiStrings(this.appearanceCfg().language);
  }

  private chatBgColor(): string {
    const pBg = this.persona().chatBackground;
    if (pBg && pBg.length > 0) return pBg;
    const wp = resolveWallpaperColor(
      this.appearanceCfg(),
      this.effectiveDark()
    );
    if (wp.length > 0) return wp;
    return this.themeTokens().canvas;
  }

  private bodyTextSize(): number {
    return Math.round(16 * (this.appearanceCfg().fontScale || 1.0));
  }

  private codeTextSize(): number {
    return this.appearanceCfg().codeFontSize || 13;
  }

  private bubbleRadiusVal(): number {
    return this.appearanceCfg().bubbleRadius || 18;
  }

  private chatDisplayCfg(): ChatItemDisplayConfig {
    return this.appearanceCfg().chatItemDisplay || defaultChatItemDisplay();
  }

  private hasAnyConfiguredKey(): boolean {
    const provs = this.workspace.providers || [];
    for (let i = 0; i < provs.length; i++) {
      if (isProviderConfigured(provs[i])) {
        return true;
      }
    }
    return false;
  }

  private showProviderHintBanner(): boolean {
    return !this.activeChat() && !this.working && !this.ephemeralMode && !this.hasAnyConfiguredKey();
  }

  private isIncognitoEmpty(): boolean {
    return !this.activeChat() && !this.working && this.ephemeralMode;
  }

  private activeBrandId(): BrandIconId {
    return resolveBrandIconId(`${this.activeModelId()} ${this.provider().name}`, this.provider().family);
  }

  private activeModelSupportsReasoning(): boolean {
    const p = this.provider();
    const mid = this.activeModelId();
    if (!mid) return false;
    return findProviderModelSpec(p, mid).reasoning;
  }

  private reasoningLabelShort(): string {
    const eff = this.effectiveParams().reasoningEffort || 'off';
    if (eff === 'off') return '关闭';
    if (eff === 'low') return '低';
    if (eff === 'high') return '高';
    if (eff === 'max') return '极高';
    return '中';
  }

  private updateReasoningConfig(effort: ReasoningEffort, budget?: number): void {
    const cur = this.workspace.generationParams || defaultGenerationParams();
    this.workspace.generationParams = {
      temperature: cur.temperature,
      topP: cur.topP,
      maxTokens: cur.maxTokens,
      reasoningEffort: effort,
      reasoningBudget: budget !== undefined ? budget : (cur.reasoningBudget || 8192),
      responseSpeed: cur.responseSpeed,
      contextLimit: cur.contextLimit,
      autoRetryCount: cur.autoRetryCount,
      retryBaseMs: cur.retryBaseMs
    };
    const p = this.persona();
    if (p.params) {
      p.params.reasoningEffort = effort;
      if (budget !== undefined) p.params.reasoningBudget = budget;
    }
    this.persistAction();
  }

  private assistantParagraphsFor(msg: ChatMessage): string[] {
    const full = this.displayMessageText(msg);
    if (this.appearanceCfg().splitParagraphsIntoBubbles) {
      const parts = splitAssistantParagraphs(full);
      if (parts.length > 0) return parts;
    }
    return full ? [full] : [];
  }

  private assistantBubbleBg(): ResourceColor {
    const st = this.appearanceCfg().bubbleStyle;
    if (st === 'frosted') {
      return hexWithAlpha(this.themeTokens().surface, this.effectiveDark() ? '90' : 'B8');
    }
    if (st === 'solid') {
      return this.themeTokens().surface;
    }
    return Color.Transparent;
  }

  private userBubbleBg(): ResourceColor {
    const st = this.appearanceCfg().bubbleStyle;
    if (st === 'frosted') {
      return hexWithAlpha(this.themeTokens().tint, this.effectiveDark() ? 'A8' : 'C0');
    }
    return $r('app.color.tint');
  }

  private composerBgColor(): string {
    const alphaNum = Math.max(0.35, Math.min(1.0, this.appearanceCfg().inputBoxOpacity ?? 0.88));
    const alphaHex = Math.round(alphaNum * 255).toString(16).padStart(2, '0').toUpperCase();
    if (this.immersiveLightOn()) {
      return hexWithAlpha(this.themeTokens().surface, alphaHex === 'FF' ? 'EB' : alphaHex);
    }
    return hexWithAlpha(this.themeTokens().surface, alphaHex === 'FF' ? 'F8' : alphaHex);
  }

  private formatMsgTime(ts?: number): string {
    if (!ts) return '';
    const d = new Date(ts);
    const hh = String(d.getHours()).padStart(2, '0');
    const mm = String(d.getMinutes()).padStart(2, '0');
    return `${hh}:${mm}`;
  }

  private modelHeaderLabel(msg: ChatMessage): string {
    const name = msg.model || '助手';
    if (this.chatDisplayCfg().showProviderAfterModelName && msg.model) {
      return `${name} (${this.provider().name})`;
    }
    return name;
  }

  private composerPlaceholder(): string {
    if (this.imageGenMode) return '输入图像生成提示词...';
    if (this.appearanceCfg().language === 'en') return 'Type a message for AI';
    return '给 AI 发送消息...';
  }

  private allQuickPhrases(): QuickPhrase[] {
    const globalList = this.workspace.quickPhrases || defaultQuickPhrases();
    const personaList = this.persona().quickPhrases || [];
    return [...personaList, ...globalList];
  }

  private displayMessageText(msg: ChatMessage): string {
    const rules = this.persona().regexRules || [];
    return applyRegexRules(msg.text, rules, 'display');
  }

  private async refreshLogsAndStats(): Promise<void> {
    if (!this.store) return;
    this.requestLogs = await this.store.listRequestLogs();
    this.contextLogs = await this.store.listContextLogs();
    this.usageStats = await this.store.listUsageStats();
  }

  private buildToolSchemaCandidates(): ToolSchemaCandidate[] {
    const out: ToolSchemaCandidate[] = [
      { name: 'web_search', defaultDescription: '使用联网搜索引擎检索最新公开网页信息', source: 'builtin' },
      { name: 'web_fetch', defaultDescription: '抓取指定网页正文转为纯文本', source: 'builtin' }
    ];
    const groups: RegisteredTool[][] = [
      buildMemoryTools(),
      buildWorkspaceTools(),
      buildSkillTools(),
      buildBrowserTools(),
      buildDeviceTools()
    ];
    for (let g = 0; g < groups.length; g++) {
      const list = groups[g];
      for (let i = 0; i < list.length; i++) {
        out.push({
          name: list[i].declaration.name,
          defaultDescription: list[i].declaration.description,
          source: list[i].source
        });
      }
    }
    const mcpServers = this.workspace.mcpServers || [];
    for (let i = 0; i < mcpServers.length; i++) {
      const srv = mcpServers[i];
      const cached = this.mcpManager.getCachedTools(srv.id);
      for (let j = 0; j < cached.length; j++) {
        out.push({
          name: cached[j].name,
          defaultDescription: cached[j].description || cached[j].name,
          source: `mcp:${srv.name}`
        });
      }
    }
    return out;
  }

  private activeWorkspaceForChat(): LocalWorkspace | undefined {
    const list = this.workspace.workspaces || [];
    if (list.length === 0) return undefined;
    const chatWsId = this.activeChat()?.workspaceId;
    if (chatWsId) {
      const hit = list.find((w: LocalWorkspace): boolean => w.id === chatWsId);
      if (hit) return hit;
    }
    const pWsId = this.persona().workspaceId;
    if (pWsId) {
      const hit = list.find((w: LocalWorkspace): boolean => w.id === pWsId);
      if (hit) return hit;
    }
    return list[0];
  }

  private openUrlInBrowser(url: string): void {
    const clean = url.trim();
    if (!clean) return;
    const tab = this.browserManager.getActiveTab();
    this.browserManager.navigateTab(tab, clean, this.workspace.workspaces || []).catch(() => {});
    if (this.wide) {
      this.setSidePanelMode('browser');
    } else {
      this.navigateTo('browser');
    }
  }

  private requestAskUserInput(req: AskUserPromptRequest): Promise<string> {
    this.askQuestionText = req.question;
    this.askQuestionOptions = req.options.slice();
    this.askQuestionPlaceholder = req.placeholder;
    this.askQuestionAnswer = '';
    return new Promise<string>((resolve) => {
      this.askUserResolver = resolve;
    });
  }

  private submitAskUserInput(answer: string): void {
    const res = this.askUserResolver;
    this.askUserResolver = undefined;
    this.askQuestionText = '';
    this.askQuestionOptions = [];
    this.askQuestionPlaceholder = '';
    this.askQuestionAnswer = '';
    if (res) res(answer);
  }

  private async handleScheduledResult(updatedTask: ScheduledTask, newConv?: Conversation): Promise<void> {
    const tasks = this.workspace.scheduledTasks || [];
    this.workspace.scheduledTasks = tasks.map((t: ScheduledTask): ScheduledTask =>
      t.id === updatedTask.id ? updatedTask : t
    );
    if (newConv) {
      this.workspace.conversations = [newConv, ...this.workspace.conversations];
    }
    if (this.ready) {
      await this.persist().catch(() => {});
    }
  }

  private buildTemplateContext(prov: Provider, modelId: string, chatTitle: string): PromptTemplateContext {
    let userName = '用户';
    const profile = this.workspace.userProfile || [];
    for (let i = 0; i < profile.length; i++) {
      const k = profile[i].key.trim().toLowerCase();
      if (k === '称呼' || k === '名字' || k === '姓名' || k === 'name' || k === 'user') {
        userName = profile[i].value.trim();
        break;
      }
    }
    return {
      userName,
      assistantName: this.persona().name,
      modelName: modelId,
      providerName: prov.name,
      conversationTitle: chatTitle
    };
  }

  private queueMemoryOrganization(
    chat: Conversation, persona: Persona, fallback: ResolvedRoleTarget, manual: boolean = false, fromEditor: boolean = false
  ): boolean {
    const workspace = this.workspace;
    if (this.organizingMemoryChatId === chat.id) {
      if (manual) return false;
      const hasAuto = this.memoryQueue.some((item: MemoryQueueJob): boolean =>
        item.workspace === workspace && item.chatId === chat.id && !item.manual
      );
      if (hasAuto) return false;
    }
    const existingIdx = this.memoryQueue.findIndex((item: MemoryQueueJob): boolean =>
      item.workspace === workspace && item.chatId === chat.id
    );
    if (existingIdx >= 0) {
      const existing = this.memoryQueue[existingIdx];
      if (manual) {
        if (existing.manual) return false;
        existing.manual = true;
        existing.fromEditor = fromEditor;
        existing.fallback = fallback;
        this.drainMemoryQueue().catch(() => {});
        return true;
      }
      return false;
    }
    this.memoryQueue.push({
      workspace,
      chatId: chat.id,
      personaId: persona.id,
      fallback,
      manual,
      fromEditor
    });
    while (this.memoryQueue.length > 8) {
      this.memoryQueue.shift();
    }
    this.drainMemoryQueue().catch(() => {});
    return true;
  }

  private async drainMemoryQueue(): Promise<void> {
    if (this.memoryQueueRunning) return;
    this.memoryQueueRunning = true;
    try {
      while (this.memoryQueue.length > 0) {
        const job = this.memoryQueue.shift()!;
        if (job.workspace !== this.workspace) continue;
        try {
          await this.organizeMemory(job.chatId, job.personaId, job.fallback, job.manual, job.fromEditor === true);
        } catch (_) {}
      }
    } finally {
      this.memoryQueueRunning = false;
    }
  }

  private organizeCurrentConversation(): void {
    const chat = this.activeChat();
    const persona = this.persona();
    if (!chat || chat.ephemeral || persona.memoryEnabled === false) {
      this.toast('请打开已启用长期记忆的普通对话');
      return;
    }
    const memSettings = normalizeMemorySettings(this.workspace.memorySettings);
    if (memSettings.useLegacyMemory) {
      this.toast('当前为旧版记忆模式，无需整理');
      return;
    }
    const queued = this.queueMemoryOrganization(chat, persona, { prov: this.provider(), model: this.activeModelId() }, true, false);
    if (!queued) {
      this.toast('正在整理当前对话记忆，请稍候');
      return;
    }
    this.toast('正在后台整理当前对话记忆...');
  }

  private organizeMemoryForAssistant(assistantId: string): void {
    const persona = this.workspace.personas.find((item: Persona): boolean => item.id === assistantId);
    if (!persona || persona.memoryEnabled === false) {
      this.toast('请先启用该助手的长期记忆');
      return;
    }
    const memSettings = normalizeMemorySettings(this.workspace.memorySettings);
    if (memSettings.useLegacyMemory) {
      this.toast('当前为旧版记忆模式，无需整理');
      return;
    }
    const active = this.activeChat();
    let targetChat: Conversation | undefined =
      (active && !active.ephemeral && active.personaId === assistantId && active.messages.length > 0)
        ? active
        : undefined;
    if (!targetChat) {
      const candidates = this.workspace.conversations
        .filter((c: Conversation): boolean => !c.ephemeral && c.personaId === assistantId && c.messages.length > 0)
        .sort((a: Conversation, b: Conversation): number => b.updated - a.updated);
      targetChat = candidates.length > 0 ? candidates[0] : undefined;
    }
    if (!targetChat) {
      this.toast('该助手暂无可整理的对话记录');
      return;
    }
    this.queueMemoryOrganization(targetChat, persona, { prov: this.provider(), model: this.activeModelId() }, true, true);
  }

  private async organizeMemory(
    chatId: string, assistantId: string, fallback: ResolvedRoleTarget, manual: boolean, fromEditor: boolean = false
  ): Promise<void> {
    const workspace = this.workspace;
    const chat = workspace.conversations.find((item: Conversation): boolean => item.id === chatId);
    const persona = workspace.personas.find((item: Persona): boolean => item.id === assistantId);
    if (!chat || chat.ephemeral || chat.personaId !== assistantId || !persona || persona.memoryEnabled === false) return;

    const memSettings = normalizeMemorySettings(workspace.memorySettings);
    if (memSettings.useLegacyMemory) return;
    const auto = persona.autoOrganizeMemory ?? (memSettings.autoExtract === true);
    if (!manual && !auto) return;
    const cadence = Math.max(1, Math.min(20, Math.floor(persona.memoryOrganizeEveryNTurns || 1)));
    const memLang = resolveMemoryPromptLang(memSettings, this.appearanceCfg().language);
    const prevWatermark = chat.memoryOrganizedThrough || '';
    const batchInfo = buildMemoryOrganizeBatch(chat.messages, cadence, prevWatermark, manual, memLang);
    if (!batchInfo.snippet) {
      if (manual && !fromEditor) this.toast('当前对话暂无可整理内容');
      return;
    }
    const endMessageId = batchInfo.endMessageId;
    const failKey = `${chat.id}|${prevWatermark}|${endMessageId}`;
    const trace: MemoryTrace = {
      id: newId(),
      ts: Date.now(),
      conversationId: chat.id,
      assistantId: persona.id,
      trigger: manual ? 'manual' : 'auto',
      gatekeeperPassed: false,
      advanced: false,
      extractedCount: 0,
      mergedCount: 0,
      conflictCount: 0,
      skippedCount: 0,
      profileUpdatedCount: 0,
      summary: ''
    };
    let hadError = false;
    this.organizingMemoryChatId = chatId;
    this.organizingMemoryAssistantId = assistantId;
    try {
      try {
        const defaults = workspace.modelDefaults;
        const configured = workspace.providers.find((provider: Provider): boolean =>
          provider.id === defaults?.memoryProviderId && provider.enabled !== false && isProviderConfigured(provider));
        const provider = configured || fallback.prov;
        const model = configured ? (defaults?.memoryModelId || configured.model || fallback.model) : fallback.model;
        if (!model) throw new Error('请先配置记忆模型');
        trace.modelId = model;
        const auth = await this.resolveProviderKeyAndProxy(provider);
        if (!auth.key && !isProviderConfigured(provider)) throw new Error('记忆模型的服务商未配置');
        const pipelineOut = await runMemoryPipeline({
          provider,
          apiKey: auth.key,
          modelId: model,
          proxyPassword: auth.proxyPass,
          conversationId: chat.id,
          assistantId: persona.id,
          snippet: batchInfo.snippet,
          existingMemories: workspace.memories || [],
          existingProfile: workspace.userProfile || [],
          settings: memSettings,
          writeScope: persona.memoryWriteScope || 'alwaysGlobal',
          smartAddMode: persona.memorySmartAddMode || 'batched',
          assistantReasoning: persona.params?.reasoningEffort,
          uiLanguage: this.appearanceCfg().language,
          onLog: (logEntry: RequestLogEntry) => {
            this.store?.addRequestLog(logEntry).catch(() => {});
          }
        });
        const current = workspace.personas.find((item: Persona): boolean => item.id === persona.id);
        const saved = workspace.conversations.find((item: Conversation): boolean => item.id === chat.id);
        if (workspace !== this.workspace || !saved || saved.ephemeral || saved.personaId !== persona.id ||
          !saved.messages.some((message: ChatMessage): boolean => message.id === endMessageId) ||
          !current || current.memoryEnabled === false ||
          (!manual && !(current.autoOrganizeMemory ?? (workspace.memorySettings?.autoExtract === true)))) return;

        if (pipelineOut.advanced) {
          saved.memoryOrganizedThrough = endMessageId;
          this.memoryWindowFailures.delete(failKey);
          trace.advanced = true;
        } else {
          hadError = true;
          const fails = (this.memoryWindowFailures.get(failKey) || 0) + 1;
          this.memoryWindowFailures.set(failKey, fails);
          if (fails >= 3) {
            saved.memoryOrganizedThrough = endMessageId;
            this.memoryWindowFailures.delete(failKey);
            trace.advanced = true;
          } else {
            trace.advanced = false;
          }
        }

        trace.gatekeeperPassed = pipelineOut.gateStatus === 'worthRemembering';
        trace.error = pipelineOut.error;
        trace.extractedCount = pipelineOut.addedCount;
        trace.mergedCount = pipelineOut.mergedCount;
        trace.conflictCount = pipelineOut.conflictCount;
        trace.skippedCount = pipelineOut.skippedCount;
        trace.profileUpdatedCount = pipelineOut.profileUpdatedCount;
        trace.summary = pipelineOut.summary + (trace.advanced && pipelineOut.error ? '（连续 3 次失败，已跳过该窗口）' : '');
        trace.steps = pipelineOut.steps;

        if (pipelineOut.addedCount > 0 || pipelineOut.mergedCount > 0 || pipelineOut.conflictCount > 0) {
          workspace.memories = pipelineOut.memories;
        }
        if (pipelineOut.profileUpdatedCount > 0) {
          workspace.userProfile = pipelineOut.profile;
        }
        if (manual && !fromEditor) {
          if (pipelineOut.shouldSave) {
            this.toast(`记忆整理完成：${pipelineOut.summary}`);
          } else if (pipelineOut.error) {
            this.toast(`记忆整理失败：${pipelineOut.error}`);
          } else {
            this.toast('整理完成，暂无新增记忆');
          }
        } else if (manual && fromEditor) {
          if (pipelineOut.error) {
            this.toast(`记忆整理失败：${pipelineOut.error}`);
          } else if (pipelineOut.shouldSave) {
            this.toast(`已更新记忆：${pipelineOut.summary}`);
          }
        }
      } catch (err) {
        hadError = true;
        const errMsg = (err as Error).message || String(err);
        trace.error = errMsg;
        trace.summary = '记忆整理失败：' + errMsg;
        if (manual) this.toast(errMsg || '记忆整理失败');
      }
      if (workspace !== this.workspace ||
        !workspace.conversations.some((item: Conversation): boolean => item.id === chat.id)) return;
      if (memSettings.recordTraces !== false || manual || hadError) {
        workspace.memoryTraces = [trace, ...(workspace.memoryTraces || [])].slice(0, 24);
      }
      this.persistAction();
    } finally {
      if (this.organizingMemoryChatId === chatId) {
        this.organizingMemoryChatId = '';
        this.organizingMemoryAssistantId = '';
      }
    }
  }

  async attach(): Promise<void> {
    if (this.picking || this.working) return;
    this.picking = true;
    try {
      const quality = this.workspace.systemSettings?.imageUploadQuality ?? 85;
      const files = await pickMultipleAttachments(this.host(), quality);
      if (files.length) this.attachedList = [...this.attachedList, ...files].slice(0, 6);
    } catch (e) { this.toast((e as Error).message || '文件选择失败'); }
    finally { this.picking = false; }
  }

  async pickPhotos(): Promise<void> {
    if (this.picking || this.working) return;
    this.picking = true;
    try {
      const quality = this.workspace.systemSettings?.imageUploadQuality ?? 85;
      const files = await pickPhotoAttachments(this.host(), quality);
      if (files.length) this.attachedList = [...this.attachedList, ...files].slice(0, 6);
    } catch (_) {
      this.picking = false;
      await this.attach();
      return;
    } finally {
      this.picking = false;
    }
  }

  async takePhoto(): Promise<void> {
    if (this.picking || this.working) return;
    this.picking = true;
    try {
      const quality = this.workspace.systemSettings?.imageUploadQuality ?? 85;
      const item = await takePhotoAttachment(this.host(), quality);
      if (item) this.attachedList = [...this.attachedList, item].slice(0, 6);
    } catch (e) {
      this.toast((e as Error).message || '当前设备无法打开相机，已切换到相册/文件');
    } finally {
      this.picking = false;
    }
  }

  async applySearch(config: SearchConfig, key: string): Promise<void> {
    const previous = this.workspace.search;
    if (config.kind === 'tavily' && key) {
      const ref = newId();
      await storeKey(ref, key);
      config.secretRef = ref;
    }
    this.workspace.search = config;
    const prevSearchEnabled = this.workspace.systemSettings?.searchEnabled === true;
    const sys = this.workspace.systemSettings || defaultSystemSettings();
    sys.searchEnabled = true;
    this.workspace.systemSettings = sys;
    try { await this.persist(); } catch (e) {
      this.workspace.search = previous;
      sys.searchEnabled = prevSearchEnabled;
      this.workspace.systemSettings = sys;
      if (config.secretRef && config.secretRef !== previous?.secretRef) await forgetKey(config.secretRef);
      throw e as Error;
    }
    if (previous?.secretRef && previous.secretRef !== config.secretRef) await forgetKey(previous.secretRef).catch(() => {});
    this.searchOn = true;
  }

  stopReply(): void {
    this.stopped = true;
    this.stream?.stop();
    this.searcher?.stop();
    if (this.approvalResolver) {
      const res = this.approvalResolver;
      this.approvalResolver = undefined;
      this.pendingApprovalTool = '';
      this.pendingApprovalArgs = '';
      res('deny');
    }
    if (this.askUserResolver) {
      this.submitAskUserInput('');
    }
  }

  private activeSearchService(): SearchServiceConfig | undefined {
    const list = this.workspace.searchServices || defaultSearchServices();
    return list.find((s: SearchServiceConfig): boolean => s.id === this.workspace.activeSearchId) || list[0];
  }

  private resolveToolApproval(choice: 'allow_once' | 'allow_all' | 'deny'): void {
    if (choice === 'allow_all') {
      this.fullAccessMode = true;
      const c = this.activeChat();
      if (c) { c.toolPermissionMode = 'full'; this.persistAction(); }
    }
    const res = this.approvalResolver;
    this.approvalResolver = undefined;
    this.pendingApprovalTool = '';
    this.pendingApprovalArgs = '';
    res?.(choice);
  }

  private requestToolApproval(tool: RegisteredTool, argsJson: string): Promise<'allow_once' | 'allow_all' | 'deny'> {
    this.pendingApprovalTool = tool.declaration.name;
    this.pendingApprovalArgs = argsJson;
    return new Promise<'allow_once' | 'allow_all' | 'deny'>((resolve) => {
      this.approvalResolver = resolve;
    });
  }

  private async executeRegisteredTool(
    tool: RegisteredTool, argsJson: string, chat: Conversation, persona: Persona
  ): Promise<ToolExecutionOutput> {
    let parsed: Record<string, Object> = {};
    try {
      const obj = JSON.parse(argsJson || '{}') as Record<string, Object>;
      if (obj && typeof obj === 'object') {
        parsed = obj;
      }
    } catch (_) {
      return { text: '工具参数 JSON 解析失败', isError: true };
    }
    if (tool.declaration.name === 'web_search') {
      const query = String(parsed['query'] || '');
      const svc = this.activeSearchService();
      if (!svc) return { text: '未配置搜索服务', isError: true };
      const searcher = new WebSearch();
      this.searcher = searcher;
      const fallbackKey = this.workspace.search?.secretRef ? await readKey(this.workspace.search.secretRef) : '';
      const hits = await searcher.findWithService(svc, fallbackKey, query);
      if (!hits.length) return { text: '未找到相关网页结果' };
      const out = hits.map((h: SearchHit, idx: number): string =>
        '[' + (idx + 1) + '] ' + h.title + '\nURL: ' + h.url + '\n摘要: ' + h.excerpt
      ).join('\n\n');
      return { text: out };
    }
    if (tool.declaration.name === 'web_fetch') {
      const url = String(parsed['url'] || '');
      const maxChars = Number(parsed['max_chars'] || 8000);
      const offset = Number(parsed['offset'] || 0);
      const txt = await fetchWebPage(url, maxChars, offset);
      return { text: txt };
    }
    if (tool.source === 'memory') {
      const current = this.workspace.personas.find((item: Persona): boolean => item.id === persona.id) || persona;
      const outcome = executeMemoryToolCall(
        tool.declaration.name, parsed, this.workspace.memories || [], this.workspace.userProfile || [],
        this.workspace.conversations, chat, current, this.workspace.memorySettings?.injectGlobal !== false
      );
      if (outcome.memories || outcome.profile) {
        if (outcome.memories) this.workspace.memories = outcome.memories;
        if (outcome.profile) this.workspace.userProfile = outcome.profile;
        this.persistAction();
      }
      return { text: outcome.text, isError: outcome.isError };
    }
    if (tool.source === 'workspace') {
      return executeWorkspaceTool(
        tool.declaration.name,
        argsJson,
        this.activeWorkspaceForChat(),
        this.workspace.envVars || []
      );
    }
    if (tool.source === 'skill') {
      return executeSkillTool(argsJson, this.workspace.skills || defaultBuiltinSkills());
    }
    if (tool.source === 'browser') {
      if (this.wide && this.sidePanelMode === '') {
        this.setSidePanelMode('browser');
      }
      return this.browserManager.executeAction(argsJson, this.workspace.workspaces || []);
    }
    if (tool.source === 'device') {
      const bridge: DeviceToolBridge = {
        hostContext: this.host(),
        speakText: async (text: string): Promise<void> => {
          const ttsCfg = this.workspace.tts;
          if (ttsCfg && ttsCfg.engine !== 'system') {
            const key = ttsCfg.secretRef ? await readKey(ttsCfg.secretRef) : '';
            await this.speaker.playWithConfig(text, ttsCfg, key, this.host().cacheDir, () => {});
          } else {
            await this.speaker.play(text, () => {});
          }
        },
        askUserInput: (req: AskUserPromptRequest): Promise<string> => this.requestAskUserInput(req),
        getConversations: (): Conversation[] => this.workspace.conversations,
        getActiveConversation: (): Conversation | undefined => this.activeChat()
      };
      return executeDeviceTool(tool.declaration.name, argsJson, bridge);
    }
    if (tool.source === 'mcp' && tool.serverId) {
      const res = await this.mcpManager.invokeMcpTool(tool.serverId, tool.declaration.name, argsJson);
      return { text: res.text, images: res.images };
    }
    return { text: '未实现的工具: ' + tool.declaration.name, isError: true };
  }

  private async resolveProviderKeyAndProxy(p: Provider): Promise<ResolvedProviderAuth> {
    let key = '';
    let keyEntryId = '';
    if (p.apiKeys && p.apiKeys.length > 0) {
      const chosen = selectApiKey(p.id, p.apiKeys, p.keyStrategy || 'round_robin');
      if (chosen) {
        keyEntryId = chosen.id;
        key = await readKey(chosen.secretRef);
      }
    }
    if (!key && p.secretRef) {
      key = await readKey(p.secretRef);
    }
    const proxyPass = p.proxy?.passwordRef ? await readKey(p.proxy.passwordRef) : '';
    return { key, keyEntryId, proxyPass };
  }

  private resolveRoleProvider(role: 'title' | 'summary' | 'suggestions' | 'compress' | 'translate' | 'ocr' | 'memory'): ResolvedRoleTarget {
    const defs = this.workspace.modelDefaults;
    let pid = '';
    let mid = '';
    if (defs) {
      if (role === 'title') { pid = defs.titleProviderId; mid = defs.titleModelId; }
      else if (role === 'summary') { pid = defs.summaryProviderId || ''; mid = defs.summaryModelId || ''; }
      else if (role === 'suggestions') { pid = defs.suggestionsProviderId || ''; mid = defs.suggestionsModelId || ''; }
      else if (role === 'compress') { pid = defs.compressProviderId || ''; mid = defs.compressModelId || ''; }
      else if (role === 'translate') { pid = defs.translateProviderId; mid = defs.translateModelId; }
      else if (role === 'ocr') { pid = defs.ocrProviderId; mid = defs.ocrModelId; }
      else { pid = defs.memoryProviderId; mid = defs.memoryModelId; }
    }
    const prov = this.workspace.providers.find((p: Provider): boolean => p.id === pid && p.enabled !== false) || this.provider();
    return { prov, model: mid || (prov.id === this.provider().id ? this.activeModelId() : prov.model) };
  }

  private async autoGenerateTitle(chatId: string, firstQuestion: string, firstAnswer: string): Promise<void> {
    if (!this.workspace.systemSettings?.autoTitleEnabled) return;
    try {
      const target = this.resolveRoleProvider('title');
      const auth = await this.resolveProviderKeyAndProxy(target.prov);
      if (!target.model) return;
      const title = await completeOnce(
        target.prov, auth.key,
        '请根据下面这轮对话生成一个简短准确的中文或原文标题（不超过16个字，不加引号和标点）。',
        '用户：' + firstQuestion.slice(0, 400) + '\n助手：' + firstAnswer.slice(0, 400),
        target.model, 64, auth.proxyPass, chatId
      );
      const clean = title.replace(/["'《》「」]/g, '').trim().slice(0, 28);
      if (!clean) return;
      const c = this.workspace.conversations.find((item: Conversation): boolean => item.id === chatId);
      if (c) {
        c.title = clean;
        this.workspace.conversations = this.workspace.conversations.slice();
        this.persistAction();
      }
    } catch (_) {}
  }

  private async fetchSuggestions(chatId: string, lastQuestion: string, lastAnswer: string): Promise<void> {
    if (!this.workspace.systemSettings?.chatSuggestionsEnabled) return;
    try {
      const roleTarget = this.resolveRoleProvider('suggestions');
      const auth = await this.resolveProviderKeyAndProxy(roleTarget.prov);
      const model = roleTarget.model;
      if (!model) return;
      const raw = await completeOnce(
        roleTarget.prov, auth.key,
        '根据对话末尾内容，用一行一个的格式给出 3 个简短的后续追问建议（每条不超过18字，不要序号）。',
        '问：' + lastQuestion.slice(0, 300) + '\n答：' + lastAnswer.slice(0, 500),
        model, 120, auth.proxyPass, chatId
      );
      const lines = raw.split('\n').map((s: string): string => s.replace(/^[-*•\d.]+\s*/, '').trim())
        .filter((s: string): boolean => s.length > 1 && s.length <= 36).slice(0, 3);
      const c = this.workspace.conversations.find((item: Conversation): boolean => item.id === chatId);
      if (c && lines.length) {
        c.suggestions = lines;
        this.workspace.conversations = this.workspace.conversations.slice();
        this.persistAction();
      }
    } catch (_) {}
  }

  async send(retry: boolean = false, fromMessageId: string = ''): Promise<void> {
    if (this.working || this.picking || !this.ready) return;
    if (!retry && !this.draft.trim() && !this.attachedList.length) return;

    const p = this.provider();
    const modelId = this.activeModelId();
    if (!modelId || !isProviderConfigured(p)) {
      this.providerOpenProxy = false;
      this.navigateTo('providers');
      this.toast('请先配置模型服务和可用模型');
      return;
    }

    let c = this.activeChat();
    const origMessages = c ? c.messages.slice() : [];
    let history = origMessages.slice();
    let tailMessages: ChatMessage[] = [];
    let targetReplaceMsg: ChatMessage | undefined = undefined;

    if (retry) {
      if (!origMessages.length) return;
      const idx = fromMessageId
        ? origMessages.findIndex((m: ChatMessage): boolean => m.id === fromMessageId)
        : origMessages.length - 1;
      if (idx < 0) return;
      if (origMessages[idx].role === 'assistant') {
        targetReplaceMsg = origMessages[idx];
        history = origMessages.slice(0, idx);
        tailMessages = origMessages.slice(idx + 1);
      } else {
        if (idx + 1 < origMessages.length && origMessages[idx + 1].role === 'assistant') {
          targetReplaceMsg = origMessages[idx + 1];
          history = origMessages.slice(0, idx + 1);
          tailMessages = origMessages.slice(idx + 2);
        } else {
          targetReplaceMsg = undefined;
          history = origMessages.slice(0, idx + 1);
          tailMessages = origMessages.slice(idx + 1);
        }
      }
      if (!history.length || history[history.length - 1].role !== 'user') return;
    } else {
      const user: ChatMessage = {
        id: newId(),
        role: 'user',
        text: this.draft.trim(),
        model: '',
        attachment: this.attachedList[0],
        attachments: this.attachedList.length ? this.attachedList.slice() : undefined,
        quote: this.quoteDraft,
        createdAt: Date.now()
      };
      history.push(user);
    }

    if (!c) {
      c = {
        id: newId(),
        title: (this.draft.trim() || this.attachedList[0]?.name || '新对话').slice(0, 32),
        updated: Date.now(),
        messages: [],
        personaId: this.persona().id,
        ephemeral: this.ephemeralMode,
        imageGenMode: this.imageGenMode
      };
    }

    const target = c;
    const isFirstTurn = !retry && history.length === 1;
    const persona = this.persona();
    const sysPrompt = (target.overridePrompt || persona.prompt || '').trim();
    const params = this.effectiveParams();

    this.working = true;
    this.regeneratingMsgId = targetReplaceMsg ? targetReplaceMsg.id : '';
    this.stopped = false;
    this.liveText = '';
    this.liveReasoning = '';
    this.liveToolCalls = [];
    this.followBottom = this.appearanceCfg().autoFollowBottom !== false;
    this.lastSendError = '';
    this.lastSendErrorChatId = '';
    this.notice = '';
    triggerHapticFeedback(this.workspace.systemSettings?.hapticsEnabled !== false, 16);
    applyKeepScreenOn(this.host(), this.workspace.systemSettings?.keepScreenOn !== false).catch(() => {});
    let answer = '';
    let thoughts = '';
    let genImages: Attachment[] = [];
    let toolCallsUsed: ToolCallRecord[] = [];
    const finalUsage: TokenUsage = { promptTokens: 0, completionTokens: 0, cachedTokens: 0, totalTokens: 0, durationMs: 0 };
    let hasUsage = false;
    let timer = -1;
    let completed = false;
    const startTs = Date.now();
    let authKeyId = '';

    try {
      const question = history[history.length - 1];
      const activeSearch = this.activeSearchService();
      const searchMode = activeSearch?.mode || 'pre_search';
      if (this.searchOn && searchMode === 'pre_search' && question.text && !question.sources?.length) {
        this.fetchingSources = true;
        const legacySearch = this.workspace.search;
        const fallbackKey = legacySearch?.kind === 'tavily' ? await readKey(legacySearch.secretRef) : '';
        if (this.stopped) return;
        this.searcher = new WebSearch();
        const hits = activeSearch
          ? await this.searcher.findWithService(activeSearch, fallbackKey, question.text)
          : (legacySearch ? await this.searcher.find(legacySearch, fallbackKey, question.text) : []);
        if (this.stopped) return;
        history[history.length - 1] = {
          id: question.id, role: question.role, text: question.text, model: question.model,
          attachment: question.attachment, attachments: question.attachments,
          quote: question.quote, createdAt: question.createdAt, sources: hits
        };
        this.fetchingSources = false;
      }

      const auth = await this.resolveProviderKeyAndProxy(p);
      authKeyId = auth.keyEntryId;
      if (this.stopped) return;

      if (!retry) {
        this.workspace.activeConversation = target.id;
        this.putChat({
          id: target.id, title: target.title, updated: Date.now(), personaId: target.personaId,
          messages: history, draftText: '', suggestions: []
        });
        if (!target.ephemeral) await this.persist();
        this.drafts.delete(target.id);
        this.draft = '';
        this.attachedList = [];
        SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
          this.quoteDraft = undefined;
        });
      }

      const modelSpec = findProviderModelSpec(p, modelId);
      if (this.imageGenMode || modelSpec.imageGen) {
        const imgs = await generateImages(p, auth.key, question.text || '生成图片', modelId, auth.proxyPass, target.id);
        genImages = imgs;
        answer = '已生成 ' + imgs.length + ' 张图片：';
        completed = true;
      } else {
        // Hydrate any sandbox-offloaded attachments inside active context window
        const sliced = sliceContextMessages(history, target.contextStartIndex || 0, params.contextLimit || 0);
        const hydratedHistory: ChatMessage[] = [];
        for (let i = 0; i < sliced.length; i++) {
          const item = sliced[i];
          let nextAtt = item.attachment;
          if (nextAtt && !nextAtt.data && nextAtt.filePath) nextAtt = await hydrateAttachmentData(nextAtt);
          let nextAtts = item.attachments;
          if (nextAtts?.length) {
            const loaded: Attachment[] = [];
            for (let k = 0; k < nextAtts.length; k++) {
              loaded.push(await hydrateAttachmentData(nextAtts[k]));
            }
            nextAtts = loaded;
          }
          const rules = persona.regexRules || [];
          let outText = item.role === 'user' ? applyRegexRules(item.text, rules, 'input') : item.text;
          if (persona.appendCurrentTimeToUserMessage && item.role === 'user' && i === sliced.length - 1) {
            const nowDt = new Date();
            const pad2 = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
            const stamp = `${nowDt.getFullYear()}-${pad2(nowDt.getMonth() + 1)}-${pad2(nowDt.getDate())} ` +
              `${pad2(nowDt.getHours())}:${pad2(nowDt.getMinutes())}:${pad2(nowDt.getSeconds())}`;
            outText = `${outText}\n\n[Current time: ${stamp}]`;
          }
          hydratedHistory.push({
            id: item.id, role: item.role, text: outText, model: item.model,
            attachment: nextAtt, attachments: nextAtts, quote: item.quote, sources: item.sources
          });
        }

        const memSettings = normalizeMemorySettings(this.workspace.memorySettings);
        const memLang = resolveMemoryPromptLang(memSettings, this.appearanceCfg().language);
        const memRules = persona.memoryEnabled !== false
          ? buildMemoryRulesSystemPrompt(memSettings, this.appearanceCfg().language, persona.allowPastConversationRecall === true)
          : '';
        const memBlock = persona.memoryEnabled !== false
          ? buildMemoryInjectionBlock(this.workspace.memories || [], this.workspace.userProfile || [], memSettings,
            persona.id, persona.memoryFullInjectionTypes)
          : '';
        const skillsBlock = buildSkillsPromptSummary(
          this.workspace.skills || defaultBuiltinSkills(),
          persona.skillIds
        );
        const promptSegments: string[] = [];
        if (sysPrompt.length > 0) promptSegments.push(sysPrompt);
        if (skillsBlock.length > 0) promptSegments.push(skillsBlock);
        if (memRules.length > 0) promptSegments.push(memRules);
        const fullBasePrompt = promptSegments.join('\n\n');
        const assembled = buildAssembledPrompt({
          baseSystemPrompt: fullBasePrompt,
          presetMessages: persona.presetMessages,
          historyMessages: hydratedHistory,
          worldBooks: this.workspace.worldBooks || [],
          enabledWorldBookIds: persona.worldBookIds,
          instructionCards: this.workspace.instructionCards || [],
          activeInstructionIds: this.workspace.activeInstructionIds || [],
          memoryBlock: memBlock,
          templateContext: this.buildTemplateContext(p, modelId, target.title)
        });

        const allMcpServers = this.workspace.mcpServers || [];
        const boundMcpIds = persona.mcpServerIds || [];
        const mcpServers = boundMcpIds.length > 0
          ? allMcpServers.filter((s: McpServerConfig): boolean => boundMcpIds.includes(s.id))
          : allMcpServers;
        const mcpToolsRaw = mcpServers.some((s: McpServerConfig): boolean => s.enabled)
          ? await this.mcpManager.discoverEnabledServers(mcpServers)
          : [];
        const mcpDescriptors: McpDiscoveredDescriptor[] = mcpToolsRaw.map((t: McpTool): McpDiscoveredDescriptor => {
          return {
            serverId: t.serverId || '',
            name: t.name,
            description: t.description || t.name,
            parametersJson: JSON.stringify(t.inputSchema || {})
          };
        });
        const sysCfg = this.workspace.systemSettings || defaultSystemSettings();
        const enabledDeviceIds = persona.builtinTools !== undefined
          ? persona.builtinTools
          : (sysCfg.enabledDeviceTools || []);
        const deviceToolsFiltered = buildDeviceTools().filter((t: RegisteredTool): boolean =>
          enabledDeviceIds.includes(t.declaration.name)
        );
        const hasSkills = (persona.skillIds?.length || 0) > 0 || (target.enabledSkillIds?.length || 0) > 0;
        const browserToolsEnabled = this.sidePanelMode === 'browser' || enabledDeviceIds.includes('browser_action');
        const hasBoundWorkspace = Boolean(target.workspaceId || persona.workspaceId) && Boolean(this.activeWorkspaceForChat());
        const extraTools: RegisteredTool[] = [
          ...buildMemoryTools(persona.memoryEnabled !== false, persona.allowPastConversationRecall === true,
            !target.ephemeral, persona.memoryWriteScope || 'alwaysGlobal', memSettings.injectGlobal, memLang),
          ...(hasSkills ? buildSkillTools() : []),
          ...(browserToolsEnabled ? buildBrowserTools() : []),
          ...deviceToolsFiltered,
          ...(hasBoundWorkspace ? buildWorkspaceTools() : [])
        ];
        const registeredTools = modelSpec.tools ? assembleToolRegistry({
          searchService: activeSearch,
          searchEnabled: this.searchOn,
          builtinFetchEnabled: sysCfg.builtinFetchEnabled && this.searchOn,
          mcpTools: mcpDescriptors,
          mcpServers,
          extraTools,
          overrides: this.workspace.toolOverrides || []
        }) : [];

        const useStreamMode = persona.streamOutput !== false;

        if (registeredTools.length > 0) {
          const permMode: ToolPermissionMode = this.fullAccessMode ? 'full' : (target.toolPermissionMode || sysCfg.defaultToolPermission);
          const loopOut = await runAgentToolLoop({
            provider: p,
            apiKey: auth.key,
            modelId,
            modelSpec,
            conversationId: target.id,
            stream: useStreamMode,
            systemPrompt: assembled.systemPrompt,
            history: assembled.messages,
            genParams: params,
            presetMessages: undefined,
            customHeaders: persona.customHeaders,
            customBodyJson: persona.customBodyJson,
            tools: registeredTools,
            permissionMode: permMode,
            maxSteps: defaultMaxToolSteps(sysCfg),
            proxy: p.proxy,
            proxyPassword: auth.proxyPass,
            runStream: async (call: ChatCall, onFrag: (f: RichFragment) => void) => {
              this.stream = new ChatStream();
              await this.stream.runRich(call, onFrag, {
                providerName: p.name,
                modelId,
                proxy: p.proxy,
                proxyPassword: auth.proxyPass,
                maxRetries: params.autoRetryCount ?? 2,
                retryBaseMs: params.retryBaseMs ?? 800,
                onLog: (entry: RequestLogEntry) => { this.store?.addRequestLog(entry).catch(() => {}); }
              });
            },
            executeTool: (tool: RegisteredTool, argsJson: string) => this.executeRegisteredTool(tool, argsJson, target, persona),
            requestApproval: (tool: RegisteredTool, argsJson: string) => this.requestToolApproval(tool, argsJson),
            onUpdate: (lText: string, lReason: string, recs: ToolCallRecord[]) => {
              if (timer < 0) {
                timer = setTimeout(() => {
                  timer = -1;
                  this.liveText = lText;
                  this.liveReasoning = lReason;
                  this.liveToolCalls = recs.slice();
                  this.scrollDown();
                }, 80);
              }
            },
            onContextLog: (payloadJson: string) => {
              if (target.ephemeral) return;
              this.store?.addContextLog({
                id: newId(), ts: Date.now(), conversationId: target.id, model: modelId,
                payloadJson, tokenEstimate: Math.ceil(payloadJson.length / 4)
              }).catch(() => {});
            },
            isStopped: () => this.stopped
          });
          answer = loopOut.text;
          thoughts = loopOut.reasoning;
          toolCallsUsed = loopOut.toolCalls;
          if (loopOut.generatedImages.length) genImages.push(...loopOut.generatedImages);
          if (loopOut.usage) {
            finalUsage.promptTokens = loopOut.usage.promptTokens;
            finalUsage.completionTokens = loopOut.usage.completionTokens;
            finalUsage.cachedTokens = loopOut.usage.cachedTokens;
            finalUsage.totalTokens = loopOut.usage.totalTokens;
            hasUsage = true;
          }
        } else {
          const callOpts: ChatCallOptions = {
            modelId,
            modelSpec,
            conversationId: target.id,
            stream: useStreamMode,
            params,
            presetMessages: undefined,
            customHeaders: persona.customHeaders,
            customBodyJson: persona.customBodyJson,
            promptCaching: p.promptCaching,
            builtinSearch: p.builtinSearch,
            builtinUrlContext: p.builtinUrlContext,
            builtinCodeExec: p.builtinCodeExec
          };
          const call = makeAdvancedChatCall(p, auth.key, assembled.systemPrompt, assembled.messages, callOpts);

          if (!target.ephemeral) this.store?.addContextLog({
            id: newId(),
            ts: Date.now(),
            conversationId: target.id,
            model: modelId,
            payloadJson: call.body,
            tokenEstimate: Math.ceil(call.body.length / 4)
          }).catch(() => {});

          if (this.stopped) return;
          this.scrollDown();
          this.stream = new ChatStream();
          await this.stream.runRich(call, (part: RichFragment) => {
            answer += part.text;
            thoughts += part.reasoning;
            if (part.generatedImages.length) genImages.push(...part.generatedImages);
            if (part.usage) {
              finalUsage.promptTokens = part.usage.promptTokens;
              finalUsage.completionTokens = part.usage.completionTokens;
              finalUsage.cachedTokens = part.usage.cachedTokens;
              finalUsage.totalTokens = part.usage.totalTokens;
              hasUsage = true;
            }
            if (timer < 0) timer = setTimeout(() => {
              timer = -1;
              this.liveText = answer;
              this.liveReasoning = thoughts;
              this.scrollDown();
            }, 80);
          }, {
            providerName: p.name,
            modelId,
            proxy: p.proxy,
            proxyPassword: auth.proxyPass,
            maxRetries: params.autoRetryCount ?? 2,
            retryBaseMs: params.retryBaseMs ?? 800,
            onLog: (entry: RequestLogEntry) => { this.store?.addRequestLog(entry).catch(() => {}); }
          });
        }
        if (!answer.trim() && !genImages.length && !toolCallsUsed.length) {
          throw new Error('模型没有返回回答，可调整提示词或切换模型后重试');
        }
        completed = true;
      }

      if (authKeyId && p.apiKeys?.length) {
        p.apiKeys = markKeySuccess(p.apiKeys, authKeyId);
      }
    } catch (e) {
      const errMsg = this.stopped ? '已停止生成' : ((e as Error).message || '请求失败，请检查网络和模型设置');
      if (this.stopped) {
        this.notice = errMsg;
      } else {
        this.lastSendError = errMsg;
        this.lastSendErrorChatId = target.id;
      }
      if (authKeyId && p.apiKeys?.length && !this.stopped) {
        p.apiKeys = markKeyError(p.apiKeys, authKeyId, 429);
      }
    } finally {
      if (timer >= 0) clearTimeout(timer);
      applyKeepScreenOn(this.host(), false).catch(() => {});
      const durationMs = Date.now() - startTs;
      finalUsage.durationMs = durationMs;
      if (answer.length > 0 && persona.regexRules?.length) {
        answer = applyRegexRules(answer, persona.regexRules, 'output');
      }

      if ((answer || genImages.length || toolCallsUsed.length) && (completed || !targetReplaceMsg)) {
        const recordedUsage: TokenUsage | undefined = hasUsage ? finalUsage : undefined;
        let nextMsg: ChatMessage;
        if (targetReplaceMsg) {
          nextMsg = appendMessageVersion(targetReplaceMsg, {
            id: newId(),
            text: answer,
            reasoning: thoughts,
            model: modelId,
            createdAt: Date.now(),
            usage: recordedUsage,
            toolCalls: toolCallsUsed.length ? toolCallsUsed : undefined,
            generatedImages: genImages.length ? genImages : undefined
          });
        } else {
          nextMsg = {
            id: newId(),
            role: 'assistant',
            text: answer,
            model: modelId,
            reasoning: thoughts,
            createdAt: Date.now(),
            usage: recordedUsage,
            toolCalls: toolCallsUsed.length ? toolCallsUsed : undefined,
            generatedImages: genImages.length ? genImages : undefined
          };
        }
        const finalMessages = [...history, nextMsg, ...tailMessages];
        const prevConvState = this.workspace.conversations.find((item: Conversation): boolean => item.id === target.id);
        const curThrough = prevConvState?.memoryOrganizedThrough;
        const rewindThrough = (retry && tailMessages.length === 0 && curThrough &&
          (curThrough === targetReplaceMsg?.id || !finalMessages.some((m: ChatMessage): boolean => m.id === curThrough)))
          ? (history.length >= 2 ? history[history.length - 2].id : '')
          : undefined;
        this.putChat({
          id: target.id, title: target.title, updated: Date.now(),
          personaId: target.personaId, messages: finalMessages,
          memoryOrganizedThrough: rewindThrough
        });
        if (!target.ephemeral) {
          try { await this.persist(); } catch (_) { this.notice = '回复保存在当前页面，写入设备失败'; }
        }
        if (hasUsage) {
          const day = new Date().toISOString().slice(0, 10);
          this.store?.recordUsage(day, modelId, target.personaId,
            finalUsage.promptTokens, finalUsage.completionTokens, finalUsage.cachedTokens).catch(() => {});
        }
        if (completed) {
          triggerHapticFeedback(this.workspace.systemSettings?.hapticsEnabled !== false, 12);
          notifyGenerationComplete(
            this.host(),
            this.workspace.systemSettings?.backgroundNotifyEnabled === true,
            target.title,
            answer
          ).catch(() => {});
        }
        if (completed && isFirstTurn && !target.ephemeral) {
          this.autoGenerateTitle(target.id, history[history.length - 1].text, answer);
        }
        if (completed) {
          this.fetchSuggestions(target.id, history[history.length - 1].text, answer);
          if (!target.ephemeral && answer.trim().length > 0 && tailMessages.length === 0) {
            const latestPersona = this.workspace.personas.find((item: Persona): boolean => item.id === persona.id) || persona;
            this.queueMemoryOrganization(target, latestPersona, { prov: p, model: modelId });
          }
          const sysAfter = this.workspace.systemSettings;
          if (sysAfter?.autoCompactEnabled && !target.ephemeral) {
            const threshold = Math.max(8, sysAfter.autoCompactThreshold || 36);
            const activeSliceCount = finalMessages.length - (target.contextStartIndex || 0);
            if (activeSliceCount >= threshold) {
              this.compressInPlace(sysAfter.compressionTemplate).catch(() => {});
            }
          }
        }
      } else if (targetReplaceMsg) {
        // Restore previous version if regeneration failed
        this.putChat({
          id: target.id, title: target.title, updated: Date.now(),
          personaId: target.personaId, messages: [...history, targetReplaceMsg, ...tailMessages]
        });
      }

      this.stream = undefined;
      this.searcher = undefined;
      this.fetchingSources = false;
      this.regeneratingMsgId = '';
      this.working = false;
      this.liveText = '';
      this.liveReasoning = '';
      this.liveToolCalls = [];
      this.scrollDown();
    }
  }

  private async compressInPlace(template: string): Promise<void> {
    const c = this.activeChat();
    if (!c || !c.messages.length) return;
    const roleTarget = this.resolveRoleProvider('compress');
    const auth = await this.resolveProviderKeyAndProxy(roleTarget.prov);
    const modelId = roleTarget.model || this.activeModelId();
    const summary = await completeOnce(
      roleTarget.prov, auth.key, '你是精准的上下文压缩助手。',
      buildCompressionPrompt(c.messages, template), modelId, 1200, auth.proxyPass, c.id
    );
    c.messages = applyContextCompression(c.messages, summary, newId(), modelId);
    c.updated = Date.now();
    this.workspace.conversations = this.workspace.conversations.slice();
    if (!c.ephemeral) await this.persist();
  }

  private undoCompression(): void {
    const c = this.activeChat();
    if (!c) return;
    c.messages = undoContextCompression(c.messages);
    this.workspace.conversations = this.workspace.conversations.slice();
    if (!c.ephemeral) this.persistAction();
  }

  private async compressToNewChat(template: string): Promise<void> {
    const c = this.activeChat();
    if (!c || !c.messages.length) return;
    const roleTarget = this.resolveRoleProvider('compress');
    const auth = await this.resolveProviderKeyAndProxy(roleTarget.prov);
    const modelId = roleTarget.model || this.activeModelId();
    const summary = await completeOnce(
      roleTarget.prov, auth.key, '你是精准的上下文压缩助手。',
      buildCompressionPrompt(c.messages, template), modelId, 1200, auth.proxyPass, c.id
    );
    const newChat: Conversation = {
      id: newId(),
      title: '续写 · ' + c.title.slice(0, 20),
      updated: Date.now(),
      personaId: c.personaId,
      messages: [{
        id: newId(),
        role: 'assistant',
        text: '【继承自「' + c.title + '」的上下文摘要】\n' + summary,
        model: modelId,
        createdAt: Date.now(),
        isSummary: true
      }]
    };
    this.putChat(newChat);
    this.workspace.activeConversation = newChat.id;
    await this.persist();
  }

  private deleteSingleMessage(msgId: string, toastMsg: string = ''): void {
    const c = this.activeChat();
    if (!c) return;
    c.messages = c.messages.filter((m: ChatMessage): boolean => m.id !== msgId);
    c.updated = Date.now();
    this.workspace.conversations = this.workspace.conversations.slice();
    if (!c.ephemeral) this.persistAction();
    if (toastMsg) this.toast(toastMsg);
  }

  private deleteActiveMessageVersion(msgId: string): void {
    const c = this.activeChat();
    if (!c) return;
    const nextList: ChatMessage[] = [];
    let removedAll = false;
    for (let i = 0; i < c.messages.length; i++) {
      const m = c.messages[i];
      if (m.id !== msgId) {
        nextList.push(m);
        continue;
      }
      const updated = deleteMessageVersion(m);
      if (updated) {
        nextList.push(updated);
      } else {
        removedAll = true;
      }
    }
    c.messages = nextList;
    c.updated = Date.now();
    this.workspace.conversations = this.workspace.conversations.slice();
    if (!c.ephemeral) this.persistAction();
    this.toast(removedAll ? '已删除消息' : '已删除本版本');
  }

  private forkConversationFrom(msgId: string): void {
    const c = this.activeChat();
    if (!c) return;
    const idx = c.messages.findIndex((m: ChatMessage): boolean => m.id === msgId);
    if (idx < 0) return;
    const forked: Conversation = {
      id: newId(),
      title: '分支 · ' + c.title.slice(0, 20),
      updated: Date.now(),
      personaId: c.personaId,
      messages: c.messages.slice(0, idx + 1)
    };
    this.putChat(forked);
    this.workspace.activeConversation = forked.id;
    this.persistAction();
    this.toast('已创建对话分支');
  }

  private switchReplyVersion(msgId: string, delta: number): void {
    const c = this.activeChat();
    if (!c) return;
    c.messages = c.messages.map((m: ChatMessage): ChatMessage => {
      if (m.id !== msgId) return m;
      const cur = m.activeVersion ?? ((m.versions?.length || 1) - 1);
      return switchMessageVersion(m, cur + delta);
    });
    this.workspace.conversations = this.workspace.conversations.slice();
    if (!c.ephemeral) this.persistAction();
  }

  private saveEditedMessage(rerun: boolean): void {
    const c = this.activeChat();
    if (!c || !this.editingMsgId) return;
    const targetId = this.editingMsgId;
    const nextText = this.editingMsgText.trim();
    if (!nextText) return;
    c.messages = c.messages.map((m: ChatMessage): ChatMessage => {
      if (m.id !== targetId) return m;
      return updateActiveMessageVersionText(m, nextText);
    });
    SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.editingMsgId = '';
      this.editingMsgText = '';
    });
    this.workspace.conversations = this.workspace.conversations.slice();
    if (!c.ephemeral) this.persistAction();
    if (rerun) this.send(true, targetId);
  }

  private async translateMessage(msgId: string): Promise<void> {
    const c = this.activeChat();
    const target = c?.messages.find((m: ChatMessage): boolean => m.id === msgId);
    if (!c || !target || !target.text.trim()) return;
    if (target.translation) {
      c.messages = c.messages.map((m: ChatMessage): ChatMessage => {
        if (m.id !== msgId) return m;
        return updateActiveMessageVersionTranslation(m, undefined);
      });
      this.workspace.conversations = this.workspace.conversations.slice();
      if (!c.ephemeral) this.persistAction();
      return;
    }
    this.toast('正在翻译…');
    try {
      const role = this.resolveRoleProvider('translate');
      const auth = await this.resolveProviderKeyAndProxy(role.prov);
      const out = await completeOnce(
        role.prov, auth.key,
        '若输入主要为中文请译为地道英文，否则译为地道简体中文，保留格式，只输出译文。',
        target.text, role.model, 2048, auth.proxyPass, c.id
      );
      c.messages = c.messages.map((m: ChatMessage): ChatMessage => {
        if (m.id !== msgId) return m;
        return updateActiveMessageVersionTranslation(m, out);
      });
      this.workspace.conversations = this.workspace.conversations.slice();
      if (!c.ephemeral) this.persistAction();
    } catch (e) {
      this.toast((e as Error).message || '翻译失败');
    }
  }

  private async shareMessageText(msg: ChatMessage): Promise<void> {
    const ok = await sharePlainText(this.host(), msg.text, this.activeChat()?.title || '分享消息');
    if (!ok) {
      this.copyText(msg.text);
      this.toast('已复制内容以便分享');
    }
  }

  private async runOcrOnImage(dataUri: string): Promise<string> {
    const comma = dataUri.indexOf(',');
    if (comma < 0) throw new Error('仅支持对本地/Base64 图片执行 OCR');
    const meta = dataUri.slice(5, comma);
    const mime = meta.split(';')[0] || 'image/png';
    const b64 = dataUri.slice(comma + 1);
    const role = this.resolveRoleProvider('ocr');
    const auth = await this.resolveProviderKeyAndProxy(role.prov);
    const ocrMsg: ChatMessage = {
      id: 'ocr',
      role: 'user',
      text: '请准确提取图片中的所有文字内容并保持原有排版，不添加额外解释。',
      model: '',
      attachment: { name: 'ocr.png', mime, data: b64, kind: 'image' }
    };
    const call = makeAdvancedChatCall(role.prov, auth.key, '', [ocrMsg], { modelId: role.model, conversationId: this.activeChat()?.id });
    const s = new ChatStream();
    let out = '';
    await s.runRich(call, (frag: RichFragment) => { out += frag.text; });
    return out.trim();
  }

  private exportSelection(asMarkdown: boolean, singleMsg?: ChatMessage): void {
    const c = this.activeChat();
    if (!c) return;
    let msgs: ChatMessage[] = [];
    if (singleMsg) {
      msgs = [singleMsg];
    } else if (this.selectedMsgIds.length > 0) {
      const idSet = new Set<string>(this.selectedMsgIds);
      msgs = c.messages.filter((m: ChatMessage): boolean => idSet.has(m.id));
    } else {
      msgs = c.messages;
    }
    const content = asMarkdown ? exportMessagesAsMarkdown(c.title, msgs) : exportMessagesAsPlainText(c.title, msgs);
    this.copyText(content);
    SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.multiSelectMode = false;
      this.selectedMsgIds = [];
    });
  }

  private toggleSelectedMsg(msgId: string): void {
    if (this.selectedMsgIds.includes(msgId)) {
      this.selectedMsgIds = this.selectedMsgIds.filter((id: string): boolean => id !== msgId);
    } else {
      this.selectedMsgIds = [...this.selectedMsgIds, msgId];
    }
  }

  private matchingMessageIndices(): number[] {
    const q = this.inChatQuery.trim().toLowerCase();
    const msgs = this.activeChat()?.messages || [];
    if (!q) return [];
    const out: number[] = [];
    for (let i = 0; i < msgs.length; i++) {
      if (msgs[i].text.toLowerCase().includes(q) || (msgs[i].reasoning || '').toLowerCase().includes(q)) {
        out.push(i);
      }
    }
    return out;
  }

  private jumpToInChatMatch(delta: number): void {
    const matches = this.matchingMessageIndices();
    if (!matches.length) return;
    this.inChatMatchPos = (this.inChatMatchPos + delta + matches.length) % matches.length;
    this.scrollView.scrollToIndex(matches[this.inChatMatchPos]);
  }

  removeChat(c: Conversation): void {
    this.getUIContext().showAlertDialog({
      title: '删除这段对话？',
      message: c.title,
      systemMaterial: ImmersiveMaterialStyle.alertDialogMaterial(this.immersiveLightOn()),
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => {
        this.workspace.conversations = this.workspace.conversations.filter((item: Conversation): boolean => item.id !== c.id);
        if (this.workspace.activeConversation === c.id) { this.workspace.activeConversation = ''; this.draft = ''; this.attachedList = []; }
        this.drafts.delete(c.id);
        this.persistAction();
      } }
    });
  }

  async mergeChats(incoming: Conversation[]): Promise<number> {
    const previous = this.workspace.conversations;
    const existing = new Set<string>(previous.map((c: Conversation): string => c.id));
    const fresh = incoming.filter((c: Conversation): boolean => {
      if (existing.has(c.id)) return false;
      existing.add(c.id);
      return true;
    });
    this.workspace.conversations = [...previous, ...fresh];
    try { await this.persist(); } catch (e) { this.workspace.conversations = previous; throw e as Error; }
    return fresh.length;
  }

  async transfer(exporting: boolean): Promise<void> {
    if (this.picking) return;
    this.picking = true;
    try {
      if (exporting) {
        if (await exportChats(this.host(), this.workspace.conversations)) this.toast('会话已导出');
      } else {
        const incoming = await importChats(this.host());
        if (!incoming.length) return;
        const count = await this.mergeChats(incoming);
        this.toast('已导入 ' + count + ' 段新对话');
      }
    } catch (e) { this.toast((e as Error).message || '文件操作失败'); }
    finally { this.picking = false; }
  }

  async narrate(msg: ChatMessage): Promise<void> {
    if (this.readingId === msg.id) {
      this.speaker.stop();
      this.readingId = '';
      this.ttsPaused = false;
      return;
    }
    this.readingId = msg.id;
    this.ttsPaused = false;
    try {
      const cfg = this.workspace.tts || {
        engine: 'system', endpoint: '', secretRef: '', model: 'tts-1', voice: 'alloy', speed: 1.0, language: 'zh-CN'
      };
      const apiKey = cfg.secretRef ? await readKey(cfg.secretRef) : '';
      await this.speaker.playWithConfig(msg.text, cfg, apiKey, this.host().cacheDir, (error: string) => {
        this.readingId = '';
        this.ttsPaused = false;
        if (error) this.toast(error);
      });
    } catch (_) {
      this.readingId = '';
      this.ttsPaused = false;
      this.toast('无法启动语音朗读，请检查 TTS 设置或离线语音资源');
    }
  }

  async toggleTtsPause(): Promise<void> {
    try {
      this.ttsPaused = await this.speaker.togglePause();
    } catch (_) {}
  }

  async toggleDictation(): Promise<void> {
    if (this.working) return;
    if (this.recording) {
      await this.speechInput.stopSystemDictation();
      this.recording = false;
      return;
    }
    const baseDraft = this.draft;
    try {
      this.recording = true;
      await this.speechInput.startSystemDictation(
        this.host(),
        this.workspace.asr?.language || 'zh-CN',
        (recognized: string, isFinal: boolean) => {
          const sep = baseDraft && !baseDraft.endsWith(' ') && !baseDraft.endsWith('\n') ? ' ' : '';
          this.draft = baseDraft + sep + recognized;
          if (isFinal) {
            this.speechInput.stopSystemDictation().catch(() => {});
            this.recording = false;
          }
        },
        (err: string) => {
          this.recording = false;
          this.toast(err);
        }
      );
    } catch (e) {
      this.recording = false;
      this.toast((e as Error).message || '无法启动语音识别');
    }
  }

  copyText(text: string): void {
    triggerHapticFeedback(this.workspace.systemSettings?.hapticsEnabled !== false, 12);
    pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text))
      .then(() => this.toast('已复制')).catch(() => this.toast('复制失败'));
  }

  private openPreview(kind: RichPreviewKind, title: string, code: string): void {
    this.previewKind = kind;
    this.previewTitle = title;
    this.previewCode = code;
    SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.previewVisible = true;
    });
  }

  private openImage(src: string, title: string): void {
    this.imageViewerTitle = title;
    SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.imageViewerSrc = src;
    });
  }

  private imageSrcForAttachment(att: Attachment): string {
    return att.data ? 'data:' + att.mime + ';base64,' + att.data : (att.filePath ? 'file://' + att.filePath : '');
  }

  private usageBadgeText(msg: ChatMessage): string {
    if (!msg.usage) return '';
    return '↑' + msg.usage.promptTokens + ' ↓' + msg.usage.completionTokens +
      (msg.usage.cachedTokens ? ' ⚡' + msg.usage.cachedTokens : '') +
      (msg.usage.durationMs ? ' · ' + (msg.usage.durationMs / 1000).toFixed(1) + 's' : '');
  }

  private compactTokenCountText(msg: ChatMessage): string {
    if (!msg.usage) return '';
    const total = msg.usage.totalTokens > 0
      ? msg.usage.totalTokens
      : (msg.usage.promptTokens + msg.usage.completionTokens);
    return total > 0 ? `${total} tokens` : '';
  }

  private versionLabel(msg: ChatMessage): string {
    const total = msg.versions?.length || 1;
    const cur = (msg.activeVersion ?? (total - 1)) + 1;
    return `${cur}/${total}`;
  }

  private isRegeneratingMessage(msg: ChatMessage): boolean {
    return this.working && this.regeneratingMsgId === msg.id;
  }

  private activeVersionCount(msg: ChatMessage): number {
    return msg.versions?.length || 1;
  }

  private canPrevVersion(msg: ChatMessage): boolean {
    const cur = msg.activeVersion ?? ((msg.versions?.length || 1) - 1);
    return cur > 0;
  }

  private canNextVersion(msg: ChatMessage): boolean {
    const total = msg.versions?.length || 1;
    const cur = msg.activeVersion ?? (total - 1);
    return cur < total - 1;
  }

  private openMessageActionSheet(msg: ChatMessage): void {
    this.messageActionTargetId = msg.id;
    this.showMessageActionSheet = true;
  }

  private actionSheetTargetMessage(): ChatMessage | undefined {
    const list = this.activeChat()?.messages || [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === this.messageActionTargetId) {
        return list[i];
      }
    }
    return undefined;
  }

  private isActionSheetTargetAssistant(): boolean {
    return this.actionSheetTargetMessage()?.role === 'assistant';
  }

  private actionSheetTargetHasMultiVersions(): boolean {
    return (this.actionSheetTargetMessage()?.versions?.length || 1) > 1;
  }

  private runMessageSheetAction(actionKey: string): void {
    const target = this.actionSheetTargetMessage();
    this.showMessageActionSheet = false;
    if (!target) return;
    if (actionKey === 'select_copy') {
      SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
        this.selectCopyText = target.text;
      });
    } else if (actionKey === 'web_render') {
      this.openPreview('markdown', '网页视图渲染', target.text);
    } else if (actionKey === 'edit') {
      this.editingMsgText = target.text;
      SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
        this.editingMsgId = target.id;
      });
    } else if (actionKey === 'share') {
      this.shareMessageText(target).catch(() => {});
    } else if (actionKey === 'select_messages') {
      this.selectedMsgIds = [target.id];
      SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
        this.multiSelectMode = true;
      });
    } else if (actionKey === 'fork') {
      this.forkConversationFrom(target.id);
    } else if (actionKey === 'delete_version') {
      this.deleteActiveMessageVersion(target.id);
    } else if (actionKey === 'delete_all') {
      this.deleteSingleMessage(target.id, '已删除全部版本');
    }
  }

  private messageRowKey(msg: ChatMessage): string {
    const total = msg.versions?.length || 1;
    const activeIdx = msg.activeVersion ?? (total - 1);
    const verId = msg.versions?.[activeIdx]?.id || '';
    return `${msg.id}-${total}-${activeIdx}-${verId}-${msg.text.length}-${(msg.translation || '').length}`;
  }

  @Builder
  actionIcon(symbol: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol).fontSize(20).fontColor([$r('app.color.ink')])
    }.width(40).height(40).backgroundColor(Color.Transparent).accessibilityText(label).onClick(action)
  }

  @Builder
  msgActionIcon(
    symbol: Resource,
    label: string,
    lockWhileWorking: boolean,
    idStr: string,
    action: () => void
  ) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol)
        .fontSize(17)
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontColor([$r('app.color.muted')])
    }
    .id(idStr)
    .width(32)
    .height(32)
    .padding(0)
    .enabled(!(lockWhileWorking && this.working))
    .opacity(lockWhileWorking && this.working ? 0.38 : 1)
    .backgroundColor(Color.Transparent)
    .accessibilityText(label)
    .onClick(action)
  }

  @Builder
  msgMoreDotsBtn(idStr: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      Row({ space: 3 }) {
        Column().width(3.5).height(3.5).borderRadius(2).backgroundColor($r('app.color.muted'))
        Column().width(3.5).height(3.5).borderRadius(2).backgroundColor($r('app.color.muted'))
        Column().width(3.5).height(3.5).borderRadius(2).backgroundColor($r('app.color.muted'))
      }
      .alignItems(VerticalAlign.Center)
    }
    .id(idStr)
    .width(32)
    .height(32)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText('更多操作')
    .onClick(action)
  }

  @Builder
  liveStreamBody() {
    Column({ space: 8 }) {
      if (this.liveReasoning) {
        Text(this.liveReasoning).fontSize(12).lineHeight(18).fontColor($r('app.color.muted'))
          .padding(8).borderRadius(8).backgroundColor($r('app.color.panel'))
      }
      if (this.liveToolCalls.length) {
        this.toolCallsView(this.liveToolCalls, 'live')
      }
      if (this.liveText) {
        MessageBody({
          source: this.liveText,
          bodyFontSize: this.bodyTextSize(),
          codeFontSize: this.codeTextSize(),
          enableMarkdown: this.appearanceCfg().enableAssistantMarkdown !== false,
          enableMathLatex: this.appearanceCfg().enableMathLatex !== false,
          onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => this.openPreview(kind, title, code),
          onOpenUrl: (url: string) => { this.openUrlInBrowser(url); },
          onViewImage: (url: string, alt: string) => this.openImage(url, alt || '图片'),
          onAskDraft: (draftStr: string) => { this.draft = draftStr; }
        })
      } else if (!this.liveReasoning && !this.liveToolCalls.length) {
        if (this.fetchingSources) {
          Text('正在检索网页…').fontSize(13).fontColor($r('app.color.accent'))
        } else {
          Row({ space: 6 }) {
            Column().width(7).height(7).borderRadius(4).backgroundColor($r('app.color.accent')).opacity(0.45)
            Column().width(7).height(7).borderRadius(4).backgroundColor($r('app.color.accent')).opacity(0.7)
            Column().width(7).height(7).borderRadius(4).backgroundColor($r('app.color.accent')).opacity(0.95)
          }.padding({ top: 6, bottom: 6 })
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  sidebarBody(isOverlay: boolean) {
    Column({ space: 10 }) {
      // Top Search Pill + New Chat Button (aligned to android_02_drawer.png)
      Row({ space: 8 }) {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(this.drawerGlobalSearch ? $r('sys.symbol.externaldrive') : $r('sys.symbol.magnifyingglass'))
              .fontSize(16)
              .fontColor([this.drawerGlobalSearch ? $r('app.color.accent') : $r('app.color.muted')])
          }
          .width(30)
          .height(30)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.drawerGlobalSearch ? '切换为当前助手检索' : '切换为全局会话检索')
          .onClick(() => { this.drawerGlobalSearch = !this.drawerGlobalSearch; })

          TextInput({
            text: this.query,
            placeholder: this.drawerGlobalSearch ? '搜索所有会话...' : `搜索 ${this.persona().name}...`
          })
            .id('historySearch')
            .layoutWeight(1)
            .height(36)
            .padding(0)
            .fontSize(13)
            .backgroundColor(Color.Transparent)
            .onChange((v: string) => { this.query = v; })

          if (this.query.length > 0) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(12)
                .fontColor([$r('app.color.muted')])
            }
            .width(24)
            .height(24)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.query = ''; })
          }
        }
        .layoutWeight(1)
        .height(40)
        .padding({ left: 8, right: 8 })
        .borderRadius(20)
        .backgroundColor($r('app.color.surface'))

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(17)
            .fontColor([$r('app.color.ink')])
        }
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor($r('app.color.surface'))
        .accessibilityText(this.uiLabels().newChat)
        .onClick(() => {
          this.setDrawerOpen(false);
          this.activate('');
        })
      }
      .width('100%')

      // Collapsible Assistant Switcher Row
      Row({ space: 10 }) {
        KelivoAvatarBadge({
          brandId: '',
          avatarText: this.persona().avatar || '',
          fallbackLetter: this.persona().name,
          badgeSize: 32
        })
        Text(this.persona().name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph(this.drawerAssistantsExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(15)
          .fontColor([$r('app.color.muted')])
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .borderRadius(12)
      .backgroundColor(this.drawerAssistantsExpanded ? $r('app.color.surface') : Color.Transparent)
      .onClick(() => { this.drawerAssistantsExpanded = !this.drawerAssistantsExpanded; })

      if (this.drawerAssistantsExpanded) {
        Column({ space: 4 }) {
          ForEach(this.workspace.personas, (pItem: Persona) => {
            Row({ space: 8 }) {
              KelivoAvatarBadge({
                brandId: '',
                avatarText: pItem.avatar || '',
                fallbackLetter: pItem.name,
                badgeSize: 26
              })
              Text(pItem.name)
                .fontSize(14)
                .fontColor(pItem.id === this.persona().id ? $r('app.color.accent') : $r('app.color.ink'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (pItem.id === this.selectedPersonaId()) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(14)
                  .fontColor([$r('app.color.accent')])
              }
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.square_and_pencil'))
                  .fontSize(14)
                  .fontColor([$r('app.color.muted')])
              }
              .width(28)
              .height(28)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .accessibilityText(`编辑 ${pItem.name}`)
              .onClick(() => {
                this.drawerAssistantsExpanded = false;
                this.personaEditTargetId = pItem.id;
                this.navigateTo('personas');
              })
            }
            .width('100%')
            .padding({ left: 10, right: 8, top: 6, bottom: 6 })
            .borderRadius(10)
            .backgroundColor(pItem.id === this.selectedPersonaId() ? $r('app.color.tint') : Color.Transparent)
            .onClick(() => {
              this.selectAssistant(pItem.id, false);
            })
          }, (pItem: Persona) => `da-${pItem.id}-${pItem.name}`)

          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(14)
              .fontColor([$r('app.color.accent')])
            Text('管理助手与提示词')
              .fontSize(13)
              .fontColor($r('app.color.accent'))
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 6 })
          .onClick(() => {
            this.drawerAssistantsExpanded = false;
            this.personaEditTargetId = '';
            this.navigateTo('personas');
          })
        }
        .width('100%')
        .padding(6)
        .borderRadius(12)
        .backgroundColor($r('app.color.surface'))
      }

      // Conversations List grouped by Pinned / Today / Yesterday / Earlier
      List({ space: 4 }) {
        ForEach(this.chatRows(), (c: Conversation, ci: number) => {
          ListItem() {
            Column({ space: 2 }) {
              if (this.isDrawerGroupStart(this.chatRows(), ci)) {
                Text(this.dateGroupLabel(c))
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.muted'))
                  .padding({ left: 8, top: ci === 0 ? 2 : 8, bottom: 2 })
                  .width('100%')
              }
              Row() {
                if (this.renameId === c.id) {
                  TextInput({ text: this.renameText, placeholder: '对话名称' }).layoutWeight(1).maxLength(120)
                    .onChange((v: string) => { this.renameText = v; })
                  Button('保存')
                    .height(30)
                    .fontSize(12)
                    .onClick(() => {
                      this.putChat({ id: c.id, title: this.renameText.trim(), updated: c.updated, messages: c.messages, personaId: c.personaId });
                      this.renameId = '';
                      this.persistAction();
                    })
                  this.actionIcon($r('sys.symbol.xmark'), '取消重命名', () => { this.renameId = ''; })
                } else {
                  Row({ space: 6 }) {
                    if (c.pinned) {
                      SymbolGlyph($r('sys.symbol.pin'))
                        .fontSize(13)
                        .fontColor([$r('app.color.accent')])
                    }
                    Text((c.ephemeral ? '🕶 ' : '') + c.title)
                      .fontSize(14)
                      .fontWeight(c.id === this.workspace.activeConversation ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor($r('app.color.ink'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  .layoutWeight(1)
                  .padding({ left: 10, right: 4, top: 11, bottom: 11 })
                  .onClick(() => {
                    this.setDrawerOpen(false);
                    this.activate(c.id);
                  })

                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                      .fontSize(16)
                      .fontColor([$r('app.color.muted')])
                  }
                  .height(34)
                  .width(34)
                  .padding(0)
                  .backgroundColor(Color.Transparent)
                  .accessibilityText('管理对话')
                  .bindMenu([
                    { value: c.pinned ? '取消置顶' : '置顶', action: () => {
                      this.putChat({ id: c.id, title: c.title, updated: c.updated, personaId: c.personaId, messages: c.messages, pinned: !c.pinned });
                      this.persistAction();
                    } },
                    { value: '重命名', action: () => { this.renameText = c.title; this.renameId = c.id; } },
                    { value: '复制对话', action: () => { this.duplicateChat(c); } },
                    { value: '迁移至下一助手', action: () => { this.moveChatToNextPersona(c); } },
                    { value: '删除对话', action: () => this.removeChat(c) }
                  ], ImmersiveMaterialStyle.menuOptions(this.immersiveLightOn()))
                }
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor(c.id === this.workspace.activeConversation ? $r('app.color.tint') : Color.Transparent)
            }
            .width('100%')
          }
        }, (c: Conversation) => `${c.id}_${c.title}_${c.updated}_${c.messages.length}_${!!c.pinned}_${c.id === this.workspace.activeConversation}_${c.id === this.renameId}`)

        if (!this.chatRows().length) {
          ListItem() {
            Text(this.query ? '没有匹配的对话' : '发送第一条消息后，对话会保存在这里。')
              .padding({ left: 10, top: 14 })
              .fontSize(13)
              .fontColor($r('app.color.muted'))
          }
        }
      }
      .width('100%')
      .layoutWeight(1)

      // Bottom User Profile + Translate + Settings Bar (matching android_02_drawer.png)
      if (this.drawerEditingUser) {
        Row({ space: 6 }) {
          TextInput({ text: this.drawerUserNameDraft, placeholder: '输入昵称' })
            .layoutWeight(1)
            .height(34)
            .fontSize(13)
            .onChange((v: string) => { this.drawerUserNameDraft = v; })
          Button('确定')
            .height(32)
            .fontSize(12)
            .onClick(() => {
              const trimmed = this.drawerUserNameDraft.trim();
              if (trimmed) {
                this.workspace.userName = trimmed;
                this.persistAction();
              }
              this.drawerEditingUser = false;
            })
        }
        .width('100%')
        .padding({ top: 4 })
      } else {
        Row({ space: 8 }) {
          KelivoAvatarBadge({
            brandId: '',
            avatarText: '',
            fallbackLetter: this.workspace.userName || '用户',
            badgeSize: 32
          })
          Text(this.workspace.userName || '用户')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .onClick(() => {
              this.drawerUserNameDraft = this.workspace.userName || '用户';
              this.drawerEditingUser = true;
            })

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.translate'))
              .fontSize(19)
              .fontColor([$r('app.color.ink')])
          }
          .width(38)
          .height(38)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.uiLabels().translateTool)
          .onClick(() => {
            this.translateInitialText = '';
            this.navigateTo('translate');
          })

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(19)
              .fontColor([$r('app.color.ink')])
          }
          .width(38)
          .height(38)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.uiLabels().settings)
          .onClick(() => {
            this.refreshStorageSize().catch(() => {});
            this.navigateTo('settings');
          })
        }
        .width('100%')
        .padding({ top: 4 })
      }
    }
    .padding({
      top: this.winTopInset + 6,
      left: 14 + (isOverlay ? this.winLeftInset : 0),
      right: 14,
      bottom: Math.max(12, this.effectiveBottomInset() + 8)
    })
    .width(isOverlay ? '100%' : 285)
    .height('100%')
    .backgroundColor(isOverlay ? $r('app.color.surface') : $r('app.color.panel'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .enabled(!this.working && !this.picking)
  }

  @Builder
  drawerOverlay() {
    Row() {
      Column() {
        this.sidebarBody(true)
      }
      .width('78%')
      .constraintSize({ maxWidth: 335 })
      .height('100%')
      .transition(SystemMotion.drawerPanelTransition(this.reduceMotion))

      Column()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => { this.setDrawerOpen(false); })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#4D000000')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .transition(SystemMotion.drawerScrimTransition(this.reduceMotion))
  }

  @Builder
  toolCallsView(records: ToolCallRecord[], keyPrefix: string) {
    Column({ space: 6 }) {
      ForEach(records, (tc: ToolCallRecord, ti: number) => {
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text(tc.status === 'done' ? '✓' : tc.status === 'error' || tc.status === 'denied' ? '✕' : '⏳')
              .fontSize(12).fontWeight(FontWeight.Bold)
              .fontColor(tc.status === 'done' ? $r('app.color.accent') : $r('app.color.warning'))
            Text('工具 · ' + tc.name).fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).layoutWeight(1)
            if (tc.durationMs > 0) {
              Text(tc.durationMs + 'ms').fontSize(11).fontColor($r('app.color.muted'))
            }
            Button(this.expandedToolId === (keyPrefix + tc.id) ? '收起' : '详情')
              .height(24).fontSize(11).backgroundColor($r('app.color.surface')).fontColor($r('app.color.accent'))
              .onClick(() => {
                const k = keyPrefix + tc.id;
                this.expandedToolId = this.expandedToolId === k ? '' : k;
              })
          }.width('100%')
          if (this.expandedToolId === (keyPrefix + tc.id)) {
            Text('参数: ' + tc.argsJson).fontFamily('monospace').fontSize(11).fontColor($r('app.color.muted'))
              .copyOption(CopyOptions.LocalDevice)
            if (tc.diffText) {
              Text(tc.diffText).fontFamily('monospace').fontSize(11).fontColor($r('app.color.ink'))
                .padding(6).borderRadius(6).backgroundColor($r('app.color.surface')).copyOption(CopyOptions.LocalDevice)
            }
            if (tc.resultText) {
              Text(tc.resultText.slice(0, 2000)).fontSize(12).fontColor($r('app.color.ink'))
                .copyOption(CopyOptions.LocalDevice)
            }
          }
        }.width('100%').padding(8).borderRadius(10).backgroundColor($r('app.color.panel'))
          .alignItems(HorizontalAlign.Start)
      }, (tc: ToolCallRecord, ti: number) => keyPrefix + '-' + ti + '-' + tc.id + '-' + tc.status)
    }.width('100%')
  }

  @Builder
  messageRow(msg: ChatMessage, msgIdx: number) {
    Column({ space: 6 }) {
      if (this.multiSelectMode) {
        Row({ space: 6 }) {
          Button(this.selectedMsgIds.includes(msg.id) ? '☑ 已选中' : '☐ 选择此消息')
            .height(26).fontSize(11)
            .backgroundColor(this.selectedMsgIds.includes(msg.id) ? $r('app.color.accent') : $r('app.color.panel'))
            .fontColor(this.selectedMsgIds.includes(msg.id) ? $r('app.color.on_accent') : $r('app.color.ink'))
            .onClick(() => this.toggleSelectedMsg(msg.id))
        }.width('100%')
      }

      if (msg.role === 'assistant') {
        if (this.chatDisplayCfg().showModelIcon || this.chatDisplayCfg().showModelName ||
          this.chatDisplayCfg().showModelTimestamp || msg.isSummary) {
          Row({ space: 8 }) {
            if (this.chatDisplayCfg().showModelIcon) {
              KelivoAvatarBadge({
                brandId: this.persona().useAssistantAvatar
                  ? ''
                  : resolveBrandIconId(`${msg.model || ''} ${this.provider().name}`, this.provider().family),
                avatarText: this.persona().useAssistantAvatar ? (this.persona().avatar || '') : '',
                fallbackLetter: this.persona().useAssistantName ? this.persona().name : (msg.model || this.provider().name),
                badgeSize: 22
              })
            }
            if (this.chatDisplayCfg().showModelName) {
              Text(this.persona().useAssistantName ? this.persona().name : this.modelHeaderLabel(msg))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (msg.isSummary) {
              Text('摘要节点')
                .fontSize(11)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(6)
                .backgroundColor($r('app.color.tint'))
                .fontColor($r('app.color.accent'))
            }
            if (this.chatDisplayCfg().showModelTimestamp && this.formatMsgTime(msg.createdAt).length > 0) {
              Text(this.formatMsgTime(msg.createdAt))
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
        }

        if (this.isRegeneratingMessage(msg)) {
          this.liveStreamBody()
        } else {
          if (msg.reasoning && this.chatDisplayCfg().showThinkingCards) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.lightbulb'))
                  .fontSize(13)
                  .fontColor([$r('app.color.accent')])
                Text(this.expandedReasoning === msg.id ? '深度思考过程（点击收起）' : '深度思考过程（点击展开）')
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                SymbolGlyph(this.expandedReasoning === msg.id ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
                  .fontSize(13)
                  .fontColor([$r('app.color.muted')])
              }
            }
            .height(30)
            .padding({ left: 10, right: 10 })
            .borderRadius(15)
            .backgroundColor($r('app.color.panel'))
            .onClick(() => { this.expandedReasoning = this.expandedReasoning === msg.id ? '' : msg.id; })

            if (this.expandedReasoning === msg.id) {
              Column() {
                if (this.appearanceCfg().enableReasoningMarkdown !== false) {
                  MessageBody({
                    source: msg.reasoning,
                    bodyFontSize: 13,
                    codeFontSize: Math.max(11, this.codeTextSize() - 1),
                    enableMarkdown: true,
                    enableMathLatex: this.appearanceCfg().enableMathLatex !== false,
                    onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => this.openPreview(kind, title, code),
                    onOpenUrl: (url: string) => { this.openUrlInBrowser(url); },
                    onViewImage: (url: string, alt: string) => this.openImage(url, alt || '图片'),
                    onAskDraft: (draftStr: string) => { this.draft = draftStr; }
                  })
                } else {
                  Text(msg.reasoning)
                    .fontSize(13)
                    .lineHeight(20)
                    .fontColor($r('app.color.muted'))
                    .copyOption(CopyOptions.LocalDevice)
                    .width('100%')
                }
              }
              .padding(10)
              .borderRadius(12)
              .backgroundColor($r('app.color.panel'))
              .width('100%')
            }
          }

          if (msg.toolCalls?.length && this.chatDisplayCfg().showToolCards) {
            this.toolCallsView(msg.toolCalls, msg.id)
          }

          ForEach(this.assistantParagraphsFor(msg), (para: string, pi: number) => {
            Column() {
              MessageBody({
                source: para,
                bodyFontSize: this.bodyTextSize(),
                codeFontSize: this.codeTextSize(),
                enableMarkdown: this.appearanceCfg().enableAssistantMarkdown !== false,
                enableMathLatex: this.appearanceCfg().enableMathLatex !== false,
                onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => this.openPreview(kind, title, code),
                onOpenUrl: (url: string) => { this.openUrlInBrowser(url); },
                onViewImage: (url: string, alt: string) => this.openImage(url, alt || '图片'),
                onAskDraft: (draftStr: string) => { this.draft = draftStr; }
              })
            }
            .width(this.appearanceCfg().fitAssistantBubble ? undefined : '100%')
            .constraintSize(this.appearanceCfg().fitAssistantBubble ? { maxWidth: '92%' } : undefined)
            .alignItems(HorizontalAlign.Start)
            .padding(this.appearanceCfg().bubbleStyle === 'default' && !this.appearanceCfg().splitParagraphsIntoBubbles
              ? 0
              : { left: 12, right: 12, top: 10, bottom: 10 })
            .borderRadius(this.bubbleRadiusVal())
            .backgroundColor(this.appearanceCfg().bubbleStyle === 'default'
              ? (this.appearanceCfg().splitParagraphsIntoBubbles ? $r('app.color.surface') : Color.Transparent)
              : this.assistantBubbleBg())
            .backgroundBlurStyle(this.appearanceCfg().bubbleStyle === 'frosted' ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
          }, (para: string, pi: number) => `${msg.id}-${this.versionLabel(msg)}-p-${pi}-${para.length}-${this.appearanceCfg().bubbleStyle}-${this.appearanceCfg().fitAssistantBubble}`)

          if (msg.generatedImages?.length && this.chatDisplayCfg().showFilesBelowReplies) {
            Row({ space: 8 }) {
              ForEach(msg.generatedImages, (imgAtt: Attachment, ii: number) => {
                Image(this.imageSrcForAttachment(imgAtt)).width(160).height(160).objectFit(ImageFit.Cover).borderRadius(12)
                  .onClick(() => this.openImage(this.imageSrcForAttachment(imgAtt), imgAtt.name))
              }, (imgAtt: Attachment, ii: number) => msg.id + '-gi-' + ii)
            }
          }
          if (msg.translation) {
            Column({ space: 4 }) {
              Text('译文').fontSize(11).fontWeight(FontWeight.Bold).fontColor($r('app.color.accent'))
              Text(msg.translation).fontSize(14).lineHeight(22).fontColor($r('app.color.ink')).copyOption(CopyOptions.LocalDevice)
            }.width('100%').padding(10).borderRadius(10).backgroundColor($r('app.color.panel')).alignItems(HorizontalAlign.Start)
          }

          Row({ space: 2 }) {
            this.msgActionIcon(
              $r('sys.symbol.rectangle_on_rectangle'),
              '复制',
              false,
              `msgCopy-${msgIdx}`,
              () => { this.copyText(msg.text); }
            )
            this.msgActionIcon(
              $r('sys.symbol.arrow_2_circlepath'),
              '重新生成',
              true,
              `msgRegen-${msgIdx}`,
              () => { this.send(true, msg.id); }
            )
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph(this.readingId === msg.id ? $r('sys.symbol.speaker_slash') : $r('sys.symbol.speaker_wave_2'))
                .fontSize(17)
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([this.readingId === msg.id ? $r('app.color.accent') : $r('app.color.muted')])
            }
            .id(`msgSpeak-${msgIdx}`)
            .width(32)
            .height(32)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .accessibilityText(this.readingId === msg.id ? '停止朗读' : '朗读')
            .onClick(() => { this.narrate(msg); })

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.translate'))
                .fontSize(17)
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([msg.translation ? $r('app.color.accent') : $r('app.color.muted')])
            }
            .id(`msgTrans-${msgIdx}`)
            .width(32)
            .height(32)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .accessibilityText(msg.translation ? '隐藏译文' : '翻译')
            .onClick(() => { this.translateMessage(msg.id); })

            this.msgMoreDotsBtn(`msgMore-${msgIdx}`, () => { this.openMessageActionSheet(msg); })
            if (this.activeVersionCount(msg) > 1) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.chevron_left'))
                  .fontSize(15)
                  .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                  .fontColor([this.canPrevVersion(msg) ? $r('app.color.muted') : $r('app.color.line')])
              }
              .id(`msgVerPrev-${msgIdx}`)
              .width(26)
              .height(28)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .enabled(this.canPrevVersion(msg))
              .accessibilityText('上一版本')
              .onClick(() => { this.switchReplyVersion(msg.id, -1); })

              Text(this.versionLabel(msg))
                .id(`msgVerLabel-${msgIdx}`)
                .fontSize(12)
                .fontColor($r('app.color.muted'))
                .padding({ left: 2, right: 2 })

              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(15)
                  .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                  .fontColor([this.canNextVersion(msg) ? $r('app.color.muted') : $r('app.color.line')])
              }
              .id(`msgVerNext-${msgIdx}`)
              .width(26)
              .height(28)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .enabled(this.canNextVersion(msg))
              .accessibilityText('下一版本')
              .onClick(() => { this.switchReplyVersion(msg.id, 1); })
            }
            Blank()
            if (this.chatDisplayCfg().showTokenStats && this.compactTokenCountText(msg).length > 0) {
              Text(this.compactTokenCountText(msg))
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ top: 2 })
        }
      } else {
        if (this.chatDisplayCfg().showUserAvatar || this.chatDisplayCfg().showUserName ||
          (this.chatDisplayCfg().showUserTimestamp && this.formatMsgTime(msg.createdAt).length > 0)) {
          Row({ space: 6 }) {
            if (this.chatDisplayCfg().showUserTimestamp && this.formatMsgTime(msg.createdAt).length > 0) {
              Text(this.formatMsgTime(msg.createdAt))
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
            if (this.chatDisplayCfg().showUserName) {
              Text(this.workspace.userName || '用户')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.muted'))
            }
            if (this.chatDisplayCfg().showUserAvatar) {
              KelivoAvatarBadge({
                brandId: '',
                avatarText: '',
                fallbackLetter: this.workspace.userName || '用户',
                badgeSize: 20
              })
            }
          }
          .justifyContent(FlexAlign.End)
          .width('100%')
        }
        Column({ space: 6 }) {
          if (msg.quote?.excerpt) {
            Text('❝ ' + msg.quote.excerpt).fontSize(12).fontColor($r('app.color.muted'))
              .padding(6).borderRadius(8).backgroundColor($r('app.color.surface'))
          }
          if (msg.sources?.length) {
            Button('网页来源 · ' + msg.sources.length).height(30).fontSize(12).fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.surface')).onClick(() => { this.expandedSources = this.expandedSources === msg.id ? '' : msg.id; })
            if (this.expandedSources === msg.id) {
              ForEach(msg.sources, (hit: SearchHit, i: number) => {
                Text('[' + (i + 1) + '] ' + hit.title + '\n' + hit.url).fontSize(12).fontColor($r('app.color.muted'))
                  .copyOption(CopyOptions.LocalDevice)
              }, (hit: SearchHit, i: number) => i + hit.url)
            }
          }
          ForEach(getAllAttachments(msg), (att: Attachment, ai: number) => {
            if (att.mime.startsWith('image/') && (att.data || att.filePath)) {
              Image(this.imageSrcForAttachment(att)).width(160).height(120).objectFit(ImageFit.Cover).borderRadius(10)
                .onClick(() => this.openImage(this.imageSrcForAttachment(att), att.name))
            } else {
              Text('附件 · ' + att.name).fontSize(12).fontColor($r('app.color.muted'))
            }
          }, (att: Attachment, ai: number) => msg.id + '-att-' + ai + '-' + att.name)
          if (msg.text) {
            if ((this.appearanceCfg().collapseLongUserChars || 0) > 0 &&
              msg.text.length > (this.appearanceCfg().collapseLongUserChars || 0) &&
              !this.expandedLongMsgIds.includes(msg.id)) {
              Column({ space: 4 }) {
                Text(msg.text.slice(0, this.appearanceCfg().collapseLongUserChars) + '...')
                  .fontSize(this.bodyTextSize())
                  .lineHeight(Math.round(this.bodyTextSize() * 1.48))
                  .fontColor($r('app.color.ink'))
                  .copyOption(CopyOptions.LocalDevice)
                Text(`展开全文 (${msg.text.length} 字)`)
                  .fontSize(12)
                  .fontColor($r('app.color.accent'))
                  .onClick(() => {
                    this.expandedLongMsgIds = [...this.expandedLongMsgIds, msg.id];
                  })
              }
              .alignItems(HorizontalAlign.Start)
            } else if (this.appearanceCfg().enableUserMarkdown !== false &&
              /(`|\*\*|#|\[.*\]\(|\n[-*>]\s)/.test(msg.text)) {
              MessageBody({
                source: msg.text,
                bodyFontSize: this.bodyTextSize(),
                codeFontSize: this.codeTextSize(),
                enableMarkdown: true,
                enableMathLatex: this.appearanceCfg().enableMathLatex !== false,
                onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => this.openPreview(kind, title, code),
                onOpenUrl: (url: string) => { this.openUrlInBrowser(url); },
                onViewImage: (url: string, alt: string) => this.openImage(url, alt || '图片'),
                onAskDraft: (draftStr: string) => { this.draft = draftStr; }
              })
            } else {
              Text(msg.text)
                .fontSize(this.bodyTextSize())
                .lineHeight(Math.round(this.bodyTextSize() * 1.48))
                .fontColor($r('app.color.ink'))
                .copyOption(CopyOptions.LocalDevice)
            }
          }
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .constraintSize({ maxWidth: '88%' })
        .borderRadius(this.bubbleRadiusVal())
        .backgroundColor(this.userBubbleBg())
        .backgroundBlurStyle(this.appearanceCfg().bubbleStyle === 'frosted' ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
        .alignItems(HorizontalAlign.Start)

        if (this.chatDisplayCfg().showUserMessageActions) {
          Row({ space: 4 }) {
            this.msgActionIcon(
              $r('sys.symbol.rectangle_on_rectangle'),
              '复制',
              false,
              `userCopy-${msgIdx}`,
              () => { this.copyText(msg.text); }
            )
            this.msgActionIcon(
              $r('sys.symbol.arrow_2_circlepath'),
              '重新生成',
              true,
              `userRegen-${msgIdx}`,
              () => { this.send(true, msg.id); }
            )
            this.msgActionIcon(
              $r('sys.symbol.pencil_line'),
              '编辑',
              true,
              `userEdit-${msgIdx}`,
              () => {
                this.editingMsgText = msg.text;
                SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
                  this.editingMsgId = msg.id;
                });
              }
            )
            this.msgMoreDotsBtn(`userMore-${msgIdx}`, () => { this.openMessageActionSheet(msg); })
          }
          .padding({ top: 2, right: 2 })
        }
      }
    }.alignItems(msg.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start).width('100%')
  }

  @Builder
  chatTitleBar() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.immersiveLightOn() && this.chatCanScrollUnderTitle()) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [[hexWithAlpha(this.chatBgColor(), '99'), 0.0], [hexWithAlpha(this.chatBgColor(), '00'), 1.0]]
          })
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      }

      Row({ space: 6 }) {
        if (!this.wide) {
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.icon_list'))
              .width(20)
              .height(20)
              .objectFit(ImageFit.Contain)
              .fillColor($r('sys.color.icon_primary'))
          }
          .id('openDrawer')
          .width(40)
          .height(40)
          .padding(0)
          .accessibilityText('打开侧边栏')
          .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.themeTokens(), this.immersiveLightOn()))
          .onClick(() => {
            if (!this.working && !this.picking) {
              this.setDrawerOpen(true);
            }
          })
          .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.themeTokens(), this.effectiveDark(), this.immersiveLightOn()))
        }

        Column({ space: 1 }) {
          Text(this.activeChat()?.title || (this.ephemeralMode ? '临时对话' : this.uiLabels().newChat))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.persona().name} · ${this.activeModelId() || this.provider().name}`)
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: this.wide ? 360 : 185 })
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(18)
        .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.themeTokens(), this.immersiveLightOn()))
        .onClick(() => {
          if (!this.working && !this.picking) {
            this.showModelQuickSheet = true;
          }
        })
        .systemMaterial(ImmersiveMaterialStyle.titlePillMaterial(this.themeTokens(), this.effectiveDark(), this.immersiveLightOn()))

        Blank()

        if (this.wideSide) {
          Button(this.sidePanelMode ? '收起' : '分栏', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(36)
            .fontSize(12)
            .fontColor($r('sys.color.font_primary'))
            .borderRadius(18)
            .padding({ left: 12, right: 12 })
            .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.themeTokens(), this.immersiveLightOn(), this.sidePanelMode !== ''))
            .onClick(() => {
              this.setSidePanelMode(this.sidePanelMode === '' ? 'browser' : '');
            })
            .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.themeTokens(), this.effectiveDark(), this.immersiveLightOn(), this.sidePanelMode !== ''))
        }

        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.map'))
            .fontSize(18)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .width(40)
        .height(40)
        .padding(0)
        .accessibilityText('对话大纲')
        .enabled(!this.working && !this.picking)
        .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.themeTokens(), this.immersiveLightOn()))
        .onClick(() => { this.showMiniMap = true; })
        .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.themeTokens(), this.effectiveDark(), this.immersiveLightOn()))

        if (!this.activeChat() || (this.activeChat()?.messages.length || 0) === 0) {
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            if (this.ephemeralMode) {
              Image($r('app.media.icon_temp_chat_checked'))
                .width(19)
                .height(19)
                .objectFit(ImageFit.Contain)
                .fillColor($r('app.color.accent'))
            } else {
              SymbolGlyph($r('sys.symbol.circle_dashed'))
                .fontSize(19)
                .fontColor([$r('sys.color.icon_primary')])
            }
          }
          .id('tempChatToggle')
          .width(40)
          .height(40)
          .padding(0)
          .accessibilityText(this.ephemeralMode ? '退出临时对话' : '临时对话')
          .enabled(!this.working && !this.picking)
          .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.themeTokens(), this.immersiveLightOn(), this.ephemeralMode))
          .onClick(() => { this.activate('', !this.ephemeralMode); })
          .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.themeTokens(), this.effectiveDark(), this.immersiveLightOn(), this.ephemeralMode))
        } else {
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(19)
              .fontColor([$r('sys.color.icon_primary')])
          }
          .width(40)
          .height(40)
          .padding(0)
          .accessibilityText(this.uiLabels().newChat)
          .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.themeTokens(), this.immersiveLightOn()))
          .onClick(() => { this.activate(''); })
          .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.themeTokens(), this.effectiveDark(), this.immersiveLightOn()))
        }

        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(19)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .id('chatMenu')
        .width(40)
        .height(40)
        .padding(0)
        .accessibilityText('更多操作')
        .enabled(!this.working && !this.picking)
        .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.themeTokens(), this.immersiveLightOn()))
        .bindMenu([
          { value: '搜索本对话内容', action: () => {
            SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
              this.inChatSearchOpen = !this.inChatSearchOpen;
            });
          } },
          { value: this.fullAccessMode ? '切换为工具审批模式' : '切换为工具完全访问', action: () => {
            this.fullAccessMode = !this.fullAccessMode;
            const c = this.activeChat();
            if (c) { c.toolPermissionMode = this.fullAccessMode ? 'full' : 'ask'; this.persistAction(); }
          } },
          { value: '整理本对话记忆', action: () => { this.organizeCurrentConversation(); } },
          { value: '助手与提示词设置', action: () => { this.navigateTo('personas'); } },
          { value: '上下文与生成参数', action: () => { this.navigateTo('context'); } },
          { value: '内置浏览器', action: () => { this.navigateTo('browser'); } },
          { value: '用量统计', action: () => { this.refreshLogsAndStats().catch(() => {}); this.navigateTo('stats'); } },
          { value: '设置中心', action: () => { this.refreshStorageSize().catch(() => {}); this.navigateTo('settings'); } }
        ], ImmersiveMaterialStyle.menuOptions(this.immersiveLightOn()))
        .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.themeTokens(), this.effectiveDark(), this.immersiveLightOn()))
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.winTopInset,
        left: this.wide ? 16 : 8,
        right: 8 + this.winTitleRightAvoid
      })
      .alignItems(VerticalAlign.Center)
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .clip(false)
  }

  @Builder
  composerCardContent() {
    if (this.quoteDraft) {
      Row({ space: 6 }) {
        Text('引用: ' + this.quoteDraft.excerpt).fontSize(12).fontColor($r('app.color.muted'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Button('×').height(24).fontSize(12).padding(0).backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
          .onClick(() => {
            SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
              this.quoteDraft = undefined;
            });
          })
      }.width('100%').padding({ left: 8, right: 4 }).backgroundColor($r('app.color.panel')).borderRadius(8)
        .transition(SystemMotion.inlineBarTransition(this.reduceMotion))
    }
    if (this.attachedList.length) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.attachedList, (att: Attachment, ai: number) => {
            Button(att.name + '  ×').height(28).fontSize(12).backgroundColor($r('app.color.tint'))
              .fontColor($r('app.color.accent')).onClick(() => {
                this.attachedList = this.attachedList.filter((_a: Attachment, idx: number): boolean => idx !== ai);
              })
          }, (att: Attachment, ai: number) => 'catt-' + ai + '-' + att.name)
        }
      }.scrollable(ScrollDirection.Horizontal).width('100%')
    }
    if (this.showPromptQuickBar) {
      Column({ space: 6 }) {
        if ((this.workspace.instructionCards || []).length > 0) {
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.workspace.instructionCards || [], (card: InstructionCard) => {
                Button(((this.workspace.activeInstructionIds || []).includes(card.id) ? '✓ ' : '') + card.title)
                  .height(26).fontSize(11).borderRadius(8)
                  .backgroundColor((this.workspace.activeInstructionIds || []).includes(card.id) ? $r('app.color.accent') : $r('app.color.panel'))
                  .fontColor((this.workspace.activeInstructionIds || []).includes(card.id) ? $r('app.color.on_accent') : $r('app.color.ink'))
                  .onClick(() => {
                    const cur = this.workspace.activeInstructionIds || [];
                    this.workspace.activeInstructionIds = cur.includes(card.id)
                      ? cur.filter((id: string): boolean => id !== card.id)
                      : [...cur, card.id];
                    this.persistAction();
                  })
              }, (card: InstructionCard) => 'ic-' + card.id)
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        }
        if (this.allQuickPhrases().length > 0) {
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.allQuickPhrases(), (qp: QuickPhrase) => {
                Button('» ' + qp.title)
                  .height(26).fontSize(11).borderRadius(8)
                  .backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                  .onClick(() => {
                    this.draft = this.draft.trim().length > 0 ? `${this.draft}\n${qp.content}` : qp.content;
                    SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
                      this.showPromptQuickBar = false;
                    });
                  })
              }, (qp: QuickPhrase) => 'qp-' + qp.id)
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        }
      }.width('100%').padding({ bottom: 4 })
        .transition(SystemMotion.inlineBarTransition(this.reduceMotion))
    }

    TextArea({ text: this.draft, placeholder: this.composerPlaceholder() })
      .id('composer')
      .width('100%')
      .enabled(!this.working && !this.picking)
      .fontSize(16)
      .fontColor(ImmersiveMaterialStyle.isActive(this.immersiveLightOn()) ? $r('sys.color.font_primary') : $r('app.color.ink'))
      .placeholderColor(ImmersiveMaterialStyle.isActive(this.immersiveLightOn()) ? $r('sys.color.font_secondary') : $r('app.color.muted'))
      .barState(BarState.Auto)
      .constraintSize({ minHeight: 40, maxHeight: 160 })
      .backgroundColor(Color.Transparent)
      .onSubmit((enterKey: EnterKeyType) => {
        if (this.appearanceCfg().enterToSend && !this.working && !this.picking && (this.draft.trim().length > 0 || this.attachedList.length > 0)) {
          this.send();
        }
      })
      .onChange((v: string) => { this.draft = v; })

    Row({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        KelivoAvatarBadge({
          brandId: this.activeBrandId(),
          avatarText: '',
          fallbackLetter: this.provider().name,
          badgeSize: 22
        })
      }
      .id('currentModel')
      .width(36)
      .height(36)
      .padding(0)
      .accessibilityText('选择模型')
      .enabled(!this.working && !this.picking)
      .backgroundColor(this.composerPillBg())
      .onClick(() => { this.showModelQuickSheet = true; })

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.globe_badge_message'))
          .fontSize(17)
          .fontColor([this.searchOn ? $r('app.color.accent') : this.composerInactiveIconColor()])
      }
      .id('webSearch')
      .width(36)
      .height(36)
      .padding(0)
      .accessibilityText(this.searchOn ? '联网搜索已开启' : '联网搜索')
      .enabled(!this.working && !this.picking)
      .backgroundColor(this.searchOn ? $r('app.color.tint') : Color.Transparent)
      .onClick(() => { this.showSearchQuickSheet = true; })

      if (this.activeModelSupportsReasoning() || (this.effectiveParams().reasoningEffort || 'off') !== 'off') {
        Button({ type: this.chatDisplayCfg().showReasoningLevelOnButton ? ButtonType.Normal : ButtonType.Circle }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(this.chatDisplayCfg().showReasoningLevelOnButton ? 15 : 17)
              .fontColor([(this.effectiveParams().reasoningEffort || 'off') !== 'off' ? $r('app.color.accent') : this.composerInactiveIconColor()])
            if (this.chatDisplayCfg().showReasoningLevelOnButton) {
              Text(this.reasoningLabelShort())
                .fontSize(11)
                .fontColor((this.effectiveParams().reasoningEffort || 'off') !== 'off' ? $r('app.color.accent') : this.composerInactiveIconColor())
            }
          }
        }
        .id('reasoningToggle')
        .height(36)
        .constraintSize({ minWidth: 36 })
        .padding(this.chatDisplayCfg().showReasoningLevelOnButton ? { left: 9, right: 9 } : 0)
        .borderRadius(18)
        .accessibilityText(`思考深度: ${this.reasoningLabelShort()}`)
        .enabled(!this.working && !this.picking)
        .backgroundColor((this.effectiveParams().reasoningEffort || 'off') !== 'off' ? $r('app.color.tint') : Color.Transparent)
        .onClick(() => { this.showReasoningSheet = true; })
      }

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
          .fontSize(16)
          .fontColor([this.fullAccessMode ? $r('app.color.accent') : this.composerInactiveIconColor()])
      }
      .id('chatTools')
      .width(36)
      .height(36)
      .padding(0)
      .accessibilityText('对话工具与工作区')
      .enabled(!this.working && !this.picking)
      .backgroundColor(this.fullAccessMode ? $r('app.color.tint') : Color.Transparent)
      .onClick(() => { this.showChatToolsSheet = true; })

      if (this.imageGenMode) {
        Text('绘图')
          .fontSize(11)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.tint'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(10)
          .onClick(() => { this.imageGenMode = false; })
      }

      Blank()

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.mic'))
          .fontSize(17)
          .fontColor([this.recording ? Color.White : this.composerInactiveIconColor()])
      }
      .id('dictateBtn')
      .width(34)
      .height(34)
      .padding(0)
      .accessibilityText(this.recording ? '停止录音' : '语音输入')
      .enabled(!this.working && !this.picking)
      .backgroundColor(this.recording ? $r('app.color.warning') : Color.Transparent)
      .onClick(() => { this.toggleDictation(); })

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([ImmersiveMaterialStyle.isActive(this.immersiveLightOn()) ? $r('sys.color.icon_primary') : $r('app.color.ink')])
      }
      .id('plusToolsBtn')
      .width(36)
      .height(36)
      .padding(0)
      .accessibilityText('更多功能')
      .enabled(!this.working && !this.picking)
      .backgroundColor(this.composerPillBg())
      .onClick(() => { this.showBottomToolsSheet = true; })

      Button({ type: ButtonType.Circle }) {
        if (this.working) {
          Rect().width(13).height(13).radius(3).fill($r('app.color.on_accent'))
        } else {
          SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(18).fontColor([$r('app.color.on_accent')])
        }
      }
      .id(this.working ? 'stop' : 'send')
      .width(36)
      .height(36)
      .padding(0)
      .backgroundColor($r('app.color.accent'))
      .accessibilityText(this.working ? this.uiLabels().stop : this.uiLabels().send)
      .enabled(this.working || (!this.picking && (!!this.draft.trim() || !!this.attachedList.length)))
      .onClick(() => { if (this.working) this.stopReply(); else this.send(); })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  composerTabBar() {
    Column() {
      if (this.readingId) {
        Row({ space: 8 }) {
          Text('🔊 正在语音朗读').fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.accent')).layoutWeight(1)
          Button(this.ttsPaused ? '继续' : '暂停').height(26).fontSize(11)
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
            .onClick(() => { this.toggleTtsPause(); })
          Button('停止').height(26).fontSize(11)
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.warning'))
            .onClick(() => { this.speaker.stop(); this.readingId = ''; this.ttsPaused = false; })
        }.width('94%').constraintSize({ maxWidth: 800 }).padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(12).backgroundColor($r('app.color.tint')).margin({ bottom: 6 })
      }

      if (this.askQuestionText) {
        Column({ space: 8 }) {
          Text('🤖 AI 向您确认：' + this.askQuestionText)
            .fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
          if (this.askQuestionOptions.length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.askQuestionOptions, (opt: string, oi: number) => {
                Button(opt)
                  .height(28).fontSize(12).margin({ right: 6, bottom: 6 }).borderRadius(8)
                  .backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                  .onClick(() => this.submitAskUserInput(opt))
              }, (opt: string, oi: number) => `ask_${oi}_${opt}`)
            }
          }
          Row({ space: 6 }) {
            TextInput({ text: this.askQuestionAnswer, placeholder: this.askQuestionPlaceholder || '输入回答...' })
              .layoutWeight(1).height(34).fontSize(12).borderRadius(8).backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => { this.askQuestionAnswer = v; })
            Button('提交').height(34).fontSize(12).borderRadius(8)
              .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
              .onClick(() => this.submitAskUserInput(this.askQuestionAnswer.trim()))
            Button('跳过').height(34).fontSize(12).borderRadius(8)
              .backgroundColor($r('app.color.panel')).fontColor($r('app.color.muted'))
              .onClick(() => this.submitAskUserInput(''))
          }.width('100%')
        }.width('94%').constraintSize({ maxWidth: 800 }).padding(10).borderRadius(12)
          .backgroundColor($r('app.color.surface')).border({ width: 1, color: $r('app.color.accent') })
          .alignItems(HorizontalAlign.Start).margin({ bottom: 6 })
      }

      if (this.pendingApprovalTool) {
        Column({ space: 6 }) {
          Text('工具执行授权请求：' + this.pendingApprovalTool)
            .fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
          Text(this.pendingApprovalArgs).fontFamily('monospace').fontSize(11).fontColor($r('app.color.muted'))
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 6 }) {
            Button('允许一次').height(28).fontSize(12).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
              .onClick(() => this.resolveToolApproval('allow_once'))
            Button('本对话全部允许').height(28).fontSize(12).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
              .onClick(() => this.resolveToolApproval('allow_all'))
            Button('拒绝').height(28).fontSize(12).backgroundColor($r('app.color.panel')).fontColor($r('app.color.warning'))
              .onClick(() => this.resolveToolApproval('deny'))
          }
        }.width('94%').constraintSize({ maxWidth: 800 }).padding(10).borderRadius(12)
          .backgroundColor($r('app.color.surface')).border({ width: 1, color: $r('app.color.accent') })
          .alignItems(HorizontalAlign.Start).margin({ bottom: 6 })
      }

      if (this.notice) { Text(this.notice).width('100%').padding({ left: 18, right: 18, bottom: 6 }).fontSize(13).fontColor($r('app.color.warning')) }

      if (ImmersiveMaterialStyle.isActive(this.immersiveLightOn())) {
        Column({ space: 6 }) {
          this.composerCardContent()
        }
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(24)
        .backgroundColor(Color.Transparent)
        .width('94%')
        .constraintSize({ maxWidth: 800 })
        .alignItems(HorizontalAlign.Start)
        .systemMaterial(ImmersiveMaterialStyle.composerMaterial(this.themeTokens(), this.effectiveDark(), true))
      } else {
        Column({ space: 6 }) {
          this.composerCardContent()
        }
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(24)
        .backgroundColor(this.composerBgColor())
        .backgroundBlurStyle(this.immersiveLightOn() || this.appearanceCfg().bubbleStyle === 'frosted'
          ? BlurStyle.COMPONENT_THICK
          : BlurStyle.NONE)
        .border({ width: 1, color: $r('app.color.line') })
        .width('94%')
        .constraintSize({ maxWidth: 800 })
        .alignItems(HorizontalAlign.Start)
        .systemMaterial(ImmersiveMaterialStyle.composerMaterial(this.themeTokens(), this.effectiveDark(), false))
      }
    }
    .width('100%')
    .clip(false)
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: this.wide ? 0 : this.winLeftInset,
      right: this.sidePanelMode !== '' && this.wideSide ? 0 : this.winRightInset,
      top: 10,
      bottom: this.winKeyboardHeight > 0 ? 8 : Math.max(12, this.effectiveBottomInset() + 8)
    })
    .linearGradient(this.immersiveLightOn()
      ? {
          direction: GradientDirection.Top,
          colors: [[hexWithAlpha(this.chatBgColor(), 'B8'), 0.0], [hexWithAlpha(this.chatBgColor(), '00'), 1.0]]
        }
      : undefined)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateComposerBarHeight(Number(newArea.height));
    })
  }

  @Builder
  chatScrollNavButton(symbolRes: Resource, rotate180: boolean, a11yText: string, onTap: () => void) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph(symbolRes)
        .fontSize(17)
        .fontColor([$r('app.color.ink')])
        .rotate({ angle: rotate180 ? 180 : 0 })
    }
    .width(38)
    .height(38)
    .padding(0)
    .accessibilityText(a11yText)
    .backgroundColor(hexWithAlpha(this.themeTokens().surface, this.effectiveDark() ? 'E0' : 'E8'))
    .border({ width: 0.8, color: $r('app.color.line') })
    .shadow({
      radius: 10,
      color: this.effectiveDark() ? '#40000000' : '#18000000',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => { onTap(); })
  }

  @Builder
  chatScrollNavButtons() {
    Column({ space: 8 }) {
      this.chatScrollNavButton($r('sys.symbol.chevron_up_2'), false, '跳转到顶部对话', () => { this.jumpChatTop(); })
      this.chatScrollNavButton($r('sys.symbol.chevron_up'), false, '跳转到上一条对话', () => { this.jumpChatPrev(); })
      this.chatScrollNavButton($r('sys.symbol.chevron_down'), false, '跳转到下一条对话', () => { this.jumpChatNext(); })
      this.chatScrollNavButton($r('sys.symbol.chevron_up_2'), true, '跳转到最新对话', () => { this.jumpChatBottom(); })
    }
    .margin({
      left: this.chatScrollNavSide === 'left' ? ((this.wide ? 0 : this.winLeftInset) + 12) : 0,
      right: this.chatScrollNavSide === 'right' ? ((this.sidePanelMode !== '' && this.wideSide ? 0 : this.winRightInset) + 12) : 0,
      bottom: this.composerBarHeightVp + 4
    })
    .transition(
      this.chatScrollNavSide === 'left'
        ? SystemMotion.startSlideTransition(this.reduceMotion)
        : SystemMotion.endSlideTransition(this.reduceMotion)
    )
  }

  @Builder
  chatPane() {
    Stack({
      alignContent: this.chatScrollNavSide === 'left' ? Alignment.BottomStart : Alignment.BottomEnd
    }) {
      WithTheme({ theme: ImmersiveMaterialStyle.pageTheme(this.chatBgColor()) }) {
        Tabs({ barPosition: BarPosition.End }) {
          TabContent() {
            Navigation() {
              Column() {
          if (this.inChatSearchOpen) {
            Row({ space: 6 }) {
              TextInput({ text: this.inChatQuery, placeholder: '在当前对话中查找…' }).layoutWeight(1)
                .onChange((v: string) => { this.inChatQuery = v; this.inChatMatchPos = 0; })
              Text(this.matchingMessageIndices().length ? ((this.inChatMatchPos + 1) + '/' + this.matchingMessageIndices().length) : '0')
                .fontSize(12).fontColor($r('app.color.muted'))
              Button('↑').height(32).fontSize(12).backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
                .onClick(() => this.jumpToInChatMatch(-1))
              Button('↓').height(32).fontSize(12).backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
                .onClick(() => this.jumpToInChatMatch(1))
              Button('×').height(32).fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
                .onClick(() => {
                  SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
                    this.inChatSearchOpen = false;
                    this.inChatQuery = '';
                  });
                })
            }.width('100%').padding({ left: 16, right: 16, bottom: 8 })
              .transition(SystemMotion.inlineBarTransition(this.reduceMotion))
          }

          if (this.multiSelectMode) {
            Row({ space: 8 }) {
              Text('已选 ' + this.selectedMsgIds.length + ' 条').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              Button('导出 MD').height(30).fontSize(12).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                .onClick(() => this.exportSelection(true))
              Button('导出文本').height(30).fontSize(12).backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
                .onClick(() => this.exportSelection(false))
              Button('取消').height(30).fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
                .onClick(() => {
                  SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
                    this.multiSelectMode = false;
                    this.selectedMsgIds = [];
                  });
                })
            }.width('100%').padding({ left: 16, right: 16, bottom: 6 }).backgroundColor($r('app.color.panel'))
              .transition(SystemMotion.inlineBarTransition(this.reduceMotion))
          }

          if (this.isIncognitoEmpty()) {
            Column({ space: 10 }) {
              Stack() {
                Image($r('app.media.icon_temp_chat_checked'))
                  .width(30)
                  .height(30)
                  .objectFit(ImageFit.Contain)
                  .fillColor($r('app.color.accent'))
              }
              .width(64)
              .height(64)
              .borderRadius(32)
              .backgroundColor($r('app.color.tint'))
              .alignContent(Alignment.Center)

              Text('临时对话')
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
              Text('聊天记录不会保存到历史列表，离开后自动清除')
                .fontSize(13)
                .fontColor($r('app.color.muted'))
                .textAlign(TextAlign.Center)
                .padding({ left: 28, right: 28 })
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ bottom: this.composerBarHeightVp })
            .justifyContent(FlexAlign.Center)
          } else if (this.showProviderHintBanner()) {
            Column({ space: 12 }) {
              Column({ space: 10 }) {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                    .fontSize(18)
                    .fontColor([$r('app.color.accent')])
                  Text('尚未配置模型 API Key')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.ink'))
                }
                Text('添加模型服务商密钥后即可开始对话，或使用本地 Ollama 服务。')
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                Row({ space: 8 }) {
                  Button('配置服务商')
                    .id('openProviders')
                    .height(34)
                    .fontSize(13)
                    .borderRadius(17)
                    .padding({ left: 14, right: 14 })
                    .backgroundColor($r('app.color.accent'))
                    .fontColor($r('app.color.on_accent'))
                    .onClick(() => {
                      this.providerOpenProxy = false;
                      this.navigateTo('providers');
                    })
                  Button('选择模型')
                    .height(34)
                    .fontSize(13)
                    .borderRadius(17)
                    .padding({ left: 14, right: 14 })
                    .backgroundColor($r('app.color.panel'))
                    .fontColor($r('app.color.ink'))
                    .onClick(() => { this.showModelQuickSheet = true; })
                }
              }
              .width('86%')
              .constraintSize({ maxWidth: 360 })
              .padding(16)
              .borderRadius(16)
              .backgroundColor($r('app.color.surface'))
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ bottom: this.composerBarHeightVp })
            .justifyContent(FlexAlign.Center)
          } else if (!this.activeChat() && !this.working) {
            Blank().layoutWeight(1)
          } else {
            List({
              scroller: this.scrollView,
              space: 16,
              initialIndex: Math.max(0, (this.activeChat()?.messages.length || 1) - 1)
            }) {
              ForEach(this.activeChat()?.messages || [], (msg: ChatMessage, msgIdx: number) => {
                ListItem() { this.messageRow(msg, msgIdx) }
              }, (msg: ChatMessage) => this.messageRowKey(msg))
              if (this.working && !this.regeneratingMsgId) {
                ListItem() {
                  Column({ space: 8 }) {
                    if (this.chatDisplayCfg().showModelIcon || this.chatDisplayCfg().showModelName) {
                      Row({ space: 8 }) {
                        if (this.chatDisplayCfg().showModelIcon) {
                          KelivoAvatarBadge({
                            brandId: this.persona().useAssistantAvatar
                              ? ''
                              : this.activeBrandId(),
                            avatarText: this.persona().useAssistantAvatar ? (this.persona().avatar || '') : '',
                            fallbackLetter: this.persona().useAssistantName ? this.persona().name : (this.activeModelId() || this.provider().name),
                            badgeSize: 22
                          })
                        }
                        if (this.chatDisplayCfg().showModelName) {
                          Text(this.persona().useAssistantName ? this.persona().name : (this.activeModelId() || this.provider().name))
                            .fontSize(12)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.ink'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                      }.alignItems(VerticalAlign.Center).width('100%')
                    }
                    this.liveStreamBody()
                  }.width('100%').alignItems(HorizontalAlign.Start)
                }
              } else if (this.lastSendError && this.lastSendErrorChatId === (this.activeChat()?.id || '')) {
                ListItem() {
                  Column({ space: 8 }) {
                    Row({ space: 6 }) {
                      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                        .fontSize(15)
                        .fontColor([$r('app.color.warning')])
                      Text('请求未成功')
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.warning'))
                        .layoutWeight(1)
                    }.width('100%')
                    Text(this.lastSendError)
                      .fontSize(13)
                      .lineHeight(19)
                      .fontColor($r('app.color.ink'))
                      .copyOption(CopyOptions.LocalDevice)
                    Row({ space: 8 }) {
                      Button('重试')
                        .type(ButtonType.Normal)
                        .height(30)
                        .fontSize(12)
                        .borderRadius(15)
                        .padding({ left: 14, right: 14 })
                        .backgroundColor($r('app.color.accent'))
                        .fontColor($r('app.color.on_accent'))
                        .onClick(() => { this.send(true); })
                      Button('查看日志')
                        .type(ButtonType.Normal)
                        .height(30)
                        .fontSize(12)
                        .borderRadius(15)
                        .padding({ left: 12, right: 12 })
                        .backgroundColor($r('app.color.panel'))
                        .fontColor($r('app.color.ink'))
                        .onClick(() => {
                          this.diagTabInit = 0;
                          this.refreshLogsAndStats().catch(() => {});
                          this.navigateTo('diagnostics');
                        })
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(14)
                  .backgroundColor($r('app.color.surface'))
                  .border({ width: 1, color: $r('app.color.line') })
                  .alignItems(HorizontalAlign.Start)
                }
              } else if (this.activeChat()?.messages.length && this.activeChat()?.suggestions?.length) {
                ListItem() {
                  Column({ space: 8 }) {
                    if (this.activeChat()?.suggestions?.length) {
                      Flex({ wrap: FlexWrap.Wrap }) {
                        ForEach(this.activeChat()?.suggestions || [], (sug: string, si: number) => {
                          Button(sug).height(28).fontSize(12).margin({ right: 6, bottom: 6 })
                            .backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                            .onClick(() => {
                              this.draft = sug;
                              if (!this.appearanceCfg().insertSuggestionOnly) {
                                this.send();
                              }
                            })
                        }, (sug: string, si: number) => 'sug-' + si + '-' + sug)
                      }
                    }
                  }.alignItems(HorizontalAlign.Start)
                }
              }
            }
            .padding({ left: 18, right: 18 })
            .contentStartOffset(this.chatCanScrollUnderTitle() ? this.chatTitleBarHeight() + 6 : 8)
            .contentEndOffset(this.composerBarHeightVp + 10)
            .width('100%')
            .constraintSize({ maxWidth: 820 })
            .layoutWeight(1)
            .onAppear(() => { this.scrollDown(true); })
            .onScrollIndex((start: number, end: number, _center: number) => {
              this.chatFirstVisibleIdx = start;
              this.chatLastVisibleIdx = end;
            })
            .onWillScroll((offset: number, state: ScrollState) => {
              if (state === ScrollState.Scroll) {
                if (offset < 0) {
                  this.followBottom = false;
                }
                if (Math.abs(offset) > 0.5) {
                  this.chatNavTargetIdx = -1;
                  this.showChatScrollNav();
                }
              } else if (state === ScrollState.Fling && this.chatScrollNavVisible) {
                this.scheduleChatScrollNavHide();
              }
            })
            .onReachEnd(() => { this.followBottom = true; })
          }
        }
        .width('100%')
        .height('100%')
        .padding({
          top: this.chatCanScrollUnderTitle() ? 0 : this.chatTitleBarHeight(),
          left: this.wide ? 0 : this.winLeftInset,
          right: this.sidePanelMode !== '' && this.wideSide ? 0 : this.winRightInset
        })
        .backgroundColor(this.chatBgColor())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .hideToolBar(true)
      .title(
        { builder: () => this.chatTitleBar(), height: this.chatTitleBarHeight() },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), this.chatCanScrollUnderTitle())
      )
      .backgroundColor(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
          }
          .tabBar(this.composerTabBar())
          .width('100%')
          .height('100%')
        }
        .vertical(false)
        .barPosition(BarPosition.End)
        .barOverlap(true)
        .barBackgroundColor(Color.Transparent)
        .barBackgroundBlurStyle(BlurStyle.NONE)
        .barHeight('auto', true)
        .divider(null)
        .scrollable(false)
        .animationDuration(0)
        .backgroundColor(Color.Transparent)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .width('100%')
        .height('100%')
      }

      if (this.chatScrollNavVisible && (this.activeChat()?.messages.length || 0) > 0 && !this.isIncognitoEmpty() && !this.showProviderHintBanner()) {
        this.chatScrollNavButtons()
      }
    }
    .backgroundColor(this.chatBgColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  modelQuickOverlay() {
    Column() {
      ModelSelectSheet({
        providers: this.workspace.providers,
        currentProviderId: this.provider().id,
        currentModelId: this.activeModelId(),
        favoriteModels: this.workspace.favoriteModels || [],
        immersiveLightEnabled: this.immersiveLightOn(),
        onSelectModel: (providerId: string, modelId: string) => {
          this.selectModelQuick(providerId, modelId);
        },
        onToggleFavorite: (providerId: string, modelId: string) => {
          this.toggleFavoriteModel(providerId, modelId);
        },
        onOpenProviders: () => {
          this.showModelQuickSheet = false;
          this.providerOpenProxy = false;
          this.navigateTo('providers');
        }
      })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  bottomToolsOverlay() {
    Column() {
      BottomToolsSheet({
        imageGenMode: this.imageGenMode,
        immersiveLightEnabled: this.immersiveLightOn(),
        enabledSkillCount: (this.workspace.skills || []).filter((s: SkillRecord): boolean => s.enabled).length,
        totalSkillCount: (this.workspace.skills || []).length,
        activeInstructionCount: (this.workspace.activeInstructionIds || []).length,
        activeWorldBookCount: (this.workspace.worldBooks || []).filter((b: WorldBook): boolean => b.enabled).length,
        hasMessages: (this.activeChat()?.messages.length || 0) > 0,
        onTakePhoto: () => {
          this.showBottomToolsSheet = false;
          this.takePhoto().catch(() => {});
        },
        onPickPhotos: () => {
          this.showBottomToolsSheet = false;
          this.pickPhotos().catch(() => {});
        },
        onUploadFile: () => {
          this.showBottomToolsSheet = false;
          this.attach().catch(() => {});
        },
        onOpenBrowser: () => {
          this.showBottomToolsSheet = false;
          this.navigateTo('browser');
        },
        onOpenSkills: () => {
          this.showBottomToolsSheet = false;
          this.navigateTo('skills');
        },
        onOpenInstructionCards: () => {
          this.showBottomToolsSheet = false;
          this.promptTabInit = 1;
          this.navigateTo('promptTools');
        },
        onOpenWorldBook: () => {
          this.showBottomToolsSheet = false;
          this.promptTabInit = 0;
          this.navigateTo('promptTools');
        },
        onOpenQuickPhrases: () => {
          this.showBottomToolsSheet = false;
          this.promptTabInit = 2;
          this.navigateTo('promptTools');
        },
        onToggleImageGen: (enabled: boolean) => {
          this.imageGenMode = enabled;
          if (this.activeChat()) {
            this.activeChat()!.imageGenMode = enabled;
            this.persistAction();
          }
        },
        onOpenContext: () => {
          this.showBottomToolsSheet = false;
          this.navigateTo('context');
        },
        onClearContext: () => {
          this.resetChatContextWindow();
        }
      })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  searchQuickOverlay() {
    Column() {
      SearchQuickSheet({
        searchOn: this.searchOn,
        searchServices: this.workspace.searchServices || defaultSearchServices(),
        activeSearchId: this.workspace.activeSearchId || '',
        immersiveLightEnabled: this.immersiveLightOn(),
        onToggleSearch: (enabled: boolean) => {
          this.setSearchEnabled(enabled);
        },
        onSelectSearchService: (id: string) => {
          this.selectSearchServiceQuick(id);
        },
        onOpenSearchSettings: () => {
          this.showSearchQuickSheet = false;
          this.navigateTo('search');
        }
      })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  reasoningQuickOverlay() {
    Column() {
      ReasoningLevelSheet({
        currentEffort: this.effectiveParams().reasoningEffort || 'off',
        budgetTokens: this.effectiveParams().reasoningBudget || 8192,
        immersiveLightEnabled: this.immersiveLightOn(),
        onSelectEffort: (effort: ReasoningEffort) => {
          this.updateReasoningConfig(effort);
        },
        onChangeBudget: (tokens: number) => {
          this.updateReasoningConfig(this.effectiveParams().reasoningEffort || 'off', tokens);
        }
      })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  chatToolsOverlay() {
    Column() {
      ChatToolsSheet({
        mcpServers: this.workspace.mcpServers || [],
        enabledMcpIds: this.activeEnabledMcpIds(),
        workspaces: this.workspace.workspaces || [],
        activeWorkspaceId: this.activeWorkspaceForChat()?.id || '',
        enabledDeviceTools: this.enabledDeviceToolsList(),
        permissionMode: this.fullAccessMode ? 'full' : 'ask',
        immersiveLightEnabled: this.immersiveLightOn(),
        onToggleMcp: (id: string, on: boolean) => {
          this.toggleChatMcp(id, on);
        },
        onToggleDeviceTool: (id: string, on: boolean) => {
          this.toggleQuickDeviceTool(id, on);
        },
        onSelectWorkspace: (id: string) => {
          this.selectChatWorkspace(id);
        },
        onToggleFullAccess: (full: boolean) => {
          this.setChatFullAccess(full);
        },
        onOpenMoreTools: () => {
          this.showChatToolsSheet = false;
          this.navigateTo('tools');
        }
      })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  sheetActionRow(
    symbol: Resource,
    label: string,
    isDanger: boolean,
    idStr: string,
    action: () => void
  ) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 16 }) {
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor([isDanger ? $r('app.color.warning') : $r('app.color.ink')])
        Text(label)
          .fontSize(16)
          .fontColor(isDanger ? $r('app.color.warning') : $r('app.color.ink'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .id(idStr)
    .width('100%')
    .height(52)
    .padding({ left: 22, right: 22 })
    .backgroundColor(Color.Transparent)
    .onClick(action)
  }

  @Builder
  messageActionSheetOverlay() {
    Column({ space: 2 }) {
      if (this.actionSheetTargetMessage()) {
        this.sheetActionRow($r('sys.symbol.textformat'), '选择复制', false, 'sheetSelectCopy', () => {
          this.runMessageSheetAction('select_copy');
        })
        this.sheetActionRow($r('sys.symbol.book'), '网页视图渲染', false, 'sheetWebRender', () => {
          this.runMessageSheetAction('web_render');
        })
        if (this.isActionSheetTargetAssistant()) {
          this.sheetActionRow($r('sys.symbol.pencil_line'), '编辑', false, 'sheetEdit', () => {
            this.runMessageSheetAction('edit');
          })
        }
        this.sheetActionRow($r('sys.symbol.share'), '分享', false, 'sheetShare', () => {
          this.runMessageSheetAction('share');
        })
        this.sheetActionRow($r('sys.symbol.checkmark_square'), '选择消息', false, 'sheetSelectMessages', () => {
          this.runMessageSheetAction('select_messages');
        })
        this.sheetActionRow($r('sys.symbol.arrow_triangle_divide'), '创建分支', false, 'sheetFork', () => {
          this.runMessageSheetAction('fork');
        })
        this.sheetActionRow($r('sys.symbol.trash'), '删除本版本', true, 'sheetDeleteVersion', () => {
          this.runMessageSheetAction('delete_version');
        })
        if (this.actionSheetTargetHasMultiVersions()) {
          this.sheetActionRow($r('sys.symbol.trash'), '删除全部版本', true, 'sheetDeleteAll', () => {
            this.runMessageSheetAction('delete_all');
          })
        }
      }
    }
    .width('100%')
    .padding({ top: 6, bottom: Math.max(16, this.effectiveBottomInset() + 8) })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  miniMapOverlay() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.map'))
          .fontSize(17)
          .fontColor([$r('app.color.accent')])
        Text('共 ' + (this.activeChat()?.messages.length || 0) + ' 条消息 · 点击跳转')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .layoutWeight(1)
        if ((this.activeChat()?.messages.length || 0) > 1) {
          Button('顶部')
            .type(ButtonType.Normal)
            .height(26)
            .fontSize(11)
            .padding({ left: 10, right: 10 })
            .borderRadius(13)
            .backgroundColor($r('app.color.tint'))
            .fontColor($r('app.color.accent'))
            .onClick(() => {
              this.showMiniMap = false;
              this.jumpChatTop();
            })
          Button('最新')
            .type(ButtonType.Normal)
            .height(26)
            .fontSize(11)
            .padding({ left: 10, right: 10 })
            .borderRadius(13)
            .backgroundColor($r('app.color.tint'))
            .fontColor($r('app.color.accent'))
            .onClick(() => {
              this.showMiniMap = false;
              this.jumpChatBottom();
            })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(14)
      .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightOn()))

      if ((this.activeChat()?.messages.length || 0) === 0) {
        Column({ space: 6 }) {
          Text('当前对话暂无消息')
            .fontSize(14)
            .fontColor($r('app.color.muted'))
        }
        .width('100%')
        .padding({ top: 24, bottom: 24 })
        .alignItems(HorizontalAlign.Center)
        .borderRadius(14)
        .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightOn()))
      } else {
        Scroll() {
          Column({ space: 6 }) {
            ForEach(this.activeChat()?.messages || [], (m: ChatMessage, idx: number) => {
              Row({ space: 10 }) {
                Text('#' + (idx + 1) + (m.role === 'user' ? ' 问' : ' 答'))
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(m.role === 'user' ? $r('app.color.accent') : $r('app.color.muted'))
                  .width(54)
                Text(m.text.replace(/\s+/g, ' ').slice(0, 80) || '[空/附件]')
                  .fontSize(13)
                  .fontColor($r('app.color.ink'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .borderRadius(12)
              .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightOn()))
              .onClick(() => {
                this.showMiniMap = false;
                const total = this.activeChat()?.messages.length || 0;
                this.followBottom = idx >= total - 1;
                this.chatNavTargetIdx = idx;
                this.scrollView.scrollToIndex(idx, !this.reduceMotion, ScrollAlign.START);
              })
            }, (m: ChatMessage, idx: number) => 'mm-' + idx + '-' + m.id)
          }
          .width('100%')
          .padding({ top: 2, bottom: 4 })
        }
        .constraintSize({ maxHeight: 380 })
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 20 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  editMessageOverlay() {
    Column({ space: 12 }) {
      Row() {
        Button('取消').backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
          .onClick(() => {
            SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
              this.editingMsgId = '';
            });
          })
        Text('编辑消息').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink')).layoutWeight(1)
        Button('仅保存').height(32).fontSize(12).backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
          .onClick(() => this.saveEditedMessage(false))
        Button('保存并重发').height(32).fontSize(12).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
          .margin({ left: 6 }).onClick(() => this.saveEditedMessage(true))
      }.width('100%').padding(12)
      TextArea({ text: this.editingMsgText }).layoutWeight(1).width('94%').fontSize(15)
        .onChange((v: string) => { this.editingMsgText = v; })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.winTopInset, bottom: Math.max(16, this.effectiveBottomInset() + 8), left: this.winLeftInset, right: this.winRightInset })
    .backgroundColor(this.themeTokens().canvas)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .transition(SystemMotion.overlayModalTransition(this.reduceMotion))
  }

  @Builder
  selectCopyOverlay() {
    Column({ space: 12 }) {
      Row() {
        Text('自由选词复制').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink')).layoutWeight(1)
        Button('全部复制').height(32).fontSize(12).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
          .onClick(() => { this.copyText(this.selectCopyText); })
        Button('关闭').backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
          .onClick(() => {
            SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
              this.selectCopyText = '';
            });
          })
      }.width('100%').padding(12)
      TextArea({ text: this.selectCopyText }).layoutWeight(1).width('94%').fontSize(15)
        .onChange((_v: string) => {})
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.winTopInset, bottom: Math.max(16, this.effectiveBottomInset() + 8), left: this.winLeftInset, right: this.winRightInset })
    .backgroundColor(this.themeTokens().canvas)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .transition(SystemMotion.overlayModalTransition(this.reduceMotion))
  }

  @Builder
  navSubHeader(titleText: string, subtitleText: string = '') {
    KelivoNavTitleBar({
      titleText: titleText,
      subtitleText: subtitleText,
      showBack: true,
      onBack: () => { this.navigateBack(); }
    })
  }

  @Builder
  appearanceNavPage(subView: string, titleText: string) {
    NavDestination() {
      Column() {
        AppearancePanel({
          appearance: this.appearanceCfg(),
          systemSettings: this.workspace.systemSettings || defaultSystemSettings(),
          generationParams: this.workspace.generationParams || defaultGenerationParams(),
          embeddedInNav: true,
          initialSubView: subView,
          onChangeAppearance: async (cfg: AppearanceConfig) => {
            this.workspace.appearance = cfg;
            applySystemColorMode(this.host(), cfg.themeMode);
            syncWindowSystemBars(resolveEffectiveDark(cfg.themeMode, this.systemDarkNow()));
            syncWindowBackgroundColor(this.themeTokens().canvas);
            this.syncImmersiveStorage();
            await this.persist();
          },
          onUpdateSettings: async (next: SystemSettings) => {
            this.workspace.systemSettings = next;
            await this.persist();
          },
          onUpdateGenerationParams: async (next: GenerationParams) => {
            this.workspace.generationParams = next;
            await this.persist();
          },
          onRequestNotifyPermission: async () => {
            await ensureNotificationPermission(this.host());
          },
          onOpenSubView: (sub: string) => {
            this.navigateTo(`appearance_${sub}`);
          },
          onClose: () => { this.navigateBack(); }
        })
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.winLeftInset, right: this.winRightInset })
      .backgroundColor(Color.Transparent)
    }
    .hideBackButton(true)
    .backgroundColor(this.themeTokens().canvas)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .title(
      { builder: () => { this.navSubHeader(titleText); }, height: 56 + this.winTopInset },
      ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), true)
    )
    .systemTransition(SystemMotion.navTransition(this.reduceMotion))
    .onShown(() => { this.syncActiveRouteFromStack(); })
    .onHidden(() => { this.syncActiveRouteFromStack(); })
    .onBackPressed(() => this.dismissTopOverlay())
  }

  @Builder
  routeDestination(name: string, _param: Object) {
    if (name === 'providers') {
      ProviderEditor({
        providers: this.workspace.providers,
        activeId: this.workspace.activeProvider,
        initialViewMode: this.providerOpenProxy ? 'detail' : 'list',
        initialTab: this.providerOpenProxy ? 2 : 0,
        modelDefaults: this.workspace.modelDefaults || {
          chatProviderId: '', chatModelId: '', titleProviderId: '', titleModelId: '',
          translateProviderId: '', translateModelId: '', ocrProviderId: '', ocrModelId: '',
          memoryProviderId: '', memoryModelId: ''
        },
        onApply: (p: Provider, key: string, reuse: boolean, setActive: boolean) => this.applyProvider(p, key, reuse, setActive),
        onImportProviders: (items: ImportedProvider[]) => this.importProviders(items),
        onDeleteProvider: (id: string) => this.deleteProvider(id),
        onStartOAuth: (kind: OAuthProviderKind) => {
          this.oauthKind = kind;
          SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
            this.oauthModalVisible = true;
          });
        },
        onDismissOverlay: () => this.dismissTopOverlay(),
        onClose: () => { this.navigateBack(); }
      })
    } else if (name === 'context') {
      ContextSheet({
        chat: this.activeChat(),
        providers: this.workspace.providers,
        activeProviderId: this.workspace.activeProvider,
        systemPrompt: this.persona().prompt,
        params: this.effectiveParams(),
        sysSettings: this.workspace.systemSettings || defaultSystemSettings(),
        onSaveParams: (p: GenerationParams, autoCompact: boolean, threshold: number, template: string) => {
          this.workspace.generationParams = p;
          const sys = this.workspace.systemSettings || defaultSystemSettings();
          sys.autoCompactEnabled = autoCompact;
          sys.autoCompactThreshold = threshold;
          sys.compressionTemplate = template;
          this.workspace.systemSettings = sys;
          this.persistAction();
        },
        onSaveChatOverrides: (provId: string, modelId: string, prompt: string, startIdx: number) => {
          const c = this.activeChat();
          if (c) {
            c.overrideProviderId = provId || undefined;
            c.overrideModel = modelId || undefined;
            c.overridePrompt = prompt || undefined;
            c.contextStartIndex = startIdx;
            this.workspace.conversations = this.workspace.conversations.slice();
            if (!c.ephemeral) this.persistAction();
          }
        },
        onCompressInPlace: (template: string) => this.compressInPlace(template),
        onUndoCompress: () => this.undoCompression(),
        onCompressToNewChat: (template: string) => this.compressToNewChat(template),
        onDismissOverlay: () => this.dismissTopOverlay(),
        onClose: () => { this.navigateBack(); }
      })
    } else if (name === 'personas') {
      PersonaEditor({
        personas: this.workspace.personas,
        activeId: this.persona().id,
        initialEditId: this.personaEditTargetId,
        providers: this.workspace.providers,
        worldBooks: this.workspace.worldBooks || [],
        mcpServers: this.workspace.mcpServers || [],
        skills: this.workspace.skills || defaultBuiltinSkills(),
        localWorkspaces: this.workspace.workspaces || [],
        memories: this.workspace.memories || [],
        memorySettings: normalizeMemorySettings(this.workspace.memorySettings),
        organizingMemoryAssistantId: this.organizingMemoryAssistantId,
        memoryTraces: this.workspace.memoryTraces || [],
        onSavePersona: (p: Persona, setActive: boolean) => this.savePersona(p, setActive),
        onDeletePersona: (id: string) => this.deletePersonaById(id),
        onApply: (p: Persona) => this.applyPersona(p),
        onSaveMemories: async (entries: MemoryEntry[]) => {
          this.workspace.memories = entries;
          await this.persist();
        },
        onOrganizeMemory: (asstId: string) => this.organizeMemoryForAssistant(asstId),
        onOpenMemorySettings: () => { this.navigateTo('memory'); },
        onDismissOverlay: () => this.dismissTopOverlay(),
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onClose: () => { this.navigateBack(); }
      })
    } else if (name === 'tools') {
      NavDestination() {
        Column() {
          ToolsPanel({
            lastEndpoint: this.workspace.mcpEndpoint || '',
            servers: this.workspace.mcpServers || [],
            builtinFetchEnabled: this.workspace.systemSettings?.builtinFetchEnabled !== false,
            mcpManager: this.mcpManager,
            embeddedInNav: true,
            onRemember: (endpoint: string) => { this.workspace.mcpEndpoint = endpoint; this.persistAction(); },
            onSaveServers: (srvs: McpServerConfig[], bFetch: boolean) => {
              this.workspace.mcpServers = srvs;
              const sys = this.workspace.systemSettings || defaultSystemSettings();
              sys.builtinFetchEnabled = bFetch;
              this.workspace.systemSettings = sys;
              this.persistAction();
            },
            onUseResult: (resName: string, text: string) => {
              this.attachedList = [...this.attachedList, { name: resName + '.txt', data: text, mime: 'text/plain', kind: 'text' }];
              this.navigateTo('chat');
            },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('MCP 工具中心'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), true)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'voice') {
      NavDestination() {
        Column() {
          VoiceSettingsPanel({
            tts: this.workspace.tts || { engine: 'system', endpoint: '', secretRef: '', model: 'tts-1', voice: 'alloy', speed: 1.0, language: 'zh-CN' },
            asr: this.workspace.asr || { engine: 'system', endpoint: '', secretRef: '', model: 'whisper-1', language: 'zh-CN' },
            embeddedInNav: true,
            onSave: (tts: TtsConfig, asr: AsrConfig) => {
              this.workspace.tts = tts;
              this.workspace.asr = asr;
              this.persistAction();
            },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('语音朗读与识别'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), true)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'webdav') {
      NavDestination() {
        Column() {
          WebDavPanel({
            initialDirectory: this.workspace.davDirectory || '',
            initialPath: this.workspace.davPath || 'kelivo_backups',
            initialUsername: this.workspace.davUsername || '',
            initialPassRef: this.workspace.davPasswordRef || '',
            initialUserAgent: this.workspace.davUserAgent || '',
            initialFile: this.workspace.davFilename || '',
            conversations: this.workspace.conversations,
            workspaceData: this.workspace,
            embeddedInNav: true,
            onWorkspaceRestored: async (nextWs: Workspace) => {
              this.workspace = nextWs;
              this.searchOn = this.workspace.systemSettings?.searchEnabled === true;
              applySystemColorMode(this.host(), this.appearanceCfg().themeMode);
              syncWindowSystemBars(this.effectiveDark());
              syncWindowBackgroundColor(this.themeTokens().canvas);
              this.syncImmersiveStorage();
              await this.persist();
              await this.refreshStorageSize().catch(() => {});
              this.scrollDown(true);
            },
            onSaveBackupConfig: (cfg: BackupPreferencesConfig) => {
              this.workspace.backupConfig = cfg;
              if (this.workspace.systemSettings) {
                this.workspace.systemSettings.autoSnapshotEnabled = cfg.localCopiesEnabled;
              }
              this.persistAction();
            },
            onSaveWebDavConfig: (url: string, path: string, user: string, passRef: string, userAgent: string) => {
              this.workspace.davDirectory = url;
              this.workspace.davPath = path;
              this.workspace.davUsername = user;
              this.workspace.davPasswordRef = passRef;
              this.workspace.davUserAgent = userAgent;
              this.persistAction();
            },
            onSaveS3Config: (s3: S3BackupConfig) => {
              this.workspace.s3Config = s3;
              this.persistAction();
            },
            onUpdateSnapshots: (list: LocalSnapshotMeta[]) => {
              this.workspace.snapshots = list;
              this.persistAction();
              this.refreshStorageSize().catch(() => {});
            },
            onOpenUrl: (url: string) => { this.openUrlInBrowser(url); },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('备份与恢复'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), true)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'search') {
      NavDestination() {
        Column() {
          SearchEditor({
            config: this.workspace.search || { kind: 'searxng', endpoint: '', secretRef: '' },
            services: this.workspace.searchServices || defaultSearchServices(),
            activeServiceId: this.workspace.activeSearchId || 'search-duckduckgo',
            embeddedInNav: true,
            onApply: (config: SearchConfig, key: string) => this.applySearch(config, key),
            onSaveServices: (svcs: SearchServiceConfig[], actId: string, enable: boolean) => {
              this.workspace.searchServices = svcs;
              this.workspace.activeSearchId = actId;
              this.setSearchEnabled(enable);
            },
            onDisable: () => { this.setSearchEnabled(false); },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('联网搜索', '26 种搜索引擎 · Agent 工具 / 预检索'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), true)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'settings') {
      SettingsPanel({
        systemSettings: this.workspace.systemSettings || defaultSystemSettings(),
        appearance: this.appearanceCfg(),
        language: this.appearanceCfg().language,
        immersiveLightEnabled: this.immersiveLightOn(),
        hasAnyKey: this.hasAnyConfiguredKey(),
        storageText: this.storageSizeLabel || '计算中...',
        onChangeThemeMode: async (mode: 'system' | 'light' | 'dark') => {
          const cfg = this.appearanceCfg();
          const next: AppearanceConfig = {
            themeMode: mode,
            paletteId: cfg.paletteId,
            customThemeJson: cfg.customThemeJson,
            bubbleStyle: cfg.bubbleStyle,
            bubbleRadius: cfg.bubbleRadius,
            bubbleBlur: cfg.bubbleBlur,
            wallpaperKind: cfg.wallpaperKind,
            wallpaperValue: cfg.wallpaperValue,
            wallpaperOpacity: cfg.wallpaperOpacity,
            fontScale: cfg.fontScale,
            codeFontSize: cfg.codeFontSize,
            language: cfg.language,
            immersiveLightEnabled: cfg.immersiveLightEnabled !== false,
            pureBackground: cfg.pureBackground === true,
            fitAssistantBubble: cfg.fitAssistantBubble === true,
            splitParagraphsIntoBubbles: cfg.splitParagraphsIntoBubbles === true,
            inputBoxOpacity: cfg.inputBoxOpacity ?? 0.88,
            chatItemDisplay: cfg.chatItemDisplay || defaultChatItemDisplay(),
            collapseLongUserChars: cfg.collapseLongUserChars ?? 0,
            enableAssistantMarkdown: cfg.enableAssistantMarkdown !== false,
            enableUserMarkdown: cfg.enableUserMarkdown !== false,
            enableReasoningMarkdown: cfg.enableReasoningMarkdown !== false,
            enableMathLatex: cfg.enableMathLatex !== false,
            autoFollowBottom: cfg.autoFollowBottom !== false,
            insertSuggestionOnly: cfg.insertSuggestionOnly === true,
            enterToSend: cfg.enterToSend === true
          };
          this.workspace.appearance = next;
          applySystemColorMode(this.host(), mode);
          syncWindowSystemBars(resolveEffectiveDark(mode, this.systemDarkNow()));
          syncWindowBackgroundColor(this.themeTokens().canvas);
          this.syncImmersiveStorage();
          await this.persist();
        },
        onNavigateRoute: (route: string) => {
          if (route === 'stats') {
            this.refreshLogsAndStats().catch(() => {});
            this.navigateTo('stats');
          } else if (route === 'diagnostics' || route === 'diagnostics_logs') {
            this.diagTabInit = 0;
            this.refreshLogsAndStats().catch(() => {});
            this.navigateTo('diagnostics');
          } else if (route === 'diagnostics_storage') {
            this.diagTabInit = 2;
            this.refreshLogsAndStats().catch(() => {});
            this.navigateTo('diagnostics');
          } else if (route === 'diagnostics_tools') {
            this.diagTabInit = 3;
            this.refreshLogsAndStats().catch(() => {});
            this.navigateTo('diagnostics');
          } else if (route === 'providers') {
            this.providerOpenProxy = false;
            this.navigateTo('providers');
          } else if (route === 'providers_proxy') {
            this.providerOpenProxy = true;
            this.navigateTo('providers');
          } else if (route === 'quickPhrases') {
            this.promptTabInit = 2;
            this.navigateTo('promptTools');
          } else if (route === 'instructionCards') {
            this.promptTabInit = 1;
            this.navigateTo('promptTools');
          } else if (route === 'promptTools') {
            this.promptTabInit = 0;
            this.navigateTo('promptTools');
          } else if (route === 'display') {
            this.navigateTo('appearance_display');
          } else if (route === 'messageStyle') {
            this.navigateTo('appearance_messageStyle');
          } else if (route === 'theme') {
            this.navigateTo('appearance_theme');
          } else if (route === 'language') {
            this.navigateTo('appearance_language');
          } else if (route === 'appearance') {
            this.navigateTo('appearance');
          } else {
            if (route === 'personas') this.personaEditTargetId = '';
            this.navigateTo(route);
          }
        },
        onOpenUrl: (url: string) => {
          this.openUrlInBrowser(url);
        },
        onDismissOverlay: () => this.dismissTopOverlay(),
        onClose: () => { this.navigateBack(); }
      })
    } else if (name === 'defaultModel') {
      NavDestination() {
        Column() {
          DefaultModelPanel({
            providers: this.workspace.providers,
            modelDefaults: this.workspace.modelDefaults,
            chatSuggestionsEnabled: this.workspace.systemSettings?.chatSuggestionsEnabled === true,
            immersiveLightEnabled: this.immersiveLightOn(),
            embeddedInNav: true,
            onSaveDefaults: async (next: ModelDefaults) => {
              this.workspace.modelDefaults = next;
              await this.persist();
            },
            onToggleChatSuggestions: async (enabled: boolean) => {
              const sys = this.workspace.systemSettings || defaultSystemSettings();
              sys.chatSuggestionsEnabled = enabled;
              this.workspace.systemSettings = sys;
              await this.persist();
            },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('默认模型'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), true)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'about') {
      NavDestination() {
        Column() {
          AboutPanel({
            providerCount: this.workspace.providers.length,
            conversationCount: this.workspace.conversations.length,
            embeddedInNav: true,
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('关于 Kelivo'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), true)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'promptTools') {
      NavDestination() {
        Column() {
          PromptToolsPanel({
            worldBooks: this.workspace.worldBooks || [],
            instructionCards: this.workspace.instructionCards || defaultInstructionCards(),
            activeInstructionIds: this.workspace.activeInstructionIds || [],
            quickPhrases: this.workspace.quickPhrases || defaultQuickPhrases(),
            initialTab: this.promptTabInit,
            embeddedInNav: true,
            onSaveWorldBooks: async (books: WorldBook[]) => {
              this.workspace.worldBooks = books;
              await this.persist();
            },
            onSaveInstructionCards: async (cards: InstructionCard[], activeIds: string[]) => {
              this.workspace.instructionCards = cards;
              this.workspace.activeInstructionIds = activeIds;
              await this.persist();
            },
            onSaveQuickPhrases: async (phrases: QuickPhrase[]) => {
              this.workspace.quickPhrases = phrases;
              await this.persist();
            },
            onInsertPhrase: (content: string) => {
              this.draft = this.draft.trim().length > 0 ? `${this.draft}\n${content}` : content;
            },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('世界书 · 指令卡 · 快捷短语'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), false)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'memory') {
      MemoryPanel({
        memories: this.workspace.memories || [],
        userProfile: this.workspace.userProfile || [],
        memoryTraces: this.workspace.memoryTraces || [],
        memorySettings: normalizeMemorySettings(this.workspace.memorySettings),
        personas: this.workspace.personas,
        providers: this.workspace.providers,
        modelDefaults: this.workspace.modelDefaults || {
          chatProviderId: '',
          chatModelId: '',
          perChatModel: false,
          titleProviderId: '',
          titleModelId: '',
          summaryProviderId: '',
          summaryModelId: '',
          suggestionsProviderId: '',
          suggestionsModelId: '',
          compressProviderId: '',
          compressModelId: '',
          translateProviderId: '',
          translateModelId: '',
          ocrProviderId: '',
          ocrModelId: '',
          memoryProviderId: '',
          memoryModelId: ''
        },
        onSaveMemories: async (entries: MemoryEntry[]) => {
          this.workspace.memories = entries;
          await this.persist();
        },
        onSaveProfile: async (fields: UserProfileField[]) => {
          this.workspace.userProfile = fields;
          await this.persist();
        },
        onSaveSettings: async (cfg: MemorySettings) => {
          this.workspace.memorySettings = cfg;
          await this.persist();
        },
        onSaveModelDefaults: async (next: ModelDefaults) => {
          this.workspace.modelDefaults = next;
          await this.persist();
        },
        onClearTraces: async () => {
          this.workspace.memoryTraces = [];
          await this.persist();
        },
        onDismissOverlay: () => this.dismissTopOverlay(),
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onClose: () => { this.navigateBack(); }
      })
    } else if (name === 'translate') {
      NavDestination() {
        Column() {
          TranslatePanel({
            providers: this.workspace.providers,
            activeProviderId: this.workspace.activeProvider,
            defaultTranslateProviderId: this.workspace.modelDefaults?.translateProviderId || '',
            defaultTranslateModelId: this.workspace.modelDefaults?.translateModelId || '',
            initialText: this.translateInitialText,
            embeddedInNav: true,
            resolveSecret: (ref: string) => readKey(ref),
            onSendToChat: (text: string) => {
              this.draft = text;
            },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('双语划词翻译'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), true)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'stats') {
      NavDestination() {
        Column() {
          StatsPanel({
            usageStats: this.usageStats,
            personas: this.workspace.personas,
            embeddedInNav: true,
            onRefresh: () => this.refreshLogsAndStats(),
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('Token 用量统计与热力图'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), true)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'diagnostics') {
      NavDestination() {
        Column() {
          DiagnosticsPanel({
            requestLogs: this.requestLogs,
            contextLogs: this.contextLogs,
            toolCandidates: this.buildToolSchemaCandidates(),
            toolOverrides: this.workspace.toolOverrides || [],
            filesDir: this.filesDirPath,
            dbDir: this.dbDirPath,
            embeddedInNav: true,
            initialTab: this.diagTabInit,
            onRefreshLogs: () => this.refreshLogsAndStats(),
            onClearRequestLogs: async () => {
              if (this.store) await this.store.clearRequestLogs();
              await this.refreshLogsAndStats();
            },
            onClearContextLogs: async () => {
              if (this.store) await this.store.clearContextLogs();
              await this.refreshLogsAndStats();
            },
            onSaveToolOverrides: async (overrides: ToolSchemaOverride[]) => {
              this.workspace.toolOverrides = overrides;
              await this.persist();
            },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('调试诊断与存储分析'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), false)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'appearance') {
      this.appearanceNavPage('', '偏好设置')
    } else if (name === 'appearance_theme') {
      this.appearanceNavPage('theme', '主题与外观')
    } else if (name === 'appearance_messageStyle') {
      this.appearanceNavPage('messageStyle', '消息样式')
    } else if (name === 'appearance_display') {
      this.appearanceNavPage('display', '显示与行为')
    } else if (name === 'appearance_language') {
      this.appearanceNavPage('language', '应用语言')
    } else if (name === 'skills') {
      NavDestination() {
        Column() {
          SkillsPanel({
            skills: this.workspace.skills || defaultBuiltinSkills(),
            embeddedInNav: true,
            onSaveSkills: async (next: SkillRecord[]) => {
              this.workspace.skills = next;
              await this.persist();
            },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('Agent Skills 技能包'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), false)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'workspace') {
      NavDestination() {
        Column() {
          WorkspacePanel({
            workspaces: this.workspace.workspaces || [],
            activeWorkspaceId: this.activeWorkspaceForChat()?.id || '',
            envVars: this.workspace.envVars || [],
            filesDir: this.filesDirPath,
            embeddedInNav: true,
            onSaveWorkspaces: async (list: LocalWorkspace[], activeWsId: string) => {
              this.workspace.workspaces = list;
              const c = this.activeChat();
              if (c) c.workspaceId = activeWsId || undefined;
              await this.persist();
            },
            onSaveEnvVars: async (vars: EnvVar[]) => {
              this.workspace.envVars = vars;
              await this.persist();
            },
            onOpenHtmlPreview: (title: string, html: string) => {
              this.openPreview('html', title, html);
            },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('本地沙箱工作区'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), false)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'browser') {
      NavDestination() {
        Column() {
          BrowserPanel({
            manager: this.browserManager,
            workspaces: this.workspace.workspaces || [],
            bookmarks: this.workspace.browserBookmarks || [],
            compactMode: false,
            embeddedInNav: true,
            onSaveBookmarks: async (list: BrowserBookmark[]) => {
              this.workspace.browserBookmarks = list;
              await this.persist();
            },
            onExtractToChat: (title: string, text: string) => {
              this.attachedList = [...this.attachedList, { name: `${title.slice(0, 24)}.txt`, data: text, mime: 'text/plain', kind: 'text' }];
              this.navigateTo('chat');
            },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('内置浏览器'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), false)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    } else if (name === 'schedules') {
      NavDestination() {
        Column() {
          ScheduledTasksPanel({
            tasks: this.workspace.scheduledTasks || [],
            personas: this.workspace.personas,
            providers: this.workspace.providers,
            embeddedInNav: true,
            onSaveTasks: async (next: ScheduledTask[]) => {
              this.workspace.scheduledTasks = next;
              await this.persist();
            },
            onRunTaskNow: async (task: ScheduledTask) => {
              await this.scheduler.executeTask(task);
            },
            onOpenConversation: (chatId: string) => {
              this.activate(chatId);
              this.navigateTo('chat');
            },
            onClose: () => { this.navigateBack(); }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(Color.Transparent)
      }
      .hideBackButton(true)
      .backgroundColor(this.themeTokens().canvas)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .title(
        { builder: () => { this.navSubHeader('自动化定时任务'); }, height: 56 + this.winTopInset },
        ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightOn(), true)
      )
      .systemTransition(SystemMotion.navTransition(this.reduceMotion))
      .onShown(() => { this.syncActiveRouteFromStack(); })
      .onHidden(() => { this.syncActiveRouteFromStack(); })
      .onBackPressed(() => this.dismissTopOverlay())
    }
  }

  build() {
    Stack() {
      WithTheme({ theme: ImmersiveMaterialStyle.pageTheme(this.themeTokens().canvas) }) {
        Navigation(this.navPathStack) {
          Row() {
            if (!this.ready) {
              Column({ space: 12 }) {
                if (this.loadError) {
                  Text(this.loadError).fontColor($r('app.color.warning'))
                  Button('重新读取').onClick(() => { this.loadWorkspace(); })
                } else { LoadingProgress().width(32).height(32) }
              }.width('100%').height('100%').justifyContent(FlexAlign.Center)
            } else {
              if (this.wide) { this.sidebarBody(false) }
              this.chatPane()
              if (this.wideSide && this.sidePanelMode !== '' && this.activeRoute === 'chat') {
                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Button('🌐 浏览器')
                      .height(26).fontSize(11).borderRadius(6)
                      .backgroundColor(this.sidePanelMode === 'browser' ? $r('app.color.accent') : $r('app.color.panel'))
                      .fontColor(this.sidePanelMode === 'browser' ? $r('app.color.on_accent') : $r('app.color.ink'))
                      .onClick(() => { this.setSidePanelMode('browser'); })
                    Button('📁 工作区')
                      .height(26).fontSize(11).borderRadius(6)
                      .backgroundColor(this.sidePanelMode === 'workspace' ? $r('app.color.accent') : $r('app.color.panel'))
                      .fontColor(this.sidePanelMode === 'workspace' ? $r('app.color.on_accent') : $r('app.color.ink'))
                      .onClick(() => { this.setSidePanelMode('workspace'); })
                    Blank()
                    Button('×')
                      .width(26).height(26).fontSize(13).borderRadius(6)
                      .backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
                      .onClick(() => { this.setSidePanelMode(''); })
                  }.width('100%').padding({ left: 8, right: 8, top: 6 })
                  if (this.sidePanelMode === 'workspace') {
                    WorkspacePanel({
                      workspaces: this.workspace.workspaces || [],
                      activeWorkspaceId: this.activeWorkspaceForChat()?.id || '',
                      envVars: this.workspace.envVars || [],
                      filesDir: this.filesDirPath,
                      onSaveWorkspaces: async (list: LocalWorkspace[], activeWsId: string) => {
                        this.workspace.workspaces = list;
                        const c = this.activeChat();
                        if (c) c.workspaceId = activeWsId || undefined;
                        await this.persist();
                      },
                      onSaveEnvVars: async (vars: EnvVar[]) => {
                        this.workspace.envVars = vars;
                        await this.persist();
                      },
                      onOpenHtmlPreview: (title: string, html: string) => {
                        this.openPreview('html', title, html);
                      },
                      onClose: () => { this.setSidePanelMode(''); }
                    }).layoutWeight(1)
                  } else {
                    BrowserPanel({
                      manager: this.browserManager,
                      workspaces: this.workspace.workspaces || [],
                      bookmarks: this.workspace.browserBookmarks || [],
                      compactMode: true,
                      onSaveBookmarks: async (list: BrowserBookmark[]) => {
                        this.workspace.browserBookmarks = list;
                        await this.persist();
                      },
                      onExtractToChat: (title: string, text: string) => {
                        this.attachedList = [...this.attachedList, { name: `${title.slice(0, 24)}.txt`, data: text, mime: 'text/plain', kind: 'text' }];
                      },
                      onClose: () => { this.setSidePanelMode(''); }
                    }).layoutWeight(1)
                  }
                }
                .width('36%')
                .height('100%')
                .padding({ top: this.winTopInset, bottom: this.effectiveBottomInset(), right: this.winRightInset })
                .backgroundColor($r('app.color.panel'))
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                .border({ width: { left: 1 }, color: $r('app.color.line') })
                .transition(SystemMotion.endSlideTransition(this.reduceMotion))
              }
            }
          }
          .width('100%')
          .height('100%')
          .backgroundColor(this.chatBgColor())
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .mode(NavigationMode.Stack)
        .hideTitleBar(true)
        .hideToolBar(true)
        .navDestination(this.routeDestination)
        .width('100%')
        .height('100%')
        .backgroundColor(this.chatBgColor())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }

      if (!this.wide && this.drawerOpen && this.activeRoute === 'chat') { this.drawerOverlay() }
      if (this.editingMsgId) { this.editMessageOverlay() }
      if (this.selectCopyText) { this.selectCopyOverlay() }
      if (this.imageViewerSrc) {
        Column() {
          ImageViewerSheet({
            imageSrc: this.imageViewerSrc,
            imageTitle: this.imageViewerTitle,
            canOcr: this.imageViewerSrc.startsWith('data:image/'),
            onRunOcr: (src: string) => this.runOcrOnImage(src),
            onClose: () => {
              SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
                this.imageViewerSrc = '';
              });
            }
          })
        }
        .width('100%').height('100%')
        .padding({ top: this.winTopInset, bottom: this.effectiveBottomInset(), left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(this.themeTokens().canvas)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(SystemMotion.overlayModalTransition(this.reduceMotion))
      }
      if (this.previewVisible) {
        Column() {
          RichPreviewSheet({
            previewKind: this.previewKind,
            previewTitle: this.previewTitle,
            sourceCode: this.previewCode,
            onClose: () => {
              SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
                this.previewVisible = false;
              });
            }
          })
        }
        .width('100%').height('100%')
        .padding({ top: this.winTopInset, bottom: this.effectiveBottomInset(), left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(this.themeTokens().canvas)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(SystemMotion.overlayModalTransition(this.reduceMotion))
      }
      if (this.oauthModalVisible) {
        Column() {
          OAuthLoginSheet({
            oauthKind: this.oauthKind,
            providers: this.workspace.providers,
            onConnected: async (prov: Provider) => {
              const exists = this.workspace.providers.some((p: Provider): boolean => p.id === prov.id);
              this.workspace.providers = exists
                ? this.workspace.providers.map((p: Provider): Provider => (p.id === prov.id ? prov : p))
                : [...this.workspace.providers, prov];
              this.workspace.activeProvider = prov.id;
              await this.persist();
            },
            onClose: () => {
              SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
                this.oauthModalVisible = false;
              });
            }
          })
        }
        .width('100%').height('100%')
        .padding({ top: this.winTopInset, bottom: this.effectiveBottomInset(), left: this.winLeftInset, right: this.winRightInset })
        .backgroundColor(this.themeTokens().canvas)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(SystemMotion.overlayModalTransition(this.reduceMotion))
      }

      Column()
        .width(0)
        .height(0)
        .bindSheet(
          $$this.showBottomToolsSheet,
          this.bottomToolsOverlay(),
          ImmersiveMaterialStyle.sheetOptions(
            this.immersiveLightOn(),
            this.themeTokens().surface,
            '快捷功能',
            () => { this.showBottomToolsSheet = false; },
            true
          )
        )

      Column()
        .width(0)
        .height(0)
        .bindSheet(
          $$this.showSearchQuickSheet,
          this.searchQuickOverlay(),
          ImmersiveMaterialStyle.sheetOptions(
            this.immersiveLightOn(),
            this.themeTokens().surface,
            '联网搜索',
            () => { this.showSearchQuickSheet = false; },
            true
          )
        )

      Column()
        .width(0)
        .height(0)
        .bindSheet(
          $$this.showReasoningSheet,
          this.reasoningQuickOverlay(),
          ImmersiveMaterialStyle.sheetOptions(
            this.immersiveLightOn(),
            this.themeTokens().surface,
            '推理思考深度',
            () => { this.showReasoningSheet = false; },
            true
          )
        )

      Column()
        .width(0)
        .height(0)
        .bindSheet(
          $$this.showChatToolsSheet,
          this.chatToolsOverlay(),
          ImmersiveMaterialStyle.sheetOptions(
            this.immersiveLightOn(),
            this.themeTokens().surface,
            '对话工具与工作区',
            () => { this.showChatToolsSheet = false; },
            true
          )
        )

      Column()
        .width(0)
        .height(0)
        .bindSheet(
          $$this.showModelQuickSheet,
          this.modelQuickOverlay(),
          ImmersiveMaterialStyle.sheetOptions(
            this.immersiveLightOn(),
            this.themeTokens().surface,
            '选择模型',
            () => { this.showModelQuickSheet = false; },
            true
          )
        )

      Column()
        .width(0)
        .height(0)
        .bindSheet(
          $$this.showMiniMap,
          this.miniMapOverlay(),
          ImmersiveMaterialStyle.sheetOptions(
            this.immersiveLightOn(),
            this.themeTokens().surface,
            '对话大纲',
            () => { this.showMiniMap = false; },
            true
          )
        )

      Column()
        .width(0)
        .height(0)
        .bindSheet(
          $$this.showMessageActionSheet,
          this.messageActionSheetOverlay(),
          ImmersiveMaterialStyle.actionSheetOptions(
            this.immersiveLightOn(),
            this.themeTokens().surface,
            () => { this.showMessageActionSheet = false; }
          )
        )
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.activeRoute === 'chat' ? this.chatBgColor() : this.themeTokens().canvas)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_old: Area, current: Area) => {
      this.wide = Number(current.width) >= 760;
      this.wideSide = Number(current.width) >= 960;
    })
  }
}
