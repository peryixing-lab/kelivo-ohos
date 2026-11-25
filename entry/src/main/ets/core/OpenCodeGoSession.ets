import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { bytesToHex, decryptBackupText, encryptBackupText, randomBytes } from './BackupCrypto';
import {
  OPENCODE_GO_CONSOLE_ORIGIN,
  OPENCODE_GO_CONSOLE_URL,
  ProxyConfig
} from './Models';
import { newId, readKey, storeKey } from './Storage';

export const OPENCODE_GO_CLIENT_ID = 'kelivo';
const PREFS_NAME = 'opencode_go_sessions';
const KEY_ALIAS = 'opencode-go-vault-v1';
const REFRESH_MARGIN_MS = 5 * 60 * 1000;

export interface OpenCodeGoSession {
  sessionId: string;
  access: string;
  refresh: string;
  expires: number;
  accountId: string;
  email: string;
  orgId: string;
  orgName: string;
}

export interface OpenCodeGoDeviceChallenge {
  deviceCode: string;
  userCode: string;
  verificationUrl: string;
  expiresAt: number;
  intervalMs: number;
}

export interface OpenCodeGoTokenPayload {
  accessToken: string;
  refreshToken: string;
  expires: number;
  orgId: string;
}

export interface OpenCodeGoProfile {
  accountId: string;
  email: string;
  orgName: string;
}

export interface OpenCodeGoHttpReply {
  status: number;
  body: string;
}

export class OpenCodeGoAuthError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

interface OpenCodeGoDeviceResp {
  device_code?: string;
  user_code?: string;
  verification_uri?: string;
  verification_uri_complete?: string;
  expires_in?: number;
  interval?: number;
  error?: string;
}

interface OpenCodeGoTokenResp {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  org_id?: string | null;
  error?: string;
}

interface OpenCodeGoUserResp {
  id?: string;
  email?: string;
}

interface OpenCodeGoOrgResp {
  id?: string;
  name?: string;
}

let context: common.UIAbilityContext | undefined = undefined;
let store: preferences.Preferences | undefined = undefined;
let master: Promise<string> | undefined = undefined;
const renewals: Map<string, Promise<OpenCodeGoSession>> = new Map<string, Promise<OpenCodeGoSession>>();

export function initOpenCodeGoStorage(ctx: common.UIAbilityContext): void {
  context = ctx;
}

function storage(): preferences.Preferences {
  if (!context) {
    throw new Error('请重新打开应用后再连接 OpenCode Go');
  }
  if (!store) {
    store = preferences.getPreferencesSync(context, { name: PREFS_NAME });
  }
  return store;
}

async function openVault(): Promise<string> {
  const existing = await readKey(KEY_ALIAS);
  if (existing) {
    return existing;
  }
  const key = bytesToHex(await randomBytes(32));
  await storeKey(KEY_ALIAS, key);
  return key;
}

async function vaultKey(): Promise<string> {
  if (!master) {
    master = openVault().catch((e: Error) => {
      master = undefined;
      throw e;
    });
  }
  return master;
}

export async function saveOpenCodeGoSession(s: OpenCodeGoSession): Promise<void> {
  const encrypted = await encryptBackupText(JSON.stringify(s), await vaultKey());
  const prefs = storage();
  await prefs.put('account.' + s.sessionId, encrypted);
  await prefs.flush();
}

export async function readOpenCodeGoSession(sessionId: string): Promise<OpenCodeGoSession | undefined> {
  const raw = storage().getSync('account.' + sessionId, '') as string;
  if (!raw) {
    return undefined;
  }
  return JSON.parse(await decryptBackupText(raw, await vaultKey())) as OpenCodeGoSession;
}

function mapDeviceErrorMessage(code: string): string {
  if (code === 'authorization_pending') {
    return '等待浏览器授权';
  }
  if (code === 'slow_down') {
    return '请求过于频繁，正在放慢轮询';
  }
  if (code === 'access_denied') {
    return '已在浏览器中拒绝 OpenCode Go 授权';
  }
  if (code === 'expired_token') {
    return '设备授权码已过期，请重新开始登录';
  }
  if (code === 'invalid_grant') {
    return 'OpenCode Go 登录已失效，请在供应商配置中重新登录';
  }
  return 'OpenCode Go 授权失败（' + code + '）';
}

export function resolveOpenCodeVerificationUrl(rawLink: string): string {
  const trimmed = (rawLink || '').trim();
  if (!trimmed || /[\s\u0000-\u001F\u007F\\]/.test(trimmed)) {
    throw new Error('OpenCode 返回的授权链接无效');
  }
  if (trimmed.startsWith('/')) {
    if (trimmed.startsWith('//')) {
      throw new Error('OpenCode 返回的授权链接无效');
    }
    return OPENCODE_GO_CONSOLE_ORIGIN + trimmed;
  }
  if (!trimmed.startsWith(OPENCODE_GO_CONSOLE_ORIGIN)) {
    throw new Error('OpenCode 返回的授权链接无效');
  }
  const rest = trimmed.slice(OPENCODE_GO_CONSOLE_ORIGIN.length);
  if (rest.length > 0 && !rest.startsWith('/') && !rest.startsWith('?') && !rest.startsWith('#')) {
    throw new Error('OpenCode 返回的授权链接无效');
  }
  return trimmed;
}

export function parseOpenCodeDeviceCodeResponse(raw: string, nowMs: number = Date.now()): OpenCodeGoDeviceChallenge {
  let resp: OpenCodeGoDeviceResp;
  try {
    resp = JSON.parse(raw) as OpenCodeGoDeviceResp;
  } catch (_) {
    throw new Error('OpenCode Console 返回的设备授权响应格式无效');
  }
  if (!resp || typeof resp !== 'object') {
    throw new Error('OpenCode Console 返回的设备授权响应格式无效');
  }
  if (typeof resp.error === 'string' && resp.error.trim().length > 0) {
    throw new OpenCodeGoAuthError(resp.error.trim(), mapDeviceErrorMessage(resp.error.trim()));
  }
  const deviceCode = typeof resp.device_code === 'string' ? resp.device_code.trim() : '';
  const userCode = typeof resp.user_code === 'string' ? resp.user_code.trim() : '';
  const expiresIn = typeof resp.expires_in === 'number' ? resp.expires_in : NaN;
  const rawInterval = resp.interval === undefined ? 5 : resp.interval;
  if (!deviceCode || !userCode || !Number.isFinite(expiresIn) || expiresIn <= 0 ||
    typeof rawInterval !== 'number' || !Number.isFinite(rawInterval) || rawInterval <= 0) {
    throw new Error('OpenCode Console 返回的设备授权响应不完整');
  }
  const baseUri = typeof resp.verification_uri === 'string' ? resp.verification_uri.trim() : '';
  if (baseUri.length > 0) {
    resolveOpenCodeVerificationUrl(baseUri);
  }
  const completeUri = typeof resp.verification_uri_complete === 'string' ? resp.verification_uri_complete.trim() : '';
  const chosenLink = completeUri.length > 0 ? completeUri : baseUri;
  const verificationUrl = resolveOpenCodeVerificationUrl(chosenLink);
  const clampedIntervalSec = Math.min(60, Math.max(1, rawInterval));
  return {
    deviceCode,
    userCode,
    verificationUrl,
    expiresAt: nowMs + Math.floor(expiresIn * 1000),
    intervalMs: Math.ceil(clampedIntervalSec * 1000)
  };
}

export function parseOpenCodeTokenResponse(raw: string, nowMs: number = Date.now()): OpenCodeGoTokenPayload {
  let resp: OpenCodeGoTokenResp;
  try {
    resp = JSON.parse(raw) as OpenCodeGoTokenResp;
  } catch (_) {
    throw new Error('OpenCode Console 返回的令牌响应格式无效');
  }
  if (!resp || typeof resp !== 'object') {
    throw new Error('OpenCode Console 返回的令牌响应格式无效');
  }
  if (typeof resp.error === 'string' && resp.error.trim().length > 0) {
    const code = resp.error.trim();
    throw new OpenCodeGoAuthError(code, mapDeviceErrorMessage(code));
  }
  const accessToken = typeof resp.access_token === 'string' ? resp.access_token.trim() : '';
  const refreshToken = typeof resp.refresh_token === 'string' ? resp.refresh_token.trim() : '';
  const expiresIn = typeof resp.expires_in === 'number' ? resp.expires_in : NaN;
  if (!accessToken || !refreshToken || !Number.isFinite(expiresIn) || expiresIn <= 0) {
    throw new Error('OpenCode Console 返回的登录凭证不完整');
  }
  const orgId = typeof resp.org_id === 'string' ? resp.org_id.trim() : '';
  return {
    accessToken,
    refreshToken,
    expires: nowMs + Math.floor(expiresIn * 1000),
    orgId
  };
}

function applyOptionalProxy(opts: http.HttpRequestOptions, proxy?: ProxyConfig, password?: string): void {
  if (!proxy || !proxy.enabled || !proxy.host || proxy.host.trim().length === 0 || proxy.port <= 0) {
    return;
  }
  const host = proxy.host.trim();
  const port = proxy.port;
  if (proxy.type === 'socks5') {
    const sCfg: http.Socks5Proxy = { host, port, exclusionList: [] };
    if (proxy.username && proxy.username.trim().length > 0) {
      sCfg.username = proxy.username.trim();
      sCfg.password = password || '';
    }
    opts.usingSocks5Proxy = sCfg;
    return;
  }
  const hCfg: http.HttpProxy = { host, port, exclusionList: [] };
  if (proxy.username && proxy.username.trim().length > 0) {
    hCfg.username = proxy.username.trim();
    hCfg.password = password || '';
  }
  opts.usingProxy = hCfg;
}

export async function postOpenCodeConsoleJson(
  path: string,
  body: Record<string, Object>,
  proxy?: ProxyConfig,
  proxyPassword?: string,
  timeoutMs: number = 20000
): Promise<OpenCodeGoHttpReply> {
  const req = http.createHttp();
  const url = OPENCODE_GO_CONSOLE_URL + path;
  try {
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify(body),
      expectDataType: http.HttpDataType.STRING,
      maxRedirects: 0,
      connectTimeout: Math.min(10000, timeoutMs),
      readTimeout: timeoutMs,
      usingCache: false
    };
    applyOptionalProxy(opts, proxy, proxyPassword);
    const response = await req.request(url, opts);
    const raw = typeof response.result === 'string' ? response.result : '';
    return { status: response.responseCode, body: raw };
  } finally {
    req.destroy();
  }
}

async function getOpenCodeConsoleJson(
  path: string,
  accessToken: string,
  proxy?: ProxyConfig,
  proxyPassword?: string
): Promise<string> {
  const req = http.createHttp();
  const url = OPENCODE_GO_CONSOLE_URL + path;
  try {
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ' + accessToken
      },
      expectDataType: http.HttpDataType.STRING,
      maxRedirects: 0,
      connectTimeout: 8000,
      readTimeout: 10000,
      usingCache: false
    };
    applyOptionalProxy(opts, proxy, proxyPassword);
    const response = await req.request(url, opts);
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error('HTTP ' + response.responseCode);
    }
    return typeof response.result === 'string' ? response.result : '';
  } finally {
    req.destroy();
  }
}

export async function fetchOpenCodeProfile(
  accessToken: string,
  orgId: string,
  proxy?: ProxyConfig,
  proxyPassword?: string
): Promise<OpenCodeGoProfile> {
  let accountId = '';
  let email = '';
  let orgName = '';
  try {
    const userRaw = await getOpenCodeConsoleJson('/api/user', accessToken, proxy, proxyPassword);
    const user = JSON.parse(userRaw) as OpenCodeGoUserResp;
    accountId = typeof user.id === 'string' ? user.id.trim() : '';
    email = typeof user.email === 'string' ? user.email.trim() : '';
  } catch (_) {}
  if (orgId) {
    try {
      const orgsRaw = await getOpenCodeConsoleJson('/api/orgs', accessToken, proxy, proxyPassword);
      const orgs = JSON.parse(orgsRaw) as OpenCodeGoOrgResp[];
      if (Array.isArray(orgs)) {
        const matched = orgs.find((item: OpenCodeGoOrgResp): boolean => (item.id || '').trim() === orgId);
        if (matched && typeof matched.name === 'string') {
          orgName = matched.name.trim();
        }
      }
    } catch (_) {}
  }
  return { accountId, email, orgName };
}

async function validSession(
  sessionId: string,
  proxy?: ProxyConfig,
  proxyPassword?: string
): Promise<OpenCodeGoSession> {
  const s = await readOpenCodeGoSession(sessionId);
  if (!s) {
    throw new Error('请在供应商配置中重新登录 OpenCode Go');
  }
  if (s.expires > Date.now() + REFRESH_MARGIN_MS) {
    return s;
  }
  if (!s.refresh.trim()) {
    throw new Error('OpenCode Go 刷新令牌缺失，请重新登录');
  }
  const fields: Record<string, Object> = {};
  fields['grant_type'] = 'refresh_token';
  fields['refresh_token'] = s.refresh;
  fields['client_id'] = OPENCODE_GO_CLIENT_ID;
  const reply = await postOpenCodeConsoleJson('/auth/device/token', fields, proxy, proxyPassword);
  const refreshed = parseOpenCodeTokenResponse(reply.body);
  if (reply.status < 200 || reply.status >= 300) {
    throw new Error('OpenCode Go 令牌刷新失败（HTTP ' + reply.status + '），请重新登录');
  }
  s.access = refreshed.accessToken;
  s.refresh = refreshed.refreshToken;
  s.expires = refreshed.expires;
  if (refreshed.orgId) {
    s.orgId = refreshed.orgId;
  }
  await saveOpenCodeGoSession(s);
  return s;
}

export async function openCodeGoAccessToken(
  sessionId: string,
  proxy?: ProxyConfig,
  proxyPassword?: string
): Promise<string> {
  let job = renewals.get(sessionId);
  if (!job) {
    job = validSession(sessionId, proxy, proxyPassword).finally(() => {
      renewals.delete(sessionId);
    });
    renewals.set(sessionId, job);
  }
  const session = await job;
  return session.access;
}

export async function disconnectOpenCodeGo(sessionId: string): Promise<void> {
  await renewals.get(sessionId)?.catch(() => {});
  let s: OpenCodeGoSession | undefined = undefined;
  try {
    s = await readOpenCodeGoSession(sessionId);
  } catch (_) {
    return;
  }
  if (!s) {
    return;
  }
  if (s.refresh) {
    const fields: Record<string, Object> = {};
    fields['token'] = s.refresh;
    fields['token_type_hint'] = 'refresh_token';
    fields['client_id'] = OPENCODE_GO_CLIENT_ID;
    await postOpenCodeConsoleJson('/auth/oauth/revoke', fields, undefined, undefined, 5000).catch(() => {});
  }
  await storage().delete('account.' + sessionId);
  await storage().flush();
}
