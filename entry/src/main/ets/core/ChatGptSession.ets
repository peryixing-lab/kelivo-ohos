import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { cert } from '@kit.DeviceCertificateKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { http } from '@kit.NetworkKit';
import { bytesToHex, decryptBackupText, encryptBackupText, randomBytes } from './BackupCrypto';
import { newId, readKey, storeKey } from './Storage';

import { CHATGPT_PLAN_API as PLAN_API } from './Models';
export const PLAN_ISSUER = 'https://auth.openai.com';
const TOKEN_URL = PLAN_ISSUER + '/api/accounts/oauth/token';
const KEY_ALIAS = 'chatgpt-plan-vault-v1';

export interface PlanSession {
  clientId: string;
  subject: string;
  email: string;
  access: string;
  refresh: string;
  identity: string;
  expires: number;
}
export interface PlanGrant {
  access_token: string;
  refresh_token: string;
  id_token?: string;
  expires_in: number;
  token_type: string;
  scope?: string;
}
interface Jwk { kty: string; kid: string; alg?: string; n: string; e?: string; x5c?: string[] }
interface KeySet { keys: Jwk[] }
interface JwtHeader { alg: string; kid: string }
export interface PlanClaims { sub: string; email?: string; iss: string; aud: string | string[]; azp?: string; exp: number; nonce: string }
let context: common.UIAbilityContext | undefined;
let store: preferences.Preferences | undefined;
let master: Promise<string> | undefined;
const renewals = new Map<string, Promise<PlanSession>>();

export function initPlanStorage(ctx: common.UIAbilityContext): void {
  context = ctx;
}
function storage(): preferences.Preferences {
  if (!context) throw new Error('请重新打开应用后再连接 ChatGPT');
  if (!store) store = preferences.getPreferencesSync(context, { name: 'chatgpt_plan_sessions' });
  return store;
}
export async function planHostId(): Promise<string> {
  const prefs = storage();
  let id = prefs.getSync('host', '') as string;
  if (!id) {
    id = 'urn:uuid:' + newId();
    prefs.putSync('host', id);
  }
  await prefs.flush();
  return id;
}
async function openVault(): Promise<string> {
  const existing = await readKey(KEY_ALIAS);
  if (existing) return existing;
  const key = bytesToHex(await randomBytes(32));
  await storeKey(KEY_ALIAS, key);
  return key;
}
async function vaultKey(): Promise<string> {
  if (!master) master = openVault().catch((e: Error) => { master = undefined; throw e; });
  return master;
}
export async function savePlanSession(s: PlanSession): Promise<void> {
  const encrypted = await encryptBackupText(JSON.stringify(s), await vaultKey());
  const prefs = storage();
  await prefs.put('account.' + s.clientId, encrypted);
  await prefs.flush();
}
export async function readPlanSession(clientId: string): Promise<PlanSession | undefined> {
  const raw = storage().getSync('account.' + clientId, '') as string;
  if (!raw) return undefined;
  return JSON.parse(await decryptBackupText(raw, await vaultKey())) as PlanSession;
}
export function formEncode(fields: Record<string, string>): string {
  return Object.keys(fields).map((k: string): string =>
    encodeURIComponent(k) + '=' + encodeURIComponent(fields[k])).join('&');
}
async function authRequest(url: string, form?: Record<string, string>): Promise<string> {
  const req = http.createHttp();
  try {
    const response = await req.request(url, {
      method: form ? http.RequestMethod.POST : http.RequestMethod.GET,
      header: { 'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json' },
      extraData: form ? formEncode(form) : undefined, expectDataType: http.HttpDataType.STRING,
      maxRedirects: 0, connectTimeout: 10000, readTimeout: 20000, usingCache: false
    });
    if (response.responseCode !== 200) {
      throw new Error('ChatGPT 授权请求失败（HTTP ' + response.responseCode + '），请重新登录或稍后重试');
    }
    return response.result as string;
  } finally { req.destroy(); }
}
export async function exchangeGrant(fields: Record<string, string>, refresh: boolean): Promise<PlanGrant> {
  const grant = JSON.parse(await authRequest(TOKEN_URL, fields)) as PlanGrant;
  if (!grant.access_token || !grant.refresh_token || grant.token_type?.toLowerCase() !== 'bearer' ||
    !Number.isFinite(grant.expires_in) || grant.expires_in <= 0) throw new Error('ChatGPT 授权响应不完整');
  if ((!refresh || grant.scope !== undefined) && !grant.scope?.split(' ').includes('chatgpt.tokens.use.direct')) {
    throw new Error('此账号尚未授权使用 ChatGPT 套餐，请在登录时允许套餐用量');
  }
  return grant;
}
function decodePart(s: string): Uint8Array {
  const base = s.replace(/-/g, '+').replace(/_/g, '/');
  return new util.Base64Helper().decodeSync(base.padEnd(Math.ceil(base.length / 4) * 4, '='));
}
export function checkPlanClaims(c: PlanClaims, clientId: string, nonce: string): void {
  const audience = Array.isArray(c.aud) ? c.aud : [c.aud];
  if (!c.sub || c.iss !== PLAN_ISSUER || !audience.includes(clientId) ||
    ((audience.length > 1 || c.azp) && c.azp !== clientId) || !Number.isFinite(c.exp) ||
    c.exp <= Date.now() / 1000 || !nonce || c.nonce !== nonce) throw new Error('ChatGPT 身份令牌校验失败');
}
const RSA_SPKI_ALGO_ID: Uint8Array = new Uint8Array([
  0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00
]);

function trimLeadingZeros(bytes: Uint8Array): Uint8Array {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) {
    start++;
  }
  return bytes.subarray(start);
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  let total = 0;
  for (let i = 0; i < parts.length; i++) {
    total += parts[i].length;
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (let i = 0; i < parts.length; i++) {
    out.set(parts[i], offset);
    offset += parts[i].length;
  }
  return out;
}

function encodeDerLength(len: number): Uint8Array {
  if (len < 0x80) {
    return new Uint8Array([len]);
  }
  const octets: number[] = [];
  let rem = len;
  while (rem > 0) {
    octets.unshift(rem & 0xff);
    rem = Math.floor(rem / 256);
  }
  const out = new Uint8Array(1 + octets.length);
  out[0] = 0x80 | octets.length;
  for (let i = 0; i < octets.length; i++) {
    out[i + 1] = octets[i];
  }
  return out;
}

function encodeDerNode(tag: number, body: Uint8Array): Uint8Array {
  return concatBytes([new Uint8Array([tag]), encodeDerLength(body.length), body]);
}

function encodeDerInteger(unsignedBytes: Uint8Array): Uint8Array {
  const trimmed = trimLeadingZeros(unsignedBytes);
  const needsZero = trimmed.length === 0 || (trimmed[0] & 0x80) !== 0;
  const payload = needsZero ? concatBytes([new Uint8Array([0x00]), trimmed]) : trimmed;
  return encodeDerNode(0x02, payload);
}

/**
 * Encodes raw unsigned RSA modulus and exponent bytes into ASN.1 DER X.509 SubjectPublicKeyInfo (SPKI).
 */
export function encodeRsaPublicKeySpki(modulus: Uint8Array, exponent: Uint8Array): Uint8Array {
  const rsaPublicKey = encodeDerNode(0x30, concatBytes([encodeDerInteger(modulus), encodeDerInteger(exponent)]));
  const bitString = encodeDerNode(0x03, concatBytes([new Uint8Array([0x00]), rsaPublicKey]));
  return encodeDerNode(0x30, concatBytes([RSA_SPKI_ALGO_ID, bitString]));
}

export async function verifyIdentity(token: string, clientId: string, nonce: string): Promise<PlanClaims> {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('ChatGPT 身份令牌无效');
  const decoder = util.TextDecoder.create();
  const header = JSON.parse(decoder.decodeToString(decodePart(parts[0]))) as JwtHeader;
  if (header.alg !== 'RS256' || !header.kid) throw new Error('不支持的 ChatGPT 签名');
  const set = JSON.parse(await authRequest(PLAN_ISSUER + '/.well-known/jwks.json')) as KeySet;
  const jwk = set.keys.find((k: Jwk): boolean => k.kid === header.kid && k.kty === 'RSA' && (!k.alg || k.alg === 'RS256'));
  if (!jwk) throw new Error('无法验证 ChatGPT 签名密钥');
  const n = trimLeadingZeros(decodePart(jwk.n));
  if (!n.length) throw new Error('无法验证 ChatGPT 签名密钥');
  const rsa = 'RSA' + n.length * 8;
  let pubBlob: cryptoFramework.DataBlob;
  if (jwk.e) {
    const e = trimLeadingZeros(decodePart(jwk.e));
    if (!e.length) throw new Error('无法验证 ChatGPT 签名密钥');
    pubBlob = { data: encodeRsaPublicKeySpki(n, e) };
  } else if (jwk.x5c?.length) {
    const certificate = await cert.createX509Cert({
      data: new util.Base64Helper().decodeSync(jwk.x5c[0]),
      encodingFormat: cert.EncodingFormat.FORMAT_DER
    });
    pubBlob = certificate.getPublicKey().getEncoded();
  } else {
    throw new Error('ChatGPT 未返回可用的签名公钥');
  }
  const keyPair = await cryptoFramework.createAsyKeyGenerator(rsa).convertKey(pubBlob, null);
  const verifier = cryptoFramework.createVerify(rsa + '|PKCS1|SHA256');
  await verifier.init(keyPair.pubKey);
  const msg = util.TextEncoder.create().encodeInto(parts[0] + '.' + parts[1]);
  if (!await verifier.verify({ data: msg }, { data: decodePart(parts[2]) })) throw new Error('ChatGPT 签名校验失败');
  const claims = JSON.parse(decoder.decodeToString(decodePart(parts[1]))) as PlanClaims;
  checkPlanClaims(claims, clientId, nonce);
  return claims;
}
async function validSession(clientId: string): Promise<PlanSession> {
  const s = await readPlanSession(clientId);
  if (!s) throw new Error('请在供应商配置中重新登录 ChatGPT');
  if (s.expires > Date.now() + 30000) return s;
  const g = await exchangeGrant({ 'grant_type': 'refresh_token', 'client_id': clientId, 'refresh_token': s.refresh,
    'resource': PLAN_API }, true);
  s.access = g.access_token;
  s.refresh = g.refresh_token;
  s.expires = Date.now() + g.expires_in * 1000;
  await savePlanSession(s);
  return s;
}
export async function planAccessToken(clientId: string): Promise<string> {
  let job = renewals.get(clientId);
  if (!job) {
    job = validSession(clientId).finally(() => { renewals.delete(clientId); });
    renewals.set(clientId, job);
  }
  return (await job).access;
}
export async function disconnectPlan(clientId: string): Promise<void> {
  await renewals.get(clientId)?.catch(() => {});
  const s = await readPlanSession(clientId);
  if (!s) return;
  await authRequest(PLAN_ISSUER + '/api/accounts/oauth/revoke', {
    'client_id': clientId, 'token': s.refresh, 'token_type_hint': 'refresh_token'
  });
  await storage().delete('account.' + clientId);
  await storage().flush();
}
