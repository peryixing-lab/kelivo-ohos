import { util } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import {
  ZipEntryMeta,
  findZipEntry,
  listZipEntries,
  normalizeZipEntryPath
} from './ZipDirectory';

export {
  ZipEntryMeta,
  findZipEntry,
  listZipEntries,
  normalizeZipEntryPath
};

const MAX_ZIP_ENTRY_BYTES = 256 * 1024 * 1024;

export async function extractZipEntryBytes(bytes: Uint8Array, entry: ZipEntryMeta): Promise<Uint8Array> {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.length);
  if (entry.size > MAX_ZIP_ENTRY_BYTES || entry.encrypted || entry.localOffset + 30 > bytes.length ||
    view.getUint32(entry.localOffset, true) !== 0x04034b50) {
    throw new Error('ZIP 条目过大、已加密或损坏: ' + entry.name);
  }
  if (entry.size === 0) return new Uint8Array(0);
  const start = entry.localOffset + 30 + view.getUint16(entry.localOffset + 26, true) + view.getUint16(entry.localOffset + 28, true);
  if (start + entry.compressedSize > bytes.length) {
    throw new Error('ZIP 数据不完整: ' + entry.name);
  }
  let raw = bytes.slice(start, start + entry.compressedSize).buffer;
  if (entry.method === 8) {
    const zip = await zlib.createZip();
    const out = new ArrayBuffer(entry.size);
    const stream: zlib.ZStream = { nextIn: raw, availableIn: raw.byteLength, nextOut: out, availableOut: entry.size };
    await zip.inflateInit2(stream, -15);
    try {
      let st = await zip.inflate(stream, zlib.CompressFlushMode.FINISH);
      while (st === zlib.ReturnStatus.OK && (stream.availableOut || 0) > 0 && (stream.availableIn || 0) > 0) {
        st = await zip.inflate(stream, zlib.CompressFlushMode.FINISH);
      }
      if (st !== zlib.ReturnStatus.STREAM_END) {
        throw new Error('ZIP 解压失败: ' + entry.name);
      }
      raw = stream.nextOut || out;
    } finally {
      await zip.inflateEnd(stream);
    }
  } else if (entry.method !== 0) {
    throw new Error('不支持此 ZIP 压缩方式: ' + entry.method);
  }
  const checksum = await zlib.createChecksum();
  let crc = 0;
  const CRC_CHUNK = 4 * 1024 * 1024;
  if (raw.byteLength <= CRC_CHUNK) {
    crc = (await checksum.crc32(0, raw)) >>> 0;
  } else {
    for (let off = 0; off < raw.byteLength; off += CRC_CHUNK) {
      const slice = raw.slice(off, Math.min(raw.byteLength, off + CRC_CHUNK));
      crc = (await checksum.crc32(crc, slice)) >>> 0;
    }
  }
  if (raw.byteLength !== entry.size || crc !== entry.crc32) {
    throw new Error('ZIP 校验失败: ' + entry.name);
  }
  return new Uint8Array(raw);
}

export async function extractZipEntryText(bytes: Uint8Array, entryName: string): Promise<string> {
  const entries = listZipEntries(bytes);
  const found = findZipEntry(entries, entryName);
  if (!found) throw new Error('ZIP 中未找到 ' + entryName);
  const raw = await extractZipEntryBytes(bytes, found);
  return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(raw);
}

export interface ZipWriteEntry {
  name: string;
  data: Uint8Array;
}

interface BuiltZipRecord {
  nameBytes: Uint8Array;
  method: number;
  crc32: number;
  uncompressedSize: number;
  compressedBytes: Uint8Array;
  localOffset: number;
}

export async function buildZipBytes(entries: ZipWriteEntry[]): Promise<Uint8Array> {
  const encoder = util.TextEncoder.create('utf-8');
  const checksum = await zlib.createChecksum();
  const zip = await zlib.createZip();
  const records: BuiltZipRecord[] = [];
  let localTotal = 0;
  let cdTotal = 0;

  for (let i = 0; i < entries.length; i++) {
    const cleanName = normalizeZipEntryPath(entries[i].name);
    if (!cleanName) continue;
    const nameBytes = encoder.encodeInto(cleanName);
    const data = entries[i].data;
    const rawBuf = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
    const crc = (await checksum.crc32(0, rawBuf)) >>> 0;

    let method = 0;
    let payload: Uint8Array = data;
    if (data.length >= 128) {
      try {
        const stream: zlib.ZStream = { nextIn: rawBuf, availableIn: rawBuf.byteLength };
        await zip.deflateInit2(
          stream,
          zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
          zlib.CompressMethod.DEFLATED,
          -15,
          zlib.MemLevel.MEM_LEVEL_DEFAULT,
          zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
        );
        try {
          const bound = Math.max(data.length + 64, await zip.deflateBound(stream, data.length));
          const outBuf = new ArrayBuffer(bound);
          stream.nextIn = rawBuf;
          stream.availableIn = rawBuf.byteLength;
          stream.nextOut = outBuf;
          stream.availableOut = bound;
          const st = await zip.deflate(stream, zlib.CompressFlushMode.FINISH);
          if (st === zlib.ReturnStatus.STREAM_END) {
            const actualBuf = stream.nextOut || outBuf;
            let usedLen = 0;
            if (typeof stream.totalOut === 'number' && stream.totalOut > 0 && stream.totalOut <= actualBuf.byteLength) {
              usedLen = stream.totalOut;
            } else if (typeof stream.availableOut === 'number' && stream.availableOut <= actualBuf.byteLength) {
              usedLen = actualBuf.byteLength - stream.availableOut;
            } else {
              usedLen = actualBuf.byteLength;
            }
            if (usedLen > 0 && usedLen < data.length) {
              method = 8;
              payload = new Uint8Array(actualBuf, 0, usedLen).slice();
            }
          }
        } finally {
          await zip.deflateEnd(stream);
        }
      } catch (_) {
        method = 0;
        payload = data;
      }
    }

    records.push({
      nameBytes,
      method,
      crc32: crc,
      uncompressedSize: data.length,
      compressedBytes: payload,
      localOffset: localTotal
    });
    localTotal += 30 + nameBytes.length + payload.length;
    cdTotal += 46 + nameBytes.length;
  }

  const out = new Uint8Array(localTotal + cdTotal + 22);
  const view = new DataView(out.buffer);
  const now = new Date();
  const dosTime = ((now.getHours() & 0x1f) << 11) | ((now.getMinutes() & 0x3f) << 5) | ((now.getSeconds() >> 1) & 0x1f);
  const dosDate = (((Math.max(1980, now.getFullYear()) - 1980) & 0x7f) << 9) | (((now.getMonth() + 1) & 0x0f) << 5) | (now.getDate() & 0x1f);

  let pos = 0;
  for (let i = 0; i < records.length; i++) {
    const r = records[i];
    view.setUint32(pos, 0x04034b50, true);
    view.setUint16(pos + 4, 20, true);
    view.setUint16(pos + 6, 0x0800, true); // UTF-8 filename flag
    view.setUint16(pos + 8, r.method, true);
    view.setUint16(pos + 10, dosTime, true);
    view.setUint16(pos + 12, dosDate, true);
    view.setUint32(pos + 14, r.crc32, true);
    view.setUint32(pos + 18, r.compressedBytes.length, true);
    view.setUint32(pos + 22, r.uncompressedSize, true);
    view.setUint16(pos + 26, r.nameBytes.length, true);
    view.setUint16(pos + 28, 0, true);
    pos += 30;
    out.set(r.nameBytes, pos);
    pos += r.nameBytes.length;
    out.set(r.compressedBytes, pos);
    pos += r.compressedBytes.length;
  }

  const cdOffset = pos;
  for (let i = 0; i < records.length; i++) {
    const r = records[i];
    view.setUint32(pos, 0x02014b50, true);
    view.setUint16(pos + 4, 20, true);
    view.setUint16(pos + 6, 20, true);
    view.setUint16(pos + 8, 0x0800, true);
    view.setUint16(pos + 10, r.method, true);
    view.setUint16(pos + 12, dosTime, true);
    view.setUint16(pos + 14, dosDate, true);
    view.setUint32(pos + 16, r.crc32, true);
    view.setUint32(pos + 20, r.compressedBytes.length, true);
    view.setUint32(pos + 24, r.uncompressedSize, true);
    view.setUint16(pos + 28, r.nameBytes.length, true);
    view.setUint16(pos + 30, 0, true);
    view.setUint16(pos + 32, 0, true);
    view.setUint16(pos + 34, 0, true);
    view.setUint16(pos + 36, 0, true);
    view.setUint32(pos + 38, 0, true);
    view.setUint32(pos + 42, r.localOffset, true);
    pos += 46;
    out.set(r.nameBytes, pos);
    pos += r.nameBytes.length;
  }

  view.setUint32(pos, 0x06054b50, true);
  view.setUint16(pos + 4, 0, true);
  view.setUint16(pos + 6, 0, true);
  view.setUint16(pos + 8, records.length, true);
  view.setUint16(pos + 10, records.length, true);
  view.setUint32(pos + 12, cdTotal, true);
  view.setUint32(pos + 16, cdOffset, true);
  view.setUint16(pos + 20, 0, true);
  return out;
}
