import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Attachment, ContextLogEntry, Conversation, RequestLogEntry, UsageStatRow, Workspace, initialWorkspace } from './Models';
import { readFlutterZip } from './FlutterBackup';
import { decodeArchive, encodeArchive } from './ChatArchive';
import { KelivoDatabase } from './Database';
import { hydrateAttachmentData, pickMultipleAttachments, readFileHandleBytes } from './AttachmentStore';

export function newId(): string { return util.generateRandomUUID(true); }

function keyQuery(ref: string): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, util.TextEncoder.create().encodeInto('kelivo.' + ref));
  return query;
}

export async function readKey(ref: string): Promise<string> {
  if (!ref) return '';
  const query = keyQuery(ref);
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  try {
    const result = await asset.query(query);
    return util.TextDecoder.create().decodeToString(result[0].get(asset.Tag.SECRET) as Uint8Array);
  } catch (e) {
    if ((e as BusinessError).code === asset.ErrorCode.NOT_FOUND) return '';
    throw new Error('系统密钥库暂时不可用，请解锁设备后重试。');
  }
}

export async function storeKey(ref: string, key: string): Promise<void> {
  const query = keyQuery(ref);
  query.set(asset.Tag.SECRET, util.TextEncoder.create().encodeInto(key));
  query.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
  try {
    await asset.remove(keyQuery(ref));
  } catch (_) {}
  await asset.add(query);
}

export async function forgetKey(ref: string): Promise<void> {
  if (ref) await asset.remove(keyQuery(ref));
}

async function writeContents(path: string, value: string): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    const bytes = util.TextEncoder.create().encodeInto(value);
    let offset = 0;
    while (offset < bytes.length) {
      const count = await fs.write(file.fd, bytes.buffer.slice(offset));
      if (count <= 0) throw new Error('文件写入失败');
      offset += count;
    }
    await fs.fsync(file.fd);
  } finally { await fs.close(file); }
}

export class WorkspaceStore {
  private file: string;
  private db?: KelivoDatabase;
  private pending: Promise<void> = Promise.resolve();

  constructor(dirOrContext: string | common.UIAbilityContext) {
    if (typeof dirOrContext === 'string') {
      this.file = dirOrContext + '/workspace-v1.json';
    } else {
      this.file = dirOrContext.filesDir + '/workspace-v1.json';
      this.db = new KelivoDatabase(dirOrContext);
    }
  }

  async load(): Promise<Workspace> {
    if (this.db) {
      return this.db.loadWorkspace();
    }
    let raw: string;
    try { raw = await fs.readText(this.file); }
    catch (e) {
      if ((e as BusinessError).code === 13900002) return initialWorkspace();
      throw e as Error;
    }
    const workspace = JSON.parse(raw) as Workspace;
    if (workspace.version !== 1 || !Array.isArray(workspace.conversations) ||
      !workspace.providers?.length || !workspace.personas?.length) throw new Error('无法读取本地工作区');
    return workspace;
  }

  save(workspace: Workspace): Promise<void> {
    if (this.db) {
      return this.db.saveWorkspace(workspace);
    }
    const snapshot = JSON.stringify(workspace);
    const task = this.pending.then(async () => {
      const temp = this.file + '.tmp';
      await writeContents(temp, snapshot);
      await fs.rename(temp, this.file);
    });
    this.pending = task.catch(() => {});
    return task;
  }

  async addRequestLog(entry: RequestLogEntry): Promise<void> {
    if (this.db) await this.db.addRequestLog(entry);
  }

  async listRequestLogs(): Promise<RequestLogEntry[]> {
    return this.db ? this.db.listRequestLogs() : [];
  }

  async clearRequestLogs(): Promise<void> {
    if (this.db) await this.db.clearRequestLogs();
  }

  async addContextLog(entry: ContextLogEntry): Promise<void> {
    if (this.db) await this.db.addContextLog(entry);
  }

  async listContextLogs(): Promise<ContextLogEntry[]> {
    return this.db ? this.db.listContextLogs() : [];
  }

  async clearContextLogs(): Promise<void> {
    if (this.db) await this.db.clearContextLogs();
  }

  async recordUsage(day: string, model: string, personaId: string, promptTokens: number, completionTokens: number, cachedTokens: number): Promise<void> {
    if (this.db) await this.db.recordUsage(day, model, personaId, promptTokens, completionTokens, cachedTokens);
  }

  async listUsageStats(): Promise<UsageStatRow[]> {
    return this.db ? this.db.listUsageStats() : [];
  }
}

export async function exportChats(context: common.UIAbilityContext, chats: Conversation[]): Promise<boolean> {
  const paths = await new picker.DocumentViewPicker(context).save({ newFileNames: ['Kelivo-' + new Date().toISOString().slice(0, 10) + '.json'] });
  if (!paths.length) return false;
  const hydrated: Conversation[] = [];
  for (let i = 0; i < chats.length; i++) {
    const c = chats[i];
    const msgs = c.messages.slice();
    for (let j = 0; j < msgs.length; j++) {
      const m = msgs[j];
      if (m.attachment && !m.attachment.data && m.attachment.filePath) {
        m.attachment = await hydrateAttachmentData(m.attachment);
      }
      if (m.attachments && m.attachments.length) {
        const list: Attachment[] = [];
        for (let k = 0; k < m.attachments.length; k++) {
          list.push(await hydrateAttachmentData(m.attachments[k]));
        }
        m.attachments = list;
      }
    }
    hydrated.push({
      id: c.id,
      title: c.title,
      updated: c.updated,
      pinned: c.pinned,
      messages: msgs,
      personaId: c.personaId
    });
  }
  await writeContents(paths[0], encodeArchive(hydrated));
  return true;
}

async function pickBytes(context: common.UIAbilityContext, filter: string[], limit: number): Promise<fs.File | undefined> {
  const paths = await new picker.DocumentViewPicker(context).select({ maxSelectNumber: 1, fileSuffixFilters: filter });
  if (!paths.length) return undefined;
  const file = await fs.open(paths[0], fs.OpenMode.READ_ONLY);
  try {
    if ((await fs.stat(file.fd)).size > limit) throw new Error('文件过大，大小上限为 ' + Math.round(limit / 1024) + ' KB');
    return file;
  } catch (e) { await fs.close(file); throw e as Error; }
}

export async function importChats(context: common.UIAbilityContext): Promise<Conversation[]> {
  const file = await pickBytes(context, ['会话备份|.json,.zip'], 64 * 1024 * 1024);
  if (!file) return [];
  try {
    const bytes = await readFileHandleBytes(file);
    const zipped = bytes[0] === 0x50 && bytes[1] === 0x4b;
    return decodeArchive(zipped ? await readFlutterZip(bytes) : util.TextDecoder.create().decodeToString(bytes));
  } finally { await fs.close(file); }
}

export async function pickAttachment(context: common.UIAbilityContext, imageQuality: number = 85): Promise<Attachment | undefined> {
  const list = await pickMultipleAttachments(context, imageQuality);
  return list.length ? list[0] : undefined;
}
