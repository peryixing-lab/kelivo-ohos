import { Attachment, ChatMessage, Conversation, SearchHit } from './Models';

interface NativeArchive { format: string; version: number; conversations: Conversation[] }
interface FlutterChat {
  id: string;
  title: string;
  updatedAt: string;
  isPinned?: boolean;
  messageIds: string[];
  versionSelections?: Record<string, number>;
}
interface FlutterMessage {
  id: string;
  conversationId: string;
  role: string;
  content: string;
  modelId?: string;
  reasoningText?: string;
  groupId?: string;
  version?: number;
}
interface FlutterArchive { version: number; conversations: FlutterChat[]; messages: FlutterMessage[] }

function validAttachment(file: Attachment): boolean {
  return !!file && typeof file.name === 'string' && typeof file.data === 'string' &&
    ['text/plain', 'image/png', 'image/jpeg', 'image/webp'].includes(file.mime);
}

function validChat(chat: Conversation): boolean {
  return !!chat && typeof chat.id === 'string' && chat.id.length > 0 && typeof chat.title === 'string' &&
    (chat.pinned === undefined || typeof chat.pinned === 'boolean') && typeof chat.personaId === 'string' && Number.isFinite(chat.updated) && Array.isArray(chat.messages) &&
    new Set(chat.messages.map((msg: ChatMessage) => msg?.id)).size === chat.messages.length &&
    chat.messages.every((msg: ChatMessage) => !!msg && typeof msg.id === 'string' && msg.id.length > 0 &&
      typeof msg.text === 'string' && typeof msg.model === 'string' &&
      (msg.role === 'user' || msg.role === 'assistant') && (!msg.attachment || validAttachment(msg.attachment)) &&
      (!msg.sources || (Array.isArray(msg.sources) && msg.sources.every((hit: SearchHit) =>
        !!hit && typeof hit.title === 'string' && typeof hit.excerpt === 'string' && typeof hit.url === 'string' && /^https?:\/\//i.test(hit.url)))) &&
      (msg.reasoning === undefined || typeof msg.reasoning === 'string'));
}

export function encodeArchive(chats: Conversation[]): string {
  const archive: NativeArchive = { format: 'kelivo-arkui-chats', version: 1, conversations: chats };
  return JSON.stringify(archive);
}

function flutterChats(archive: FlutterArchive): Conversation[] {
  const lookup = new Map<string, FlutterMessage>();
  archive.messages.forEach((msg: FlutterMessage) => {
    if (!msg || typeof msg.id !== 'string' || typeof msg.content !== 'string' || typeof msg.conversationId !== 'string') {
      throw new Error('备份中的消息数据不完整');
    }
    lookup.set(msg.id, msg);
  });
  return archive.conversations.map((chat: FlutterChat): Conversation => {
    if (!chat || typeof chat.id !== 'string' || typeof chat.title !== 'string' || !Array.isArray(chat.messageIds)) {
      throw new Error('备份中的会话数据不完整');
    }
    const groups = new Map<string, FlutterMessage[]>();
    chat.messageIds.forEach((id: string) => {
      const msg = lookup.get(id);
      if (!msg || msg.conversationId !== chat.id || (msg.role !== 'assistant' && msg.role !== 'user')) return;
      const gid = msg.groupId || msg.id;
      const group = groups.get(gid);
      if (group) group.push(msg);
      else groups.set(gid, [msg]);
    });
    const messages: ChatMessage[] = [];
    groups.forEach((items: FlutterMessage[], gid: string) => {
      items.sort((a: FlutterMessage, b: FlutterMessage) => (a.version || 0) - (b.version || 0));
      const selected = items.find((m: FlutterMessage) => m.version === chat.versionSelections?.[gid]) || items[items.length - 1];
      messages.push({ id: selected.id, role: selected.role === 'assistant' ? 'assistant' : 'user',
        text: selected.content, model: selected.modelId || '', reasoning: selected.reasoningText || '' });
    });
    return { id: chat.id, title: chat.title, updated: Date.parse(chat.updatedAt), pinned: chat.isPinned === true, messages, personaId: 'default' };
  });
}

export function decodeArchive(raw: string): Conversation[] {
  const input = JSON.parse(raw) as NativeArchive;
  if (!input || input.version !== 1 || !Array.isArray(input.conversations)) throw new Error('无法识别会话备份格式');
  let chats: Conversation[];
  if (input.format === 'kelivo-arkui-chats') chats = input.conversations;
  else {
    const legacy = JSON.parse(raw) as FlutterArchive;
    if (input.format || !Array.isArray(legacy.messages)) throw new Error('请选择本应用的 JSON 备份或 Kelivo 的 chats.json');
    chats = flutterChats(legacy);
  }
  if (!chats.every(validChat)) throw new Error('备份中存在无效会话');
  return chats;
}

