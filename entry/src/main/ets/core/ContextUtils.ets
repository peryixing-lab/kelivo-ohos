import { ChatMessage, MessageVersion, messageText } from './Models';

export function sliceContextMessages(
  messages: ChatMessage[],
  contextStartIndex: number = 0,
  contextLimit: number = 0
): ChatMessage[] {
  const start = Math.max(0, Math.min(contextStartIndex, messages.length));
  const afterStart = messages.slice(start);
  // If there is a summary message, start context from the latest summary
  let summaryIdx = -1;
  for (let i = afterStart.length - 1; i >= 0; i--) {
    if (afterStart[i].isSummary) {
      summaryIdx = i;
      break;
    }
  }
  const effective = summaryIdx >= 0 ? afterStart.slice(summaryIdx) : afterStart;
  if (contextLimit > 0 && effective.length > contextLimit) {
    return effective.slice(effective.length - contextLimit);
  }
  return effective;
}

export function buildCompressionPrompt(messages: ChatMessage[], template: string): string {
  const transcript = messages.map((m: ChatMessage): string => {
    const label = m.role === 'user' ? 'User' : 'Assistant';
    return label + ': ' + messageText(m);
  }).join('\n\n');
  return template + '\n\n---\n对话内容：\n' + transcript;
}

export function applyContextCompression(
  messages: ChatMessage[],
  summaryText: string,
  summaryId: string,
  model: string
): ChatMessage[] {
  if (!messages.length) return [];
  const summaryMsg: ChatMessage = {
    id: summaryId,
    role: 'assistant',
    text: '【上下文摘要】\n' + summaryText.trim(),
    model,
    createdAt: Date.now(),
    isSummary: true,
    compressedCount: messages.length,
    compressionSnapshot: messages.slice()
  };
  return [summaryMsg];
}

export function undoContextCompression(messages: ChatMessage[]): ChatMessage[] {
  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    if (msg.isSummary && msg.compressionSnapshot && msg.compressionSnapshot.length > 0) {
      const before = messages.slice(0, i);
      const after = messages.slice(i + 1);
      return [...before, ...msg.compressionSnapshot, ...after];
    }
  }
  return messages;
}

export function ensureMessageVersions(msg: ChatMessage): MessageVersion[] {
  if (msg.versions && msg.versions.length > 0) return msg.versions.slice();
  return [{
    id: msg.id + '-v0',
    text: msg.text,
    reasoning: msg.reasoning || '',
    model: msg.model,
    createdAt: msg.createdAt || Date.now(),
    usage: msg.usage,
    toolCalls: msg.toolCalls,
    generatedImages: msg.generatedImages,
    sources: msg.sources,
    translation: msg.translation
  }];
}

export function appendMessageVersion(msg: ChatMessage, nextVer: MessageVersion): ChatMessage {
  const existing = ensureMessageVersions(msg);
  existing.push(nextVer);
  return {
    id: msg.id,
    role: msg.role,
    text: nextVer.text,
    model: nextVer.model,
    attachment: msg.attachment,
    attachments: msg.attachments,
    reasoning: nextVer.reasoning,
    sources: nextVer.sources,
    createdAt: nextVer.createdAt,
    usage: nextVer.usage,
    toolCalls: nextVer.toolCalls,
    generatedImages: nextVer.generatedImages,
    quote: msg.quote,
    translation: nextVer.translation,
    versions: existing,
    activeVersion: existing.length - 1
  };
}

export function switchMessageVersion(msg: ChatMessage, targetIndex: number): ChatMessage {
  const versions = ensureMessageVersions(msg);
  if (!versions.length) return msg;
  const idx = Math.max(0, Math.min(versions.length - 1, targetIndex));
  const sel = versions[idx];
  return {
    id: msg.id,
    role: msg.role,
    text: sel.text,
    model: sel.model,
    attachment: msg.attachment,
    attachments: msg.attachments,
    reasoning: sel.reasoning,
    sources: sel.sources,
    createdAt: sel.createdAt,
    usage: sel.usage,
    toolCalls: sel.toolCalls,
    generatedImages: sel.generatedImages,
    quote: msg.quote,
    translation: sel.translation,
    versions,
    activeVersion: idx
  };
}

export function deleteMessageVersion(msg: ChatMessage, targetIndex?: number): ChatMessage | undefined {
  const versions = ensureMessageVersions(msg);
  if (versions.length <= 1) {
    return undefined;
  }
  const rawIdx = targetIndex !== undefined ? targetIndex : (msg.activeVersion ?? (versions.length - 1));
  const curIdx = Math.max(0, Math.min(versions.length - 1, rawIdx));
  const remaining: MessageVersion[] = [];
  for (let i = 0; i < versions.length; i++) {
    if (i !== curIdx) {
      remaining.push(versions[i]);
    }
  }
  if (!remaining.length) {
    return undefined;
  }
  const nextIdx = Math.min(curIdx, remaining.length - 1);
  const sel = remaining[nextIdx];
  const hasMulti = remaining.length > 1;
  return {
    id: msg.id,
    role: msg.role,
    text: sel.text,
    model: sel.model,
    attachment: msg.attachment,
    attachments: msg.attachments,
    reasoning: sel.reasoning,
    sources: sel.sources,
    createdAt: sel.createdAt,
    usage: sel.usage,
    toolCalls: sel.toolCalls,
    generatedImages: sel.generatedImages,
    quote: msg.quote,
    translation: sel.translation,
    versions: hasMulti ? remaining : undefined,
    activeVersion: hasMulti ? nextIdx : undefined
  };
}

export function updateActiveMessageVersionText(msg: ChatMessage, nextText: string): ChatMessage {
  let nextVersions: MessageVersion[] | undefined = undefined;
  let activeIdx = msg.activeVersion;
  if (msg.versions && msg.versions.length > 0) {
    const idx = Math.max(0, Math.min(msg.versions.length - 1, msg.activeVersion ?? (msg.versions.length - 1)));
    activeIdx = idx;
    nextVersions = msg.versions.map((ver: MessageVersion, vi: number): MessageVersion => {
      if (vi !== idx) return ver;
      return {
        id: ver.id,
        text: nextText,
        reasoning: ver.reasoning,
        model: ver.model,
        createdAt: ver.createdAt,
        usage: ver.usage,
        toolCalls: ver.toolCalls,
        generatedImages: ver.generatedImages,
        sources: ver.sources,
        translation: ver.translation
      };
    });
  }
  return {
    id: msg.id,
    role: msg.role,
    text: nextText,
    model: msg.model,
    attachment: msg.attachment,
    attachments: msg.attachments,
    reasoning: msg.reasoning,
    sources: msg.sources,
    createdAt: msg.createdAt,
    usage: msg.usage,
    toolCalls: msg.toolCalls,
    generatedImages: msg.generatedImages,
    quote: msg.quote,
    translation: msg.translation,
    versions: nextVersions,
    activeVersion: activeIdx
  };
}

export function updateActiveMessageVersionTranslation(msg: ChatMessage, translation: string | undefined): ChatMessage {
  let nextVersions: MessageVersion[] | undefined = undefined;
  let activeIdx = msg.activeVersion;
  if (msg.versions && msg.versions.length > 0) {
    const idx = Math.max(0, Math.min(msg.versions.length - 1, msg.activeVersion ?? (msg.versions.length - 1)));
    activeIdx = idx;
    nextVersions = msg.versions.map((ver: MessageVersion, vi: number): MessageVersion => {
      if (vi !== idx) return ver;
      return {
        id: ver.id,
        text: ver.text,
        reasoning: ver.reasoning,
        model: ver.model,
        createdAt: ver.createdAt,
        usage: ver.usage,
        toolCalls: ver.toolCalls,
        generatedImages: ver.generatedImages,
        sources: ver.sources,
        translation
      };
    });
  }
  return {
    id: msg.id,
    role: msg.role,
    text: msg.text,
    model: msg.model,
    attachment: msg.attachment,
    attachments: msg.attachments,
    reasoning: msg.reasoning,
    sources: msg.sources,
    createdAt: msg.createdAt,
    usage: msg.usage,
    toolCalls: msg.toolCalls,
    generatedImages: msg.generatedImages,
    quote: msg.quote,
    translation,
    versions: nextVersions,
    activeVersion: activeIdx
  };
}

export function exportMessagesAsMarkdown(title: string, msgs: ChatMessage[]): string {
  const lines: string[] = ['# ' + title, ''];
  for (let i = 0; i < msgs.length; i++) {
    const m = msgs[i];
    const who = m.role === 'user' ? '## 用户' : '## 助手' + (m.model ? ' (`' + m.model + '`)' : '');
    lines.push(who, '');
    if (m.reasoning) {
      lines.push('<details><summary>思考过程</summary>', '', m.reasoning, '', '</details>', '');
    }
    lines.push(m.text, '');
    if (m.sources?.length) {
      lines.push('**来源引用**');
      for (let j = 0; j < m.sources.length; j++) {
        lines.push('- [' + m.sources[j].title + '](' + m.sources[j].url + ')');
      }
      lines.push('');
    }
  }
  return lines.join('\n');
}

export function exportMessagesAsPlainText(title: string, msgs: ChatMessage[]): string {
  const lines: string[] = [title, '========================================', ''];
  for (let i = 0; i < msgs.length; i++) {
    const m = msgs[i];
    const who = m.role === 'user' ? '[用户]' : '[助手' + (m.model ? ' · ' + m.model : '') + ']';
    lines.push(who);
    lines.push(m.text);
    lines.push('');
  }
  return lines.join('\n');
}
