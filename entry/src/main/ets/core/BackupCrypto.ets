import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { taskpool, util } from '@kit.ArkTS';
import { argon2id } from './Argon2id';

@Concurrent
function deriveArgon2idKeyWorker(
  pwdBytes: Uint8Array,
  saltBytes: Uint8Array,
  memoryKiB: number,
  passes: number,
  lanes: number,
  tagLen: number
): Uint8Array {
  return argon2id(pwdBytes, saltBytes, memoryKiB, passes, lanes, tagLen);
}

export interface EncryptedEnvelope {
  format: string;
  version: number;
  kdf: string;
  iterations: number;
  salt: string;
  iv: string;
  tag: string;
  ciphertext: string;
}

export function bytesToHex(bytes: Uint8Array): string {
  const hexChars = '0123456789abcdef';
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i];
    out += hexChars.charAt((b >> 4) & 0xf) + hexChars.charAt(b & 0xf);
  }
  return out;
}

export async function randomBytes(len: number): Promise<Uint8Array> {
  const rng = cryptoFramework.createRandom();
  const blob = await rng.generateRandom(len);
  return blob.data;
}

export async function sha256Bytes(data: Uint8Array): Promise<Uint8Array> {
  const md = cryptoFramework.createMd('SHA256');
  if (data.length > 0) await md.update({ data });
  const digest = await md.digest();
  return digest.data;
}

export async function sha256Hex(textOrBytes: string | Uint8Array): Promise<string> {
  const bytes = typeof textOrBytes === 'string' ? util.TextEncoder.create().encodeInto(textOrBytes) : textOrBytes;
  return bytesToHex(await sha256Bytes(bytes));
}

export async function hmacSha256(keyBytes: Uint8Array, msg: string | Uint8Array): Promise<Uint8Array> {
  const symGen = cryptoFramework.createSymKeyGenerator('HMAC');
  const symKey = await symGen.convertKey({ data: keyBytes });
  const mac = cryptoFramework.createMac('SHA256');
  await mac.init(symKey);
  const msgBytes = typeof msg === 'string' ? util.TextEncoder.create().encodeInto(msg) : msg;
  if (msgBytes.length > 0) await mac.update({ data: msgBytes });
  const res = await mac.doFinal();
  return res.data;
}

async function deriveAesKey(password: string, salt: Uint8Array, iterations: number): Promise<cryptoFramework.SymKey> {
  const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
  const spec: cryptoFramework.PBKDF2Spec = {
    algName: 'PBKDF2',
    password,
    salt,
    iterations,
    keySize: 32
  };
  const keyBlob = await kdf.generateSecret(spec);
  const symGen = cryptoFramework.createSymKeyGenerator('AES256');
  return symGen.convertKey(keyBlob);
}

export async function encryptBackupText(plainText: string, password: string): Promise<string> {
  if (!password) throw new Error('请输入加密密码');
  const salt = await randomBytes(16);
  const iv = await randomBytes(12);
  const iterations = 100000;
  const symKey = await deriveAesKey(password, salt, iterations);

  const gcmSpec: cryptoFramework.GcmParamsSpec = {
    algName: 'GcmParamsSpec',
    iv: { data: iv },
    aad: { data: new Uint8Array(0) },
    authTag: { data: new Uint8Array(16) }
  };
  const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
  await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, gcmSpec);
  const plainBytes = util.TextEncoder.create().encodeInto(plainText);
  const emptyBlob: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
  const plainBlob: cryptoFramework.DataBlob = { data: plainBytes };
  const updated = plainBytes.length > 0 ? await cipher.update(plainBlob) : emptyBlob;
  const tail = await cipher.doFinal(null);

  const upData = updated?.data || new Uint8Array(0);
  const tailData = tail?.data || new Uint8Array(0);
  const combined = new Uint8Array(upData.length + tailData.length);
  combined.set(upData, 0);
  combined.set(tailData, upData.length);
  if (combined.length < 16) throw new Error('AES-GCM 加密失败');

  const cipherBytes = combined.slice(0, combined.length - 16);
  const tagBytes = combined.slice(combined.length - 16);
  const b64 = new util.Base64Helper();
  const env: EncryptedEnvelope = {
    format: 'kelivo-enc-v1',
    version: 1,
    kdf: 'PBKDF2-SHA256',
    iterations,
    salt: b64.encodeToStringSync(salt),
    iv: b64.encodeToStringSync(iv),
    tag: b64.encodeToStringSync(tagBytes),
    ciphertext: b64.encodeToStringSync(cipherBytes)
  };
  return JSON.stringify(env);
}

export function isEncryptedBackup(raw: string): boolean {
  const trimmed = raw.trim();
  return trimmed.startsWith('{') && trimmed.includes('"kelivo-enc-v1"');
}

export async function decryptBackupText(rawJson: string, password: string): Promise<string> {
  if (!password) throw new Error('该备份已加密，请输入解密密码');
  const env = JSON.parse(rawJson) as EncryptedEnvelope;
  if (env.format !== 'kelivo-enc-v1') throw new Error('未知加密格式');
  const b64 = new util.Base64Helper();
  const salt = b64.decodeSync(env.salt);
  const iv = b64.decodeSync(env.iv);
  const tag = b64.decodeSync(env.tag);
  const cipherBytes = b64.decodeSync(env.ciphertext);
  const symKey = await deriveAesKey(password, salt, env.iterations || 100000);

  const gcmSpec: cryptoFramework.GcmParamsSpec = {
    algName: 'GcmParamsSpec',
    iv: { data: iv },
    aad: { data: new Uint8Array(0) },
    authTag: { data: tag }
  };
  const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
  await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, gcmSpec);
  const emptyBlob: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
  const cipherBlob: cryptoFramework.DataBlob = { data: cipherBytes };
  const part1 = cipherBytes.length > 0 ? await cipher.update(cipherBlob) : emptyBlob;
  const part2 = await cipher.doFinal(null);
  const d1 = part1?.data || new Uint8Array(0);
  const d2 = part2?.data || new Uint8Array(0);
  const plain = new Uint8Array(d1.length + d2.length);
  plain.set(d1, 0);
  plain.set(d2, d1.length);
  return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(plain);
}

const KELIVENC_MAGIC: number[] = [0x4b, 0x45, 0x4c, 0x49, 0x56, 0x45, 0x4e, 0x43]; // "KELIVENC"
const KELIVENC_HEADER_LEN = 41;
const KELIVENC_CHUNK_SIZE = 1024 * 1024;
const KELIVENC_MAX_BYTES = 512 * 1024 * 1024;

export function isKelivencBytes(bytes: Uint8Array): boolean {
  if (bytes.length < KELIVENC_MAGIC.length) return false;
  for (let i = 0; i < KELIVENC_MAGIC.length; i++) {
    if (bytes[i] !== KELIVENC_MAGIC[i]) return false;
  }
  return true;
}

async function derivePbkdf2Raw(password: string, salt: Uint8Array, iterations: number): Promise<Uint8Array> {
  const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
  const spec: cryptoFramework.PBKDF2Spec = {
    algName: 'PBKDF2',
    password,
    salt,
    iterations,
    keySize: 32
  };
  const keyBlob = await kdf.generateSecret(spec);
  return keyBlob.data;
}

function buildKelivencNonce(prefix: Uint8Array, index: number): Uint8Array {
  const nonce = new Uint8Array(12);
  nonce.set(prefix, 0);
  const view = new DataView(nonce.buffer);
  view.setUint32(8, index >>> 0, false);
  return nonce;
}

function buildKelivencAad(header: Uint8Array, index: number): Uint8Array {
  const aad = new Uint8Array(KELIVENC_HEADER_LEN + 4);
  aad.set(header, 0);
  const view = new DataView(aad.buffer);
  view.setUint32(KELIVENC_HEADER_LEN, index >>> 0, false);
  return aad;
}

export async function makeBackupPasswordVerifier(password: string): Promise<string> {
  if (!password) throw new Error('请输入加密口令');
  const salt = await randomBytes(16);
  const derived = await derivePbkdf2Raw(password, salt, 100000);
  const out = new Uint8Array(48);
  out.set(salt, 0);
  out.set(derived, 16);
  derived.fill(0);
  return new util.Base64Helper().encodeToStringSync(out);
}

export async function verifyBackupPassword(password: string, verifier: string): Promise<boolean> {
  if (!password || !verifier) return false;
  try {
    const raw = new util.Base64Helper().decodeSync(verifier);
    if (raw.length !== 48) return false;
    const salt = raw.subarray(0, 16);
    const expected = raw.subarray(16, 48);
    const actual = await derivePbkdf2Raw(password, salt, 100000);
    let diff = 0;
    for (let i = 0; i < 32; i++) {
      diff |= (actual[i] ^ expected[i]);
    }
    actual.fill(0);
    return diff === 0;
  } catch (_) {
    return false;
  }
}

export async function encryptKelivencBytes(plainBytes: Uint8Array, password: string): Promise<Uint8Array> {
  if (!password) throw new Error('请输入加密口令');
  const plainLen = plainBytes.length;
  if (plainLen > KELIVENC_MAX_BYTES) throw new Error('备份体积超出加密上限');
  const salt = await randomBytes(16);
  const noncePrefix = await randomBytes(8);
  const header = new Uint8Array(KELIVENC_HEADER_LEN);
  for (let i = 0; i < KELIVENC_MAGIC.length; i++) {
    header[i] = KELIVENC_MAGIC[i];
  }
  // Write version 2 (PBKDF2-HMAC-SHA256 600k): fast natively in CryptoArchitectureKit and supported by official Android Kelivo
  header[8] = 2;
  header.set(salt, 9);
  header.set(noncePrefix, 25);
  const hView = new DataView(header.buffer);
  hView.setUint32(33, Math.floor(plainLen / 0x100000000) >>> 0, false);
  hView.setUint32(37, plainLen >>> 0, false);

  const symKey = await deriveAesKey(password, salt, 600000);
  const chunks = Math.max(1, Math.ceil(plainLen / KELIVENC_CHUNK_SIZE));
  const out = new Uint8Array(KELIVENC_HEADER_LEN + plainLen + chunks * 16);
  out.set(header, 0);
  let outPos = KELIVENC_HEADER_LEN;
  let processed = 0;
  const emptyBlob: cryptoFramework.DataBlob = { data: new Uint8Array(0) };

  for (let index = 0; index < chunks; index++) {
    const count = Math.min(KELIVENC_CHUNK_SIZE, plainLen - processed);
    const chunk = count > 0 ? plainBytes.subarray(processed, processed + count) : new Uint8Array(0);
    const nonce = buildKelivencNonce(noncePrefix, index);
    const aad = buildKelivencAad(header, index);
    const gcmSpec: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: nonce },
      aad: { data: aad },
      authTag: { data: new Uint8Array(16) }
    };
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, gcmSpec);
    const updated = count > 0 ? await cipher.update({ data: chunk }) : emptyBlob;
    const tail = await cipher.doFinal(null);
    const uData = updated?.data || new Uint8Array(0);
    const tData = tail?.data || new Uint8Array(0);
    const combinedLen = uData.length + tData.length;
    if (combinedLen !== count + 16) throw new Error('KELIVENC 加密分块长度异常');
    out.set(uData, outPos);
    out.set(tData, outPos + uData.length);
    outPos += combinedLen;
    processed += count;
  }
  return out;
}

export async function decryptKelivencBytes(encBytes: Uint8Array, password: string): Promise<Uint8Array> {
  if (!password) throw new Error('该备份已加密，请输入解密口令');
  if (encBytes.length < KELIVENC_HEADER_LEN || !isKelivencBytes(encBytes)) {
    throw new Error('加密备份不完整或格式无效');
  }
  const version = encBytes[8];
  if (version !== 2 && version !== 3) {
    throw new Error('此加密备份需要更新版本的 Kelivo');
  }
  const hView = new DataView(encBytes.buffer, encBytes.byteOffset, KELIVENC_HEADER_LEN);
  const hi = hView.getUint32(33, false);
  const lo = hView.getUint32(37, false);
  const plainLen = hi * 0x100000000 + lo;
  if (plainLen < 0 || plainLen > KELIVENC_MAX_BYTES) {
    throw new Error('加密备份大小异常或超出支持范围');
  }
  const chunks = Math.max(1, Math.ceil(plainLen / KELIVENC_CHUNK_SIZE));
  if (encBytes.length !== KELIVENC_HEADER_LEN + plainLen + chunks * 16) {
    throw new Error('加密备份不完整或格式无效');
  }

  const header = encBytes.subarray(0, KELIVENC_HEADER_LEN);
  const salt = encBytes.subarray(9, 25);
  const noncePrefix = encBytes.subarray(25, 33);
  let keyBytes: Uint8Array;
  if (version === 2) {
    keyBytes = await derivePbkdf2Raw(password, salt, 600000);
  } else {
    const pwdBytes = util.TextEncoder.create('utf-8').encodeInto(password);
    const saltCopy = new Uint8Array(salt.length);
    saltCopy.set(salt, 0);
    try {
      const task = new taskpool.Task(deriveArgon2idKeyWorker, pwdBytes, saltCopy, 19 * 1024, 2, 1, 32);
      keyBytes = (await taskpool.execute(task)) as Uint8Array;
    } finally {
      pwdBytes.fill(0);
      saltCopy.fill(0);
    }
  }

  let symKey: cryptoFramework.SymKey;
  try {
    const symGen = cryptoFramework.createSymKeyGenerator('AES256');
    symKey = await symGen.convertKey({ data: keyBytes });
  } finally {
    keyBytes.fill(0);
  }

  const out = new Uint8Array(plainLen);
  let encPos = KELIVENC_HEADER_LEN;
  let processed = 0;
  const emptyBlob: cryptoFramework.DataBlob = { data: new Uint8Array(0) };

  for (let index = 0; index < chunks; index++) {
    const count = Math.min(KELIVENC_CHUNK_SIZE, plainLen - processed);
    const cipherSlice = count > 0 ? encBytes.subarray(encPos, encPos + count) : new Uint8Array(0);
    const tagSlice = encBytes.subarray(encPos + count, encPos + count + 16);
    encPos += count + 16;

    const nonce = buildKelivencNonce(noncePrefix, index);
    const aad = buildKelivencAad(header, index);
    const gcmSpec: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: nonce },
      aad: { data: aad },
      authTag: { data: tagSlice }
    };
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, gcmSpec);
    try {
      const part1 = count > 0 ? await cipher.update({ data: cipherSlice }) : emptyBlob;
      const part2 = await cipher.doFinal(null);
      const d1 = part1?.data || new Uint8Array(0);
      const d2 = part2?.data || new Uint8Array(0);
      if (d1.length + d2.length !== count) {
        throw new Error('口令错误或备份已损坏，请重试');
      }
      if (d1.length > 0) out.set(d1, processed);
      if (d2.length > 0) out.set(d2, processed + d1.length);
      processed += count;
    } catch (_) {
      throw new Error('口令错误或备份已损坏，请重试');
    }
  }
  return out;
}
