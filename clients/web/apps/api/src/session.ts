import { randomBytes, timingSafeEqual } from 'node:crypto';
import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';

type Session = { id: string; publicId:string; csrf: string; expiresAt: number; activeAt: number;tabs:Map<string,{visible:boolean;at:number}>;hiddenAt?:number };
export interface SessionOptions { sessionMode?: 'local' | 'server'; authToken?: string; allowedOrigin?: string; securitySettings?: () => { appLockEnabled: boolean; appLockTimeoutMs: number }; }
const failure = (statusCode: number, code: string) => Object.assign(new Error(code), { statusCode, code, causeCategory: 'validation', publicError: true });
function cookies(request: FastifyRequest) { return Object.fromEntries(String(request.headers.cookie ?? '').split(';').map((part) => { const at = part.indexOf('='); return [part.slice(0, at).trim(), part.slice(at + 1)]; })); }
export function installSessions(app: FastifyInstance, options: SessionOptions, revoked: (id: string) => void) {
  const mode = options.sessionMode ?? (process.env.WEB_SESSION_MODE === 'server' ? 'server' : 'local');
  const sessions = new Map<string, Session>();
  const attached = new WeakMap<FastifyRequest, Session>();
  const secure = '; Secure';
  const create = (reply: FastifyReply) => {
    const value:Session = { tabs:new Map(),id: randomBytes(32).toString('base64url'),publicId:randomBytes(16).toString('base64url'), csrf: randomBytes(32).toString('base64url'), expiresAt: Date.now() + 12 * 60 * 60 * 1000, activeAt: Date.now() };
    sessions.set(value.id, value);
    reply.header('set-cookie', [`hp_session=${value.id}; Path=/; HttpOnly; SameSite=Strict${secure}; Max-Age=43200`, `hp_csrf=${value.csrf}; Path=/; SameSite=Strict${secure}; Max-Age=43200`]);
    return value;
  };
  const drop = (id: string) => { sessions.delete(id); revoked(id); };
  app.addHook('onRequest', async (request, reply) => {
    const path = request.url.split('?')[0]!;
    if (!path.startsWith('/api/v1/')) return;
    // Browser metadata gates the request before any session is read, created or refreshed.
    if (request.headers['sec-fetch-site'] === 'cross-site') throw failure(403, 'ORIGIN_FORBIDDEN');
    if(mode==='local') { let hostname: string; try {hostname=new URL(`http://${request.headers.host}`).hostname;}catch{throw failure(403,'ORIGIN_FORBIDDEN');}if(!['localhost','127.0.0.1','[::1]'].includes(hostname))throw failure(403,'ORIGIN_FORBIDDEN'); }
    const now = Date.now();
    for (const [id, value] of sessions) if (value.expiresAt <= now) drop(id);
    const cookie = cookies(request);
    let current = sessions.get(cookie.hp_session ?? '');
    const security = options.securitySettings?.();
    if(current && security?.appLockEnabled && current.hiddenAt!==undefined&&now-current.hiddenAt >= security.appLockTimeoutMs) { drop(current.id); current=undefined; }
    if (!current && mode === 'local' && !security?.appLockEnabled) current = create(reply);
    if (current) attached.set(request, current);
    if (!current && !['/api/v1/session', '/api/v1/session/login'].includes(path)) throw failure(401, 'AUTH');
    const write = !['GET', 'HEAD', 'OPTIONS'].includes(request.method);
    if (write) {
      const configured = options.allowedOrigin ?? process.env.WEB_ALLOWED_ORIGIN;
      const origin = request.headers.origin;
      const expected = configured ?? `${request.protocol}://${request.headers.host}`;
      if ((origin !== undefined && origin !== expected) || (mode === 'server' && !origin)) throw failure(403, 'ORIGIN_FORBIDDEN');
      if (mode === 'server' && path !== '/api/v1/session/login') {
        if (!current || request.headers['x-csrf-token'] !== current.csrf || cookie.hp_csrf !== current.csrf) throw failure(403, 'CSRF_INVALID');
      }
    }
    if(current && path==='/api/v1/session/activity')current.activeAt=now;
  });
  const describe = (current?: Session) => ({ sessionId: current?.publicId ?? '', mode, authenticated: Boolean(current), csrfToken: current?.csrf });
  app.post('/api/v1/session/activity', async request => {const body=request.body as {tabId?:unknown;visible?:unknown}|undefined,current=attached.get(request);if(current&&body?.tabId!==undefined){if(typeof body.tabId!=='string'||body.tabId.length>128||typeof body.visible!=='boolean')throw failure(400,'BAD_REQUEST');const now=Date.now();current.tabs.set(body.tabId,{visible:body.visible,at:now});for(const [id,tab]of current.tabs)if(now-tab.at>60000)current.tabs.delete(id);if([...current.tabs.values()].some(tab=>tab.visible))current.hiddenAt=undefined;else current.hiddenAt??=now;if(options.securitySettings?.().appLockEnabled&&current.hiddenAt!==undefined&&options.securitySettings().appLockTimeoutMs===0)drop(current.id);}return {active:true,requestId:request.id};});
  app.get('/api/v1/session', async (request) => ({ ...describe(attached.get(request)), requestId: request.id }));
  app.post('/api/v1/session/login', async (request, reply) => {
    const body = request.body as { token?: unknown } | undefined;
    if (mode === 'server' || options.securitySettings?.().appLockEnabled) {
      const expected = options.authToken ?? process.env.AUTH_TOKEN;
      const supplied = typeof body?.token === 'string' ? body.token : '';
      if (!expected || supplied.length > 4096 || Buffer.byteLength(supplied) !== Buffer.byteLength(expected) || !timingSafeEqual(Buffer.from(supplied), Buffer.from(expected))) throw failure(401, 'AUTH');
    }
    const previous = attached.get(request); if (previous) drop(previous.id);
    const current = create(reply);
    return { ...describe(current), requestId: request.id };
  });
  app.post('/api/v1/session/logout', async (request, reply) => {
    const current = attached.get(request); if (current) drop(current.id);
    reply.header('set-cookie', [`hp_session=; Path=/; HttpOnly; SameSite=Strict${secure}; Max-Age=0`, `hp_csrf=; Path=/; SameSite=Strict${secure}; Max-Age=0`]);
    return { ...describe(), requestId: request.id };
  });
  return { id: (request: FastifyRequest) => attached.get(request)?.id ?? '', valid: (request: FastifyRequest) => {const value=attached.get(request);const security=options.securitySettings?.();if(!value||!sessions.has(value.id))return false;if(value.expiresAt<=Date.now()||security?.appLockEnabled&&value.hiddenAt!==undefined&&Date.now()-value.hiddenAt>=security.appLockTimeoutMs){drop(value.id);return false;}return true;}, mode };
}
