import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  Attachment,
  ChatMessage,
  ContextLogEntry,
  Conversation,
  RequestLogEntry,
  UsageStatRow,
  Workspace,
  defaultAppearance,
  defaultGenerationParams,
  defaultInstructionCards,
  defaultQuickPhrases,
  defaultSearchServices,
  defaultSystemSettings,
  initialWorkspace,
  normalizeBackupConfig
} from './Models';
import { saveAttachmentToSandbox } from './AttachmentStore';
import {
  normalizeMemoryEntries,
  normalizeMemorySettings,
  normalizeUserProfileFields
} from './MemoryLogic';

interface ConversationMetaPayload {
  ephemeral?: boolean;
  contextStartIndex?: number;
  memoryOrganizedThrough?: string;
  overrideProviderId?: string;
  overrideModel?: string;
  overridePrompt?: string;
  enabledMcpIds?: string[];
  enabledSkillIds?: string[];
  workspaceId?: string;
  toolPermissionMode?: 'ask' | 'full';
  draftText?: string;
  imageGenMode?: boolean;
  suggestions?: string[];
}

function hydrateWorkspaceDefaults(ws: Workspace): Workspace {
  const base = initialWorkspace();
  if (!ws.providers || !ws.providers.length) ws.providers = base.providers;
  if (!ws.personas || !ws.personas.length) ws.personas = base.personas;
  if (!ws.conversations) ws.conversations = [];
  if (!ws.searchServices || !ws.searchServices.length) ws.searchServices = defaultSearchServices();
  if (!ws.activeSearchId) ws.activeSearchId = ws.searchServices[0].id;
  if (!ws.mcpServers) ws.mcpServers = [];
  if (!ws.generationParams) ws.generationParams = defaultGenerationParams();
  if (!ws.modelDefaults) ws.modelDefaults = base.modelDefaults;
  if (!ws.tts) ws.tts = base.tts;
  if (!ws.asr) ws.asr = base.asr;
  ws.memories = normalizeMemoryEntries(ws.memories);
  ws.userProfile = normalizeUserProfileFields(ws.userProfile);
  if (!ws.memoryTraces) ws.memoryTraces = [];
  ws.memorySettings = normalizeMemorySettings(ws.memorySettings);
  if (!ws.worldBooks) ws.worldBooks = [];
  if (!ws.instructionCards || !ws.instructionCards.length) ws.instructionCards = defaultInstructionCards();
  if (!ws.activeInstructionIds) ws.activeInstructionIds = [];
  if (!ws.quickPhrases || !ws.quickPhrases.length) ws.quickPhrases = defaultQuickPhrases();
  if (!ws.skills) ws.skills = [];
  if (!ws.workspaces) ws.workspaces = [];
  if (!ws.envVars) ws.envVars = [];
  if (!ws.scheduledTasks) ws.scheduledTasks = [];
  if (!ws.browserBookmarks) ws.browserBookmarks = base.browserBookmarks;
  if (!ws.appearance) ws.appearance = defaultAppearance();
  if (!ws.systemSettings) ws.systemSettings = defaultSystemSettings();
  if (!ws.toolOverrides) ws.toolOverrides = [];
  if (!ws.snapshots) ws.snapshots = [];
  if (!ws.backupConfig) {
    ws.backupConfig = normalizeBackupConfig();
    if (ws.systemSettings && ws.systemSettings.autoSnapshotEnabled === false) {
      ws.backupConfig.localCopiesEnabled = false;
    }
  } else {
    ws.backupConfig = normalizeBackupConfig(ws.backupConfig);
  }
  if (ws.search && !ws.searchServices.some((s) => s.kind === ws.search?.kind && s.endpoint === ws.search?.endpoint)) {
    const legacy = ws.search;
    ws.searchServices.push({
      id: 'search-legacy',
      kind: legacy.kind,
      name: legacy.kind === 'tavily' ? 'Tavily (迁移)' : 'SearXNG (迁移)',
      endpoint: legacy.endpoint,
      apiKeys: legacy.secretRef ? [{
        id: 'key-legacy',
        label: '迁移密钥',
        secretRef: legacy.secretRef,
        priority: 0,
        usageCount: 0,
        errorCount: 0,
        disabledUntil: 0
      }] : [],
      keyStrategy: 'round_robin',
      maxResults: 5,
      enabled: true,
      mode: 'pre_search',
      webFetchEnabled: true
    });
  }
  return ws;
}

export class KelivoDatabase {
  private store?: relationalStore.RdbStore;
  private context: common.UIAbilityContext;
  private queue: Promise<void> = Promise.resolve();
  private savedConvMetaSig: Map<string, string> = new Map<string, string>();
  private savedConvMsgsSig: Map<string, string> = new Map<string, string>();
  private hasSyncedChats: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async open(): Promise<void> {
    if (this.store) return;
    const config: relationalStore.StoreConfig = {
      name: 'kelivo.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const rdb = await relationalStore.getRdbStore(this.context, config);
    await rdb.executeSql('CREATE TABLE IF NOT EXISTS kv_meta (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
    await rdb.executeSql('CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, title TEXT, updated INTEGER, pinned INTEGER, persona_id TEXT, meta_json TEXT)');
    await rdb.executeSql('CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, conversation_id TEXT, seq INTEGER, role TEXT, text TEXT, model TEXT, payload_json TEXT, created_at INTEGER)');
    await rdb.executeSql('CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages (conversation_id, seq)');
    await rdb.executeSql('CREATE TABLE IF NOT EXISTS request_logs (id TEXT PRIMARY KEY, ts INTEGER, provider TEXT, model TEXT, url TEXT, status INTEGER, duration_ms INTEGER, req_preview TEXT, resp_preview TEXT, error TEXT)');
    await rdb.executeSql('CREATE TABLE IF NOT EXISTS context_logs (id TEXT PRIMARY KEY, ts INTEGER, conversation_id TEXT, model TEXT, payload_json TEXT, token_estimate INTEGER)');
    await rdb.executeSql('CREATE TABLE IF NOT EXISTS usage_stats (id TEXT PRIMARY KEY, day TEXT, model TEXT, persona_id TEXT, prompt_tokens INTEGER, completion_tokens INTEGER, cached_tokens INTEGER, msg_count INTEGER)');
    this.store = rdb;
  }

  private async getMeta(key: string): Promise<string> {
    await this.open();
    const rs = await this.store!.querySql('SELECT v FROM kv_meta WHERE k = ?', [key]);
    try {
      if (rs.goToNextRow()) {
        return rs.getString(0);
      }
      return '';
    } finally {
      rs.close();
    }
  }

  private async putMeta(key: string, val: string): Promise<void> {
    await this.store!.executeSql('INSERT OR REPLACE INTO kv_meta (k, v) VALUES (?, ?)', [key, val]);
  }

  private async offloadAttachment(att: Attachment): Promise<Attachment> {
    if (!att.data || att.filePath) return att;
    const isBinary = att.mime.startsWith('image/') || att.mime.startsWith('audio/');
    if (!isBinary && att.data.length < 32 * 1024) return att;
    try {
      const id = att.id || util.generateRandomUUID(true);
      const bytes = isBinary ? new util.Base64Helper().decodeSync(att.data) : util.TextEncoder.create().encodeInto(att.data);
      const kind = att.kind || (att.mime.startsWith('image/') ? 'image' : att.mime.startsWith('audio/') ? 'audio' : 'text');
      const savedPath = await saveAttachmentToSandbox(this.context.filesDir, id, att.name, att.mime, bytes, kind);
      return {
        id,
        name: att.name,
        mime: att.mime,
        data: isBinary && bytes.length <= 160 * 1024 ? att.data : '',
        filePath: savedPath,
        sizeBytes: bytes.length,
        kind
      };
    } catch (_) {
      return att;
    }
  }

  private attachmentNeedsOffload(att?: Attachment): boolean {
    if (!att || !att.data || att.filePath) return false;
    const isBinary = att.mime.startsWith('image/') || att.mime.startsWith('audio/');
    return isBinary || att.data.length >= 32 * 1024;
  }

  private buildConversationMetaJson(chat: Conversation): string {
    const meta: ConversationMetaPayload = {
      ephemeral: chat.ephemeral,
      contextStartIndex: chat.contextStartIndex,
      memoryOrganizedThrough: chat.memoryOrganizedThrough,
      overrideProviderId: chat.overrideProviderId,
      overrideModel: chat.overrideModel,
      overridePrompt: chat.overridePrompt,
      enabledMcpIds: chat.enabledMcpIds,
      enabledSkillIds: chat.enabledSkillIds,
      workspaceId: chat.workspaceId,
      toolPermissionMode: chat.toolPermissionMode,
      draftText: chat.draftText,
      imageGenMode: chat.imageGenMode,
      suggestions: chat.suggestions
    };
    return JSON.stringify(meta);
  }

  private conversationMetaSignature(chat: Conversation, metaJson: string): string {
    return `${chat.title}\u0000${chat.updated}\u0000${chat.pinned ? 1 : 0}\u0000${chat.personaId}\u0000${metaJson}`;
  }

  private async offloadConversationAttachments(chat: Conversation): Promise<Conversation> {
    let dirty = false;
    for (let i = 0; i < chat.messages.length; i++) {
      const m = chat.messages[i];
      if (this.attachmentNeedsOffload(m.attachment)) {
        dirty = true;
        break;
      }
      if (m.attachments && m.attachments.length > 0) {
        for (let j = 0; j < m.attachments.length; j++) {
          if (this.attachmentNeedsOffload(m.attachments[j])) {
            dirty = true;
            break;
          }
        }
        if (dirty) break;
      }
    }
    if (!dirty) return chat;
    const messages: ChatMessage[] = [];
    for (let i = 0; i < chat.messages.length; i++) {
      const msg = chat.messages[i];
      const nextAtt = msg.attachment ? await this.offloadAttachment(msg.attachment) : undefined;
      let nextList: Attachment[] | undefined = undefined;
      if (msg.attachments && msg.attachments.length > 0) {
        nextList = [];
        for (let j = 0; j < msg.attachments.length; j++) {
          nextList.push(await this.offloadAttachment(msg.attachments[j]));
        }
      }
      messages.push({
        id: msg.id,
        role: msg.role,
        text: msg.text,
        model: msg.model,
        attachment: nextAtt,
        attachments: nextList,
        reasoning: msg.reasoning,
        sources: msg.sources,
        createdAt: msg.createdAt,
        usage: msg.usage,
        reasoningDurationMs: msg.reasoningDurationMs,
        toolCalls: msg.toolCalls,
        generatedImages: msg.generatedImages,
        quote: msg.quote,
        translation: msg.translation,
        versions: msg.versions,
        activeVersion: msg.activeVersion,
        isSummary: msg.isSummary,
        compressedCount: msg.compressedCount,
        compressionSnapshot: msg.compressionSnapshot
      });
    }
    return {
      id: chat.id,
      title: chat.title,
      updated: chat.updated,
      pinned: chat.pinned,
      messages,
      personaId: chat.personaId,
      ephemeral: chat.ephemeral,
      contextStartIndex: chat.contextStartIndex,
      memoryOrganizedThrough: chat.memoryOrganizedThrough,
      overrideProviderId: chat.overrideProviderId,
      overrideModel: chat.overrideModel,
      overridePrompt: chat.overridePrompt,
      enabledMcpIds: chat.enabledMcpIds,
      enabledSkillIds: chat.enabledSkillIds,
      workspaceId: chat.workspaceId,
      toolPermissionMode: chat.toolPermissionMode,
      draftText: chat.draftText,
      imageGenMode: chat.imageGenMode,
      suggestions: chat.suggestions
    };
  }

  async loadWorkspace(): Promise<Workspace> {
    await this.open();
    const metaRaw = await this.getMeta('workspace_meta');
    if (!metaRaw) {
      const legacyFile = this.context.filesDir + '/workspace-v1.json';
      try {
        const exists = await fs.access(legacyFile);
        if (exists) {
          const text = await fs.readText(legacyFile);
          const legacy = hydrateWorkspaceDefaults(JSON.parse(text) as Workspace);
          await this.saveWorkspace(legacy);
          return legacy;
        }
      } catch (_) {}
      const fresh = initialWorkspace();
      await this.saveWorkspace(fresh);
      return fresh;
    }

    const ws = hydrateWorkspaceDefaults(JSON.parse(metaRaw) as Workspace);
    const chats: Conversation[] = [];
    const convMap = new Map<string, Conversation>();
    const convRs = await this.store!.querySql('SELECT id, title, updated, pinned, persona_id, meta_json FROM conversations ORDER BY pinned DESC, updated DESC');
    try {
      while (convRs.goToNextRow()) {
        const id = convRs.getString(0);
        const title = convRs.getString(1);
        const updated = convRs.getLong(2);
        const pinned = convRs.getLong(3) === 1;
        const personaId = convRs.getString(4);
        const metaStr = convRs.getString(5);
        const emptyMeta: ConversationMetaPayload = {};
        const meta: ConversationMetaPayload = metaStr ? (JSON.parse(metaStr) as ConversationMetaPayload) : emptyMeta;
        const conv: Conversation = {
          id,
          title,
          updated,
          pinned,
          personaId,
          messages: [],
          ephemeral: meta.ephemeral,
          contextStartIndex: meta.contextStartIndex,
          memoryOrganizedThrough: meta.memoryOrganizedThrough,
          overrideProviderId: meta.overrideProviderId,
          overrideModel: meta.overrideModel,
          overridePrompt: meta.overridePrompt,
          enabledMcpIds: meta.enabledMcpIds,
          enabledSkillIds: meta.enabledSkillIds,
          workspaceId: meta.workspaceId,
          toolPermissionMode: meta.toolPermissionMode,
          draftText: meta.draftText,
          imageGenMode: meta.imageGenMode,
          suggestions: meta.suggestions
        };
        chats.push(conv);
        convMap.set(id, conv);
      }
    } finally {
      convRs.close();
    }

    const msgRs = await this.store!.querySql('SELECT conversation_id, payload_json FROM messages ORDER BY seq ASC');
    try {
      while (msgRs.goToNextRow()) {
        const convId = msgRs.getString(0);
        const payload = msgRs.getString(1);
        const target = convMap.get(convId);
        if (target && payload) {
          target.messages.push(JSON.parse(payload) as ChatMessage);
        }
      }
    } finally {
      msgRs.close();
    }

    this.savedConvMetaSig.clear();
    this.savedConvMsgsSig.clear();
    for (let i = 0; i < chats.length; i++) {
      const c = chats[i];
      const metaJson = this.buildConversationMetaJson(c);
      this.savedConvMetaSig.set(c.id, this.conversationMetaSignature(c, metaJson));
      const payloads: string[] = [];
      for (let j = 0; j < c.messages.length; j++) {
        payloads.push(JSON.stringify(c.messages[j]));
      }
      this.savedConvMsgsSig.set(c.id, payloads.join('\u0001'));
    }
    this.hasSyncedChats = true;
    ws.conversations = chats;
    return ws;
  }

  saveWorkspace(ws: Workspace): Promise<void> {
    const snapshotChats = ws.conversations.filter((c: Conversation): boolean => !c.ephemeral);
    const metaCopy: Workspace = {
      version: ws.version,
      providers: ws.providers,
      personas: ws.personas,
      conversations: [],
      search: ws.search,
      searchServices: ws.searchServices,
      activeSearchId: ws.activeSearchId,
      mcpEndpoint: ws.mcpEndpoint,
      mcpServers: ws.mcpServers,
      davDirectory: ws.davDirectory,
      davPath: ws.davPath,
      davFilename: ws.davFilename,
      davUsername: ws.davUsername,
      davPasswordRef: ws.davPasswordRef,
      davUserAgent: ws.davUserAgent,
      s3Config: ws.s3Config,
      backupConfig: ws.backupConfig,
      activeProvider: ws.activeProvider,
      activeConversation: ws.activeConversation,
      generationParams: ws.generationParams,
      modelDefaults: ws.modelDefaults,
      tts: ws.tts,
      asr: ws.asr,
      memories: ws.memories,
      userProfile: ws.userProfile,
      memoryTraces: ws.memoryTraces,
      memorySettings: ws.memorySettings,
      worldBooks: ws.worldBooks,
      instructionCards: ws.instructionCards,
      activeInstructionIds: ws.activeInstructionIds,
      quickPhrases: ws.quickPhrases,
      skills: ws.skills,
      workspaces: ws.workspaces,
      envVars: ws.envVars,
      scheduledTasks: ws.scheduledTasks,
      browserBookmarks: ws.browserBookmarks,
      appearance: ws.appearance,
      systemSettings: ws.systemSettings,
      toolOverrides: ws.toolOverrides,
      snapshots: ws.snapshots,
      userName: ws.userName,
      favoriteModels: ws.favoriteModels
    };
    const metaJson = JSON.stringify(metaCopy);

    const task = this.queue.then(async () => {
      await this.open();
      const processedChats: Conversation[] = [];
      for (let i = 0; i < snapshotChats.length; i++) {
        processedChats.push(await this.offloadConversationAttachments(snapshotChats[i]));
      }
      const rdb = this.store!;
      rdb.beginTransaction();
      try {
        await this.putMeta('workspace_meta', metaJson);
        const nextMetaSig = new Map<string, string>();
        const nextMsgsSig = new Map<string, string>();
        if (!this.hasSyncedChats) {
          await rdb.executeSql('DELETE FROM messages');
          await rdb.executeSql('DELETE FROM conversations');
          for (let i = 0; i < processedChats.length; i++) {
            const chat = processedChats[i];
            const convMetaJson = this.buildConversationMetaJson(chat);
            nextMetaSig.set(chat.id, this.conversationMetaSignature(chat, convMetaJson));
            await rdb.executeSql(
              'INSERT OR REPLACE INTO conversations (id, title, updated, pinned, persona_id, meta_json) VALUES (?, ?, ?, ?, ?, ?)',
              [chat.id, chat.title, chat.updated, chat.pinned ? 1 : 0, chat.personaId, convMetaJson]
            );
            const payloads: string[] = [];
            for (let j = 0; j < chat.messages.length; j++) {
              const msg = chat.messages[j];
              const payload = JSON.stringify(msg);
              payloads.push(payload);
              await rdb.executeSql(
                'INSERT OR REPLACE INTO messages (id, conversation_id, seq, role, text, model, payload_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                [msg.id, chat.id, j, msg.role, msg.text, msg.model, payload, msg.createdAt || chat.updated]
              );
            }
            nextMsgsSig.set(chat.id, payloads.join('\u0001'));
          }
        } else {
          const liveIds = new Set<string>();
          for (let i = 0; i < processedChats.length; i++) {
            liveIds.add(processedChats[i].id);
          }
          const prevIds = Array.from(this.savedConvMetaSig.keys());
          for (let i = 0; i < prevIds.length; i++) {
            const oldId = prevIds[i];
            if (!liveIds.has(oldId)) {
              await rdb.executeSql('DELETE FROM messages WHERE conversation_id = ?', [oldId]);
              await rdb.executeSql('DELETE FROM conversations WHERE id = ?', [oldId]);
            }
          }
          for (let i = 0; i < processedChats.length; i++) {
            const chat = processedChats[i];
            const convMetaJson = this.buildConversationMetaJson(chat);
            const metaSig = this.conversationMetaSignature(chat, convMetaJson);
            nextMetaSig.set(chat.id, metaSig);
            if (this.savedConvMetaSig.get(chat.id) !== metaSig) {
              await rdb.executeSql(
                'INSERT OR REPLACE INTO conversations (id, title, updated, pinned, persona_id, meta_json) VALUES (?, ?, ?, ?, ?, ?)',
                [chat.id, chat.title, chat.updated, chat.pinned ? 1 : 0, chat.personaId, convMetaJson]
              );
            }
            const payloads: string[] = [];
            for (let j = 0; j < chat.messages.length; j++) {
              payloads.push(JSON.stringify(chat.messages[j]));
            }
            const msgsSig = payloads.join('\u0001');
            nextMsgsSig.set(chat.id, msgsSig);
            if (this.savedConvMsgsSig.get(chat.id) !== msgsSig) {
              await rdb.executeSql('DELETE FROM messages WHERE conversation_id = ?', [chat.id]);
              for (let j = 0; j < chat.messages.length; j++) {
                const msg = chat.messages[j];
                await rdb.executeSql(
                  'INSERT OR REPLACE INTO messages (id, conversation_id, seq, role, text, model, payload_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                  [msg.id, chat.id, j, msg.role, msg.text, msg.model, payloads[j], msg.createdAt || chat.updated]
                );
              }
            }
          }
        }
        rdb.commit();
        this.savedConvMetaSig = nextMetaSig;
        this.savedConvMsgsSig = nextMsgsSig;
        this.hasSyncedChats = true;
      } catch (e) {
        try { rdb.rollBack(); } catch (_) {}
        this.hasSyncedChats = false;
        this.savedConvMetaSig.clear();
        this.savedConvMsgsSig.clear();
        throw e as Error;
      }
    });
    this.queue = task.catch(() => {});
    return task;
  }

  async addRequestLog(entry: RequestLogEntry): Promise<void> {
    await this.open();
    await this.store!.executeSql(
      'INSERT OR REPLACE INTO request_logs (id, ts, provider, model, url, status, duration_ms, req_preview, resp_preview, error) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [entry.id, entry.ts, entry.provider, entry.model, entry.url, entry.status, entry.durationMs,
        entry.reqPreview.slice(0, 4000), entry.respPreview.slice(0, 4000), entry.error.slice(0, 1000)]
    );
    await this.store!.executeSql(
      'DELETE FROM request_logs WHERE id NOT IN (SELECT id FROM request_logs ORDER BY ts DESC LIMIT 120)'
    );
  }

  async listRequestLogs(limit: number = 80): Promise<RequestLogEntry[]> {
    await this.open();
    const rs = await this.store!.querySql(
      'SELECT id, ts, provider, model, url, status, duration_ms, req_preview, resp_preview, error FROM request_logs ORDER BY ts DESC LIMIT ?',
      [limit]
    );
    const rows: RequestLogEntry[] = [];
    try {
      while (rs.goToNextRow()) {
        rows.push({
          id: rs.getString(0),
          ts: rs.getLong(1),
          provider: rs.getString(2),
          model: rs.getString(3),
          url: rs.getString(4),
          status: rs.getLong(5),
          durationMs: rs.getLong(6),
          reqPreview: rs.getString(7),
          respPreview: rs.getString(8),
          error: rs.getString(9)
        });
      }
    } finally {
      rs.close();
    }
    return rows;
  }

  async clearRequestLogs(): Promise<void> {
    await this.open();
    await this.store!.executeSql('DELETE FROM request_logs');
  }

  async addContextLog(entry: ContextLogEntry): Promise<void> {
    await this.open();
    await this.store!.executeSql(
      'INSERT OR REPLACE INTO context_logs (id, ts, conversation_id, model, payload_json, token_estimate) VALUES (?, ?, ?, ?, ?, ?)',
      [entry.id, entry.ts, entry.conversationId, entry.model, entry.payloadJson.slice(0, 16000), entry.tokenEstimate]
    );
    await this.store!.executeSql(
      'DELETE FROM context_logs WHERE id NOT IN (SELECT id FROM context_logs ORDER BY ts DESC LIMIT 60)'
    );
  }

  async listContextLogs(limit: number = 40): Promise<ContextLogEntry[]> {
    await this.open();
    const rs = await this.store!.querySql(
      'SELECT id, ts, conversation_id, model, payload_json, token_estimate FROM context_logs ORDER BY ts DESC LIMIT ?',
      [limit]
    );
    const rows: ContextLogEntry[] = [];
    try {
      while (rs.goToNextRow()) {
        rows.push({
          id: rs.getString(0),
          ts: rs.getLong(1),
          conversationId: rs.getString(2),
          model: rs.getString(3),
          payloadJson: rs.getString(4),
          tokenEstimate: rs.getLong(5)
        });
      }
    } finally {
      rs.close();
    }
    return rows;
  }

  async clearContextLogs(): Promise<void> {
    await this.open();
    await this.store!.executeSql('DELETE FROM context_logs');
  }

  async recordUsage(day: string, model: string, personaId: string, promptTokens: number, completionTokens: number, cachedTokens: number): Promise<void> {
    await this.open();
    const key = day + '::' + model + '::' + personaId;
    const rs = await this.store!.querySql(
      'SELECT prompt_tokens, completion_tokens, cached_tokens, msg_count FROM usage_stats WHERE id = ?',
      [key]
    );
    let p = promptTokens;
    let c = completionTokens;
    let ca = cachedTokens;
    let cnt = 1;
    try {
      if (rs.goToNextRow()) {
        p += rs.getLong(0);
        c += rs.getLong(1);
        ca += rs.getLong(2);
        cnt += rs.getLong(3);
      }
    } finally {
      rs.close();
    }
    await this.store!.executeSql(
      'INSERT OR REPLACE INTO usage_stats (id, day, model, persona_id, prompt_tokens, completion_tokens, cached_tokens, msg_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [key, day, model, personaId, p, c, ca, cnt]
    );
  }

  async listUsageStats(): Promise<UsageStatRow[]> {
    await this.open();
    const rs = await this.store!.querySql(
      'SELECT id, day, model, persona_id, prompt_tokens, completion_tokens, cached_tokens, msg_count FROM usage_stats ORDER BY day DESC'
    );
    const rows: UsageStatRow[] = [];
    try {
      while (rs.goToNextRow()) {
        rows.push({
          id: rs.getString(0),
          day: rs.getString(1),
          model: rs.getString(2),
          personaId: rs.getString(3),
          promptTokens: rs.getLong(4),
          completionTokens: rs.getLong(5),
          cachedTokens: rs.getLong(6),
          msgCount: rs.getLong(7)
        });
      }
    } finally {
      rs.close();
    }
    return rows;
  }
}
