import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { displaySync } from '@kit.ArkGraphics2D';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
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
  Persona,
  Provider,
  ProxyConfig,
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
  defaultGlobalProxy,
  defaultInstructionCards,
  defaultQuickPhrases,
  defaultSearchServices,
  defaultSystemSettings,
  cloneModelSpec,
  cloneProvider,
  defaultModelSpec,
  findProviderModelSpec,
  initialWorkspace,
  isProviderConfigured,
  normalizeAppearanceConfig,
  normalizeBackupConfig,
  normalizeInstructionCards,
  normalizeProxyConfig,
  normalizeQuickPhrases,
  normalizeWorldBooks,
  openCodeGoSessionId,
  preset,
  planClientId,
  resolveActiveModel
} from '../core/Models';
import { ReasoningControl, effectiveEffort, reasoningBulbRayCount, reasoningControl, reasoningTokens, withReasoning } from '../core/Reasoning';
import { ChatCall, ChatCallOptions, ReplyReasoningTimer, RichFragment, makeAdvancedChatCall } from '../core/Protocol';
import { ChatStream, completeOnce, generateImages, setGlobalHttpProxy } from '../core/ChatClient';
import { WorkspaceStore, exportChats, forgetKey, importChats, newId, readKey, storeKey } from '../core/Storage';
import { ImportedProvider } from '../core/ProviderLink';
import {
  computeStorageBreakdown,
  hydrateAttachmentData,
  pickMultipleAttachments,
  pickPhotoAttachments,
  takePhotoAttachment
} from '../core/AttachmentStore';
import { BrandIconId, resolveBrandIconId } from '../core/BrandIcons';
import { markKeyError, markKeySuccess } from '../core/KeyPool';
import {
  appendMessageVersion,
  applyContextCompression,
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
import { runAgentToolLoop } from '../core/ToolLoop';
import { applyRegexRules, buildAssembledPrompt } from '../core/PromptEngine';
import {
  buildMemoryInjectionBlock,
  buildMemoryRulesSystemPrompt,
  normalizeMemorySettings,
  resolveMemoryPromptLang
} from '../core/MemoryLogic';
import {
  buildMemoryTools,
  buildMemoryOrganizeBatch,
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
import { StreamTextSmoother } from '../core/StreamSmoother';
import { formatLocalDay } from '../core/UsageStatsLogic';
import {
  isBuiltInSearchEnabled,
  isClaudeDynamicSearchEnabled,
  mergeDeduplicatedCitations,
  needsMoonshotBuiltinSearchLoop,
  requiresResponsesApiForBuiltInSearch,
  supportsBuiltInSearch,
  supportsClaudeDynamicWebSearch
} from '../core/BuiltinSearch';
import { MessageBody } from '../components/MessageBody';
import { PersonaEditor } from '../components/PersonaEditor';
import { disconnectPlan } from '../core/ChatGptSession';
import { disconnectOpenCodeGo } from '../core/OpenCodeGoSession';
import { ProviderEditor } from '../components/ProviderEditor';
import { ModelSpecEditor } from '../components/ModelSpecEditor';
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
import { KelivoAvatarBadge, KelivoNavRouteShell } from '../components/KelivoChrome';
import { BottomToolsSheet } from '../components/BottomToolsSheet';
import { ModelSelectSheet } from '../components/ModelSelectSheet';
import { ChatToolsSheet, ReasoningLevelSheet, SearchQuickSheet } from '../components/ChatQuickSheets';
import { WorkspacePanel } from '../components/WorkspacePanel';
import { SkillsPanel } from '../components/SkillsPanel';
import { NetworkProxyPanel } from '../components/NetworkProxyPanel';
import { BrowserPanel } from '../components/BrowserPanel';
import { ScheduledTasksPanel } from '../components/ScheduledTasksPanel';
import { ChatSidebarView, ChatDrawerOverlay } from '../components/ChatSidebarView';
import { ChatMessageRowView, ChatReplyActivityCard } from '../components/ChatMessageRowView';
import { ChatTitleBarView } from '../components/ChatTitleBarView';
import { ChatComposerView } from '../components/ChatComposerView';
import {
  ChatEditMessageModal,
  ChatMessageActionSheet,
  ChatMiniMapSheet,
  ChatScrollNavOverlay,
  ChatSelectCopyModal,
  ChatWideSidePanel
} from '../components/ChatOverlaysView';
import { buildWorkspaceTools } from '../core/WorkspaceTools';
import { buildSkillsPromptSummary, defaultBuiltinSkills } from '../core/SkillsParser';
import { buildSkillTools } from '../core/SkillsManager';
import { BrowserAgentManager, buildBrowserTools } from '../core/BrowserAgent';
import { AskUserPromptRequest, buildDeviceTools } from '../core/DeviceTools';
import { ScheduledTaskRunner } from '../core/ScheduledTasks';
import { WebSearch } from '../core/WebSearch';
import {
  ResolvedRoleTarget,
  buildChatTemplateContext,
  buildChatToolSchemaCandidates,
  executeChatRegisteredTool,
  formatChatMessageTime,
  formatStorageSizeLabel,
  generateAutoChatTitle,
  generateChatCompressionSummary,
  generateChatSuggestions,
  resolveProviderKeyAndProxy,
  resolveRoleProviderTarget,
  runChatOcrOnImage,
  translateChatMessageText
} from '../core/ChatAuxService';
import { computeFloatingBottomInsetVp, hexWithAlpha } from '../core/ImmersiveUtils';
import { syncWindowBackgroundColor, syncWindowSystemBars } from '../core/WindowController';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { SystemMotion } from '../core/SystemMotion';
import { backgroundGenerationManager, GenerationPhase } from '../core/BackgroundGeneration';
import { ChatGenerationJob, GenerationSessionRegistry } from '../core/GenerationSession';

interface ComposerDraftData {
  text: string;
  attachments: Attachment[];
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
  @State query: string = '';
  @State draft: string = '';
  @State attachedList: Attachment[] = [];
  @State quoteDraft?: QuoteRef = undefined;
  @State draftPersona: string = 'default';
  @State draftOverrideProviderId: string = '';
  @State draftOverrideModel: string = '';
  @State modelConfigTick: number = 0;
  @State working: boolean = false;
  @State picking: boolean = false;
  @State liveText: string = '';
  @State liveReasoning: string = '';
  @State liveMessageId: string = '';
  @State liveThinking: boolean = false;
  @State liveReasoningMs: number = 0;
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
  @State sidePanelMode: '' | 'browser' | 'workspace' = '';
  @State wideSide: boolean = false;
  @State askQuestionText: string = '';
  @State askQuestionOptions: string[] = [];
  @State askQuestionPlaceholder: string = '';
  @State askQuestionAnswer: string = '';
  @State drawerOpen: boolean = false;
  @State drawerGlobalSearch: boolean = false;
  @State promptTabInit: number = 0;
  @State diagTabInit: number = 0;
  @State providerDetailId: string = '';
  @State modelEditProvider: Provider = preset('', '', 'openai', '', '');
  @State modelEditSpec: ModelSpec = defaultModelSpec('');
  @State modelEditIsNew: boolean = false;
  @State globalProxyPasswordPlain: string = '';
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
  @State lastSendError: string = '';
  @State lastSendErrorChatId: string = '';
  @State expandedLongMsgIds: string[] = [];
  @State organizingMemoryChatId: string = '';
  @State organizingMemoryAssistantId: string = '';
  @State generatingChatIds: string[] = [];
  @State pendingPromptChatId: string = '';
  @State pendingPromptLabel: string = '';
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('windowKeyboardHeightVp') @Watch('onKeyboardHeightChanged') winKeyboardHeight: number = 0;
  @StorageProp('windowLeftInsetVp') winLeftInset: number = 0;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('windowTitleRightAvoidVp') winTitleRightAvoid: number = 0;
  @StorageProp('windowIsFloating') winIsFloating: boolean = false;
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;
  @StorageProp('systemIsDark') @Watch('onSystemDarkChanged') sysDarkFromAbility: boolean = false;
  @StorageLink('appInBackground') @Watch('onAppBackgroundChanged') appInBackground: boolean = false;
  @StorageLink('pendingOpenChatId') @Watch('consumePendingOpenChat') pendingOpenChatId: string = '';

  private store?: WorkspaceStore;
  private cachedHostContext?: common.UIAbilityContext;
  private modelEditSaveCallback?: (spec: ModelSpec) => void = undefined;
  private genRegistry: GenerationSessionRegistry = new GenerationSessionRegistry();
  private mcpManager: McpManager = new McpManager();
  private browserManager: BrowserAgentManager = new BrowserAgentManager();
  private scheduler: ScheduledTaskRunner = new ScheduledTaskRunner();
  private speechInput: SpeechInputController = new SpeechInputController();
  private scrollView: Scroller = new Scroller();
  private memoryQueue: MemoryQueueJob[] = [];
  private memoryQueueRunning: boolean = false;
  private memoryWindowFailures: Map<string, number> = new Map<string, number>();
  private drafts: Map<string, ComposerDraftData> = new Map<string, ComposerDraftData>();
  private speaker: Narration = new Narration();
  private followBottom: boolean = true;
  private lastLiveBodyHeight: number = 0;
  private scrollFollowTimer: number = -1;
  private chatScrollNavHideTimer: number = -1;
  private chatFirstVisibleIdx: number = 0;
  private chatLastVisibleIdx: number = 0;
  private chatNavTargetIdx: number = -1;
  private navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (_) {}
    this.navPathStack.setInterception({
      didShow: (_from: NavDestinationContext | NavBar, _to: NavDestinationContext | NavBar, _op: NavigationOperation, _animated: boolean) => {
        this.syncActiveRouteFromStack();
      }
    });
    this.loadWorkspace();
  }
  onPageShow(): void {
    this.consumePendingShareText();
    this.consumePendingOpenChat();
    this.syncActiveGenerationView();
    if (this.working && this.activeRoute === 'chat' && this.followBottom) {
      this.scrollDown();
    }
  }
  aboutToDisappear(): void {
    this.hideChatScrollNavImmediate();
    if (this.scrollFollowTimer >= 0) {
      clearTimeout(this.scrollFollowTimer);
      this.scrollFollowTimer = -1;
    }
    this.stopAllGenerations(false);
    backgroundGenerationManager.stopAll();
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

  private consumePendingShareText(): void {
    const shared = AppStorage.get<string>('pendingShareText');
    if (shared && shared.trim().length > 0) {
      this.draft = this.draft.trim().length > 0 ? `${this.draft}\n\n${shared.trim()}` : shared.trim();
      AppStorage.setOrCreate('pendingShareText', '');
      this.navigateTo('chat');
      this.toast('已填入系统分享文本');
    }
  }

  private consumePendingOpenChat(): void {
    if (!this.ready) {
      return;
    }
    const targetChatId = this.pendingOpenChatId;
    if (targetChatId && targetChatId.trim().length > 0) {
      const cleanId = targetChatId.trim();
      AppStorage.setOrCreate('pendingOpenChatId', '');
      if (this.workspace.conversations.some((c: Conversation): boolean => c.id === cleanId)) {
        this.activate(cleanId);
      }
    }
  }

  private onAppBackgroundChanged(): void {
    if (this.appInBackground) {
      applyKeepScreenOn(this.host(), false).catch(() => {});
      return;
    }
    this.refreshKeepScreenOn();
    this.syncActiveGenerationView();
    if (this.activeRoute === 'chat' && this.working && this.followBottom) {
      this.scrollDown();
    }
  }

  private isChatGenerating(chatId: string): boolean {
    return this.genRegistry.isGenerating(chatId);
  }

  private hasOtherGeneratingChat(): boolean {
    const activeId = this.workspace.activeConversation;
    for (let i = 0; i < this.generatingChatIds.length; i++) {
      if (this.generatingChatIds[i] !== activeId) {
        return true;
      }
    }
    return false;
  }

  private syncGeneratingMetadata(): void {
    this.generatingChatIds = this.genRegistry.activeChatIds();
    const other = this.genRegistry.findOtherPendingPrompt(this.workspace.activeConversation);
    this.pendingPromptChatId = other ? other.chatId : '';
    this.pendingPromptLabel = other ? other.label : '';
  }

  private syncActiveGenerationView(): void {
    this.syncGeneratingMetadata();
    const proj = this.genRegistry.projectForChat(this.workspace.activeConversation);
    this.working = proj.working;
    this.liveMessageId = proj.liveMessageId;
    this.liveText = proj.liveText;
    this.liveReasoning = proj.liveReasoning;
    this.liveThinking = proj.liveThinking;
    this.liveReasoningMs = proj.liveReasoningMs;
    this.liveToolCalls = proj.liveToolCalls;
    this.fetchingSources = proj.fetchingSources;
    this.regeneratingMsgId = proj.regeneratingMsgId;
    this.pendingApprovalTool = proj.pendingApprovalTool;
    this.pendingApprovalArgs = proj.pendingApprovalArgs;
    this.askQuestionText = proj.askQuestionText;
    this.askQuestionOptions = proj.askQuestionOptions;
    this.askQuestionPlaceholder = proj.askQuestionPlaceholder;
    this.askQuestionAnswer = proj.askQuestionAnswer;
    this.lastSendError = proj.lastSendError;
    this.lastSendErrorChatId = proj.lastSendErrorChatId;
  }

  private refreshKeepScreenOn(): void {
    const shouldKeep = !this.appInBackground && this.genRegistry.hasAny() && this.workspace.systemSettings?.keepScreenOn !== false;
    applyKeepScreenOn(this.host(), shouldKeep).catch(() => {});
  }

  private activeLiveJob(): ChatGenerationJob | undefined {
    return this.genRegistry.get(this.workspace.activeConversation);
  }

  private activeLiveBrandId(): BrandIconId {
    const job = this.activeLiveJob();
    if (job) {
      return resolveBrandIconId(`${job.modelId} ${job.providerName}`, job.providerFamily);
    }
    return this.activeBrandId();
  }

  private activeLiveModelLabel(): string {
    const job = this.activeLiveJob();
    if (job) {
      return job.modelId || job.providerName;
    }
    return this.activeModelId() || this.provider().name;
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
    if (this.activeRoute === 'chat') {
      this.syncActiveGenerationView();
      if (this.working && this.followBottom) {
        this.scrollDown();
      }
    }
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

  host(): common.UIAbilityContext {
    if (this.cachedHostContext) {
      return this.cachedHostContext;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (ctx) {
      this.cachedHostContext = ctx;
    }
    return ctx;
  }

  private async syncGlobalProxyRuntime(): Promise<void> {
    const gp = normalizeProxyConfig(this.workspace.globalProxy, true);
    this.workspace.globalProxy = gp;
    let pass = '';
    if (gp.passwordRef) {
      try {
        pass = await readKey(gp.passwordRef);
      } catch (_) {
        pass = '';
      }
    }
    this.globalProxyPasswordPlain = pass;
    setGlobalHttpProxy(gp, pass);
  }

  private promptToolsNavTitle(): string {
    if (this.promptTabInit === 1) return '指令注入';
    if (this.promptTabInit === 2) return '快捷短语';
    return '世界书 · 指令卡 · 快捷短语';
  }

  async loadWorkspace(): Promise<void> {
    this.loadError = '';
    try {
      const ctx = this.host();
      this.cachedHostContext = ctx;
      backgroundGenerationManager.attachContext(ctx);
      this.filesDirPath = ctx.filesDir;
      this.dbDirPath = ctx.databaseDir || ctx.filesDir;
      const cfgDark = ctx.config?.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      this.isSystemDark = cfgDark;
      if (AppStorage.get<boolean>('systemIsDark') === undefined) {
        AppStorage.setOrCreate('systemIsDark', cfgDark);
      }
      this.store = new WorkspaceStore(ctx);
      this.workspace = await this.store.load();
      this.workspace.globalProxy = normalizeProxyConfig(this.workspace.globalProxy, true);
      this.workspace.worldBooks = normalizeWorldBooks(this.workspace.worldBooks);
      const normCards = normalizeInstructionCards(this.workspace.instructionCards);
      this.workspace.instructionCards = normCards.length > 0 ? normCards : defaultInstructionCards();
      const normPhrases = normalizeQuickPhrases(this.workspace.quickPhrases);
      this.workspace.quickPhrases = normPhrases.length > 0 ? normPhrases : defaultQuickPhrases();
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
      await this.syncGlobalProxyRuntime();
      this.refreshStorageSize().catch(() => {});
      const active = this.activeChat();
      if (active?.draftText) this.draft = active.draftText;
      this.draftPersona = active?.personaId || (this.workspace.personas[0]?.id || 'default');
      this.ready = true;
      this.syncActiveGenerationView();
      this.scrollDown(true);
      this.consumePendingShareText();
      this.consumePendingOpenChat();
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

  private resolvedChatForModel(): Conversation | undefined {
    const c = this.activeChat();
    if (c) {
      return c;
    }
    if (this.workspace.modelDefaults?.perChatModel === true && this.draftOverrideProviderId.length > 0) {
      return {
        id: '',
        title: '',
        updated: 0,
        messages: [],
        personaId: this.selectedPersonaId(),
        overrideProviderId: this.draftOverrideProviderId,
        overrideModel: this.draftOverrideModel
      };
    }
    return undefined;
  }

  provider(): Provider {
    const tick = this.modelConfigTick;
    const res = resolveActiveModel(this.workspace, this.resolvedChatForModel(), this.persona());
    return tick >= 0 ? res.provider : res.provider;
  }

  activeModelId(): string {
    const tick = this.modelConfigTick;
    const res = resolveActiveModel(this.workspace, this.resolvedChatForModel(), this.persona());
    const mid = res.modelId || res.provider.model;
    return tick >= 0 ? mid : mid;
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
    const tick = this.modelConfigTick;
    const id = this.selectedPersonaId();
    const found = this.workspace.personas.find((p: Persona): boolean => p.id === id) || this.workspace.personas[0];
    return tick >= 0 ? found : found;
  }

  effectiveParams(): GenerationParams {
    const tick = this.modelConfigTick;
    const global = this.workspace.generationParams || defaultGenerationParams();
    const local = this.persona().params;
    const source = local?.reasoningEffort ? local : global;
    const params = withReasoning(local || global, source.reasoningEffort, source.reasoningBudget);
    return tick >= 0 ? params : params;
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

  private async refreshStorageSize(): Promise<void> {
    if (!this.filesDirPath) return;
    const stats = await computeStorageBreakdown(this.filesDirPath, this.dbDirPath || this.filesDirPath);
    this.storageSizeLabel = formatStorageSizeLabel(stats.totalBytes);
  }

  private selectModelQuick(providerId: string, modelId: string): void {
    this.workspace.activeProvider = providerId;
    const prov = this.workspace.providers.find((p: Provider): boolean => p.id === providerId);
    if (prov && modelId) {
      prov.model = modelId;
      this.workspace.providers = this.workspace.providers.slice();
    }
    const perChat = this.workspace.modelDefaults?.perChatModel === true;
    const c = this.activeChat();
    if (perChat) {
      if (c) {
        c.overrideProviderId = providerId;
        c.overrideModel = modelId;
        this.workspace.conversations = this.workspace.conversations.slice();
        this.draftOverrideProviderId = '';
        this.draftOverrideModel = '';
      } else {
        this.draftOverrideProviderId = providerId;
        this.draftOverrideModel = modelId;
      }
    } else {
      this.draftOverrideProviderId = '';
      this.draftOverrideModel = '';
      if (c) {
        c.overrideProviderId = undefined;
        c.overrideModel = undefined;
        this.workspace.conversations = this.workspace.conversations.slice();
      }
      if (this.persona()) {
        const curPersona = this.persona();
        curPersona.providerId = providerId;
        curPersona.modelId = modelId;
        this.workspace.personas = this.workspace.personas.slice();
      }
    }
    this.modelConfigTick += 1;
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
    if (this.isChatGenerating(c.id)) {
      this.toast('当前对话正在生成中，请稍候');
      return;
    }
    c.contextStartIndex = c.messages.length;
    c.updated = Date.now();
    this.workspace.conversations = this.workspace.conversations.slice();
    this.showBottomToolsSheet = false;
    if (!c.ephemeral) {
      this.persistAction();
    }
    this.toast('已重置上下文窗口');
  }

  private currentModelSpec(): ModelSpec {
    return findProviderModelSpec(this.provider(), this.activeModelId());
  }

  private currentSupportsBuiltinSearch(): boolean {
    return supportsBuiltInSearch(this.provider(), this.activeModelId(), this.currentModelSpec());
  }

  private currentBuiltinSearchOn(): boolean {
    return isBuiltInSearchEnabled(this.provider(), this.activeModelId());
  }

  private currentNeedsResponsesHint(): boolean {
    return requiresResponsesApiForBuiltInSearch(this.provider(), this.activeModelId(), this.currentModelSpec());
  }

  private currentSupportsClaudeDynamicSearch(): boolean {
    return supportsClaudeDynamicWebSearch(this.provider(), this.activeModelId(), this.currentModelSpec());
  }

  private currentClaudeDynamicSearchOn(): boolean {
    return isClaudeDynamicSearchEnabled(this.provider(), this.activeModelId());
  }

  private updateCurrentModelBuiltinFlags(updateFn: (spec: ModelSpec) => ModelSpec, save: boolean = true): void {
    const prov = this.provider();
    const mid = this.activeModelId();
    if (!prov || !mid) {
      return;
    }
    const cloned = cloneProvider(prov);
    const existingModels = cloned.models ? cloned.models.slice() : [];
    const idx = existingModels.findIndex((m: ModelSpec): boolean => m.id === mid);
    const baseSpec = idx >= 0 ? existingModels[idx] : defaultModelSpec(mid);
    const nextSpec = updateFn(cloneModelSpec(baseSpec));
    if (idx >= 0) {
      existingModels[idx] = nextSpec;
    } else {
      existingModels.unshift(nextSpec);
    }
    cloned.models = existingModels;
    this.workspace.providers = this.workspace.providers.map((item: Provider): Provider =>
      item.id === cloned.id ? cloned : item
    );
    this.modelConfigTick += 1;
    if (save) {
      this.persistAction();
    }
  }

  private setModelBuiltinSearchEnabled(enabled: boolean): void {
    if (enabled) {
      this.setSearchEnabled(false, false);
    }
    this.updateCurrentModelBuiltinFlags((spec: ModelSpec): ModelSpec => {
      spec.builtinSearch = enabled;
      return spec;
    }, true);
  }

  private setModelClaudeDynamicSearchEnabled(enabled: boolean): void {
    this.updateCurrentModelBuiltinFlags((spec: ModelSpec): ModelSpec => {
      spec.claudeDynamicSearch = enabled;
      return spec;
    }, true);
  }

  private setSearchEnabled(enabled: boolean, save: boolean = true): void {
    if (enabled && this.currentBuiltinSearchOn()) {
      this.updateCurrentModelBuiltinFlags((spec: ModelSpec): ModelSpec => {
        spec.builtinSearch = false;
        return spec;
      }, false);
    }
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
    this.draftOverrideProviderId = '';
    this.draftOverrideModel = '';
    this.modelConfigTick += 1;
    this.drawerGlobalSearch = false;
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
    if (this.picking) return;
    const prevId = this.workspace.activeConversation;
    const prevJob = this.genRegistry.get(prevId);
    if (prevJob) {
      prevJob.askQuestionAnswer = this.askQuestionAnswer;
    }
    this.drafts.set(prevId, { text: this.draft, attachments: this.attachedList.slice() });
    const prevChat = this.activeChat();
    if (prevChat && !prevChat.ephemeral) {
      prevChat.draftText = this.draft;
    }
    const stored = this.drafts.get(chatId);
    this.workspace.activeConversation = chatId;
    this.draftOverrideProviderId = '';
    this.draftOverrideModel = '';
    this.modelConfigTick += 1;
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
    this.notice = '';
    this.lastLiveBodyHeight = 0;
    this.syncActiveGenerationView();
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
    if (chat.enabledMcpIds === undefined) chat.enabledMcpIds = prev?.enabledMcpIds;
    if (chat.enabledSkillIds === undefined) chat.enabledSkillIds = prev?.enabledSkillIds;
    if (chat.workspaceId === undefined) chat.workspaceId = prev?.workspaceId;
    if (chat.toolPermissionMode === undefined) chat.toolPermissionMode = prev?.toolPermissionMode;
    if (chat.draftText === undefined) chat.draftText = prev?.draftText;
    if (chat.imageGenMode === undefined) chat.imageGenMode = prev?.imageGenMode;
    if (chat.suggestions === undefined) chat.suggestions = prev?.suggestions;
    this.workspace.conversations = [chat, ...this.workspace.conversations.filter((c: Conversation): boolean => c.id !== chat.id)];
  }

  scrollDown(force: boolean = false): void {
    if (force) {
      if (this.scrollFollowTimer >= 0) {
        clearTimeout(this.scrollFollowTimer);
        this.scrollFollowTimer = -1;
      }
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
      if (this.scrollFollowTimer >= 0) {
        return;
      }
      this.scrollFollowTimer = setTimeout(() => {
        this.scrollFollowTimer = -1;
        if (this.followBottom) {
          this.scrollView.scrollEdge(Edge.Bottom);
        }
      }, 30);
    }
  }

  private onLiveStreamAreaChanged(nextHeight: number): void {
    if (this.regeneratingMsgId) {
      return;
    }
    if (nextHeight > this.lastLiveBodyHeight + 1) {
      this.lastLiveBodyHeight = nextHeight;
      if (this.followBottom && this.working && this.activeRoute === 'chat' && !this.appInBackground) {
        this.scrollView.scrollEdge(Edge.Bottom);
      }
    } else if (nextHeight < this.lastLiveBodyHeight) {
      this.lastLiveBodyHeight = nextHeight;
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
    const checkMid = (p.id === priorId || setActive) ? (this.activeModelId() || p.model.trim()) : p.model.trim();
    if ((p.id === priorId || setActive) && checkMid) {
      const prevSpec = priorActiveProv && priorActiveProv.id === p.id
        ? findProviderModelSpec(priorActiveProv, checkMid)
        : undefined;
      const nextSpec = findProviderModelSpec(p, checkMid);
      if (
        nextSpec.reasoningDefaultLevel &&
        nextSpec.reasoningDefaultLevel !== 'auto' &&
        nextSpec.reasoningDefaultLevel !== prevSpec?.reasoningDefaultLevel
      ) {
        const curGen = this.workspace.generationParams || defaultGenerationParams();
        this.workspace.generationParams = withReasoning(curGen, nextSpec.reasoningDefaultLevel, curGen.reasoningBudget);
        const curPersona = this.persona();
        if (curPersona.params?.reasoningEffort) {
          curPersona.params = withReasoning(
            curPersona.params,
            nextSpec.reasoningDefaultLevel,
            curPersona.params.reasoningBudget
          );
        }
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
    this.modelConfigTick += 1;
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
      this.modelConfigTick += 1;
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
    if (target && planClientId(target)) await disconnectPlan(planClientId(target));
    if (target && openCodeGoSessionId(target)) await disconnectOpenCodeGo(openCodeGoSessionId(target));
    if (target?.secretRef) await forgetKey(target.secretRef).catch(() => {});
    this.workspace.providers = this.workspace.providers.filter((p: Provider): boolean => p.id !== id);
    if (this.workspace.activeProvider === id) this.workspace.activeProvider = this.workspace.providers[0].id;
    this.modelConfigTick += 1;
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
      this.modelConfigTick += 1;
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
    this.modelConfigTick += 1;
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

  private activeReasoningControl(): ReasoningControl {
    const p = this.provider();
    const model = this.activeModelId();
    return reasoningControl(p, model, findProviderModelSpec(p, model));
  }

  private activeReasoningEffort(): ReasoningEffort {
    const spec = findProviderModelSpec(this.provider(), this.activeModelId());
    const fallback: ReasoningEffort = (spec.reasoningDefaultLevel && spec.reasoningDefaultLevel !== 'auto')
      ? spec.reasoningDefaultLevel
      : 'off';
    return effectiveEffort(this.activeReasoningControl(), this.effectiveParams().reasoningEffort || fallback);
  }

  private isActiveReasoningToggleOnly(): boolean {
    const ctrl = this.activeReasoningControl();
    return ctrl.levels.length === 2 && ctrl.levels.includes('off');
  }

  private reasoningLabelShort(): string {
    const eff = this.activeReasoningEffort();
    if (eff !== 'off' && this.isActiveReasoningToggleOnly()) return '开启';
    if (eff === 'off') return '关闭';
    if (eff === 'minimal') return '最低';
    if (eff === 'xhigh') return '极高';
    if (eff === 'low') return '低';
    if (eff === 'high') return '高';
    if (eff === 'max') return '最高';
    return '中';
  }

  private updateReasoningConfig(effort: ReasoningEffort, budget?: number): void {
    const cur = this.workspace.generationParams || defaultGenerationParams();
    this.workspace.generationParams = withReasoning(cur, effort, budget);
    const p = this.persona();
    if (p.params?.reasoningEffort) {
      p.params = withReasoning(p.params, effort, budget);
      this.workspace.personas = this.workspace.personas.slice();
    }
    this.modelConfigTick += 1;
    this.persistAction();
  }

  private composerBgColor(): string {
    const alphaNum = Math.max(0.35, Math.min(1.0, this.appearanceCfg().inputBoxOpacity ?? 0.88));
    const alphaHex = Math.round(alphaNum * 255).toString(16).padStart(2, '0').toUpperCase();
    if (this.immersiveLightOn()) {
      return hexWithAlpha(this.themeTokens().surface, alphaHex === 'FF' ? 'EB' : alphaHex);
    }
    return hexWithAlpha(this.themeTokens().surface, alphaHex === 'FF' ? 'F8' : alphaHex);
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

  private async refreshLogsAndStats(): Promise<void> {
    if (!this.store) return;
    try {
      this.requestLogs = await this.store.listRequestLogs();
    } catch (_) {}
    try {
      this.contextLogs = await this.store.listContextLogs();
    } catch (_) {}
    await this.refreshUsageStats().catch(() => {});
  }

  private async refreshUsageStats(): Promise<UsageStatRow[]> {
    if (!this.store) return this.usageStats;
    const rows = await this.store.listUsageStats();
    this.usageStats = rows;
    return rows;
  }

  private buildToolSchemaCandidates(): ToolSchemaCandidate[] {
    return buildChatToolSchemaCandidates(this.workspace.mcpServers || [], this.mcpManager);
  }

  private workspaceForChat(chat: Conversation | undefined, persona: Persona): LocalWorkspace | undefined {
    const list = this.workspace.workspaces || [];
    if (list.length === 0) return undefined;
    const chatWsId = chat?.workspaceId;
    if (chatWsId) {
      const hit = list.find((w: LocalWorkspace): boolean => w.id === chatWsId);
      if (hit) return hit;
    }
    const pWsId = persona.workspaceId;
    if (pWsId) {
      const hit = list.find((w: LocalWorkspace): boolean => w.id === pWsId);
      if (hit) return hit;
    }
    return list[0];
  }

  private activeWorkspaceForChat(): LocalWorkspace | undefined {
    return this.workspaceForChat(this.activeChat(), this.persona());
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

  private requestAskUserInput(job: ChatGenerationJob, req: AskUserPromptRequest): Promise<string> {
    job.askQuestionText = req.question;
    job.askQuestionOptions = req.options.slice();
    job.askQuestionPlaceholder = req.placeholder;
    job.askQuestionAnswer = '';
    this.syncActiveGenerationView();
    if (this.appInBackground && this.workspace.systemSettings?.backgroundNotifyEnabled !== false) {
      notifyGenerationComplete(this.host(), true, job.title || 'Kelivo', `AI 向您确认：${req.question}`, job.chatId).catch(() => {});
    }
    return new Promise<string>((resolve) => {
      job.askUserResolver = resolve;
    });
  }

  private submitAskUserInput(answer: string): void {
    const job = this.genRegistry.get(this.workspace.activeConversation);
    if (!job) {
      this.askQuestionText = '';
      this.askQuestionOptions = [];
      this.askQuestionPlaceholder = '';
      this.askQuestionAnswer = '';
      return;
    }
    const res = job.askUserResolver;
    job.askUserResolver = undefined;
    job.askQuestionText = '';
    job.askQuestionOptions = [];
    job.askQuestionPlaceholder = '';
    job.askQuestionAnswer = '';
    this.syncActiveGenerationView();
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
    if (this.isChatGenerating(chat.id)) {
      this.toast('当前对话正在生成中，请稍候');
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
        const auth = await resolveProviderKeyAndProxy(provider);
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

  stopReply(chatId?: string): void {
    const targetId = chatId ?? this.workspace.activeConversation;
    if (!targetId) {
      return;
    }
    if (this.genRegistry.stopChat(targetId)) {
      this.syncActiveGenerationView();
    }
  }

  private stopAllGenerations(markDeleted: boolean = false): void {
    this.genRegistry.stopAll(markDeleted);
    this.syncActiveGenerationView();
    this.refreshKeepScreenOn();
  }

  private activeSearchService(): SearchServiceConfig | undefined {
    const list = this.workspace.searchServices || defaultSearchServices();
    return list.find((s: SearchServiceConfig): boolean => s.id === this.workspace.activeSearchId) || list[0];
  }

  private resolveToolApproval(choice: 'allow_once' | 'allow_all' | 'deny'): void {
    const job = this.genRegistry.get(this.workspace.activeConversation);
    if (!job) {
      this.pendingApprovalTool = '';
      this.pendingApprovalArgs = '';
      return;
    }
    if (choice === 'allow_all') {
      this.fullAccessMode = true;
      const c = this.workspace.conversations.find((item: Conversation): boolean => item.id === job.chatId);
      if (c) {
        c.toolPermissionMode = 'full';
        this.persistAction();
      }
    }
    const res = job.approvalResolver;
    job.approvalResolver = undefined;
    job.pendingApprovalTool = '';
    job.pendingApprovalArgs = '';
    this.syncActiveGenerationView();
    res?.(choice);
  }

  private requestToolApproval(
    job: ChatGenerationJob, tool: RegisteredTool, argsJson: string
  ): Promise<'allow_once' | 'allow_all' | 'deny'> {
    job.pendingApprovalTool = tool.declaration.name;
    job.pendingApprovalArgs = argsJson;
    this.syncActiveGenerationView();
    if (this.appInBackground && this.workspace.systemSettings?.backgroundNotifyEnabled !== false) {
      notifyGenerationComplete(
        this.host(),
        true,
        job.title || 'Kelivo',
        `工具「${tool.declaration.name}」等待您的授权`,
        job.chatId
      ).catch(() => {});
    }
    return new Promise<'allow_once' | 'allow_all' | 'deny'>((resolve) => {
      job.approvalResolver = resolve;
    });
  }

  private async autoGenerateTitle(chatId: string, firstQuestion: string, firstAnswer: string): Promise<void> {
    const clean = await generateAutoChatTitle(
      this.workspace, this.provider(), this.activeModelId(), chatId, firstQuestion, firstAnswer
    );
    if (!clean) return;
    const c = this.workspace.conversations.find((item: Conversation): boolean => item.id === chatId);
    if (c) {
      c.title = clean;
      this.workspace.conversations = this.workspace.conversations.slice();
      this.persistAction();
    }
  }

  private async fetchSuggestions(chatId: string, lastQuestion: string, lastAnswer: string): Promise<void> {
    const lines = await generateChatSuggestions(
      this.workspace, this.provider(), this.activeModelId(), chatId, lastQuestion, lastAnswer
    );
    const c = this.workspace.conversations.find((item: Conversation): boolean => item.id === chatId);
    if (c && lines.length) {
      c.suggestions = lines;
      this.workspace.conversations = this.workspace.conversations.slice();
      this.persistAction();
    }
  }

  async send(retry: boolean = false, fromMessageId: string = ''): Promise<void> {
    if (this.working || this.picking || !this.ready) return;
    if (!retry && !this.draft.trim() && !this.attachedList.length) return;

    const p = this.provider();
    const modelId = this.activeModelId();
    if (!modelId || !isProviderConfigured(p)) {
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
      const hasDraftOverride = this.workspace.modelDefaults?.perChatModel === true && this.draftOverrideProviderId.length > 0;
      c = {
        id: newId(),
        title: (this.draft.trim() || this.attachedList[0]?.name || '新对话').slice(0, 32),
        updated: Date.now(),
        messages: [],
        personaId: this.persona().id,
        ephemeral: this.ephemeralMode,
        imageGenMode: this.imageGenMode,
        overrideProviderId: hasDraftOverride ? this.draftOverrideProviderId : undefined,
        overrideModel: hasDraftOverride ? (this.draftOverrideModel || undefined) : undefined
      };
    }

    const target = c;
    if (this.genRegistry.isGenerating(target.id)) {
      return;
    }

    const wsAtStart = this.workspace;
    const isFirstTurn = !retry && history.length === 1;
    const persona = this.persona();
    const sysPrompt = (target.overridePrompt || persona.prompt || '').trim();
    const params = this.effectiveParams();
    const useSearchOn = this.searchOn;
    const useBuiltinSearch = isBuiltInSearchEnabled(p, modelId);
    const useClaudeDynamicSearch = isClaudeDynamicSearchEnabled(p, modelId);
    const effectiveExternalSearch = useSearchOn && !useBuiltinSearch;
    const useImageGen = this.imageGenMode;
    const useFullAccess = this.fullAccessMode;
    const useBrowserPanel = this.sidePanelMode === 'browser';

    if (!retry) {
      this.workspace.activeConversation = target.id;
      this.putChat({
        id: target.id,
        title: target.title,
        updated: Date.now(),
        personaId: target.personaId,
        ephemeral: target.ephemeral,
        imageGenMode: target.imageGenMode,
        overrideProviderId: target.overrideProviderId,
        overrideModel: target.overrideModel,
        messages: history.slice(),
        draftText: '',
        suggestions: []
      });
      this.draftOverrideProviderId = '';
      this.draftOverrideModel = '';
      this.drafts.delete(target.id);
      this.draft = '';
      this.attachedList = [];
      if (this.quoteDraft !== undefined) {
        SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
          this.quoteDraft = undefined;
        });
      }
      if (!target.ephemeral) {
        this.persistAction();
      }
    }

    const job = new ChatGenerationJob(
      target.id,
      target.title,
      targetReplaceMsg?.id || newId(),
      targetReplaceMsg ? targetReplaceMsg.id : '',
      modelId,
      p.name,
      p.family,
      persona.id
    );
    this.genRegistry.start(job);
    this.followBottom = this.appearanceCfg().autoFollowBottom !== false;
    this.notice = '';
    if (this.expandedReasoning === job.liveMessageId) {
      this.expandedReasoning = '';
    }
    this.lastLiveBodyHeight = 0;
    this.syncActiveGenerationView();
    this.refreshKeepScreenOn();
    backgroundGenerationManager.beginTask(target.id, target.title, this.host());
    triggerHapticFeedback(this.workspace.systemSettings?.hapticsEnabled !== false, 16);

    const isViewingThisChat = (): boolean => this.workspace.activeConversation === target.id;
    const latestChatTitle = (): string =>
      this.workspace.conversations.find((item: Conversation): boolean => item.id === target.id)?.title || target.title;

    let answer = '';
    let thoughts = '';
    let genImages: Attachment[] = [];
    let toolCallsUsed: ToolCallRecord[] = [];
    let replySources: SearchHit[] = [];
    const finalUsage: TokenUsage = { promptTokens: 0, completionTokens: 0, cachedTokens: 0, totalTokens: 0, durationMs: 0 };
    let hasUsage = false;
    let isImageTask = useImageGen;
    const reasoningTimer = new ReplyReasoningTimer();
    const smoother = new StreamTextSmoother(params.responseSpeed || 'standard', this.reduceMotion);
    let toolCallsDirty = false;
    let lastBgNotifyAt = 0;
    let pacerRunning = false;
    let pacerSync: displaySync.DisplaySync | undefined = undefined;
    let pacerTimer: number = -1;
    let lastFrameTsMs = 0;

    const resolveCurrentPhase = (): GenerationPhase => {
      if (isImageTask) return 'image';
      if (job.fetchingSources) return 'searching';
      if (toolCallsUsed.some((tc: ToolCallRecord): boolean => tc.status === 'running' || tc.status === 'pending')) {
        return 'tool';
      }
      if (reasoningTimer.active) return 'thinking';
      return 'streaming';
    };

    const syncReasoningPhase = (): void => {
      job.liveReasoningMs = reasoningTimer.elapsedMs;
      const activeChanged = job.liveThinking !== reasoningTimer.active;
      job.liveThinking = reasoningTimer.active;
      if (!isViewingThisChat()) {
        return;
      }
      if (activeChanged || !job.liveThinking) {
        this.liveReasoningMs = job.liveReasoningMs;
      }
      if (!activeChanged && this.liveThinking === job.liveThinking) {
        return;
      }
      this.liveThinking = job.liveThinking;
      if (this.liveThinking) {
        this.expandedReasoning = job.liveMessageId;
      } else if (this.expandedReasoning === job.liveMessageId) {
        this.expandedReasoning = '';
      }
    };
    const observeFragment = (part: RichFragment): void => {
      reasoningTimer.update(part, Date.now());
      syncReasoningPhase();
    };
    const endReasoning = (): void => {
      reasoningTimer.finish(Date.now());
      syncReasoningPhase();
    };
    const stopFramePacer = (): void => {
      pacerRunning = false;
      lastFrameTsMs = 0;
      if (pacerSync) {
        try { pacerSync.stop(); } catch (_) {}
        try { pacerSync.off('frame'); } catch (_) {}
        pacerSync = undefined;
      }
      if (pacerTimer >= 0) {
        clearInterval(pacerTimer);
        pacerTimer = -1;
      }
    };
    job.frameStop = stopFramePacer;

    const flushBgProgress = (force: boolean): void => {
      const now = Date.now();
      if (!force && now - lastBgNotifyAt < 500) {
        return;
      }
      lastBgNotifyAt = now;
      backgroundGenerationManager.updateTask(
        target.id,
        latestChatTitle(),
        resolveCurrentPhase(),
        answer.length + thoughts.length
      );
    };

    const applyFrame = (dtMs: number): void => {
      if (job.stopped || job.deleted) {
        stopFramePacer();
        return;
      }
      if (!isViewingThisChat() || this.appInBackground) {
        const snapped = smoother.snapToTarget();
        job.liveText = snapped.text;
        job.liveReasoning = snapped.reasoning;
        if (toolCallsDirty) {
          job.liveToolCalls = toolCallsUsed.slice();
          toolCallsDirty = false;
        }
        flushBgProgress(false);
        stopFramePacer();
        return;
      }
      const res = smoother.step(dtMs);
      if (res.textChanged) {
        job.liveText = res.text;
        this.liveText = res.text;
      }
      if (res.reasoningChanged) {
        job.liveReasoning = res.reasoning;
        this.liveReasoning = res.reasoning;
      }
      if (toolCallsDirty) {
        job.liveToolCalls = toolCallsUsed.slice();
        this.liveToolCalls = job.liveToolCalls.slice();
        toolCallsDirty = false;
      }
      flushBgProgress(false);
      if (!res.hasMore && !toolCallsDirty) {
        stopFramePacer();
      }
    };

    const ensureFramePacer = (): void => {
      if (pacerRunning || job.stopped || job.deleted) return;
      pacerRunning = true;
      lastFrameTsMs = 0;
      try {
        const ds = displaySync.create();
        ds.setExpectedFrameRateRange({ min: 30, max: 60, expected: 60 });
        ds.on('frame', (info: displaySync.IntervalInfo) => {
          const nowMs = info.timestamp > 0 ? info.timestamp / 1000000 : Date.now();
          const dt = lastFrameTsMs > 0 ? Math.max(8, nowMs - lastFrameTsMs) : 16;
          lastFrameTsMs = nowMs;
          applyFrame(dt);
        });
        ds.start();
        pacerSync = ds;
      } catch (_) {
        pacerSync = undefined;
        lastFrameTsMs = Date.now();
        pacerTimer = setInterval(() => {
          const nowMs = Date.now();
          const dt = lastFrameTsMs > 0 ? Math.max(8, nowMs - lastFrameTsMs) : 16;
          lastFrameTsMs = nowMs;
          applyFrame(dt);
        }, 16);
      }
    };

    const scheduleLiveUpdate = (): void => {
      smoother.setTarget(answer, thoughts);
      if (!isViewingThisChat() || this.appInBackground) {
        const snapped = smoother.snapToTarget();
        job.liveText = snapped.text;
        job.liveReasoning = snapped.reasoning;
        if (toolCallsDirty) {
          job.liveToolCalls = toolCallsUsed.slice();
          toolCallsDirty = false;
        }
        flushBgProgress(false);
        stopFramePacer();
        return;
      }
      if (smoother.hasPending() || toolCallsDirty) {
        ensureFramePacer();
      }
    };
    let completed = false;
    const startTs = Date.now();
    let authKeyId = '';

    try {
      const question = history[history.length - 1];
      const activeSearch = this.activeSearchService();
      const searchMode = activeSearch?.mode || 'pre_search';
      if (effectiveExternalSearch && searchMode === 'pre_search' && question.text && !question.sources?.length) {
        job.fetchingSources = true;
        if (isViewingThisChat()) this.fetchingSources = true;
        backgroundGenerationManager.updateTask(target.id, latestChatTitle(), 'searching', 0);
        const legacySearch = this.workspace.search;
        const fallbackKey = legacySearch?.kind === 'tavily' ? await readKey(legacySearch.secretRef) : '';
        if (job.stopped) return;
        const searcher = new WebSearch();
        job.searcher = searcher;
        const hits = activeSearch
          ? await searcher.findWithService(activeSearch, fallbackKey, question.text)
          : (legacySearch ? await searcher.find(legacySearch, fallbackKey, question.text) : []);
        if (job.stopped) return;
        const updatedQuestion: ChatMessage = {
          id: question.id, role: question.role, text: question.text, model: question.model,
          attachment: question.attachment, attachments: question.attachments,
          quote: question.quote, createdAt: question.createdAt, sources: hits
        };
        history[history.length - 1] = updatedQuestion;
        const existingConv = this.workspace.conversations.find((item: Conversation): boolean => item.id === target.id);
        if (existingConv && !job.deleted && wsAtStart === this.workspace) {
          existingConv.messages = existingConv.messages.map((m: ChatMessage): ChatMessage =>
            m.id === updatedQuestion.id ? updatedQuestion : m
          );
          this.workspace.conversations = this.workspace.conversations.slice();
        }
        job.fetchingSources = false;
        if (isViewingThisChat()) this.fetchingSources = false;
      }

      const auth = await resolveProviderKeyAndProxy(p);
      authKeyId = auth.keyEntryId;
      if (job.stopped) return;

      const modelSpec = findProviderModelSpec(p, modelId);
      isImageTask = useImageGen || modelSpec.imageGen;
      if (isImageTask) {
        backgroundGenerationManager.updateTask(target.id, latestChatTitle(), 'image', 0);
        const imgs = await generateImages(p, auth.key, question.text || '生成图片', modelId, auth.proxyPass, target.id);
        if (job.stopped) return;
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
        if (job.stopped) return;

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
          templateContext: buildChatTemplateContext(
            this.workspace.userProfile || [], this.persona().name, p.name, modelId, target.title
          )
        });

        const allMcpServers = this.workspace.mcpServers || [];
        const boundMcpIds = persona.mcpServerIds || [];
        const mcpServers = boundMcpIds.length > 0
          ? allMcpServers.filter((s: McpServerConfig): boolean => boundMcpIds.includes(s.id))
          : allMcpServers;
        const mcpToolsRaw = mcpServers.some((s: McpServerConfig): boolean => s.enabled)
          ? await this.mcpManager.discoverEnabledServers(mcpServers)
          : [];
        if (job.stopped) return;
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
        const browserToolsEnabled = useBrowserPanel || enabledDeviceIds.includes('browser_action');
        const hasBoundWorkspace = Boolean(target.workspaceId || persona.workspaceId) && Boolean(this.workspaceForChat(target, persona));
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
          searchEnabled: effectiveExternalSearch,
          builtinFetchEnabled: sysCfg.builtinFetchEnabled && effectiveExternalSearch,
          mcpTools: mcpDescriptors,
          mcpServers,
          extraTools,
          overrides: this.workspace.toolOverrides || []
        }) : [];

        const useStreamMode = persona.streamOutput !== false;

        if (registeredTools.length > 0 || needsMoonshotBuiltinSearchLoop(p, modelId, useBuiltinSearch)) {
          const permMode: ToolPermissionMode = useFullAccess ? 'full' : (target.toolPermissionMode || sysCfg.defaultToolPermission);
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
            builtinSearch: useBuiltinSearch,
            claudeDynamicSearch: useClaudeDynamicSearch,
            tools: registeredTools,
            permissionMode: permMode,
            maxSteps: defaultMaxToolSteps(sysCfg),
            proxy: p.proxy,
            proxyPassword: auth.proxyPass,
            runStream: async (call: ChatCall, onFrag: (f: RichFragment) => void) => {
              const s = new ChatStream();
              job.stream = s;
              await s.runRich(call, (part: RichFragment) => {
                observeFragment(part);
                onFrag(part);
              }, {
                providerName: p.name,
                modelId,
                proxy: p.proxy,
                proxyPassword: auth.proxyPass,
                maxRetries: params.autoRetryCount ?? 2,
                retryBaseMs: params.retryBaseMs ?? 800,
                onLog: (entry: RequestLogEntry) => { this.store?.addRequestLog(entry).catch(() => {}); }
              });
              endReasoning();
            },
            executeTool: (tool: RegisteredTool, argsJson: string) => executeChatRegisteredTool(
              tool, argsJson, target, persona, job, {
                workspace: this.workspace,
                activeSearchService: () => this.activeSearchService(),
                workspaceForChat: (chatArg: Conversation, personaArg: Persona) => this.workspaceForChat(chatArg, personaArg),
                onWorkspaceMutated: () => { this.persistAction(); },
                mcpManager: this.mcpManager,
                browserManager: this.browserManager,
                shouldOpenBrowserPanel: (chatId: string): boolean =>
                  this.wide && this.sidePanelMode === '' && this.workspace.activeConversation === chatId && this.activeRoute === 'chat',
                onOpenBrowserPanel: () => { this.setSidePanelMode('browser'); },
                hostContext: this.host(),
                speaker: this.speaker,
                requestAskUserInput: (jobArg: ChatGenerationJob, req: AskUserPromptRequest) => this.requestAskUserInput(jobArg, req)
              }
            ),
            requestApproval: (tool: RegisteredTool, argsJson: string) => this.requestToolApproval(job, tool, argsJson),
            onUpdate: (lText: string, lReason: string, recs: ToolCallRecord[]) => {
              answer = lText;
              thoughts = lReason;
              const prevCount = toolCallsUsed.length;
              toolCallsUsed = recs;
              if (recs.length > 0 || prevCount > 0) {
                toolCallsDirty = true;
              }
              if (recs.some((r: ToolCallRecord): boolean => r.status === 'pending')) {
                job.liveToolCalls = recs.slice();
                if (isViewingThisChat()) {
                  this.liveToolCalls = job.liveToolCalls.slice();
                }
              }
              scheduleLiveUpdate();
            },
            onContextLog: (payloadJson: string) => {
              if (target.ephemeral) return;
              this.store?.addContextLog({
                id: newId(), ts: Date.now(), conversationId: target.id, model: modelId,
                payloadJson, tokenEstimate: Math.ceil(payloadJson.length / 4)
              }).catch(() => {});
            },
            isStopped: () => job.stopped
          });
          answer = loopOut.text;
          thoughts = loopOut.reasoning;
          toolCallsUsed = loopOut.toolCalls;
          if (loopOut.generatedImages.length) genImages.push(...loopOut.generatedImages);
          if (loopOut.citations.length) replySources = mergeDeduplicatedCitations(replySources, loopOut.citations);
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
            builtinSearch: useBuiltinSearch,
            claudeDynamicSearch: useClaudeDynamicSearch,
            builtinUrlContext: modelSpec.builtinUrlContext !== undefined ? modelSpec.builtinUrlContext : p.builtinUrlContext,
            builtinCodeExec: modelSpec.builtinCodeExec !== undefined ? modelSpec.builtinCodeExec : p.builtinCodeExec
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

          if (job.stopped) return;
          if (isViewingThisChat() && this.activeRoute === 'chat' && !this.appInBackground) {
            this.scrollDown();
          }
          const s = new ChatStream();
          job.stream = s;
          await s.runRich(call, (part: RichFragment) => {
            observeFragment(part);
            answer += part.text;
            thoughts += part.reasoning;
            if (part.generatedImages.length) genImages.push(...part.generatedImages);
            if (part.citations && part.citations.length > 0) {
              replySources = mergeDeduplicatedCitations(replySources, part.citations);
            }
            if (part.usage) {
              finalUsage.promptTokens = part.usage.promptTokens;
              finalUsage.completionTokens = part.usage.completionTokens;
              finalUsage.cachedTokens = part.usage.cachedTokens;
              finalUsage.totalTokens = part.usage.totalTokens;
              hasUsage = true;
            }
            scheduleLiveUpdate();
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
      const errMsg = job.stopped ? '已停止生成' : ((e as Error).message || '请求失败，请检查网络和模型设置');
      if (job.stopped) {
        if (isViewingThisChat() && !job.deleted) {
          this.notice = errMsg;
        }
      } else {
        this.genRegistry.setError(target.id, errMsg);
        if (isViewingThisChat()) {
          this.lastSendError = errMsg;
          this.lastSendErrorChatId = target.id;
        }
        if (this.appInBackground && this.workspace.systemSettings?.backgroundNotifyEnabled !== false && !job.deleted) {
          await notifyGenerationComplete(this.host(), true, latestChatTitle(), '生成未完成：' + errMsg, target.id).catch(() => {});
        }
      }
      if (authKeyId && p.apiKeys?.length && !job.stopped) {
        p.apiKeys = markKeyError(p.apiKeys, authKeyId, 429);
      }
    } finally {
      job.clearTimer();
      endReasoning();
      const durationMs = Date.now() - startTs;
      finalUsage.durationMs = durationMs;
      if (answer.length > 0 && persona.regexRules?.length) {
        answer = applyRegexRules(answer, persona.regexRules, 'output');
      }

      const prevConvState = (!job.deleted && wsAtStart === this.workspace)
        ? this.workspace.conversations.find((item: Conversation): boolean => item.id === target.id)
        : undefined;

      if (prevConvState) {
        const latestTitle = prevConvState.title || target.title;
        const latestPersonaId = prevConvState.personaId || target.personaId;
        if ((answer || genImages.length || toolCallsUsed.length) && (completed || !targetReplaceMsg)) {
          const recordedUsage: TokenUsage | undefined = hasUsage ? finalUsage : undefined;
          let nextMsg: ChatMessage;
          if (targetReplaceMsg) {
            nextMsg = appendMessageVersion(targetReplaceMsg, {
              id: newId(),
              text: answer,
              reasoning: thoughts,
              reasoningDurationMs: reasoningTimer.elapsedMs || undefined,
              model: modelId,
              createdAt: Date.now(),
              usage: recordedUsage,
              toolCalls: toolCallsUsed.length ? toolCallsUsed : undefined,
              generatedImages: genImages.length ? genImages : undefined,
              sources: replySources.length ? replySources : undefined
            });
          } else {
            nextMsg = {
              id: job.liveMessageId,
              role: 'assistant',
              text: answer,
              model: modelId,
              reasoning: thoughts,
              reasoningDurationMs: reasoningTimer.elapsedMs || undefined,
              createdAt: Date.now(),
              usage: recordedUsage,
              toolCalls: toolCallsUsed.length ? toolCallsUsed : undefined,
              generatedImages: genImages.length ? genImages : undefined,
              sources: replySources.length ? replySources : undefined
            };
          }
          const finalMessages = [...history, nextMsg, ...tailMessages];
          const curThrough = prevConvState.memoryOrganizedThrough;
          const rewindThrough = (retry && tailMessages.length === 0 && curThrough &&
            (curThrough === targetReplaceMsg?.id || !finalMessages.some((m: ChatMessage): boolean => m.id === curThrough)))
            ? (history.length >= 2 ? history[history.length - 2].id : '')
            : undefined;
          this.putChat({
            id: target.id, title: latestTitle, updated: Date.now(),
            personaId: latestPersonaId, messages: finalMessages,
            memoryOrganizedThrough: rewindThrough
          });
          if (!target.ephemeral) {
            try { await this.persist(); } catch (_) {
              if (isViewingThisChat()) this.notice = '回复保存在当前页面，写入设备失败';
            }
          }
          if (hasUsage) {
            const day = formatLocalDay(new Date());
            this.store?.recordUsage(day, modelId, latestPersonaId,
              finalUsage.promptTokens, finalUsage.completionTokens, finalUsage.cachedTokens)
              .then(() => { this.refreshUsageStats().catch(() => {}); })
              .catch(() => {});
          }
          if (completed) {
            if (!this.appInBackground && isViewingThisChat() && this.activeRoute === 'chat') {
              triggerHapticFeedback(this.workspace.systemSettings?.hapticsEnabled !== false, 12);
            }
            const notifyEnabled = this.workspace.systemSettings?.backgroundNotifyEnabled !== false;
            const shouldNotify = notifyEnabled && (this.appInBackground || this.activeRoute !== 'chat' || !isViewingThisChat());
            if (shouldNotify) {
              await notifyGenerationComplete(this.host(), true, latestTitle, answer, target.id).catch(() => {});
            }
          }
          if (completed && isFirstTurn && !target.ephemeral) {
            this.autoGenerateTitle(target.id, history[history.length - 1].text, answer);
          }
          if (completed) {
            this.fetchSuggestions(target.id, history[history.length - 1].text, answer);
            if (!target.ephemeral && answer.trim().length > 0 && tailMessages.length === 0) {
              const latestPersona = this.workspace.personas.find((item: Persona): boolean => item.id === latestPersonaId) || persona;
              const latestConvForMem = this.workspace.conversations.find((item: Conversation): boolean => item.id === target.id) || prevConvState;
              this.queueMemoryOrganization(latestConvForMem, latestPersona, { prov: p, model: modelId });
            }
          }
        } else if (targetReplaceMsg) {
          // Restore previous version if regeneration failed
          this.putChat({
            id: target.id, title: latestTitle, updated: Date.now(),
            personaId: latestPersonaId, messages: [...history, targetReplaceMsg, ...tailMessages]
          });
        }
      }

      this.genRegistry.finish(target.id, job);
      if (completed && !job.deleted && wsAtStart === this.workspace) {
        const sysAfter = this.workspace.systemSettings;
        const latestConv = this.workspace.conversations.find((item: Conversation): boolean => item.id === target.id);
        if (sysAfter?.autoCompactEnabled && !target.ephemeral && latestConv) {
          const threshold = Math.max(8, sysAfter.autoCompactThreshold || 36);
          const activeSliceCount = latestConv.messages.length - (latestConv.contextStartIndex || 0);
          if (activeSliceCount >= threshold) {
            this.compressInPlace(sysAfter.compressionTemplate, target.id).catch(() => {});
          }
        }
      }
      this.syncActiveGenerationView();
      this.refreshKeepScreenOn();
      backgroundGenerationManager.endTask(target.id);
      if (isViewingThisChat() && this.activeRoute === 'chat' && !this.appInBackground) {
        this.scrollDown();
      }
    }
  }

  private async compressInPlace(template: string, targetChatId?: string): Promise<void> {
    const c = targetChatId
      ? this.workspace.conversations.find((item: Conversation): boolean => item.id === targetChatId)
      : this.activeChat();
    if (!c || !c.messages.length) return;
    if (this.isChatGenerating(c.id)) {
      if (!targetChatId) this.toast('当前对话正在生成中，请稍候');
      return;
    }
    const compressed = await generateChatCompressionSummary(
      this.workspace, this.provider(), this.activeModelId(), c.messages, template, c.id
    );
    c.messages = applyContextCompression(c.messages, compressed.summary, newId(), compressed.modelId);
    c.updated = Date.now();
    this.workspace.conversations = this.workspace.conversations.slice();
    if (!c.ephemeral) await this.persist();
  }

  private undoCompression(): void {
    const c = this.activeChat();
    if (!c) return;
    if (this.isChatGenerating(c.id)) {
      this.toast('当前对话正在生成中，请稍候');
      return;
    }
    c.messages = undoContextCompression(c.messages);
    this.workspace.conversations = this.workspace.conversations.slice();
    if (!c.ephemeral) this.persistAction();
  }

  private async compressToNewChat(template: string): Promise<void> {
    const c = this.activeChat();
    if (!c || !c.messages.length) return;
    const compressed = await generateChatCompressionSummary(
      this.workspace, this.provider(), this.activeModelId(), c.messages, template, c.id
    );
    const newChat: Conversation = {
      id: newId(),
      title: '续写 · ' + c.title.slice(0, 20),
      updated: Date.now(),
      personaId: c.personaId,
      messages: [{
        id: newId(),
        role: 'assistant',
        text: '【继承自「' + c.title + '」的上下文摘要】\n' + compressed.summary,
        model: compressed.modelId,
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
    if (this.isChatGenerating(c.id)) {
      this.toast('当前对话正在生成中，请稍候');
      return;
    }
    c.messages = c.messages.filter((m: ChatMessage): boolean => m.id !== msgId);
    c.updated = Date.now();
    this.workspace.conversations = this.workspace.conversations.slice();
    if (!c.ephemeral) this.persistAction();
    if (toastMsg) this.toast(toastMsg);
  }

  private deleteActiveMessageVersion(msgId: string): void {
    const c = this.activeChat();
    if (!c) return;
    if (this.isChatGenerating(c.id)) {
      this.toast('当前对话正在生成中，请稍候');
      return;
    }
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
    if (this.isChatGenerating(c.id)) {
      this.toast('当前对话正在生成中，请稍候');
      return;
    }
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
      const out = await translateChatMessageText(
        this.workspace, this.provider(), this.activeModelId(), c.id, target.text
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
    return runChatOcrOnImage(this.workspace, this.provider(), this.activeModelId(), this.activeChat()?.id, dataUri);
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
        this.genRegistry.markDeletedAndStop(c.id);
        this.workspace.conversations = this.workspace.conversations.filter((item: Conversation): boolean => item.id !== c.id);
        if (this.workspace.activeConversation === c.id) { this.workspace.activeConversation = ''; this.draft = ''; this.attachedList = []; }
        this.drafts.delete(c.id);
        this.syncActiveGenerationView();
        this.refreshKeepScreenOn();
        backgroundGenerationManager.endTask(c.id);
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

  private isRegeneratingMessage(msg: ChatMessage): boolean {
    return this.working && this.regeneratingMsgId === msg.id;
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
  liveStreamBody() {
    Column({ space: 8 }) {
      ChatReplyActivityCard({
        messageId: this.liveMessageId,
        reasoning: this.liveReasoning,
        records: this.liveToolCalls,
        thinking: this.liveThinking,
        durationMs: this.liveReasoningMs,
        showThinkingCards: this.chatDisplayCfg().showThinkingCards,
        showToolCards: this.chatDisplayCfg().showToolCards,
        enableReasoningMarkdown: this.appearanceCfg().enableReasoningMarkdown !== false,
        enableMathLatex: this.appearanceCfg().enableMathLatex !== false,
        codeFontSize: this.codeTextSize(),
        tintHex: this.themeTokens().tint,
        isDark: this.effectiveDark(),
        liveMessageId: this.liveMessageId,
        working: this.working,
        pendingApprovalTool: this.pendingApprovalTool,
        pendingApprovalArgs: this.pendingApprovalArgs,
        expandedReasoning: this.expandedReasoning,
        expandedToolId: this.expandedToolId,
        onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => this.openPreview(kind, title, code),
        onOpenUrl: (url: string) => { this.openUrlInBrowser(url); },
        onViewImage: (url: string, alt: string) => this.openImage(url, alt || '图片'),
        onAskDraft: (draftStr: string) => { this.draft = draftStr; },
        onResolveToolApproval: (choice: 'allow_once' | 'allow_all' | 'deny') => this.resolveToolApproval(choice)
      })
      if (this.liveText) {
        MessageBody({
          source: this.liveText,
          bodyFontSize: this.bodyTextSize(),
          codeFontSize: this.codeTextSize(),
          enableMarkdown: this.appearanceCfg().enableAssistantMarkdown !== false,
          enableMathLatex: this.appearanceCfg().enableMathLatex !== false,
          streaming: true,
          onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => this.openPreview(kind, title, code),
          onOpenUrl: (url: string) => { this.openUrlInBrowser(url); },
          onViewImage: (url: string, alt: string) => this.openImage(url, alt || '图片'),
          onAskDraft: (draftStr: string) => { this.draft = draftStr; }
        })
      } else if (!(this.liveReasoning && this.chatDisplayCfg().showThinkingCards) &&
        !(this.liveToolCalls.length && this.chatDisplayCfg().showToolCards)) {
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
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.onLiveStreamAreaChanged(Number(newArea.height) || 0);
    })
  }

  @Builder
  sidebarBody(isOverlay: boolean) {
    ChatSidebarView({
      isOverlay: isOverlay,
      drawerGlobalSearch: this.drawerGlobalSearch,
      query: this.query,
      personaName: this.persona().name,
      personaAvatar: this.persona().avatar || '',
      selectedPersonaIdVal: this.selectedPersonaId(),
      personas: this.workspace.personas,
      chatListRows: this.chatRows(),
      activeConversationId: this.workspace.activeConversation,
      generatingChatIds: this.generatingChatIds,
      userName: this.workspace.userName || '用户',
      newChatLabel: this.uiLabels().newChat,
      translateToolLabel: this.uiLabels().translateTool,
      settingsLabel: this.uiLabels().settings,
      picking: this.picking,
      bottomInset: this.effectiveBottomInset(),
      onCloseDrawer: () => { this.setDrawerOpen(false); },
      onSelectChat: (chatId: string) => { this.activate(chatId); },
      onSelectAssistant: (personaId: string) => { this.selectAssistant(personaId, false); },
      onOpenPersonaDetail: (personaId: string) => {
        this.personaEditTargetId = personaId;
        this.navigateTo('persona_detail');
      },
      onOpenPersonas: () => {
        this.personaEditTargetId = '';
        this.navigateTo('personas');
      },
      onRenameChat: (c: Conversation, titleText: string) => {
        this.putChat({ id: c.id, title: titleText, updated: c.updated, pinned: c.pinned, messages: c.messages, personaId: c.personaId });
        this.persistAction();
      },
      onTogglePinChat: (c: Conversation) => {
        this.putChat({ id: c.id, title: c.title, updated: c.updated, personaId: c.personaId, messages: c.messages, pinned: !c.pinned });
        this.persistAction();
      },
      onDuplicateChat: (c: Conversation) => { this.duplicateChat(c); },
      onMoveChatToNextPersona: (c: Conversation) => { this.moveChatToNextPersona(c); },
      onRemoveChat: (c: Conversation) => { this.removeChat(c); },
      onSaveUserName: (name: string) => {
        this.workspace.userName = name;
        this.persistAction();
      },
      onOpenTranslate: () => {
        this.translateInitialText = '';
        this.navigateTo('translate');
      },
      onOpenSettings: () => {
        this.refreshStorageSize().catch(() => {});
        this.navigateTo('settings');
      }
    })
  }

  @Builder
  drawerOverlay() {
    ChatDrawerOverlay({
      sidebarContent: () => { this.sidebarBody(true); },
      onDismiss: () => { this.setDrawerOpen(false); }
    })
  }

  @Builder
  messageRow(msg: ChatMessage, msgIdx: number) {
    if (msg.role === 'assistant' && this.isRegeneratingMessage(msg)) {
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
              Text(this.persona().useAssistantName
                ? this.persona().name
                : (this.chatDisplayCfg().showProviderAfterModelName && msg.model
                  ? `${msg.model} (${this.provider().name})`
                  : (msg.model || '助手')))
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
            if (this.chatDisplayCfg().showModelTimestamp && formatChatMessageTime(msg.createdAt).length > 0) {
              Text(formatChatMessageTime(msg.createdAt))
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
        }
        this.liveStreamBody()
      }.alignItems(HorizontalAlign.Start).width('100%')
    } else {
      ChatMessageRowView({
        msg: msg,
        msgIdx: msgIdx,
        multiSelectMode: this.multiSelectMode,
        isSelected: this.selectedMsgIds.includes(msg.id),
        working: this.working,
        readingId: this.readingId,
        userName: this.workspace.userName || '用户',
        displayCfg: this.chatDisplayCfg(),
        appearance: this.appearanceCfg(),
        useAssistantAvatar: this.persona().useAssistantAvatar === true,
        useAssistantName: this.persona().useAssistantName === true,
        personaName: this.persona().name,
        personaAvatar: this.persona().avatar || '',
        personaRegexRules: this.persona().regexRules || [],
        providerName: this.provider().name,
        providerFamily: this.provider().family,
        surfaceHex: this.themeTokens().surface,
        tintHex: this.themeTokens().tint,
        isDark: this.effectiveDark(),
        liveMessageId: this.liveMessageId,
        pendingApprovalTool: this.pendingApprovalTool,
        pendingApprovalArgs: this.pendingApprovalArgs,
        expandedReasoning: this.expandedReasoning,
        expandedToolId: this.expandedToolId,
        expandedSources: this.expandedSources,
        expandedLongMsgIds: this.expandedLongMsgIds,
        onToggleSelect: (msgId: string) => this.toggleSelectedMsg(msgId),
        onCopyText: (text: string) => { this.copyText(text); },
        onRegenerate: (msgId: string) => { this.send(true, msgId); },
        onNarrate: (m: ChatMessage) => { this.narrate(m); },
        onTranslate: (msgId: string) => { this.translateMessage(msgId); },
        onOpenActionSheet: (m: ChatMessage) => { this.openMessageActionSheet(m); },
        onSwitchVersion: (msgId: string, delta: number) => { this.switchReplyVersion(msgId, delta); },
        onStartEdit: (m: ChatMessage) => {
          this.editingMsgText = m.text;
          SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
            this.editingMsgId = m.id;
          });
        },
        onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => this.openPreview(kind, title, code),
        onOpenUrl: (url: string) => { this.openUrlInBrowser(url); },
        onViewImage: (url: string, alt: string) => this.openImage(url, alt || '图片'),
        onAskDraft: (draftStr: string) => { this.draft = draftStr; },
        onResolveToolApproval: (choice: 'allow_once' | 'allow_all' | 'deny') => this.resolveToolApproval(choice)
      })
    }
  }

  @Builder
  chatTitleBar() {
    ChatTitleBarView({
      wide: this.wide,
      wideSide: this.wideSide,
      picking: this.picking,
      working: this.working,
      hasOtherGenerating: this.hasOtherGeneratingChat(),
      titleLabel: this.activeChat()?.title || (this.ephemeralMode ? '临时对话' : this.uiLabels().newChat),
      subtitleLabel: `${this.persona().name} · ${this.activeModelId() || this.provider().name}`,
      sidePanelMode: this.sidePanelMode,
      hasActiveMessages: Boolean(this.activeChat()) && (this.activeChat()?.messages.length || 0) > 0,
      ephemeralMode: this.ephemeralMode,
      fullAccessMode: this.fullAccessMode,
      newChatLabel: this.uiLabels().newChat,
      chatBgHex: this.chatBgColor(),
      palette: this.themeTokens(),
      scrollUnderTitle: this.chatCanScrollUnderTitle(),
      onOpenDrawer: () => { this.setDrawerOpen(true); },
      onOpenModelQuickSheet: () => { this.showModelQuickSheet = true; },
      onToggleSidePanel: () => { this.setSidePanelMode(this.sidePanelMode === '' ? 'browser' : ''); },
      onOpenMiniMap: () => { this.showMiniMap = true; },
      onToggleEphemeral: () => { this.activate('', !this.ephemeralMode); },
      onNewChat: () => { this.activate(''); },
      onToggleInChatSearch: () => {
        SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
          this.inChatSearchOpen = !this.inChatSearchOpen;
        });
      },
      onToggleFullAccess: () => {
        this.fullAccessMode = !this.fullAccessMode;
        const c = this.activeChat();
        if (c) { c.toolPermissionMode = this.fullAccessMode ? 'full' : 'ask'; this.persistAction(); }
      },
      onOrganizeMemory: () => { this.organizeCurrentConversation(); },
      onOpenPersonas: () => { this.navigateTo('personas'); },
      onOpenContext: () => { this.navigateTo('context'); },
      onOpenBrowser: () => { this.navigateTo('browser'); },
      onOpenStats: () => { this.refreshUsageStats().catch(() => {}); this.navigateTo('stats'); },
      onOpenSettings: () => { this.refreshStorageSize().catch(() => {}); this.navigateTo('settings'); }
    })
  }

  @Builder
  composerTabBar() {
    ChatComposerView({
      draft: this.draft,
      showPromptQuickBar: this.showPromptQuickBar,
      askQuestionAnswer: this.askQuestionAnswer,
      quoteExcerpt: this.quoteDraft?.excerpt || '',
      attachedList: this.attachedList,
      instructionCards: this.workspace.instructionCards || [],
      activeInstructionIds: this.workspace.activeInstructionIds || [],
      quickPhrases: this.allQuickPhrases(),
      placeholderText: this.composerPlaceholder(),
      working: this.working,
      picking: this.picking,
      enterToSend: this.appearanceCfg().enterToSend === true,
      activeBrandId: this.activeBrandId(),
      providerName: this.provider().name,
      builtinSearchOn: this.currentBuiltinSearchOn(),
      searchOn: this.searchOn,
      reasoningLevelCount: this.activeReasoningControl().levels.length,
      reasoningBulbRays: reasoningBulbRayCount(this.activeReasoningControl(), this.activeReasoningEffort()),
      reasoningEffort: this.activeReasoningEffort(),
      reasoningLabel: this.reasoningLabelShort(),
      showReasoningLevelOnButton: this.chatDisplayCfg().showReasoningLevelOnButton === true,
      fullAccessMode: this.fullAccessMode,
      imageGenMode: this.imageGenMode,
      recording: this.recording,
      stopLabel: this.uiLabels().stop,
      sendLabel: this.uiLabels().send,
      readingId: this.readingId,
      ttsPaused: this.ttsPaused,
      pendingPromptChatId: this.pendingPromptChatId,
      activeConversationId: this.workspace.activeConversation,
      pendingPromptLabel: this.pendingPromptLabel,
      askQuestionText: this.askQuestionText,
      askQuestionOptions: this.askQuestionOptions,
      askQuestionPlaceholder: this.askQuestionPlaceholder,
      pendingApprovalTool: this.pendingApprovalTool,
      pendingApprovalArgs: this.pendingApprovalArgs,
      showToolCards: this.chatDisplayCfg().showToolCards,
      notice: this.notice,
      palette: this.themeTokens(),
      composerBgHex: this.composerBgColor(),
      bubbleStyle: this.appearanceCfg().bubbleStyle,
      chatBgHex: this.chatBgColor(),
      wide: this.wide,
      wideSide: this.wideSide,
      hasSidePanel: this.sidePanelMode !== '',
      bottomInset: this.effectiveBottomInset(),
      onClearQuote: () => {
        SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
          this.quoteDraft = undefined;
        });
      },
      onRemoveAttachment: (idx: number) => {
        this.attachedList = this.attachedList.filter((_a: Attachment, i: number): boolean => i !== idx);
      },
      onToggleInstructionCard: (cardId: string) => {
        const cur = this.workspace.activeInstructionIds || [];
        this.workspace.activeInstructionIds = cur.includes(cardId)
          ? cur.filter((id: string): boolean => id !== cardId)
          : [...cur, cardId];
        this.persistAction();
      },
      onOpenModelQuickSheet: () => { this.showModelQuickSheet = true; },
      onOpenSearchQuickSheet: () => { this.showSearchQuickSheet = true; },
      onOpenReasoningSheet: () => { this.showReasoningSheet = true; },
      onOpenChatToolsSheet: () => { this.showChatToolsSheet = true; },
      onClearImageGenMode: () => { this.imageGenMode = false; },
      onToggleDictation: () => { this.toggleDictation(); },
      onOpenBottomToolsSheet: () => { this.showBottomToolsSheet = true; },
      onSend: () => { this.send(); },
      onStop: () => { this.stopReply(); },
      onToggleTtsPause: () => { this.toggleTtsPause(); },
      onStopTts: () => { this.speaker.stop(); this.readingId = ''; this.ttsPaused = false; },
      onOpenPendingPromptChat: (chatId: string) => { this.activate(chatId); },
      onAskAnswerChanged: (v: string) => {
        const curJob = this.genRegistry.get(this.workspace.activeConversation);
        if (curJob) {
          curJob.askQuestionAnswer = v;
        }
      },
      onSubmitAskAnswer: (ans: string) => { this.submitAskUserInput(ans); },
      onResolveToolApproval: (choice: 'allow_once' | 'allow_all' | 'deny') => this.resolveToolApproval(choice),
      onAreaHeightChange: (heightVp: number) => { this.updateComposerBarHeight(heightVp); }
    })
  }

  @Builder
  chatScrollNavButtons() {
    ChatScrollNavOverlay({
      hasSidePanel: this.sidePanelMode !== '',
      wideSide: this.wideSide,
      composerBarHeightVp: this.composerBarHeightVp,
      surfaceHex: this.themeTokens().surface,
      onJumpTop: () => { this.jumpChatTop(); },
      onJumpPrev: () => { this.jumpChatPrev(); },
      onJumpNext: () => { this.jumpChatNext(); },
      onJumpBottom: () => { this.jumpChatBottom(); }
    })
  }

  @Builder
  chatPane() {
    Stack({
      alignContent: Alignment.Bottom
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
                              : this.activeLiveBrandId(),
                            avatarText: this.persona().useAssistantAvatar ? (this.persona().avatar || '') : '',
                            fallbackLetter: this.persona().useAssistantName ? this.persona().name : this.activeLiveModelLabel(),
                            badgeSize: 22
                          })
                        }
                        if (this.chatDisplayCfg().showModelName) {
                          Text(this.persona().useAssistantName ? this.persona().name : this.activeLiveModelLabel())
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
    ModelSelectSheet({
      palette: this.themeTokens(),
      isDark: this.effectiveDark(),
      onClose: () => { this.showModelQuickSheet = false; },
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
        this.navigateTo('providers');
      }
    })
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
        supportsBuiltinSearch: this.currentSupportsBuiltinSearch(),
        builtinSearchOn: this.currentBuiltinSearchOn(),
        needsResponsesHint: this.currentNeedsResponsesHint(),
        supportsClaudeDynamicSearch: this.currentSupportsClaudeDynamicSearch(),
        claudeDynamicSearchOn: this.currentClaudeDynamicSearchOn(),
        onToggleSearch: (enabled: boolean) => {
          this.setSearchEnabled(enabled);
        },
        onSelectSearchService: (id: string) => {
          this.selectSearchServiceQuick(id);
        },
        onOpenSearchSettings: () => {
          this.showSearchQuickSheet = false;
          this.navigateTo('search');
        },
        onToggleBuiltinSearch: (enabled: boolean) => {
          this.setModelBuiltinSearchEnabled(enabled);
        },
        onToggleClaudeDynamicSearch: (enabled: boolean) => {
          this.setModelClaudeDynamicSearchEnabled(enabled);
        },
        onOpenProviderSettings: () => {
          this.showSearchQuickSheet = false;
          this.navigateTo('providers');
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
        control: this.activeReasoningControl(),
        currentEffort: this.activeReasoningEffort(),
        budgetTokens: reasoningTokens(this.activeReasoningControl(), this.activeReasoningEffort(), this.effectiveParams().reasoningBudget),
        immersiveLightEnabled: this.immersiveLightOn(),
        onSelectEffort: (effort: ReasoningEffort) => {
          this.updateReasoningConfig(effort);
        },
        onChangeBudget: (tokens: number) => {
          this.updateReasoningConfig(this.activeReasoningEffort(), tokens);
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
  messageActionSheetOverlay() {
    ChatMessageActionSheet({
      hasTarget: Boolean(this.actionSheetTargetMessage()),
      isAssistant: this.isActionSheetTargetAssistant(),
      hasMultiVersions: this.actionSheetTargetHasMultiVersions(),
      bottomInset: this.effectiveBottomInset(),
      onAction: (actionKey: string) => { this.runMessageSheetAction(actionKey); }
    })
  }

  @Builder
  miniMapOverlay() {
    ChatMiniMapSheet({
      messages: this.activeChat()?.messages || [],
      palette: this.themeTokens(),
      onClose: () => { this.showMiniMap = false; },
      onJumpTop: () => {
        this.showMiniMap = false;
        this.jumpChatTop();
      },
      onJumpBottom: () => {
        this.showMiniMap = false;
        this.jumpChatBottom();
      },
      onJumpIndex: (idx: number) => {
        this.showMiniMap = false;
        const total = this.activeChat()?.messages.length || 0;
        this.followBottom = idx >= total - 1;
        this.chatNavTargetIdx = idx;
        this.scrollView.scrollToIndex(idx, !this.reduceMotion, ScrollAlign.START);
      }
    })
  }

  @Builder
  editMessageOverlay() {
    ChatEditMessageModal({
      editingMsgText: this.editingMsgText,
      canvasHex: this.themeTokens().canvas,
      bottomInset: this.effectiveBottomInset(),
      onCancel: () => {
        SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
          this.editingMsgId = '';
        });
      },
      onSaveOnly: () => { this.saveEditedMessage(false); },
      onSaveAndRerun: () => { this.saveEditedMessage(true); }
    })
  }

  @Builder
  selectCopyOverlay() {
    ChatSelectCopyModal({
      selectCopyText: this.selectCopyText,
      canvasHex: this.themeTokens().canvas,
      bottomInset: this.effectiveBottomInset(),
      onCopyAll: () => { this.copyText(this.selectCopyText); },
      onClose: () => {
        SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
          this.selectCopyText = '';
        });
      }
    })
  }

  @Builder
  appearanceNavPage(subView: string, titleText: string) {
    KelivoNavRouteShell({
      titleText: titleText,
      canvasColor: this.themeTokens().canvas,
      scrollUnderTitle: true,
      onBack: () => { this.navigateBack(); },
      onRouteShown: () => { this.syncActiveRouteFromStack(); },
      onRouteHidden: () => { this.syncActiveRouteFromStack(); },
      onDismissOverlay: () => this.dismissTopOverlay()
    }) {
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
  }

  @Builder
  providerNavPage(pageMode: 'list' | 'detail', initialProviderId: string) {
    ProviderEditor({
      providers: this.workspace.providers,
      activeId: this.workspace.activeProvider,
      pageMode,
      initialProviderId,
      modelDefaults: this.workspace.modelDefaults || {
        chatProviderId: '', chatModelId: '', titleProviderId: '', titleModelId: '',
        translateProviderId: '', translateModelId: '', ocrProviderId: '', ocrModelId: '',
        memoryProviderId: '', memoryModelId: ''
      },
      onApply: (p: Provider, key: string, reuse: boolean, setActive: boolean) => this.applyProvider(p, key, reuse, setActive),
      onImportProviders: (items: ImportedProvider[]) => this.importProviders(items),
      onDeleteProvider: (id: string) => this.deleteProvider(id),
      onOpenDetail: (pid: string) => {
        this.providerDetailId = pid;
        this.navigateTo('provider_detail');
      },
      onOpenModelEditor: (
        editProv: Provider,
        editSpec: ModelSpec,
        isNew: boolean,
        onSaved: (spec: ModelSpec) => void
      ) => {
        this.modelEditProvider = cloneProvider(editProv);
        this.modelEditSpec = cloneModelSpec(editSpec);
        this.modelEditIsNew = isNew;
        this.modelEditSaveCallback = onSaved;
        this.navigateTo('model_edit');
      },
      onDismissOverlay: () => this.dismissTopOverlay(),
      onRouteShown: () => { this.syncActiveRouteFromStack(); },
      onRouteHidden: () => { this.syncActiveRouteFromStack(); },
      onClose: () => { this.navigateBack(); }
    })
  }

  @Builder
  personaNavPage(pageMode: 'list' | 'detail', initialEditId: string) {
    PersonaEditor({
      personas: this.workspace.personas,
      activeId: this.persona().id,
      pageMode,
      initialEditId,
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
      onOpenDetail: (pid: string) => {
        this.personaEditTargetId = pid;
        this.navigateTo('persona_detail');
      },
      onDismissOverlay: () => this.dismissTopOverlay(),
      onRouteShown: () => { this.syncActiveRouteFromStack(); },
      onRouteHidden: () => { this.syncActiveRouteFromStack(); },
      onClose: () => { this.navigateBack(); }
    })
  }

  @Builder
  routeDestination(name: string, _param: Object) {
    if (name === 'providers') {
      this.providerNavPage('list', '')
    } else if (name === 'provider_detail') {
      this.providerNavPage('detail', this.providerDetailId)
    } else if (name === 'model_edit') {
      ModelSpecEditor({
        provider: this.modelEditProvider,
        initialSpec: this.modelEditSpec,
        isNew: this.modelEditIsNew,
        onSave: (spec: ModelSpec) => {
          if (this.modelEditSaveCallback) {
            this.modelEditSaveCallback(spec);
          }
          this.modelEditSaveCallback = undefined;
          this.navigateBack();
        },
        onCancel: () => {
          this.modelEditSaveCallback = undefined;
          this.navigateBack();
        },
        onDismissOverlay: () => this.dismissTopOverlay(),
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); }
      })
    } else if (name === 'context') {
      ContextSheet({
        chat: this.activeChat(),
        providers: this.workspace.providers,
        activeProviderId: this.provider().id,
        activeModelId: this.activeModelId(),
        systemPrompt: this.persona().prompt,
        params: this.effectiveParams(),
        sysSettings: this.workspace.systemSettings || defaultSystemSettings(),
        onSaveParams: (p: GenerationParams, autoCompact: boolean, threshold: number, template: string) => {
          this.workspace.generationParams = p;
          const persona = this.persona();
          if (persona.params?.reasoningEffort) {
            persona.params.reasoningEffort = p.reasoningEffort;
            persona.params.reasoningBudget = p.reasoningBudget;
          }
          this.modelConfigTick += 1;
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
            this.modelConfigTick += 1;
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
      this.personaNavPage('list', '')
    } else if (name === 'persona_detail') {
      this.personaNavPage('detail', this.personaEditTargetId)
    } else if (name === 'tools') {
      KelivoNavRouteShell({
        titleText: 'MCP 工具中心',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: true,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
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
    } else if (name === 'voice') {
      KelivoNavRouteShell({
        titleText: '语音朗读与识别',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: true,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
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
    } else if (name === 'webdav') {
      KelivoNavRouteShell({
        titleText: '备份与恢复',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: true,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
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
            this.stopAllGenerations(true);
            backgroundGenerationManager.stopAll();
            this.workspace = nextWs;
            this.workspace.globalProxy = normalizeProxyConfig(this.workspace.globalProxy, true);
            this.workspace.worldBooks = normalizeWorldBooks(this.workspace.worldBooks);
            const normCards = normalizeInstructionCards(this.workspace.instructionCards);
            this.workspace.instructionCards = normCards.length > 0 ? normCards : defaultInstructionCards();
            const normPhrases = normalizeQuickPhrases(this.workspace.quickPhrases);
            this.workspace.quickPhrases = normPhrases.length > 0 ? normPhrases : defaultQuickPhrases();
            this.draftOverrideProviderId = '';
            this.draftOverrideModel = '';
            this.modelConfigTick += 1;
            this.searchOn = this.workspace.systemSettings?.searchEnabled === true;
            applySystemColorMode(this.host(), this.appearanceCfg().themeMode);
            syncWindowSystemBars(this.effectiveDark());
            syncWindowBackgroundColor(this.themeTokens().canvas);
            this.syncImmersiveStorage();
            await this.syncGlobalProxyRuntime();
            this.syncActiveGenerationView();
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
    } else if (name === 'search') {
      KelivoNavRouteShell({
        titleText: '联网搜索',
        subtitleText: '26 种搜索引擎 · Agent 工具 / 预检索',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: true,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
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
            this.refreshUsageStats().catch(() => {});
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
            this.navigateTo('providers');
          } else if (route === 'networkProxy' || route === 'providers_proxy') {
            this.navigateTo('networkProxy');
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
      KelivoNavRouteShell({
        titleText: '默认模型',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: true,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
        DefaultModelPanel({
          providers: this.workspace.providers,
          modelDefaults: this.workspace.modelDefaults,
          chatSuggestionsEnabled: this.workspace.systemSettings?.chatSuggestionsEnabled === true,
          immersiveLightEnabled: this.immersiveLightOn(),
          embeddedInNav: true,
          onSaveDefaults: async (next: ModelDefaults) => {
            this.workspace.modelDefaults = next;
            this.modelConfigTick += 1;
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
    } else if (name === 'about') {
      KelivoNavRouteShell({
        titleText: '关于 Kelivo',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: true,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
        AboutPanel({
          providerCount: this.workspace.providers.length,
          conversationCount: this.workspace.conversations.length,
          embeddedInNav: true,
          onClose: () => { this.navigateBack(); }
        })
      }
    } else if (name === 'networkProxy') {
      KelivoNavRouteShell({
        titleText: '网络代理',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: true,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
        NetworkProxyPanel({
          globalProxy: this.workspace.globalProxy || defaultGlobalProxy(),
          initialPassword: this.globalProxyPasswordPlain,
          immersiveLightEnabled: this.immersiveLightOn(),
          embeddedInNav: true,
          onSaveGlobalProxy: async (next: ProxyConfig, passwordPlain: string) => {
            const normalized = normalizeProxyConfig(next, true);
            const existingRef = this.workspace.globalProxy?.passwordRef || normalized.passwordRef || '';
            if (passwordPlain.length > 0) {
              const ref = existingRef || newId();
              await storeKey(ref, passwordPlain);
              normalized.passwordRef = ref;
            } else {
              if (existingRef) {
                await forgetKey(existingRef).catch(() => {});
              }
              normalized.passwordRef = undefined;
            }
            this.workspace.globalProxy = normalized;
            this.globalProxyPasswordPlain = passwordPlain;
            setGlobalHttpProxy(normalized, passwordPlain);
            await this.persist();
          },
          onClose: () => { this.navigateBack(); }
        })
      }
    } else if (name === 'promptTools') {
      KelivoNavRouteShell({
        titleText: this.promptToolsNavTitle(),
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: false,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
        PromptToolsPanel({
          worldBooks: normalizeWorldBooks(this.workspace.worldBooks || []),
          instructionCards: normalizeInstructionCards(this.workspace.instructionCards || defaultInstructionCards()),
          activeInstructionIds: this.workspace.activeInstructionIds || [],
          quickPhrases: normalizeQuickPhrases(this.workspace.quickPhrases || defaultQuickPhrases()),
          initialTab: this.promptTabInit,
          embeddedInNav: true,
          onSaveWorldBooks: async (books: WorldBook[]) => {
            this.workspace.worldBooks = normalizeWorldBooks(books);
            await this.persist();
          },
          onSaveInstructionCards: async (cards: InstructionCard[], activeIds: string[]) => {
            this.workspace.instructionCards = normalizeInstructionCards(cards);
            this.workspace.activeInstructionIds = activeIds;
            await this.persist();
          },
          onSaveQuickPhrases: async (phrases: QuickPhrase[]) => {
            this.workspace.quickPhrases = normalizeQuickPhrases(phrases);
            await this.persist();
          },
          onInsertPhrase: (content: string) => {
            this.draft = this.draft.trim().length > 0 ? `${this.draft}\n${content}` : content;
          },
          onClose: () => { this.navigateBack(); }
        })
      }
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
          this.modelConfigTick += 1;
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
      KelivoNavRouteShell({
        titleText: '双语划词翻译',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: true,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
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
    } else if (name === 'stats') {
      KelivoNavRouteShell({
        titleText: 'Token 用量统计与热力图',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: true,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => {
          this.syncActiveRouteFromStack();
          this.refreshUsageStats().catch(() => {});
        },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
        StatsPanel({
          usageStats: this.usageStats,
          personas: this.workspace.personas,
          embeddedInNav: true,
          onRefresh: () => this.refreshUsageStats(),
          onClose: () => { this.navigateBack(); }
        })
      }
    } else if (name === 'diagnostics') {
      KelivoNavRouteShell({
        titleText: '调试诊断与存储分析',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: false,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
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
      KelivoNavRouteShell({
        titleText: 'Agent Skills 技能包',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: false,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
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
    } else if (name === 'workspace') {
      KelivoNavRouteShell({
        titleText: '本地沙箱工作区',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: false,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
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
    } else if (name === 'browser') {
      KelivoNavRouteShell({
        titleText: '内置浏览器',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: false,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
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
    } else if (name === 'schedules') {
      KelivoNavRouteShell({
        titleText: '自动化定时任务',
        canvasColor: this.themeTokens().canvas,
        scrollUnderTitle: true,
        onBack: () => { this.navigateBack(); },
        onRouteShown: () => { this.syncActiveRouteFromStack(); },
        onRouteHidden: () => { this.syncActiveRouteFromStack(); },
        onDismissOverlay: () => this.dismissTopOverlay()
      }) {
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
                ChatWideSidePanel({
                  sidePanelMode: this.sidePanelMode,
                  browserManager: this.browserManager,
                  workspaces: this.workspace.workspaces || [],
                  activeWorkspaceId: this.activeWorkspaceForChat()?.id || '',
                  envVars: this.workspace.envVars || [],
                  filesDir: this.filesDirPath,
                  bookmarks: this.workspace.browserBookmarks || [],
                  bottomInset: this.effectiveBottomInset(),
                  onChangeMode: (mode: '' | 'browser' | 'workspace') => { this.setSidePanelMode(mode); },
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
                  onSaveBookmarks: async (list: BrowserBookmark[]) => {
                    this.workspace.browserBookmarks = list;
                    await this.persist();
                  },
                  onExtractToChat: (title: string, text: string) => {
                    this.attachedList = [...this.attachedList, { name: `${title.slice(0, 24)}.txt`, data: text, mime: 'text/plain', kind: 'text' }];
                  }
                })
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
          ImmersiveMaterialStyle.chatListSheetOptions(
            this.immersiveLightOn(),
            this.themeTokens().surface,
            () => { this.showModelQuickSheet = false; }
          )
        )

      Column()
        .width(0)
        .height(0)
        .bindSheet(
          $$this.showMiniMap,
          this.miniMapOverlay(),
          ImmersiveMaterialStyle.chatListSheetOptions(
            this.immersiveLightOn(),
            this.themeTokens().surface,
            () => { this.showMiniMap = false; }
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
