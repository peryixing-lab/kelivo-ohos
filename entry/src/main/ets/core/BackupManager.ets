import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  Attachment,
  BackupPreferencesConfig,
  BackupScopeConfig,
  ChatMessage,
  Conversation,
  LocalSnapshotMeta,
  MessageVersion,
  Workspace,
  defaultBackupConfig,
  defaultBackupScope,
  normalizeBackupScope
} from './Models';
import {
  decryptBackupText,
  decryptKelivencBytes,
  encryptBackupText,
  encryptKelivencBytes,
  isEncryptedBackup,
  isKelivencBytes
} from './BackupCrypto';
import {
  ensureDir,
  hydrateAttachmentData,
  readBinaryFile,
  readFileHandleBytes,
  saveAttachmentToSandbox,
  writeBinaryFile
} from './AttachmentStore';
import {
  ZipEntryMeta,
  ZipWriteEntry,
  buildZipBytes,
  extractZipEntryBytes,
  extractZipEntryText,
  findZipEntry,
  listZipEntries,
  normalizeZipEntryPath
} from './ZipReader';
import { readKey, storeKey } from './Storage';
import {
  ApplyRestoreOutput,
  ParsedBackupData,
  RestoreStats,
  applyScopedRestore,
  buildAndroidChatsJson,
  buildAndroidSettingsJson,
  buildHarmonyBackupJson,
  collectSecretRefsForScope,
  parseAndroidChatsJson,
  parseAndroidSettingsJson,
  parseHarmonyBackupJson
} from './BackupCodec';
import {
  assembleChatboxZipV2Json,
  detectAndImportThirdPartyJson,
  detectAndParseThirdPartyJson,
  parseChatboxData,
  parseCherryStudioData
} from './ThirdPartyImport';

export interface RestoreOutcome {
  workspace: Workspace;
  stats: RestoreStats;
  summary: string;
}

export type PasswordPromptFn = (isRetry: boolean) => Promise<string | undefined>;

export class BackupCancelledError extends Error {
  constructor() {
    super('已取消操作');
  }
}

export { defaultBackupScope };

async function readScopedSecrets(ws: Workspace, scope: BackupScopeConfig): Promise<Record<string, string>> {
  const refs = collectSecretRefsForScope(ws, scope);
  const secrets: Record<string, string> = {};
  for (let i = 0; i < refs.length; i++) {
    const r = refs[i];
    try {
      const val = await readKey(r);
      if (val) secrets[r] = val;
    } catch (_) {}
  }
  return secrets;
}

async function persistSecretsMap(secrets: Record<string, string>): Promise<void> {
  const refs = Object.keys(secrets);
  for (let i = 0; i < refs.length; i++) {
    const ref = refs[i];
    const val = secrets[ref];
    if (ref && val) {
      await storeKey(ref, val);
    }
  }
}

interface HydratedBackupChats {
  chats: Conversation[];
  zipFiles: ZipWriteEntry[];
}

interface SqliteMsgPartsResult {
  text: string;
  reasoning: string;
  atts: Attachment[];
}

interface ExtractedAttachmentResult {
  pathMap: Map<string, string>;
  count: number;
}

async function hydrateWorkspaceAttachmentsForBackup(
  conversations: Conversation[],
  includeAttachments: boolean
): Promise<HydratedBackupChats> {
  const chats: Conversation[] = [];
  const zipFiles: ZipWriteEntry[] = [];
  let totalFileBytes = 0;
  const MAX_ARCHIVE_FILES_BYTES = 96 * 1024 * 1024;
  const MAX_SINGLE_FILE_BYTES = 16 * 1024 * 1024;

  const packAttachment = async (att: Attachment): Promise<Attachment> => {
    if (!includeAttachments) return att;
    let outAtt = att;
    if (!outAtt.data && outAtt.filePath) {
      try {
        const bytes = await readBinaryFile(outAtt.filePath);
        if (bytes.length <= MAX_SINGLE_FILE_BYTES && totalFileBytes + bytes.length <= MAX_ARCHIVE_FILES_BYTES) {
          const base = (outAtt.filePath.split('/').pop() || (outAtt.id || 'file') + '.bin');
          zipFiles.push({ name: 'upload/' + base, data: bytes });
          totalFileBytes += bytes.length;
        }
        if (bytes.length <= 2 * 1024 * 1024) {
          outAtt = await hydrateAttachmentData(outAtt);
        }
      } catch (_) {}
    }
    return outAtt;
  };

  for (let i = 0; i < conversations.length; i++) {
    const c = conversations[i];
    if (c.ephemeral) continue;
    const msgs: ChatMessage[] = [];
    for (let j = 0; j < c.messages.length; j++) {
      const m = c.messages[j];
      const att = m.attachment ? await packAttachment(m.attachment) : undefined;
      let attList: Attachment[] | undefined = undefined;
      if (m.attachments && m.attachments.length > 0) {
        attList = [];
        for (let k = 0; k < m.attachments.length; k++) {
          attList.push(await packAttachment(m.attachments[k]));
        }
      }
      msgs.push({
        id: m.id,
        role: m.role,
        text: m.text,
        model: m.model,
        attachment: att,
        attachments: attList,
        reasoning: m.reasoning,
        sources: m.sources,
        createdAt: m.createdAt,
        usage: m.usage,
        toolCalls: m.toolCalls,
        generatedImages: m.generatedImages,
        quote: m.quote,
        translation: m.translation,
        versions: m.versions,
        activeVersion: m.activeVersion,
        isSummary: m.isSummary,
        compressedCount: m.compressedCount,
        compressionSnapshot: m.compressionSnapshot
      });
    }
    chats.push({
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
  return { chats, zipFiles };
}

export async function buildScopedBackupJson(
  workspace: Workspace,
  scope: BackupScopeConfig,
  password: string = ''
): Promise<string> {
  const normScope = normalizeBackupScope(scope);
  const secrets = await readScopedSecrets(workspace, normScope);
  const hydrated = normScope.chats
    ? (await hydrateWorkspaceAttachmentsForBackup(workspace.conversations, normScope.attachments)).chats
    : undefined;
  const json = buildHarmonyBackupJson(workspace, normScope, secrets, hydrated);
  return password.trim() ? encryptBackupText(json, password.trim()) : json;
}

export interface BuiltBackupArchive {
  bytes: Uint8Array;
  fileName: string;
  encrypted: boolean;
}

export async function buildBackupArchiveBytes(
  workspace: Workspace,
  rawScope: BackupScopeConfig,
  password: string = ''
): Promise<BuiltBackupArchive> {
  const scope = normalizeBackupScope(rawScope);
  const secrets = await readScopedSecrets(workspace, scope);
  const hydrated: HydratedBackupChats = scope.chats
    ? await hydrateWorkspaceAttachmentsForBackup(workspace.conversations, scope.attachments)
    : { chats: [], zipFiles: [] };

  const enc = util.TextEncoder.create('utf-8');
  const entries: ZipWriteEntry[] = [];

  // 1. Cross-platform Android-compatible entries (omit manifest.json so Android imports seamlessly as portable archive)
  entries.push({
    name: 'settings.json',
    data: enc.encodeInto(buildAndroidSettingsJson(workspace, scope, secrets))
  });
  if (scope.chats) {
    entries.push({
      name: 'chats.json',
      data: enc.encodeInto(buildAndroidChatsJson(hydrated.chats))
    });
  }

  // 2. Full-fidelity HarmonyOS workspace envelope + secrets
  entries.push({
    name: 'kelivo_harmony_workspace.json',
    data: enc.encodeInto(buildHarmonyBackupJson(workspace, scope, secrets, hydrated.chats))
  });

  // 3. Attachments when enabled
  if (scope.attachments && hydrated.zipFiles.length > 0) {
    for (let i = 0; i < hydrated.zipFiles.length; i++) {
      entries.push(hydrated.zipFiles[i]);
    }
  }

  const zipBytes = await buildZipBytes(entries);
  const stamp = new Date().toISOString().replace(/:/g, '-').slice(0, 19);
  const cleanPwd = password.trim();
  if (cleanPwd.length > 0) {
    const encBytes = await encryptKelivencBytes(zipBytes, cleanPwd);
    return {
      bytes: encBytes,
      fileName: 'kelivo_backup_' + stamp + '.kbackup',
      encrypted: true
    };
  }
  return {
    bytes: zipBytes,
    fileName: 'kelivo_backup_' + stamp + '.zip',
    encrypted: false
  };
}

interface AndroidSqliteRowMsg {
  id: string;
  conversationId: string;
  role: string;
  timestampMs: number;
  modelId: string;
  translation: string;
  groupId: string;
  version: number;
  totalTokens?: number;
  promptTokens?: number;
  completionTokens?: number;
  cachedTokens?: number;
  durationMs?: number;
}

interface SqlitePartRecord {
  kind: string;
  payload: string;
}

interface SqliteConvMeta {
  id: string;
  title: string;
  updatedMs: number;
  pinned: boolean;
  personaId: string;
  truncIdx: number;
  verSelections: Record<string, number>;
  overrideProv?: string;
  overrideModel?: string;
}

async function readAndroidSqliteChats(
  context: common.UIAbilityContext,
  dbBytes: Uint8Array,
  extractedFileMap: Map<string, string>
): Promise<Conversation[]> {
  const dirName = 'impdb_' + util.generateRandomUUID(true).replace(/-/g, '').slice(0, 12);
  const dirPath = context.tempDir + '/' + dirName;
  const dbPath = dirPath + '/kelivo.db';
  await ensureDir(dirPath);
  await writeBinaryFile(dbPath, dbBytes);

  let rdb: relationalStore.RdbStore | undefined = undefined;
  try {
    rdb = await relationalStore.getRdbStore(context, {
      name: 'kelivo.db',
      securityLevel: relationalStore.SecurityLevel.S1,
      rootDir: context.tempDir,
      customDir: dirName,
      isReadOnly: true
    });

    const convMetas: SqliteConvMeta[] = [];
    const convRs = await rdb.querySql(
      'SELECT id, title, updated_at, is_pinned, assistant_id, truncate_index, version_selections_json, chat_model_provider, chat_model_id FROM conversation_rows ORDER BY updated_at DESC'
    );
    try {
      while (convRs.goToNextRow()) {
        const cid = convRs.getString(0);
        const title = convRs.getString(1);
        const updUs = convRs.getLong(2);
        const updMs = updUs > 100000000000000 ? Math.floor(updUs / 1000) : updUs;
        const pinned = convRs.getLong(3) === 1;
        const personaId = convRs.isColumnNull(4) ? 'default' : (convRs.getString(4) || 'default');
        const truncIdx = convRs.isColumnNull(5) ? -1 : convRs.getLong(5);
        const verSelStr = convRs.isColumnNull(6) ? '{}' : convRs.getString(6);
        let verSelections: Record<string, number> = {};
        try { verSelections = JSON.parse(verSelStr) as Record<string, number>; } catch (_) {}
        const overrideProv = convRs.isColumnNull(7) ? undefined : (convRs.getString(7) || undefined);
        const overrideModel = convRs.isColumnNull(8) ? undefined : (convRs.getString(8) || undefined);
        convMetas.push({
          id: cid,
          title,
          updatedMs: updMs,
          pinned,
          personaId,
          truncIdx,
          verSelections,
          overrideProv,
          overrideModel
        });
      }
    } finally {
      convRs.close();
    }

    const resolveExtractedPath = (rawUri: string): string | undefined => {
      const stripped = rawUri.replace(/^kelivo-file:\/\/\//, '');
      const normUri = normalizeZipEntryPath(stripped);
      const direct = extractedFileMap.get(normUri);
      if (direct) return direct;
      try {
        const decoded = normalizeZipEntryPath(decodeURIComponent(stripped));
        return extractedFileMap.get(decoded);
      } catch (_) {
        return undefined;
      }
    };

    const out: Conversation[] = [];
    for (let cIdx = 0; cIdx < convMetas.length; cIdx++) {
      const cm = convMetas[cIdx];
      const partsByMsg = new Map<string, SqlitePartRecord[]>();
      try {
        const partRs = await rdb.querySql(
          'SELECT revision_id, kind, payload FROM message_part_rows WHERE conversation_id = ? ORDER BY revision_id ASC, ordinal ASC',
          [cm.id]
        );
        try {
          while (partRs.goToNextRow()) {
            const revId = partRs.getString(0);
            const kind = partRs.getString(1);
            const payload = partRs.getString(2);
            const arr = partsByMsg.get(revId) || [];
            arr.push({ kind, payload });
            partsByMsg.set(revId, arr);
          }
        } finally {
          partRs.close();
        }
      } catch (_) {}

      const rawMsgs: AndroidSqliteRowMsg[] = [];
      const msgRs = await rdb.querySql(
        'SELECT id, conversation_id, role, timestamp, model_id, total_tokens, translation, group_id, version, prompt_tokens, completion_tokens, cached_tokens, duration_ms FROM message_rows WHERE conversation_id = ? ORDER BY message_order ASC, version ASC',
        [cm.id]
      );
      try {
        while (msgRs.goToNextRow()) {
          const role = msgRs.getString(2);
          if (role !== 'user' && role !== 'assistant') continue;
          const tsUs = msgRs.getLong(3);
          const totalTok = msgRs.isColumnNull(5) ? undefined : msgRs.getLong(5);
          rawMsgs.push({
            id: msgRs.getString(0),
            conversationId: cm.id,
            role,
            timestampMs: tsUs > 100000000000000 ? Math.floor(tsUs / 1000) : tsUs,
            modelId: msgRs.isColumnNull(4) ? '' : msgRs.getString(4),
            translation: msgRs.isColumnNull(6) ? '' : msgRs.getString(6),
            groupId: msgRs.isColumnNull(7) ? '' : msgRs.getString(7),
            version: msgRs.isColumnNull(8) ? 0 : msgRs.getLong(8),
            totalTokens: totalTok,
            promptTokens: msgRs.isColumnNull(9) ? undefined : msgRs.getLong(9),
            completionTokens: msgRs.isColumnNull(10) ? undefined : msgRs.getLong(10),
            cachedTokens: msgRs.isColumnNull(11) ? undefined : msgRs.getLong(11),
            durationMs: msgRs.isColumnNull(12) ? undefined : msgRs.getLong(12)
          });
        }
      } finally {
        msgRs.close();
      }

      const groups = new Map<string, AndroidSqliteRowMsg[]>();
      for (let m = 0; m < rawMsgs.length; m++) {
        const rm = rawMsgs[m];
        const gid = rm.groupId || rm.id;
        const arr = groups.get(gid) || [];
        arr.push(rm);
        groups.set(gid, arr);
      }

      const messages: ChatMessage[] = [];
      groups.forEach((items: AndroidSqliteRowMsg[], gid: string) => {
        items.sort((a: AndroidSqliteRowMsg, b: AndroidSqliteRowMsg): number => a.version - b.version);
        const selVer = cm.verSelections[gid];
        let activeIdx = items.length - 1;
        if (selVer !== undefined) {
          const idx = items.findIndex((it: AndroidSqliteRowMsg): boolean => it.version === selVer);
          if (idx >= 0) activeIdx = idx;
        }

        const buildTextAndAttachments = (msgRow: AndroidSqliteRowMsg): SqliteMsgPartsResult => {
          const parts = partsByMsg.get(msgRow.id) || [];
          const texts: string[] = [];
          const reasons: string[] = [];
          const atts: Attachment[] = [];
          for (let p = 0; p < parts.length; p++) {
            const pt = parts[p];
            if (pt.kind === 'text') texts.push(pt.payload);
            else if (pt.kind === 'reasoning') reasons.push(pt.payload);
            else if (pt.kind === 'image' || pt.kind === 'file') {
              try {
                const obj = JSON.parse(pt.payload) as Record<string, string>;
                const uri = obj['uri'] || '';
                const fname = obj['name'] || (uri.split('/').pop() || 'file');
                const mime = obj['mime'] || (pt.kind === 'image' ? 'image/png' : 'application/octet-stream');
                const localPath = resolveExtractedPath(uri);
                let decodedName = fname;
                try { decodedName = decodeURIComponent(fname); } catch (_) {}
                atts.push({
                  id: msgRow.id + '-a-' + p,
                  name: decodedName,
                  mime,
                  data: '',
                  filePath: localPath,
                  kind: pt.kind === 'image' ? 'image' : 'text'
                });
              } catch (_) {}
            }
          }
          return { text: texts.join(''), reasoning: reasons.join('\n'), atts };
        };

        const selected = items[activeIdx];
        const selData = buildTextAndAttachments(selected);
        const versions: MessageVersion[] = [];
        for (let v = 0; v < items.length; v++) {
          const d = buildTextAndAttachments(items[v]);
          versions.push({
            id: items[v].id,
            text: d.text,
            reasoning: d.reasoning,
            model: items[v].modelId,
            createdAt: items[v].timestampMs,
            translation: items[v].translation || undefined
          });
        }

        messages.push({
          id: selected.id,
          role: selected.role === 'assistant' ? 'assistant' : 'user',
          text: selData.text,
          model: selected.modelId,
          reasoning: selData.reasoning,
          createdAt: selected.timestampMs,
          translation: selected.translation || undefined,
          attachment: selData.atts.length > 0 ? selData.atts[0] : undefined,
          attachments: selData.atts.length > 1 ? selData.atts : undefined,
          usage: typeof selected.totalTokens === 'number' ? {
            promptTokens: selected.promptTokens || 0,
            completionTokens: selected.completionTokens || 0,
            cachedTokens: selected.cachedTokens || 0,
            totalTokens: selected.totalTokens,
            durationMs: selected.durationMs || 0
          } : undefined,
          versions: versions.length > 1 ? versions : undefined,
          activeVersion: versions.length > 1 ? activeIdx : undefined
        });
      });

      out.push({
        id: cm.id,
        title: cm.title || 'Android 导入对话',
        updated: cm.updatedMs || Date.now(),
        pinned: cm.pinned,
        messages,
        personaId: cm.personaId,
        contextStartIndex: cm.truncIdx >= 0 ? cm.truncIdx : undefined,
        overrideProviderId: cm.overrideProv,
        overrideModel: cm.overrideModel
      });
    }
    return out;
  } finally {
    if (rdb) {
      try { await rdb.close(); } catch (_) {}
    }
    try { await fs.unlink(dbPath); } catch (_) {}
    try { await fs.unlink(dbPath + '-wal'); } catch (_) {}
    try { await fs.unlink(dbPath + '-shm'); } catch (_) {}
    try { await fs.rmdir(dirPath); } catch (_) {}
  }
}

async function extractZipAttachments(
  filesDir: string,
  zipBytes: Uint8Array,
  entries: ZipEntryMeta[]
): Promise<ExtractedAttachmentResult> {
  const pathMap = new Map<string, string>();
  let count = 0;
  let totalExtracted = 0;
  const MAX_SINGLE = 20 * 1024 * 1024;
  const MAX_TOTAL = 64 * 1024 * 1024;

  for (let i = 0; i < entries.length; i++) {
    const e = entries[i];
    const norm = normalizeZipEntryPath(e.name);
    if (!norm.startsWith('upload/') && !norm.startsWith('images/')) continue;
    if (e.size <= 0 || e.size > MAX_SINGLE || totalExtracted + e.size > MAX_TOTAL) continue;
    try {
      const raw = await extractZipEntryBytes(zipBytes, e);
      const base = norm.split('/').pop() || ('file_' + i);
      const ext = (base.split('.').pop() || '').toLowerCase();
      const isImg = ['png', 'jpg', 'jpeg', 'webp', 'gif'].includes(ext);
      const savedPath = await saveAttachmentToSandbox(
        filesDir,
        util.generateRandomUUID(true).slice(0, 12),
        base,
        isImg ? ('image/' + (ext === 'jpg' ? 'jpeg' : ext)) : 'application/octet-stream',
        raw,
        isImg ? 'image' : 'text'
      );
      pathMap.set(norm, savedPath);
      totalExtracted += raw.length;
      count++;
    } catch (_) {}
  }
  return { pathMap, count };
}

async function unwrapEncryptedBytes(
  rawBytes: Uint8Array,
  presetPassword: string,
  promptPassword?: PasswordPromptFn
): Promise<Uint8Array> {
  if (isKelivencBytes(rawBytes)) {
    let pwd = presetPassword.trim();
    if (!pwd && promptPassword) {
      const res = await promptPassword(false);
      if (res === undefined) throw new BackupCancelledError();
      pwd = res;
    }
    while (true) {
      try {
        return await decryptKelivencBytes(rawBytes, pwd);
      } catch (e) {
        if (!promptPassword) throw e as Error;
        const retry = await promptPassword(true);
        if (retry === undefined) throw new BackupCancelledError();
        pwd = retry;
      }
    }
  }

  // Check legacy kelivo-enc-v1 JSON wrapper
  const headText = util.TextDecoder.create('utf-8', { fatal: false }).decodeToString(
    rawBytes.subarray(0, Math.min(256, rawBytes.length))
  );
  if (headText.trim().startsWith('{') && headText.includes('"kelivo-enc-v1"')) {
    const fullText = util.TextDecoder.create('utf-8', { fatal: false }).decodeToString(rawBytes);
    let pwd = presetPassword.trim();
    if (!pwd && promptPassword) {
      const res = await promptPassword(false);
      if (res === undefined) throw new BackupCancelledError();
      pwd = res;
    }
    while (true) {
      try {
        const plainText = await decryptBackupText(fullText, pwd);
        return util.TextEncoder.create('utf-8').encodeInto(plainText);
      } catch (e) {
        if (!promptPassword) throw e as Error;
        const retry = await promptPassword(true);
        if (retry === undefined) throw new BackupCancelledError();
        pwd = retry;
      }
    }
  }

  return rawBytes;
}

export async function importBackupBytes(
  context: common.UIAbilityContext | undefined,
  current: Workspace,
  rawBytes: Uint8Array,
  scope: BackupScopeConfig,
  mode: 'merge' | 'overwrite',
  presetPassword: string = '',
  promptPassword?: PasswordPromptFn,
  forcedSource?: 'cherry' | 'chatbox' | 'auto'
): Promise<RestoreOutcome> {
  const normScope = normalizeBackupScope(scope);
  const unwrapped = await unwrapEncryptedBytes(rawBytes, presetPassword, promptPassword);
  const decoder = util.TextDecoder.create('utf-8', { fatal: false });
  const isZip = unwrapped.length >= 4 && unwrapped[0] === 0x50 && unwrapped[1] === 0x4b;

  let parsed: ParsedBackupData | undefined = undefined;
  let restoredFileCount = 0;

  if (isZip) {
    const entries = listZipEntries(unwrapped);
    const extractedMap: ExtractedAttachmentResult = (context && normScope.attachments)
      ? await extractZipAttachments(context.filesDir, unwrapped, entries)
      : { pathMap: new Map<string, string>(), count: 0 };
    restoredFileCount = extractedMap.count;

    // 1. Native lossless Harmony workspace inside ZIP?
    const harmonyEntry = findZipEntry(entries, 'kelivo_harmony_workspace.json');
    if (harmonyEntry && forcedSource !== 'cherry' && forcedSource !== 'chatbox') {
      const hJson = decoder.decodeToString(await extractZipEntryBytes(unwrapped, harmonyEntry));
      parsed = parseHarmonyBackupJson(hJson);
    }

    // 2. Chatbox v2 ZIP?
    if (!parsed) {
      const manifestEntry = findZipEntry(entries, 'manifest.json');
      if (manifestEntry) {
        const manifestText = decoder.decodeToString(await extractZipEntryBytes(unwrapped, manifestEntry));
        if (forcedSource === 'chatbox' || manifestText.includes('"chatbox-backup"')) {
          const filesMap: Record<string, string> = {};
          filesMap['manifest.json'] = manifestText;
          for (let i = 0; i < entries.length; i++) {
            const norm = normalizeZipEntryPath(entries[i].name);
            if (!norm.endsWith('.json') || norm === 'manifest.json') continue;
            if (entries[i].size > 32 * 1024 * 1024) continue;
            try {
              filesMap[norm] = decoder.decodeToString(await extractZipEntryBytes(unwrapped, entries[i]));
            } catch (_) {}
          }
          parsed = parseChatboxData(assembleChatboxZipV2Json(filesMap));
        }
      }
    }

    // 3. Android Kelivo ZIP (settings.json + database/kelivo.db OR chats.json)
    if (!parsed && forcedSource !== 'cherry' && forcedSource !== 'chatbox') {
      const settingsEntry = findZipEntry(entries, 'settings.json');
      const dbEntry = findZipEntry(entries, 'database/kelivo.db');
      const chatsEntry = findZipEntry(entries, 'chats.json');

      if (settingsEntry || dbEntry || chatsEntry) {
        if (settingsEntry) {
          const sText = decoder.decodeToString(await extractZipEntryBytes(unwrapped, settingsEntry));
          parsed = parseAndroidSettingsJson(sText);
        } else {
          parsed = { sourceName: 'Kelivo (Android)', secretsToStore: {} };
        }
        if (dbEntry && context) {
          const dbRaw = await extractZipEntryBytes(unwrapped, dbEntry);
          parsed.conversations = await readAndroidSqliteChats(context, dbRaw, extractedMap.pathMap);
        } else if (chatsEntry) {
          const cText = decoder.decodeToString(await extractZipEntryBytes(unwrapped, chatsEntry));
          parsed.conversations = parseAndroidChatsJson(cText);
        }
      }
    }

    // 4. Cherry Studio ZIP (or forced Cherry)
    if (!parsed) {
      const jsonEntries = entries.filter((e: ZipEntryMeta): boolean =>
        normalizeZipEntryPath(e.name).toLowerCase().endsWith('.json') && e.size > 0 && e.size < 64 * 1024 * 1024
      );
      for (let i = 0; i < jsonEntries.length; i++) {
        try {
          const txt = decoder.decodeToString(await extractZipEntryBytes(unwrapped, jsonEntries[i]));
          if (txt.includes('"localStorage"') && txt.includes('"indexedDB"')) {
            parsed = parseCherryStudioData(txt);
            break;
          }
        } catch (_) {}
      }
      if (!parsed && forcedSource === 'cherry') {
        throw new Error('Cherry Studio ZIP 中未找到有效数据文件 (data.json)');
      }
    }

    if (!parsed) {
      throw new Error('未能识别此 ZIP 备份文件格式');
    }
  } else {
    const plainText = decoder.decodeToString(unwrapped);
    if (forcedSource === 'cherry') {
      parsed = parseCherryStudioData(plainText);
    } else if (forcedSource === 'chatbox') {
      parsed = parseChatboxData(plainText);
    } else {
      const trimmed = plainText.trim();
      if (trimmed.includes('"kelivo-workspace-backup"') || trimmed.includes('"kelivo-arkui-full"')) {
        parsed = parseHarmonyBackupJson(plainText);
      } else if (trimmed.includes('"provider_configs_v1"') || trimmed.includes('"assistants_v1"')) {
        parsed = parseAndroidSettingsJson(plainText);
      } else {
        parsed = detectAndParseThirdPartyJson(plainText);
      }
    }
  }

  const out: ApplyRestoreOutput = applyScopedRestore(
    current,
    parsed,
    normScope,
    mode,
    (): string => util.generateRandomUUID(true)
  );
  await persistSecretsMap(out.secretsToStore);
  out.stats.files = restoredFileCount;
  return {
    workspace: out.workspace,
    stats: out.stats,
    summary: out.summary + (restoredFileCount > 0 ? (' · ' + restoredFileCount + ' 个文件') : '')
  };
}

export async function restoreFromBackupPayload(
  current: Workspace,
  rawPayload: string,
  mode: 'merge' | 'overwrite',
  password: string = '',
  scope?: BackupScopeConfig
): Promise<RestoreOutcome> {
  const bytes = util.TextEncoder.create('utf-8').encodeInto(rawPayload);
  return importBackupBytes(
    undefined,
    current,
    bytes,
    scope || defaultBackupScope(),
    mode,
    password
  );
}

// ===== Local Copies / Snapshots =====
export async function createLocalSnapshot(
  filesDir: string,
  workspace: Workspace,
  reason: 'auto' | 'manual' | 'pre_restore',
  pinned: boolean = false
): Promise<LocalSnapshotMeta> {
  const dir = filesDir + '/snapshots';
  await ensureDir(dir);
  const id = util.generateRandomUUID(true);
  const fileName = 'snap-' + reason + '-' + Date.now() + '.zip';
  const cfg = workspace.backupConfig || defaultBackupConfig();
  const snapScope = normalizeBackupScope({
    chats: true,
    attachments: false,
    assistants: true,
    providers: true,
    mcp: true,
    envVars: true,
    skills: true,
    worldBooks: true,
    memory: true,
    quickPhrases: true,
    instructions: true,
    workspaces: true,
    search: true,
    speech: true,
    settings: true
  });
  const built = await buildBackupArchiveBytes(workspace, snapScope, '');
  await writeBinaryFile(dir + '/' + fileName, built.bytes);

  let msgCount = 0;
  for (let i = 0; i < workspace.conversations.length; i++) {
    if (!workspace.conversations[i].ephemeral) {
      msgCount += workspace.conversations[i].messages.length;
    }
  }

  const meta: LocalSnapshotMeta = {
    id,
    fileName,
    createdAt: Date.now(),
    sizeBytes: built.bytes.length,
    reason,
    encrypted: false,
    pinned: pinned || reason === 'pre_restore',
    conversationCount: workspace.conversations.filter((c: Conversation): boolean => !c.ephemeral).length,
    messageCount: msgCount
  };
  const next = [meta, ...(workspace.snapshots || [])];
  workspace.snapshots = await pruneSnapshots(dir, next, cfg);
  return meta;
}

async function pruneSnapshots(
  dir: string,
  list: LocalSnapshotMeta[],
  cfg: BackupPreferencesConfig
): Promise<LocalSnapshotMeta[]> {
  const sorted = list.slice().sort((a: LocalSnapshotMeta, b: LocalSnapshotMeta): number => b.createdAt - a.createdAt);
  const keepRecent = Math.max(1, Math.min(10, cfg.localCopiesKeepRecent || 3));
  const keepIds = new Set<string>();
  const now = Date.now();
  const weekMs = 7 * 24 * 3600 * 1000;
  let keptWeek = false;
  let keptMonth = false;
  let unpinnedRecent = 0;

  for (let i = 0; i < sorted.length; i++) {
    const s = sorted[i];
    if (s.pinned || s.reason === 'pre_restore') {
      keepIds.add(s.id);
      continue;
    }
    if (unpinnedRecent < keepRecent) {
      keepIds.add(s.id);
      unpinnedRecent++;
    } else if (cfg.localCopiesKeepWeekly && !keptWeek && now - s.createdAt >= weekMs && now - s.createdAt < 4 * weekMs) {
      keepIds.add(s.id);
      keptWeek = true;
    } else if (cfg.localCopiesKeepMonthly && !keptMonth && now - s.createdAt >= 4 * weekMs) {
      keepIds.add(s.id);
      keptMonth = true;
    }
  }

  // Respect maximumTotalBytes cap across unpinned snapshots (keep newest first)
  if (cfg.localCopiesMaxBytes > 0) {
    let runningBytes = 0;
    for (let i = 0; i < sorted.length; i++) {
      if (keepIds.has(sorted[i].id)) runningBytes += sorted[i].sizeBytes;
    }
    for (let i = sorted.length - 1; i >= 0 && runningBytes > cfg.localCopiesMaxBytes; i--) {
      const s = sorted[i];
      if (!keepIds.has(s.id) || s.pinned || s.reason === 'pre_restore') continue;
      if (i === 0) break; // Always keep the single latest copy
      keepIds.delete(s.id);
      runningBytes -= s.sizeBytes;
    }
  }

  const kept: LocalSnapshotMeta[] = [];
  for (let i = 0; i < sorted.length; i++) {
    if (keepIds.has(sorted[i].id)) {
      kept.push(sorted[i]);
    } else {
      try { await fs.unlink(dir + '/' + sorted[i].fileName); } catch (_) {}
    }
  }
  return kept;
}

export async function readLocalSnapshotBytes(filesDir: string, fileName: string): Promise<Uint8Array> {
  return readBinaryFile(filesDir + '/snapshots/' + fileName);
}

export async function readLocalSnapshotPayload(filesDir: string, fileName: string): Promise<string> {
  const bytes = await readLocalSnapshotBytes(filesDir, fileName);
  return util.TextDecoder.create('utf-8').decodeToString(bytes);
}

export async function deleteLocalSnapshotFile(filesDir: string, fileName: string): Promise<void> {
  try {
    await fs.unlink(filesDir + '/snapshots/' + fileName);
  } catch (_) {}
}

export async function exportLocalSnapshotToFile(
  context: common.UIAbilityContext,
  filesDir: string,
  meta: LocalSnapshotMeta
): Promise<boolean> {
  const bytes = await readLocalSnapshotBytes(filesDir, meta.fileName);
  const ext = meta.fileName.endsWith('.json') ? '.json' : '.zip';
  const name = 'kelivo_copy_' + new Date(meta.createdAt).toISOString().replace(/:/g, '-').slice(0, 19) + ext;
  const paths = await new picker.DocumentViewPicker(context).save({ newFileNames: [name] });
  if (!paths.length) return false;
  await writeBinaryFile(paths[0], bytes);
  return true;
}

export async function exportFullBackupToFile(
  context: common.UIAbilityContext,
  workspace: Workspace,
  scope: BackupScopeConfig,
  password: string
): Promise<boolean> {
  const built = await buildBackupArchiveBytes(workspace, scope, password);
  const paths = await new picker.DocumentViewPicker(context).save({
    newFileNames: [built.fileName]
  });
  if (!paths.length) return false;
  await writeBinaryFile(paths[0], built.bytes);
  return true;
}

async function pickBytesWithFilter(
  context: common.UIAbilityContext,
  filters?: string[]
): Promise<Uint8Array | undefined> {
  const opts: picker.DocumentSelectOptions = filters && filters.length > 0
    ? { maxSelectNumber: 1, fileSuffixFilters: filters }
    : { maxSelectNumber: 1 };
  const paths = await new picker.DocumentViewPicker(context).select(opts);
  if (!paths.length) return undefined;
  const file = await fs.open(paths[0], fs.OpenMode.READ_ONLY);
  try {
    return await readFileHandleBytes(file);
  } finally {
    await fs.close(file);
  }
}

export async function pickAnyBackupBytes(context: common.UIAbilityContext): Promise<Uint8Array | undefined> {
  return pickBytesWithFilter(context);
}

export async function pickCherryBackupBytes(context: common.UIAbilityContext): Promise<Uint8Array | undefined> {
  return pickBytesWithFilter(context, ['Cherry Studio 备份|.zip,.bak,.json']);
}

export async function pickChatboxBackupBytes(context: common.UIAbilityContext): Promise<Uint8Array | undefined> {
  return pickBytesWithFilter(context, ['Chatbox 备份|.json,.zip']);
}

export async function pickThirdPartyOrFullBackup(context: common.UIAbilityContext): Promise<string | undefined> {
  const bytes = await pickAnyBackupBytes(context);
  if (!bytes) return undefined;
  return util.TextDecoder.create('utf-8', { fatal: false }).decodeToString(bytes);
}

export function formatBytesReadable(bytes: number): string {
  if (!bytes || bytes <= 0) return '0 B';
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
}
