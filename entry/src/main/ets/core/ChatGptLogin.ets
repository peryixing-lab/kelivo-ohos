import { common } from '@kit.AbilityKit';
import { url, util } from '@kit.ArkTS';
import { socket } from '@kit.NetworkKit';
import { randomBytes, sha256Bytes } from './BackupCrypto';
import {
  PLAN_ISSUER, PlanSession, exchangeGrant, formEncode, planHostId, readPlanSession, verifyIdentity
} from './ChatGptSession';

import { CHATGPT_PLAN_API as PLAN_API } from './Models';

interface CallbackGrant { code: string; clientId: string }

const CALLBACK = '/auth/callback';
function base64url(data: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(data).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

export function parsePlanCallback(target: string, state: string, registeredId: string): CallbackGrant | undefined {
  if (!target.startsWith(CALLBACK + '?')) return undefined;
  const query = new url.URLParams(target.slice(CALLBACK.length + 1));
  if (query.getAll('state').length !== 1 || query.get('state') !== state) return undefined;
  if (query.has('error')) throw new Error('ChatGPT 登录已取消或未获授权');
  const issued = query.get('client_id') || registeredId;
  if (!issued || issued === 'dynamic_agent_client' || !/^[A-Za-z0-9_-]{1,160}$/.test(issued) ||
    (registeredId && registeredId !== issued) || query.getAll('client_id').length > 1 ||
    query.getAll('code').length !== 1 || !query.get('code')) throw new Error('ChatGPT 授权回调无效');
  return { code: query.get('code')!, clientId: issued };
}

export class ChatGptLogin {
  issuedId: string = '';
  private cancelled: boolean = false;
  private abort?: () => void;

  cancel(): void {
    this.cancelled = true;
    this.abort?.();
  }

  async authorize(ctx: common.UIAbilityContext, registeredId: string): Promise<PlanSession> {
    const existing = registeredId ? await readPlanSession(registeredId) : undefined;
    const hostId = await planHostId();
    const verifier = base64url(await randomBytes(32));
    const challenge = base64url(await sha256Bytes(util.TextEncoder.create().encodeInto(verifier)));
    const state = base64url(await randomBytes(24));
    const nonce = base64url(await randomBytes(24));
    const server = socket.constructTCPSocketServerInstance();
    const connections = new Set<socket.TCPSocketConnection>();
    let timer = -1;
    try {
      await server.listen({ address: '127.0.0.1', family: 1, port: 0 });
      const address = await server.getLocalAddress();
      const redirect = 'http://127.0.0.1:' + address.port + CALLBACK;
      const params: Record<string, string> = {
        'response_type': 'code', 'client_id': registeredId || 'dynamic_agent_client', 'ext_agent_host_id': hostId,
        'redirect_uri': redirect, 'resource': PLAN_API, 'scope': 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct',
        'state': state, 'nonce': nonce, 'code_challenge': challenge, 'code_challenge_method': 'S256'
      };
      if (!registeredId) params['agent_name_hint'] = 'Kelivo for HarmonyOS';
      if (existing?.identity) params['id_token_hint'] = existing.identity;
      if (this.cancelled) throw new Error('已取消登录');
      const callback = await new Promise<CallbackGrant>((resolve, reject) => {
        this.abort = () => reject(new Error('已取消登录'));
        timer = setTimeout(() => reject(new Error('登录已超时，请重试')), 300000);
        server.on('connect', (conn: socket.TCPSocketConnection) => {
          connections.add(conn);
          let buffer = '';
          let handled = false;
          conn.on('close', () => { connections.delete(conn); });
          conn.on('message', (message: socket.SocketMessageInfo) => {
            if (handled) return;
            buffer += util.TextDecoder.create().decodeToString(new Uint8Array(message.message));
            if (buffer.length > 16384) { handled = true; conn.close().catch(() => {}); return; }
            if (!buffer.includes('\r\n\r\n')) return;
            handled = true;
            const request = /^GET ([^ ]+) HTTP\/1\.[01]\r\n/.exec(buffer);
            let grant: CallbackGrant | undefined;
            try {
              if (request) grant = parsePlanCallback(request[1], state, registeredId);
            } catch (e) { reject(e as Error); return; }
            const response = grant ? '200 OK' : '400 Bad Request';
            const msg = grant ? 'Authorization received. Return to Kelivo.' : 'Invalid callback.';
            conn.send({ data: 'HTTP/1.1 ' + response + '\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: ' + msg.length + '\r\n\r\n' + msg })
              .catch(() => {}).finally(() => { conn.close().catch(() => {}); if (grant) resolve(grant); });
          });
        });
        server.on('error', () => reject(new Error('本机授权回调不可用，请重试')));
        ctx.openLink(PLAN_ISSUER + '/api/accounts/authorize?' + formEncode(params), { appLinkingOnly: false })
          .catch(() => reject(new Error('无法打开系统浏览器')));
      });
      this.issuedId = callback.clientId;
      const token = await exchangeGrant({ 'grant_type': 'authorization_code', 'code': callback.code, 'client_id': callback.clientId,
        'code_verifier': verifier, 'redirect_uri': redirect, 'resource': PLAN_API }, false);
      const identity = token.id_token || '';
      const claims = await verifyIdentity(identity, callback.clientId, nonce);
      if (existing && existing.subject !== claims.sub) throw new Error('返回的账号与所选连接不匹配');
      if (this.cancelled) throw new Error('已取消登录');
      return { clientId: callback.clientId, subject: claims.sub, email: claims.email || '', identity,
        access: token.access_token, refresh: token.refresh_token, expires: Date.now() + token.expires_in * 1000 };
    } finally {
      clearTimeout(timer);
      this.abort = undefined;
      connections.forEach((connection: socket.TCPSocketConnection) => { connection.close().catch(() => {}); });
      await server.close().catch(() => {});
    }
  }
}
