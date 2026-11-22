import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { pdfService } from '@kit.PDFKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { Attachment, AttachmentKind } from './Models';
import { extractZipEntryText } from './ZipReader';

export interface StorageBreakdown {
  databaseBytes: number;
  attachmentsBytes: number;
  snapshotsBytes: number;
  workspacesBytes: number;
  skillsBytes: number;
  totalBytes: number;
}

const TEXT_EXTENSIONS: string[] = [
  'txt', 'md', 'markdown', 'csv', 'json', 'jsonl', 'xml', 'yaml', 'yml', 'toml',
  'ts', 'tsx', 'js', 'jsx', 'ets', 'dart', 'py', 'java', 'kt', 'swift', 'go', 'rs',
  'c', 'cpp', 'h', 'hpp', 'sh', 'sql', 'html', 'htm', 'css', 'scss', 'log', 'ini'
];

const IMAGE_EXTENSIONS: string[] = ['jpg', 'jpeg', 'png', 'webp'];
const AUDIO_EXTENSIONS: string[] = ['wav', 'mp3', 'm4a', 'ogg', 'aac', 'flac'];

export async function ensureDir(path: string): Promise<void> {
  try {
    const exists = await fs.access(path);
    if (!exists) await fs.mkdir(path, true);
  } catch (_) {
    try { await fs.mkdir(path, true); } catch (__) {}
  }
}

export async function writeBinaryFile(path: string, bytes: Uint8Array): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    let offset = 0;
    while (offset < bytes.length) {
      const slice = bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + bytes.length);
      const written = await fs.write(file.fd, slice);
      if (written <= 0) throw new Error('写入文件失败');
      offset += written;
    }
    await fs.fsync(file.fd);
  } finally {
    await fs.close(file);
  }
}

export async function readBinaryFile(path: string): Promise<Uint8Array> {
  const file = await fs.open(path, fs.OpenMode.READ_ONLY);
  try {
    const size = (await fs.stat(file.fd)).size;
    const out = new Uint8Array(size);
    let offset = 0;
    while (offset < size) {
      const buf = new ArrayBuffer(Math.min(size - offset, 65536));
      const read = await fs.read(file.fd, buf);
      if (!read) break;
      out.set(new Uint8Array(buf, 0, read), offset);
      offset += read;
    }
    return out;
  } finally {
    await fs.close(file);
  }
}

export async function readFileHandleBytes(file: fs.File): Promise<Uint8Array> {
  const length = (await fs.stat(file.fd)).size;
  const bytes = new Uint8Array(length);
  let offset = 0;
  while (offset < length) {
    const chunk = new ArrayBuffer(Math.min(length - offset, 65536));
    const read = await fs.read(file.fd, chunk);
    if (!read) throw new Error('文件读取不完整');
    bytes.set(new Uint8Array(chunk, 0, read), offset);
    offset += read;
  }
  return bytes;
}

export async function compressImageBytes(bytes: Uint8Array, mime: string, quality: number): Promise<Uint8Array> {
  if (quality >= 98 && bytes.length <= 2 * 1024 * 1024) return bytes;
  const clamped = Math.max(25, Math.min(100, Math.round(quality)));
  const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length);
  const src = image.createImageSource(buf);
  const packer = image.createImagePacker();
  try {
    const targetMime = mime === 'image/png' ? 'image/jpeg' : mime;
    const packed = await packer.packToData(src, { format: targetMime, quality: clamped });
    const out = new Uint8Array(packed);
    return out.length < bytes.length || bytes.length > 3 * 1024 * 1024 ? out : bytes;
  } catch (_) {
    return bytes;
  } finally {
    try { await packer.release(); } catch (__) {}
    try { await src.release(); } catch (__) {}
  }
}

function stripXmlEntities(text: string): string {
  return text
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'");
}

export function extractDocxXmlText(xml: string): string {
  const withBreaks = xml
    .replace(/<w:p[^>]*>/g, '\n')
    .replace(/<w:br[^>]*\/>/g, '\n')
    .replace(/<w:tab[^>]*\/>/g, '\t')
    .replace(/<[^>]+>/g, '');
  return stripXmlEntities(withBreaks).replace(/\n{3,}/g, '\n\n').trim();
}

export async function extractPdfTextFromPath(path: string, maxPages: number = 40): Promise<string> {
  const doc = new pdfService.PdfDocument();
  const status = doc.loadDocument(path);
  if (status !== pdfService.ParseResult.PARSE_SUCCESS) {
    throw new Error('PDF 解析失败（错误码 ' + status + '）');
  }
  try {
    const total = Math.min(doc.getPageCount(), maxPages);
    const parts: string[] = [];
    for (let i = 0; i < total; i++) {
      const page = doc.getPage(i);
      const txt = page.getTextContent().trim();
      if (txt) parts.push('[第 ' + (i + 1) + ' 页]\n' + txt);
    }
    if (doc.getPageCount() > maxPages) {
      parts.push('\n[已截取前 ' + maxPages + ' / ' + doc.getPageCount() + ' 页]');
    }
    return parts.join('\n\n') || '[PDF 未包含可提取的文本内容，建议使用具备视觉能力的模型查看截图]';
  } finally {
    try { doc.releaseDocument(); } catch (_) {}
  }
}

export async function saveAttachmentToSandbox(
  filesDir: string,
  id: string,
  name: string,
  mime: string,
  rawBytes: Uint8Array,
  kind: AttachmentKind
): Promise<string> {
  const dir = filesDir + '/attachments';
  await ensureDir(dir);
  const ext = (name.split('.').pop() || 'bin').replace(/[^a-zA-Z0-9]/g, '').toLowerCase() || 'bin';
  const target = dir + '/' + id + '.' + ext;
  await writeBinaryFile(target, rawBytes);
  return target;
}

export async function hydrateAttachmentData(att: Attachment): Promise<Attachment> {
  if (att.data || !att.filePath) return att;
  const bytes = await readBinaryFile(att.filePath);
  let data = '';
  if (att.kind === 'text' || att.kind === 'pdf' || att.kind === 'docx' || att.mime === 'text/plain') {
    data = util.TextDecoder.create('utf-8').decodeToString(bytes);
  } else {
    data = new util.Base64Helper().encodeToStringSync(bytes);
  }
  return {
    name: att.name,
    mime: att.mime,
    data,
    id: att.id,
    filePath: att.filePath,
    sizeBytes: att.sizeBytes,
    kind: att.kind
  };
}

async function ingestFileUri(
  uri: string,
  context: common.UIAbilityContext,
  imageQuality: number,
  forceImageIfUnknown: boolean = false
): Promise<Attachment> {
  const file = await fs.open(uri, fs.OpenMode.READ_ONLY);
  try {
    const size = (await fs.stat(file.fd)).size;
    if (size > 20 * 1024 * 1024) {
      throw new Error(file.name + ' 超过 20 MB 限制');
    }
    const rawName = file.name || ('file_' + util.generateRandomUUID(true).slice(0, 8));
    const ext = rawName.split('.').pop()?.toLowerCase() || '';
    const bytes = await readFileHandleBytes(file);
    const id = util.generateRandomUUID(true);

    if (IMAGE_EXTENSIONS.includes(ext) || (forceImageIfUnknown && !ext)) {
      const safeName = ext ? rawName : rawName + '.jpg';
      const mime = 'image/' + (ext === 'jpg' || !ext ? 'jpeg' : ext);
      const compressed = await compressImageBytes(bytes, mime, imageQuality);
      const finalMime = (mime === 'image/png' && compressed !== bytes && imageQuality < 98) ? 'image/jpeg' : mime;
      if (compressed.length > 6 * 1024 * 1024) {
        throw new Error(safeName + ' 压缩后仍超过 6 MB');
      }
      const savedPath = await saveAttachmentToSandbox(context.filesDir, id, safeName, finalMime, compressed, 'image');
      return {
        id,
        name: safeName,
        mime: finalMime,
        data: new util.Base64Helper().encodeToStringSync(compressed),
        filePath: savedPath,
        sizeBytes: compressed.length,
        kind: 'image'
      };
    } else if (ext === 'pdf') {
      const tempPath = context.filesDir + '/attachments/' + id + '.pdf';
      await ensureDir(context.filesDir + '/attachments');
      await writeBinaryFile(tempPath, bytes);
      let text = '';
      try {
        text = await extractPdfTextFromPath(tempPath);
      } catch (err) {
        text = '[PDF 读取失败: ' + ((err as Error).message || '未知错误') + ']';
      }
      return {
        id,
        name: rawName,
        mime: 'text/plain',
        data: text.slice(0, 512 * 1024),
        filePath: tempPath,
        sizeBytes: bytes.length,
        kind: 'pdf'
      };
    } else if (ext === 'docx') {
      const xml = await extractZipEntryText(bytes, 'word/document.xml');
      const text = extractDocxXmlText(xml).slice(0, 512 * 1024);
      const savedPath = await saveAttachmentToSandbox(context.filesDir, id, rawName + '.txt', 'text/plain',
        util.TextEncoder.create().encodeInto(text), 'docx');
      return {
        id,
        name: rawName,
        mime: 'text/plain',
        data: text,
        filePath: savedPath,
        sizeBytes: bytes.length,
        kind: 'docx'
      };
    } else if (AUDIO_EXTENSIONS.includes(ext)) {
      const audioMime = ext === 'mp3' ? 'audio/mpeg' : 'audio/' + ext;
      const savedPath = await saveAttachmentToSandbox(context.filesDir, id, rawName, audioMime, bytes, 'audio');
      return {
        id,
        name: rawName,
        mime: audioMime,
        data: new util.Base64Helper().encodeToStringSync(bytes),
        filePath: savedPath,
        sizeBytes: bytes.length,
        kind: 'audio'
      };
    } else if (TEXT_EXTENSIONS.includes(ext) || bytes.length <= 512 * 1024) {
      if (bytes.length > 512 * 1024) throw new Error(rawName + ' 文本附件上限为 512 KB');
      const text = util.TextDecoder.create('utf-8', { fatal: false }).decodeToString(bytes);
      const savedPath = await saveAttachmentToSandbox(context.filesDir, id, rawName, 'text/plain', bytes, 'text');
      return {
        id,
        name: rawName,
        mime: 'text/plain',
        data: text,
        filePath: savedPath,
        sizeBytes: bytes.length,
        kind: 'text'
      };
    }
    throw new Error('不支持的文件类型: ' + rawName);
  } finally {
    await fs.close(file);
  }
}

export async function pickMultipleAttachments(
  context: common.UIAbilityContext,
  imageQuality: number = 85
): Promise<Attachment[]> {
  const paths = await new picker.DocumentViewPicker(context).select({
    maxSelectNumber: 6,
    fileSuffixFilters: ['文档、图片与音频|.txt,.md,.csv,.json,.pdf,.docx,.jpg,.jpeg,.png,.webp,.wav,.mp3,.m4a,.ogg,.ts,.ets,.py,.js,.html,.css,.xml,.yaml,.yml,.log']
  });
  if (!paths.length) return [];
  const results: Attachment[] = [];
  for (let i = 0; i < paths.length; i++) {
    results.push(await ingestFileUri(paths[i], context, imageQuality));
  }
  return results;
}

export async function pickPhotoAttachments(
  context: common.UIAbilityContext,
  imageQuality: number = 85
): Promise<Attachment[]> {
  const opts = new photoAccessHelper.PhotoSelectOptions();
  opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  opts.maxSelectNumber = 6;
  const res = await new photoAccessHelper.PhotoViewPicker().select(opts);
  const uris = res.photoUris || [];
  if (!uris.length) return [];
  const results: Attachment[] = [];
  for (let i = 0; i < uris.length; i++) {
    results.push(await ingestFileUri(uris[i], context, imageQuality, true));
  }
  return results;
}

export async function takePhotoAttachment(
  context: common.UIAbilityContext,
  imageQuality: number = 85
): Promise<Attachment | undefined> {
  const res = await cameraPicker.pick(
    context,
    [cameraPicker.PickerMediaType.PHOTO],
    { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK }
  );
  if (res.resultCode !== 0 || !res.resultUri) {
    return undefined;
  }
  return await ingestFileUri(res.resultUri, context, imageQuality, true);
}

async function computeDirSize(dir: string): Promise<number> {
  try {
    if (!await fs.access(dir)) return 0;
    const names = await fs.listFile(dir);
    let total = 0;
    for (let i = 0; i < names.length; i++) {
      const p = dir + '/' + names[i];
      try {
        const st = await fs.stat(p);
        if (st.isDirectory()) total += await computeDirSize(p);
        else total += st.size;
      } catch (_) {}
    }
    return total;
  } catch (_) {
    return 0;
  }
}

export async function computeStorageBreakdown(filesDir: string, dbDir?: string): Promise<StorageBreakdown> {
  let dbBytes = 0;
  const rdbBase = dbDir || filesDir;
  try {
    const candidates = [rdbBase + '/rdb/kelivo.db', filesDir + '/workspace-v1.json'];
    for (let i = 0; i < candidates.length; i++) {
      if (await fs.access(candidates[i])) {
        dbBytes += (await fs.stat(candidates[i])).size;
      }
    }
  } catch (_) {}
  const attachmentsBytes = await computeDirSize(filesDir + '/attachments');
  const snapshotsBytes = await computeDirSize(filesDir + '/snapshots');
  const workspacesBytes = await computeDirSize(filesDir + '/workspaces');
  const skillsBytes = await computeDirSize(filesDir + '/skills');
  return {
    databaseBytes: dbBytes,
    attachmentsBytes,
    snapshotsBytes,
    workspacesBytes,
    skillsBytes,
    totalBytes: dbBytes + attachmentsBytes + snapshotsBytes + workspacesBytes + skillsBytes
  };
}

export async function clearDirectoryFiles(dir: string): Promise<number> {
  let removed = 0;
  try {
    if (!await fs.access(dir)) return 0;
    const names = await fs.listFile(dir);
    for (let i = 0; i < names.length; i++) {
      const p = dir + '/' + names[i];
      try {
        const st = await fs.stat(p);
        if (st.isDirectory()) {
          removed += await clearDirectoryFiles(p);
          await fs.rmdir(p);
        } else {
          await fs.unlink(p);
          removed++;
        }
      } catch (_) {}
    }
  } catch (_) {}
  return removed;
}
