import {
  BackupScopeConfig,
  ChatMessage,
  Conversation,
  Persona,
  Provider,
  Workspace,
  defaultBackupScope,
  normalizeBackupScope,
  normalizeInstructionCards,
  normalizeProxyConfig,
  normalizeQuickPhrases,
  normalizeWorldBooks
} from './Models';
import { ParsedBackupData } from './BackupCodecTypes';

export { ParsedBackupData, RestoreStats, ApplyRestoreOutput } from './BackupCodecTypes';
export {
  buildAndroidSettingsJson,
  buildAndroidChatsJson,
  parseAndroidChatsJson,
  parseAndroidSettingsJson
} from './BackupAndroidCodec';
export { applyScopedRestore } from './BackupRestoreEngine';

interface HarmonyBackupEnvelopeV2 {
  format: string;
  version: number;
  exportedAt: number;
  scope?: Partial<BackupScopeConfig>;
  secrets?: Record<string, string>;
  workspace?: Workspace;
  // Legacy v2 fields compatibility
  conversations?: Conversation[];
  providers?: Provider[];
  personas?: Persona[];
  workspaceMetaJson?: string;
}

function addRef(set: Set<string>, ref?: string): void {
  if (ref && ref.trim().length > 0) set.add(ref.trim());
}

export function collectSecretRefsForScope(ws: Workspace, rawScope?: BackupScopeConfig): string[] {
  const scope = normalizeBackupScope(rawScope);
  const refs = new Set<string>();
  if (scope.providers) {
    for (let i = 0; i < ws.providers.length; i++) {
      const p = ws.providers[i];
      addRef(refs, p.secretRef);
      if (p.proxy) addRef(refs, p.proxy.passwordRef);
      if (p.oauth) {
        addRef(refs, p.oauth.accessTokenRef);
        addRef(refs, p.oauth.refreshTokenRef);
      }
      if (p.apiKeys) {
        for (let k = 0; k < p.apiKeys.length; k++) {
          addRef(refs, p.apiKeys[k].secretRef);
        }
      }
    }
  }
  if (scope.mcp && ws.mcpServers) {
    for (let i = 0; i < ws.mcpServers.length; i++) {
      addRef(refs, ws.mcpServers[i].bearerSecretRef);
      addRef(refs, ws.mcpServers[i].oauthAccessTokenRef);
    }
  }
  if (scope.search) {
    if (ws.search) addRef(refs, ws.search.secretRef);
    if (ws.searchServices) {
      for (let i = 0; i < ws.searchServices.length; i++) {
        const s = ws.searchServices[i];
        for (let k = 0; k < s.apiKeys.length; k++) {
          addRef(refs, s.apiKeys[k].secretRef);
        }
      }
    }
  }
  if (scope.speech) {
    if (ws.tts) addRef(refs, ws.tts.secretRef);
    if (ws.asr) addRef(refs, ws.asr.secretRef);
  }
  if (scope.envVars && ws.envVars) {
    for (let i = 0; i < ws.envVars.length; i++) {
      addRef(refs, ws.envVars[i].secretRef);
    }
  }
  if (scope.settings && ws.globalProxy) {
    addRef(refs, ws.globalProxy.passwordRef);
  }
  return Array.from(refs);
}

function stripConversationAttachments(chats: Conversation[], keepAttachments: boolean): Conversation[] {
  const out: Conversation[] = [];
  for (let i = 0; i < chats.length; i++) {
    const c = chats[i];
    if (c.ephemeral) continue;
    const msgs: ChatMessage[] = [];
    for (let j = 0; j < c.messages.length; j++) {
      const m = c.messages[j];
      msgs.push({
        id: m.id,
        role: m.role,
        text: m.text,
        model: m.model,
        attachment: keepAttachments ? m.attachment : undefined,
        attachments: keepAttachments ? m.attachments : undefined,
        reasoning: m.reasoning,
        sources: m.sources,
        createdAt: m.createdAt,
        usage: m.usage,
        reasoningDurationMs: m.reasoningDurationMs,
        toolCalls: m.toolCalls,
        generatedImages: keepAttachments ? m.generatedImages : undefined,
        quote: m.quote,
        translation: m.translation,
        versions: m.versions,
        activeVersion: m.activeVersion,
        isSummary: m.isSummary,
        compressedCount: m.compressedCount,
        compressionSnapshot: m.compressionSnapshot
      });
    }
    out.push({
      id: c.id,
      title: c.title,
      updated: c.updated,
      pinned: c.pinned,
      messages: msgs,
      personaId: c.personaId,
      contextStartIndex: c.contextStartIndex,
      memoryOrganizedThrough: c.memoryOrganizedThrough,
      overrideProviderId: c.overrideProviderId,
      overrideModel: c.overrideModel,
      overridePrompt: c.overridePrompt,
      enabledMcpIds: c.enabledMcpIds,
      enabledSkillIds: c.enabledSkillIds,
      workspaceId: c.workspaceId,
      toolPermissionMode: c.toolPermissionMode,
      suggestions: c.suggestions
    });
  }
  return out;
}

export function buildHarmonyBackupJson(
  ws: Workspace,
  rawScope: BackupScopeConfig,
  secrets: Record<string, string>,
  hydratedConversations?: Conversation[]
): string {
  const scope = normalizeBackupScope(rawScope);
  const srcChats = hydratedConversations || ws.conversations;
  const scopedWs: Workspace = {
    version: ws.version,
    providers: scope.providers ? ws.providers : [],
    personas: scope.assistants ? ws.personas : [],
    conversations: scope.chats ? stripConversationAttachments(srcChats, scope.attachments) : [],
    activeProvider: scope.providers ? ws.activeProvider : '',
    activeConversation: scope.chats ? ws.activeConversation : '',
    search: scope.search ? ws.search : undefined,
    searchServices: scope.search ? ws.searchServices : undefined,
    activeSearchId: scope.search ? ws.activeSearchId : undefined,
    globalProxy: scope.settings ? ws.globalProxy : undefined,
    mcpEndpoint: scope.mcp ? ws.mcpEndpoint : undefined,
    mcpServers: scope.mcp ? ws.mcpServers : undefined,
    memories: scope.memory ? ws.memories : undefined,
    userProfile: scope.memory ? ws.userProfile : undefined,
    memoryTraces: scope.memory ? ws.memoryTraces : undefined,
    memorySettings: scope.memory ? ws.memorySettings : undefined,
    worldBooks: scope.worldBooks ? ws.worldBooks : undefined,
    instructionCards: scope.instructions ? ws.instructionCards : undefined,
    activeInstructionIds: scope.instructions ? ws.activeInstructionIds : undefined,
    quickPhrases: scope.quickPhrases ? ws.quickPhrases : undefined,
    skills: scope.skills ? ws.skills : undefined,
    workspaces: scope.workspaces ? ws.workspaces : undefined,
    envVars: scope.envVars ? ws.envVars : undefined,
    tts: scope.speech ? ws.tts : undefined,
    asr: scope.speech ? ws.asr : undefined,
    generationParams: scope.settings ? ws.generationParams : undefined,
    modelDefaults: scope.settings ? ws.modelDefaults : undefined,
    scheduledTasks: scope.settings ? ws.scheduledTasks : undefined,
    appearance: scope.settings ? ws.appearance : undefined,
    systemSettings: scope.settings ? ws.systemSettings : undefined,
    toolOverrides: scope.settings ? ws.toolOverrides : undefined,
    userName: scope.settings ? ws.userName : undefined,
    favoriteModels: scope.providers ? ws.favoriteModels : undefined
  };

  // Filter secrets strictly to refs belonging to enabled scope
  const allowedRefs = collectSecretRefsForScope(ws, scope);
  const exportedSecrets: Record<string, string> = {};
  for (let i = 0; i < allowedRefs.length; i++) {
    const r = allowedRefs[i];
    const v = secrets[r];
    if (v !== undefined && v.length > 0) exportedSecrets[r] = v;
  }

  const envelope: HarmonyBackupEnvelopeV2 = {
    format: 'kelivo-workspace-backup',
    version: 2,
    exportedAt: Date.now(),
    scope,
    secrets: exportedSecrets,
    workspace: scopedWs
  };
  return JSON.stringify(envelope);
}

export function parseHarmonyBackupJson(raw: string): ParsedBackupData {
  const env = JSON.parse(raw) as HarmonyBackupEnvelopeV2;
  if (env.format === 'kelivo-workspace-backup' && env.workspace) {
    const ws = env.workspace;
    const scope = env.scope ? normalizeBackupScope(env.scope) : defaultBackupScope();
    const secrets: Record<string, string> = env.secrets || {};
    return {
      sourceName: 'Kelivo (Harmony)',
      sourceScope: scope,
      conversations: scope.chats ? (ws.conversations || []) : undefined,
      providers: scope.providers ? (ws.providers || []) : undefined,
      personas: scope.assistants ? (ws.personas || []) : undefined,
      mcpServers: scope.mcp ? (ws.mcpServers || []) : undefined,
      mcpEndpoint: scope.mcp ? ws.mcpEndpoint : undefined,
      searchServices: scope.search ? (ws.searchServices || []) : undefined,
      activeSearchId: scope.search ? ws.activeSearchId : undefined,
      globalProxy: scope.settings && ws.globalProxy ? normalizeProxyConfig(ws.globalProxy, true) : undefined,
      memories: scope.memory ? (ws.memories || []) : undefined,
      userProfile: scope.memory ? (ws.userProfile || []) : undefined,
      memorySettings: scope.memory ? ws.memorySettings : undefined,
      worldBooks: scope.worldBooks && ws.worldBooks ? normalizeWorldBooks(ws.worldBooks) : undefined,
      quickPhrases: scope.quickPhrases && ws.quickPhrases ? normalizeQuickPhrases(ws.quickPhrases) : undefined,
      instructionCards: scope.instructions && ws.instructionCards ? normalizeInstructionCards(ws.instructionCards) : undefined,
      activeInstructionIds: scope.instructions ? ws.activeInstructionIds : undefined,
      skills: scope.skills ? (ws.skills || []) : undefined,
      workspaces: scope.workspaces ? (ws.workspaces || []) : undefined,
      envVars: scope.envVars ? (ws.envVars || []) : undefined,
      scheduledTasks: scope.settings ? ws.scheduledTasks : undefined,
      tts: scope.speech ? ws.tts : undefined,
      asr: scope.speech ? ws.asr : undefined,
      generationParams: scope.settings ? ws.generationParams : undefined,
      modelDefaults: scope.settings ? ws.modelDefaults : undefined,
      appearance: scope.settings ? ws.appearance : undefined,
      systemSettings: scope.settings ? ws.systemSettings : undefined,
      toolOverrides: scope.settings ? ws.toolOverrides : undefined,
      favoriteModels: scope.providers ? ws.favoriteModels : undefined,
      userName: scope.settings ? ws.userName : undefined,
      activeProvider: scope.providers ? ws.activeProvider : undefined,
      secretsToStore: secrets
    };
  }

  // Legacy kelivo-arkui-full v2 JSON format
  if (env.format === 'kelivo-arkui-full') {
    const scope = env.scope ? normalizeBackupScope(env.scope) : defaultBackupScope();
    const meta = env.workspaceMetaJson ? (JSON.parse(env.workspaceMetaJson) as Workspace) : undefined;
    return {
      sourceName: 'Kelivo (ArkUI v1)',
      sourceScope: scope,
      conversations: env.conversations,
      providers: env.providers,
      personas: env.personas,
      mcpServers: meta?.mcpServers,
      mcpEndpoint: meta?.mcpEndpoint,
      searchServices: meta?.searchServices,
      activeSearchId: meta?.activeSearchId,
      memories: meta?.memories,
      userProfile: meta?.userProfile,
      memorySettings: meta?.memorySettings,
      worldBooks: meta?.worldBooks,
      quickPhrases: meta?.quickPhrases,
      instructionCards: meta?.instructionCards,
      skills: meta?.skills,
      generationParams: meta?.generationParams,
      modelDefaults: meta?.modelDefaults,
      tts: meta?.tts,
      asr: meta?.asr,
      appearance: meta?.appearance,
      systemSettings: meta?.systemSettings,
      toolOverrides: meta?.toolOverrides,
      secretsToStore: {}
    };
  }

  throw new Error('不是有效的 Harmony Kelivo 备份 JSON');
}
