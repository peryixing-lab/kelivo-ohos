import {
  ApiKeyEntry,
  BackupScopeConfig,
  Conversation,
  EnvVar,
  InstructionCard,
  LocalWorkspace,
  McpServerConfig,
  MemoryEntry,
  Persona,
  Provider,
  QuickPhrase,
  SearchServiceConfig,
  SkillRecord,
  WorldBook,
  Workspace,
  normalizeBackupScope,
  normalizeInstructionCards,
  normalizeProxyConfig,
  normalizeProxyType,
  normalizeQuickPhrases,
  normalizeWorldBooks
} from './Models';
import {
  normalizeMemoryEntries,
  normalizeMemorySettings,
  normalizeUserProfileFields
} from './MemoryLogic';
import { ApplyRestoreOutput, ParsedBackupData } from './BackupCodecTypes';

export function applyScopedRestore(
  current: Workspace,
  incoming: ParsedBackupData,
  rawScope: BackupScopeConfig,
  mode: 'overwrite' | 'merge',
  makeRefId: () => string
): ApplyRestoreOutput {
  const scope = normalizeBackupScope(rawScope);
  const srcScope = incoming.sourceScope ? normalizeBackupScope(incoming.sourceScope) : undefined;
  const allowCategory = (selected: boolean, hasPayload: boolean, srcEnabled?: boolean): boolean => {
    if (!selected || !hasPayload) return false;
    if (srcEnabled === false) return false;
    return true;
  };

  const outSecrets: Record<string, string> = {};
  const remapRef = (oldRef: string | undefined, sameDeviceFallback: boolean): string => {
    if (!oldRef) return '';
    const secretVal = incoming.secretsToStore[oldRef];
    if (secretVal !== undefined && secretVal.length > 0) {
      const fresh = makeRefId();
      outSecrets[fresh] = secretVal;
      return fresh;
    }
    return sameDeviceFallback ? oldRef : '';
  };
  const isHarmonySource = incoming.sourceName.indexOf('Harmony') >= 0 || incoming.sourceName.indexOf('ArkUI') >= 0;

  // Clone base workspace keeping all existing data & local-only security config untouched by default
  const next: Workspace = {
    version: current.version,
    providers: current.providers.slice(),
    personas: current.personas.slice(),
    conversations: current.conversations.slice(),
    search: current.search,
    searchServices: current.searchServices ? current.searchServices.slice() : [],
    activeSearchId: current.activeSearchId,
    globalProxy: current.globalProxy,
    mcpEndpoint: current.mcpEndpoint,
    mcpServers: current.mcpServers ? current.mcpServers.slice() : [],
    davDirectory: current.davDirectory,
    davPath: current.davPath,
    davFilename: current.davFilename,
    davUsername: current.davUsername,
    davPasswordRef: current.davPasswordRef,
    davUserAgent: current.davUserAgent,
    s3Config: current.s3Config,
    backupConfig: current.backupConfig,
    activeProvider: current.activeProvider,
    activeConversation: current.activeConversation,
    generationParams: current.generationParams,
    modelDefaults: current.modelDefaults,
    tts: current.tts,
    asr: current.asr,
    memories: current.memories ? current.memories.slice() : [],
    userProfile: current.userProfile ? current.userProfile.slice() : [],
    memoryTraces: current.memoryTraces ? current.memoryTraces.slice() : [],
    memorySettings: current.memorySettings,
    worldBooks: current.worldBooks ? current.worldBooks.slice() : [],
    instructionCards: current.instructionCards ? current.instructionCards.slice() : [],
    activeInstructionIds: current.activeInstructionIds ? current.activeInstructionIds.slice() : [],
    quickPhrases: current.quickPhrases ? current.quickPhrases.slice() : [],
    skills: current.skills ? current.skills.slice() : [],
    workspaces: current.workspaces ? current.workspaces.slice() : [],
    envVars: current.envVars ? current.envVars.slice() : [],
    scheduledTasks: current.scheduledTasks ? current.scheduledTasks.slice() : [],
    browserBookmarks: current.browserBookmarks ? current.browserBookmarks.slice() : [],
    appearance: current.appearance,
    systemSettings: current.systemSettings,
    toolOverrides: current.toolOverrides ? current.toolOverrides.slice() : [],
    snapshots: current.snapshots ? current.snapshots.slice() : [],
    userName: current.userName,
    favoriteModels: current.favoriteModels ? current.favoriteModels.slice() : []
  };

  let importedChats = 0;
  let importedMsgs = 0;
  let importedProviders = 0;
  let importedAssistants = 0;

  // 1. Chats
  if (allowCategory(scope.chats, Array.isArray(incoming.conversations), srcScope?.chats)) {
    const incChats = incoming.conversations || [];
    if (mode === 'overwrite') {
      next.conversations = incChats.slice();
      importedChats = incChats.length;
      for (let i = 0; i < incChats.length; i++) importedMsgs += incChats[i].messages.length;
    } else {
      const byId = new Map<string, Conversation>();
      for (let i = 0; i < next.conversations.length; i++) byId.set(next.conversations[i].id, next.conversations[i]);
      const list = next.conversations.slice();
      for (let i = 0; i < incChats.length; i++) {
        const inc = incChats[i];
        const existing = byId.get(inc.id);
        if (!existing) {
          byId.set(inc.id, inc);
          list.push(inc);
          importedChats++;
          importedMsgs += inc.messages.length;
        } else {
          const sameLen = existing.messages.length === inc.messages.length;
          const sameLast = !sameLen || existing.messages.length === 0 ||
            existing.messages[existing.messages.length - 1].text === inc.messages[inc.messages.length - 1].text;
          if (sameLen && sameLast) continue;
          const remappedId = 'conv-' + makeRefId();
          const cloned: Conversation = {
            id: remappedId,
            title: inc.title,
            updated: inc.updated,
            pinned: inc.pinned,
            messages: inc.messages,
            personaId: inc.personaId,
            contextStartIndex: inc.contextStartIndex,
            memoryOrganizedThrough: inc.memoryOrganizedThrough,
            overrideProviderId: inc.overrideProviderId,
            overrideModel: inc.overrideModel,
            overridePrompt: inc.overridePrompt,
            enabledMcpIds: inc.enabledMcpIds,
            enabledSkillIds: inc.enabledSkillIds,
            workspaceId: inc.workspaceId,
            toolPermissionMode: inc.toolPermissionMode,
            suggestions: inc.suggestions
          };
          byId.set(remappedId, cloned);
          list.push(cloned);
          importedChats++;
          importedMsgs += inc.messages.length;
        }
      }
      next.conversations = list;
    }
  }

  // 2. Providers + Secrets
  const cloneIncomingProvider = (p: Provider): Provider => {
    const newPool: ApiKeyEntry[] = [];
    if (p.apiKeys) {
      for (let k = 0; k < p.apiKeys.length; k++) {
        const ak = p.apiKeys[k];
        const nr = remapRef(ak.secretRef, isHarmonySource);
        if (nr || isHarmonySource) {
          newPool.push({
            id: ak.id,
            label: ak.label,
            secretRef: nr,
            priority: ak.priority,
            usageCount: ak.usageCount,
            errorCount: ak.errorCount,
            disabledUntil: ak.disabledUntil
          });
        }
      }
    }
    return {
      id: p.id,
      name: p.name,
      family: p.family,
      baseUrl: p.baseUrl,
      chatPath: p.chatPath,
      model: p.model,
      secretRef: remapRef(p.secretRef, isHarmonySource),
      models: p.models ? p.models.slice() : [],
      apiKeys: newPool,
      keyStrategy: p.keyStrategy,
      groupName: p.groupName,
      proxy: p.proxy ? {
        enabled: p.proxy.enabled,
        type: normalizeProxyType(p.proxy.type),
        host: p.proxy.host,
        port: p.proxy.port,
        username: p.proxy.username,
        passwordRef: remapRef(p.proxy.passwordRef, isHarmonySource) || undefined,
        bypass: p.proxy.bypass
      } : undefined,
      customHeaders: p.customHeaders ? p.customHeaders.slice() : undefined,
      customBodyJson: p.customBodyJson,
      promptCaching: p.promptCaching,
      sendConversationCacheKey: p.sendConversationCacheKey,
      balanceUrl: p.balanceUrl,
      lastBalance: p.lastBalance,
      builtinSearch: p.builtinSearch,
      builtinUrlContext: p.builtinUrlContext,
      builtinCodeExec: p.builtinCodeExec,
      builtinImageGen: p.builtinImageGen,
      oauth: p.oauth ? {
        kind: p.oauth.kind,
        accountEmail: p.oauth.accountEmail,
        accessTokenRef: remapRef(p.oauth.accessTokenRef, isHarmonySource),
        refreshTokenRef: remapRef(p.oauth.refreshTokenRef, isHarmonySource),
        expiresAt: p.oauth.expiresAt,
        quotaSummary: p.oauth.quotaSummary
      } : undefined,
      enabled: p.enabled !== false
    };
  };

  if (allowCategory(scope.providers, Array.isArray(incoming.providers), srcScope?.providers)) {
    const incProvs = incoming.providers || [];
    const prepared: Provider[] = [];
    for (let i = 0; i < incProvs.length; i++) {
      prepared.push(cloneIncomingProvider(incProvs[i]));
    }
    if (mode === 'overwrite') {
      if (prepared.length > 0) {
        next.providers = prepared;
        importedProviders = prepared.length;
        if (incoming.activeProvider) next.activeProvider = incoming.activeProvider;
      }
      if (incoming.favoriteModels) next.favoriteModels = incoming.favoriteModels.slice();
    } else {
      const byId = new Map<string, number>();
      for (let i = 0; i < next.providers.length; i++) byId.set(next.providers[i].id, i);
      for (let i = 0; i < prepared.length; i++) {
        const inc = prepared[i];
        const idx = byId.get(inc.id);
        if (idx === undefined) {
          byId.set(inc.id, next.providers.length);
          next.providers.push(inc);
          importedProviders++;
        } else {
          // If existing provider had no key at all and incoming brings a configured key, enrich it cleanly
          const cur = next.providers[idx];
          if (!cur.secretRef && (!cur.apiKeys || cur.apiKeys.length === 0) && (inc.secretRef || (inc.apiKeys && inc.apiKeys.length > 0))) {
            next.providers[idx] = inc;
            importedProviders++;
          }
        }
      }
      if (incoming.favoriteModels && incoming.favoriteModels.length > 0) {
        const favSet = new Set<string>(next.favoriteModels || []);
        for (let i = 0; i < incoming.favoriteModels.length; i++) favSet.add(incoming.favoriteModels[i]);
        next.favoriteModels = Array.from(favSet);
      }
    }
  }

  // 3. Assistants
  if (allowCategory(scope.assistants, Array.isArray(incoming.personas), srcScope?.assistants)) {
    const incAssts = incoming.personas || [];
    if (mode === 'overwrite' && incAssts.length > 0) {
      next.personas = incAssts.slice();
      importedAssistants = incAssts.length;
    } else {
      const seen = new Set<string>(next.personas.map((p: Persona): string => p.id));
      for (let i = 0; i < incAssts.length; i++) {
        if (!seen.has(incAssts[i].id)) {
          seen.add(incAssts[i].id);
          next.personas.push(incAssts[i]);
          importedAssistants++;
        }
      }
    }
  }

  // 4. MCP Servers
  if (allowCategory(scope.mcp, Array.isArray(incoming.mcpServers), srcScope?.mcp)) {
    const incMcp = incoming.mcpServers || [];
    const preparedMcp: McpServerConfig[] = [];
    for (let i = 0; i < incMcp.length; i++) {
      const m = incMcp[i];
      preparedMcp.push({
        id: m.id,
        name: m.name,
        transport: m.transport,
        endpoint: m.endpoint,
        bearerSecretRef: remapRef(m.bearerSecretRef, isHarmonySource),
        customHeaders: m.customHeaders ? m.customHeaders.slice() : [],
        oauthAccessTokenRef: remapRef(m.oauthAccessTokenRef, isHarmonySource) || undefined,
        enabled: m.enabled,
        disabledTools: m.disabledTools ? m.disabledTools.slice() : [],
        autoApproveTools: m.autoApproveTools ? m.autoApproveTools.slice() : []
      });
    }
    if (mode === 'overwrite') {
      next.mcpServers = preparedMcp;
      if (incoming.mcpEndpoint !== undefined) next.mcpEndpoint = incoming.mcpEndpoint;
    } else {
      const seen = new Set<string>((next.mcpServers || []).map((m: McpServerConfig): string => m.id));
      for (let i = 0; i < preparedMcp.length; i++) {
        if (!seen.has(preparedMcp[i].id)) {
          seen.add(preparedMcp[i].id);
          next.mcpServers!.push(preparedMcp[i]);
        }
      }
    }
  }

  // 5. Env Vars
  if (allowCategory(scope.envVars, Array.isArray(incoming.envVars), srcScope?.envVars)) {
    const incEnv = incoming.envVars || [];
    const preparedEnv: EnvVar[] = [];
    for (let i = 0; i < incEnv.length; i++) {
      const e = incEnv[i];
      const nr = remapRef(e.secretRef, isHarmonySource);
      if (!nr) continue;
      preparedEnv.push({ id: e.id, key: e.key, secretRef: nr, masked: e.masked });
    }
    if (mode === 'overwrite') {
      next.envVars = preparedEnv;
    } else {
      const seenKeys = new Set<string>((next.envVars || []).map((e: EnvVar): string => e.key));
      for (let i = 0; i < preparedEnv.length; i++) {
        if (!seenKeys.has(preparedEnv[i].key)) {
          seenKeys.add(preparedEnv[i].key);
          next.envVars!.push(preparedEnv[i]);
        }
      }
    }
  }

  // 6. Skills
  if (allowCategory(scope.skills, Array.isArray(incoming.skills), srcScope?.skills)) {
    const incSkills = incoming.skills || [];
    if (mode === 'overwrite') {
      next.skills = incSkills.slice();
    } else {
      const seen = new Set<string>((next.skills || []).map((s: SkillRecord): string => s.id));
      for (let i = 0; i < incSkills.length; i++) {
        if (!seen.has(incSkills[i].id)) {
          seen.add(incSkills[i].id);
          next.skills!.push(incSkills[i]);
        }
      }
    }
  }

  // 7. WorldBooks
  if (allowCategory(scope.worldBooks, Array.isArray(incoming.worldBooks), srcScope?.worldBooks)) {
    const incWb = normalizeWorldBooks(incoming.worldBooks || []);
    if (mode === 'overwrite') {
      next.worldBooks = incWb.slice();
    } else {
      next.worldBooks = normalizeWorldBooks(next.worldBooks);
      const seen = new Set<string>((next.worldBooks || []).map((w: WorldBook): string => w.id));
      for (let i = 0; i < incWb.length; i++) {
        if (!seen.has(incWb[i].id)) {
          seen.add(incWb[i].id);
          next.worldBooks!.push(incWb[i]);
        }
      }
    }
  }

  // 8. Memory + UserProfile + Settings
  if (allowCategory(scope.memory, Array.isArray(incoming.memories) || Array.isArray(incoming.userProfile) || Boolean(incoming.memorySettings),
    srcScope?.memory)) {
    if (Array.isArray(incoming.memories)) {
      const normIncMems = normalizeMemoryEntries(incoming.memories);
      if (mode === 'overwrite') {
        next.memories = normIncMems;
      } else {
        const seen = new Set<string>((next.memories || []).map((m: MemoryEntry): string => m.id));
        for (let i = 0; i < normIncMems.length; i++) {
          if (!seen.has(normIncMems[i].id)) {
            seen.add(normIncMems[i].id);
            next.memories!.push(normIncMems[i]);
          }
        }
      }
    }
    if (Array.isArray(incoming.userProfile)) {
      const normIncProf = normalizeUserProfileFields(incoming.userProfile);
      if (mode === 'overwrite') {
        next.userProfile = normIncProf;
      } else {
        next.userProfile = normalizeUserProfileFields((next.userProfile || []).concat(normIncProf));
      }
    }
    if (incoming.memorySettings) {
      if (mode === 'overwrite' || !next.memorySettings) {
        next.memorySettings = normalizeMemorySettings(incoming.memorySettings);
      } else {
        const cur = normalizeMemorySettings(next.memorySettings);
        const inc = normalizeMemorySettings(incoming.memorySettings);
        next.memorySettings = {
          autoExtract: cur.autoExtract,
          injectGlobal: cur.injectGlobal,
          maxInjectCount: inc.maxInjectCount || cur.maxInjectCount,
          useLegacyMemory: inc.useLegacyMemory ?? cur.useLegacyMemory,
          enableThinking: inc.enableThinking ?? cur.enableThinking,
          promptLanguage: inc.promptLanguage || cur.promptLanguage,
          recordTraces: inc.recordTraces ?? cur.recordTraces,
          templates: inc.templates || cur.templates,
          legacyMemories: inc.legacyMemories || cur.legacyMemories
        };
      }
    }
    if (incoming.modelDefaults?.memoryProviderId && incoming.modelDefaults?.memoryModelId) {
      const curMd = next.modelDefaults;
      if (curMd) {
        if (mode === 'overwrite' || !curMd.memoryProviderId) {
          next.modelDefaults = {
            chatProviderId: curMd.chatProviderId,
            chatModelId: curMd.chatModelId,
            perChatModel: curMd.perChatModel,
            titleProviderId: curMd.titleProviderId,
            titleModelId: curMd.titleModelId,
            summaryProviderId: curMd.summaryProviderId,
            summaryModelId: curMd.summaryModelId,
            suggestionsProviderId: curMd.suggestionsProviderId,
            suggestionsModelId: curMd.suggestionsModelId,
            compressProviderId: curMd.compressProviderId,
            compressModelId: curMd.compressModelId,
            translateProviderId: curMd.translateProviderId,
            translateModelId: curMd.translateModelId,
            ocrProviderId: curMd.ocrProviderId,
            ocrModelId: curMd.ocrModelId,
            memoryProviderId: incoming.modelDefaults.memoryProviderId,
            memoryModelId: incoming.modelDefaults.memoryModelId
          };
        }
      } else {
        next.modelDefaults = {
          chatProviderId: '',
          chatModelId: '',
          titleProviderId: '',
          titleModelId: '',
          translateProviderId: '',
          translateModelId: '',
          ocrProviderId: '',
          ocrModelId: '',
          memoryProviderId: incoming.modelDefaults.memoryProviderId,
          memoryModelId: incoming.modelDefaults.memoryModelId
        };
      }
    }
  }

  // 9. Quick Phrases
  if (allowCategory(scope.quickPhrases, Array.isArray(incoming.quickPhrases), srcScope?.quickPhrases)) {
    const incQp = normalizeQuickPhrases(incoming.quickPhrases || []);
    if (mode === 'overwrite') {
      next.quickPhrases = incQp.slice();
    } else {
      next.quickPhrases = normalizeQuickPhrases(next.quickPhrases);
      const seen = new Set<string>((next.quickPhrases || []).map((q: QuickPhrase): string => q.id));
      for (let i = 0; i < incQp.length; i++) {
        if (!seen.has(incQp[i].id)) {
          seen.add(incQp[i].id);
          next.quickPhrases!.push(incQp[i]);
        }
      }
    }
  }

  // 10. Instruction Cards
  if (allowCategory(scope.instructions, Array.isArray(incoming.instructionCards), srcScope?.instructions)) {
    const incCards = normalizeInstructionCards(incoming.instructionCards || []);
    if (mode === 'overwrite') {
      next.instructionCards = incCards.slice();
      if (incoming.activeInstructionIds) next.activeInstructionIds = incoming.activeInstructionIds.slice();
    } else {
      next.instructionCards = normalizeInstructionCards(next.instructionCards);
      const seen = new Set<string>((next.instructionCards || []).map((c: InstructionCard): string => c.id));
      for (let i = 0; i < incCards.length; i++) {
        if (!seen.has(incCards[i].id)) {
          seen.add(incCards[i].id);
          next.instructionCards!.push(incCards[i]);
        }
      }
    }
  }

  // 11. Workspaces
  if (allowCategory(scope.workspaces, Array.isArray(incoming.workspaces), srcScope?.workspaces)) {
    const incWs = incoming.workspaces || [];
    if (mode === 'overwrite') {
      next.workspaces = incWs.slice();
    } else {
      const seen = new Set<string>((next.workspaces || []).map((w: LocalWorkspace): string => w.id));
      for (let i = 0; i < incWs.length; i++) {
        if (!seen.has(incWs[i].id)) {
          seen.add(incWs[i].id);
          next.workspaces!.push(incWs[i]);
        }
      }
    }
  }

  // 12. Search Services
  if (allowCategory(scope.search, Array.isArray(incoming.searchServices), srcScope?.search)) {
    const incSearch = incoming.searchServices || [];
    const preparedSearch: SearchServiceConfig[] = [];
    for (let i = 0; i < incSearch.length; i++) {
      const s = incSearch[i];
      const newKeys: ApiKeyEntry[] = [];
      for (let k = 0; k < s.apiKeys.length; k++) {
        const nr = remapRef(s.apiKeys[k].secretRef, isHarmonySource);
        if (nr || isHarmonySource) {
          newKeys.push({
            id: s.apiKeys[k].id,
            label: s.apiKeys[k].label,
            secretRef: nr,
            priority: s.apiKeys[k].priority,
            usageCount: s.apiKeys[k].usageCount,
            errorCount: s.apiKeys[k].errorCount,
            disabledUntil: s.apiKeys[k].disabledUntil
          });
        }
      }
      preparedSearch.push({
        id: s.id,
        kind: s.kind,
        name: s.name,
        endpoint: s.endpoint,
        apiKeys: newKeys,
        keyStrategy: s.keyStrategy,
        maxResults: s.maxResults,
        enabled: s.enabled,
        mode: s.mode,
        webFetchEnabled: s.webFetchEnabled
      });
    }
    if (mode === 'overwrite') {
      next.searchServices = preparedSearch;
      if (incoming.activeSearchId) next.activeSearchId = incoming.activeSearchId;
    } else {
      const seen = new Set<string>((next.searchServices || []).map((s: SearchServiceConfig): string => s.id));
      for (let i = 0; i < preparedSearch.length; i++) {
        if (!seen.has(preparedSearch[i].id)) {
          seen.add(preparedSearch[i].id);
          next.searchServices!.push(preparedSearch[i]);
        }
      }
    }
  }

  // 13. Speech Services (TTS / ASR)
  if (allowCategory(scope.speech, Boolean(incoming.tts || incoming.asr), srcScope?.speech)) {
    if (incoming.tts && (mode === 'overwrite' || !next.tts || next.tts.engine === 'system')) {
      next.tts = {
        engine: incoming.tts.engine,
        endpoint: incoming.tts.endpoint,
        secretRef: remapRef(incoming.tts.secretRef, isHarmonySource),
        model: incoming.tts.model,
        voice: incoming.tts.voice,
        speed: incoming.tts.speed,
        language: incoming.tts.language,
        region: incoming.tts.region
      };
    }
    if (incoming.asr && (mode === 'overwrite' || !next.asr || next.asr.engine === 'system')) {
      next.asr = {
        engine: incoming.asr.engine,
        endpoint: incoming.asr.endpoint,
        secretRef: remapRef(incoming.asr.secretRef, isHarmonySource),
        model: incoming.asr.model,
        language: incoming.asr.language
      };
    }
  }

  // 14. Settings
  if (scope.settings && (srcScope === undefined || srcScope.settings)) {
    if (incoming.generationParams && (mode === 'overwrite' || !next.generationParams)) {
      next.generationParams = incoming.generationParams;
    }
    if (incoming.modelDefaults) {
      if (mode === 'overwrite' || !next.modelDefaults?.chatProviderId) {
        const preservedMemProv = next.modelDefaults?.memoryProviderId || '';
        const preservedMemModel = next.modelDefaults?.memoryModelId || '';
        const incMd = incoming.modelDefaults;
        next.modelDefaults = {
          chatProviderId: incMd.chatProviderId || (next.modelDefaults?.chatProviderId || ''),
          chatModelId: incMd.chatModelId || (next.modelDefaults?.chatModelId || ''),
          perChatModel: incMd.perChatModel,
          titleProviderId: incMd.titleProviderId,
          titleModelId: incMd.titleModelId,
          summaryProviderId: incMd.summaryProviderId,
          summaryModelId: incMd.summaryModelId,
          suggestionsProviderId: incMd.suggestionsProviderId,
          suggestionsModelId: incMd.suggestionsModelId,
          compressProviderId: incMd.compressProviderId,
          compressModelId: incMd.compressModelId,
          translateProviderId: incMd.translateProviderId,
          translateModelId: incMd.translateModelId,
          ocrProviderId: incMd.ocrProviderId,
          ocrModelId: incMd.ocrModelId,
          memoryProviderId: incMd.memoryProviderId || preservedMemProv,
          memoryModelId: incMd.memoryModelId || preservedMemModel
        };
      }
    }
    if (incoming.appearance && mode === 'overwrite') {
      next.appearance = incoming.appearance;
    }
    if (incoming.systemSettings && mode === 'overwrite') {
      next.systemSettings = incoming.systemSettings;
    }
    if (incoming.toolOverrides && mode === 'overwrite') {
      next.toolOverrides = incoming.toolOverrides;
    }
    if (incoming.scheduledTasks && mode === 'overwrite') {
      next.scheduledTasks = incoming.scheduledTasks;
    }
    if (incoming.userName && (mode === 'overwrite' || !next.userName || next.userName === '用户')) {
      next.userName = incoming.userName;
    }
    if (incoming.globalProxy && (mode === 'overwrite' || !next.globalProxy?.host)) {
      const normGp = normalizeProxyConfig(incoming.globalProxy, true);
      normGp.passwordRef = remapRef(normGp.passwordRef, isHarmonySource) || undefined;
      next.globalProxy = normGp;
    }
  }

  const summary = mode === 'overwrite'
    ? ('已覆盖恢复（' + importedChats + ' 段对话 · ' + importedProviders + ' 个供应商）')
    : ('已合并导入 ' + importedChats + ' 段对话、' + importedProviders + ' 个供应商、' + importedAssistants + ' 个助手');

  return {
    workspace: next,
    stats: {
      providers: importedProviders,
      assistants: importedAssistants,
      conversations: importedChats,
      messages: importedMsgs,
      files: 0
    },
    secretsToStore: outSecrets,
    summary
  };
}
