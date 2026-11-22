// Pure ArkTS ZIP32 + ZIP64 Central Directory parser (zero @kit imports for unit test compatibility).

export interface ZipEntryMeta {
  name: string;
  method: number;
  compressedSize: number;
  size: number;
  crc32: number;
  localOffset: number;
  encrypted: boolean;
}

export function normalizeZipEntryPath(name: string): string {
  let clean = name.replace(/\\/g, '/');
  while (clean.startsWith('./')) clean = clean.slice(2);
  while (clean.startsWith('/')) clean = clean.slice(1);
  return clean;
}

export function findZipEntry(entries: ZipEntryMeta[], targetName: string): ZipEntryMeta | undefined {
  const norm = normalizeZipEntryPath(targetName);
  for (let i = 0; i < entries.length; i++) {
    if (normalizeZipEntryPath(entries[i].name) === norm) return entries[i];
  }
  return undefined;
}

export function decodeUtf8Bytes(bytes: Uint8Array, start: number, len: number): string {
  const end = Math.min(bytes.length, start + len);
  let out = '';
  let i = start;
  while (i < end) {
    const b0 = bytes[i];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i++;
    } else if ((b0 & 0xe0) === 0xc0 && i + 1 < end && (bytes[i + 1] & 0xc0) === 0x80) {
      const cp = ((b0 & 0x1f) << 6) | (bytes[i + 1] & 0x3f);
      out += cp >= 0x80 ? String.fromCharCode(cp) : '\ufffd';
      i += 2;
    } else if ((b0 & 0xf0) === 0xe0 && i + 2 < end && (bytes[i + 1] & 0xc0) === 0x80 && (bytes[i + 2] & 0xc0) === 0x80) {
      const cp = ((b0 & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f);
      out += (cp >= 0x800 && (cp < 0xd800 || cp > 0xdfff)) ? String.fromCharCode(cp) : '\ufffd';
      i += 3;
    } else if ((b0 & 0xf8) === 0xf0 && i + 3 < end &&
      (bytes[i + 1] & 0xc0) === 0x80 && (bytes[i + 2] & 0xc0) === 0x80 && (bytes[i + 3] & 0xc0) === 0x80) {
      let cp = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3f) << 12) | ((bytes[i + 2] & 0x3f) << 6) | (bytes[i + 3] & 0x3f);
      if (cp >= 0x10000 && cp <= 0x10ffff) {
        cp -= 0x10000;
        out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
      } else {
        out += '\ufffd';
      }
      i += 4;
    } else {
      out += '\ufffd';
      i++;
    }
  }
  return out;
}

function readUint64Le(view: DataView, offset: number): number {
  const lo = view.getUint32(offset, true);
  const hi = view.getUint32(offset + 4, true);
  return hi * 0x100000000 + lo;
}

function findEocdOffset(bytes: Uint8Array, view: DataView): number {
  if (bytes.length < 22) return -1;
  const min = Math.max(0, bytes.length - 22 - 65535);
  for (let pos = bytes.length - 22; pos >= min; pos--) {
    if (view.getUint32(pos, true) === 0x06054b50 && pos + 22 + view.getUint16(pos + 20, true) === bytes.length) {
      return pos;
    }
  }
  // Fallback when trailing bytes exist after EOCD: match last valid EOCD whose CD or ZIP64 Locator validates
  for (let pos = bytes.length - 22; pos >= min; pos--) {
    if (view.getUint32(pos, true) !== 0x06054b50) continue;
    const cmtLen = view.getUint16(pos + 20, true);
    if (pos + 22 + cmtLen > bytes.length) continue;
    const loc = pos - 20;
    if (loc >= 0 && view.getUint32(loc, true) === 0x07064b50) {
      const z64Off = readUint64Le(view, loc + 8);
      if (z64Off >= 0 && z64Off + 56 <= loc && view.getUint32(z64Off, true) === 0x06064b50) {
        return pos;
      }
    }
    const cdOff = view.getUint32(pos + 16, true);
    if (cdOff < pos && view.getUint32(cdOff, true) === 0x02014b50) {
      return pos;
    }
  }
  return -1;
}

export function listZipEntries(bytes: Uint8Array): ZipEntryMeta[] {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.length);
  const end = findEocdOffset(bytes, view);
  if (end < 0) {
    throw new Error('无法读取 ZIP 目录');
  }

  const diskNum = view.getUint16(end + 4, true);
  const cdDisk = view.getUint16(end + 6, true);
  let count = view.getUint16(end + 10, true);
  let cdSize = view.getUint32(end + 12, true);
  let cdOffset = view.getUint32(end + 16, true);
  let cdEnd = end;
  let usedZip64 = false;

  // Check for ZIP64 End of Central Directory Locator immediately preceding EOCD
  const loc = end - 20;
  if (loc >= 0 && view.getUint32(loc, true) === 0x07064b50) {
    const z64LocatorDisk = view.getUint32(loc + 4, true);
    const zip64Off = readUint64Le(view, loc + 8);
    const z64TotalDisks = view.getUint32(loc + 16, true);
    if (zip64Off >= 0 && zip64Off + 56 <= loc && view.getUint32(zip64Off, true) === 0x06064b50) {
      if (z64LocatorDisk !== 0 || z64TotalDisks > 1) {
        throw new Error('暂不支持分卷 ZIP 压缩包');
      }
      const zDisk = view.getUint32(zip64Off + 16, true);
      const zCdDisk = view.getUint32(zip64Off + 20, true);
      if (zDisk !== 0 || zCdDisk !== 0) {
        throw new Error('暂不支持分卷 ZIP 压缩包');
      }
      count = readUint64Le(view, zip64Off + 32);
      cdSize = readUint64Le(view, zip64Off + 40);
      cdOffset = readUint64Le(view, zip64Off + 48);
      cdEnd = zip64Off;
      usedZip64 = true;
    }
  }

  if (!usedZip64 && (diskNum !== 0 || cdDisk !== 0)) {
    throw new Error('暂不支持分卷 ZIP 压缩包');
  }
  if (cdOffset < 0 || cdOffset > cdEnd || cdOffset + cdSize > cdEnd) {
    throw new Error('无效的 ZIP 目录长度');
  }

  let at = cdOffset;
  const entries: ZipEntryMeta[] = [];
  for (let i = 0; i < count; i++) {
    if (at + 46 > cdEnd || view.getUint32(at, true) !== 0x02014b50) {
      throw new Error('无效的 ZIP 条目');
    }
    const nameLen = view.getUint16(at + 28, true);
    const extraLen = view.getUint16(at + 30, true);
    const commentLen = view.getUint16(at + 32, true);
    const next = at + 46 + nameLen + extraLen + commentLen;
    if (next > cdEnd) {
      throw new Error('无效的 ZIP 目录长度');
    }

    let compressedSize = view.getUint32(at + 20, true);
    let size = view.getUint32(at + 24, true);
    let localOffset = view.getUint32(at + 42, true);

    if (size === 0xffffffff || compressedSize === 0xffffffff || localOffset === 0xffffffff) {
      let exPos = at + 46 + nameLen;
      const exEnd = exPos + extraLen;
      while (exPos + 4 <= exEnd) {
        const tag = view.getUint16(exPos, true);
        const fLen = view.getUint16(exPos + 2, true);
        const fStart = exPos + 4;
        if (fStart + fLen > exEnd) break;
        if (tag === 0x0001) {
          let p = fStart;
          if (size === 0xffffffff && p + 8 <= fStart + fLen) {
            size = readUint64Le(view, p);
            p += 8;
          }
          if (compressedSize === 0xffffffff && p + 8 <= fStart + fLen) {
            compressedSize = readUint64Le(view, p);
            p += 8;
          }
          if (localOffset === 0xffffffff && p + 8 <= fStart + fLen) {
            localOffset = readUint64Le(view, p);
            p += 8;
          }
          break;
        }
        exPos = fStart + fLen;
      }
    }

    const name = decodeUtf8Bytes(bytes, at + 46, nameLen);
    entries.push({
      name,
      method: view.getUint16(at + 10, true),
      compressedSize,
      size,
      crc32: view.getUint32(at + 16, true),
      localOffset,
      encrypted: (view.getUint16(at + 8, true) & 1) !== 0
    });
    at = next;
  }
  return entries;
}
