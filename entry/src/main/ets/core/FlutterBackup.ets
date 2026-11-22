import { extractZipEntryText, listZipEntries, ZipEntryMeta } from './ZipReader';

export async function readFlutterZip(bytes: Uint8Array): Promise<string> {
  const entries = listZipEntries(bytes);
  const chatEntry = entries.find((e: ZipEntryMeta): boolean => e.name === 'chats.json');
  if (!chatEntry) throw new Error('ZIP 备份中未找到 chats.json');
  if (chatEntry.size === 0) throw new Error('会话条目过大、已加密或损坏');
  return extractZipEntryText(bytes, 'chats.json');
}
