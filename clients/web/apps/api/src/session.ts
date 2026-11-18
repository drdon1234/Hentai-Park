import { createHash, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';

type Session = {
  id: string;
  publicId: string;
  csrf: string;
  expiresAt: number;
  activeAt: number;
  locked: boolean;
  tabs: Map<string, { visible: boolean; at: number }>;
  hiddenAt?: number;
};

export interface SecuritySettingsSnapshot {
  appLockEnabled: boolean;
  appLockTimeoutMs: number;
  appLockPinHash?: string;
}

export interface SessionOptions {
  sessionMode?: 'local' | 'server';
  authToken?: string;
  allowedOrigin?: string;
  securitySettings?: () => SecuritySettingsSnapshot;
  saveAppLockPinHash?: (hash: string | null) => void;
}

const failure = (statusCode: number, code: string) =>
  Object.assign(new Error(code), { statusCode, code, causeCategory: 'validation', publicError: true });

function cookies(request: FastifyRequest) {
  return Object.fromEntries(
    String(request.headers.cookie ?? '')
      .split(';')
      .map((part) => {
        const at = part.indexOf('=');
        if (at < 0) return ['', ''];
        return [part.slice(0, at).trim(), part.slice(at + 1)];
      })
      .filter(([k]) => Boolean(k)),
  );
}

export function hashAppLockPin(pin: string): string {
  const salt = randomBytes(16).toString('base64url');
  const derived = scryptSync(pin, salt, 32).toString('base64url');
  return `scrypt$${salt}$${derived}`;
}

export function verifyAppLockPin(pin: string, stored?: string): boolean {
  if (!stored || !pin || pin.length > 256) return false;
  if (stored.startsWith('scrypt$')) {
    const [, salt, expected] = stored.split('$');
    if (!salt || !expected) return false;
    const actual = scryptSync(pin, salt, 32);
    const expBuf = Buffer.from(expected, 'base64url');
    return actual.length === expBuf.length && timingSafeEqual(actual, expBuf);
  }
  const actual = createHash('sha256').update(pin).digest();
  const expBuf = Buffer.from(stored, 'hex');
  return actual.length === expBuf.length && timingSafeEqual(actual, expBuf);
}

export function installSessions(
  app: FastifyInstance,
  options: SessionOptions,
  revoked: (id: string) => void,
) {
  const mode = options.sessionMode ?? (process.env.WEB_SESSION_MODE === 'server' ? 'server' : 'local');
  const sessions = new Map<string, Session>();
  const attached = new WeakMap<FastifyRequest, Session>();
  const secure = mode === 'server' ? '; Secure' : '';

  const canLock = (security?: SecuritySettingsSnapshot) =>
    Boolean(
      security?.appLockEnabled &&
        (Boolean(security.appLockPinHash) || mode === 'server' || Boolean(options.authToken ?? process.env.AUTH_TOKEN)),
    );

  const create = (reply: FastifyReply, startLocked = false) => {
    const value: Session = {
      tabs: new Map(),
      id: randomBytes(32).toString('base64url'),
      publicId: randomBytes(16).toString('base64url'),
      csrf: randomBytes(32).toString('base64url'),
      expiresAt: Date.now() + 12 * 60 * 60 * 1000,
      activeAt: Date.now(),
      locked: startLocked,
    };
    sessions.set(value.id, value);
    reply.header('set-cookie', [
      `hp_session=${value.id}; Path=/; HttpOnly; SameSite=Strict${secure}; Max-Age=43200`,
      `hp_csrf=${value.csrf}; Path=/; SameSite=Strict${secure}; Max-Age=43200`,
    ]);
    return value;
  };

  const drop = (id: string) => {
    sessions.delete(id);
    revoked(id);
  };

  const verifyCredential = (supplied: string, security?: SecuritySettingsSnapshot): boolean => {
    if (!supplied || supplied.length > 4096) return false;
    if (security?.appLockPinHash && verifyAppLockPin(supplied, security.appLockPinHash)) {
      return true;
    }
    const expected = options.authToken ?? process.env.AUTH_TOKEN;
    if (
      expected &&
      Buffer.byteLength(supplied) === Buffer.byteLength(expected) &&
      timingSafeEqual(Buffer.from(supplied), Buffer.from(expected))
    ) {
      return true;
    }
    return false;
  };

  app.addHook('onRequest', async (request, reply) => {
    const path = request.url.split('?')[0]!;
    if (!path.startsWith('/api/v1/')) return;
    if (request.headers['sec-fetch-site'] === 'cross-site') throw failure(403, 'ORIGIN_FORBIDDEN');
    if (mode === 'local') {
      let hostname: string;
      try {
        hostname = new URL(`http://${request.headers.host}`).hostname;
      } catch {
        throw failure(403, 'ORIGIN_FORBIDDEN');
      }
      if (!['localhost', '127.0.0.1', '[::1]'].includes(hostname)) throw failure(403, 'ORIGIN_FORBIDDEN');
    }
    const now = Date.now();
    for (const [id, value] of sessions) if (value.expiresAt <= now) drop(id);
    const cookie = cookies(request);
    let current = sessions.get(cookie.hp_session ?? '');
    const security = options.securitySettings?.();

    if (
      current &&
      canLock(security) &&
      current.hiddenAt !== undefined &&
      now - current.hiddenAt >= (security?.appLockTimeoutMs ?? 0)
    ) {
      current.locked = true;
    }

    if (!current && mode === 'local') {
      current = create(reply, Boolean(security?.appLockEnabled && security?.appLockPinHash));
    }
    if (current) attached.set(request, current);

    const sessionPublicEndpoints = [
      '/api/v1/session',
      '/api/v1/session/login',
      '/api/v1/session/unlock',
      '/api/v1/session/logout',
      '/api/v1/session/activity',
    ];
    if (!current && !['/api/v1/session', '/api/v1/session/login'].includes(path)) {
      throw failure(401, 'AUTH');
    }
    if (current?.locked && !sessionPublicEndpoints.includes(path)) {
      throw failure(423, 'APP_LOCKED');
    }

    const write = !['GET', 'HEAD', 'OPTIONS'].includes(request.method);
    if (write) {
      const configured = options.allowedOrigin ?? process.env.WEB_ALLOWED_ORIGIN;
      const origin = request.headers.origin;
      const expected = configured ?? `${request.protocol}://${request.headers.host}`;
      if ((origin !== undefined && origin !== expected) || (mode === 'server' && !origin)) {
        throw failure(403, 'ORIGIN_FORBIDDEN');
      }
      if (mode === 'server' && path !== '/api/v1/session/login') {
        if (!current || request.headers['x-csrf-token'] !== current.csrf || cookie.hp_csrf !== current.csrf) {
          throw failure(403, 'CSRF_INVALID');
        }
      }
    }
    if (current && path === '/api/v1/session/activity') current.activeAt = now;
  });

  const describe = (current?: Session) => {
    const security = options.securitySettings?.();
    return {
      sessionId: current?.publicId ?? '',
      mode,
      authenticated: Boolean(current),
      locked: Boolean(current?.locked),
      hasPin: Boolean(security?.appLockPinHash),
      csrfToken: current?.csrf,
    };
  };

  app.post('/api/v1/session/activity', async (request) => {
    const body = request.body as { tabId?: unknown; visible?: unknown } | undefined;
    const current = attached.get(request);
    const security = options.securitySettings?.();
    if (current && body?.tabId !== undefined) {
      if (typeof body.tabId !== 'string' || body.tabId.length > 128 || typeof body.visible !== 'boolean') {
        throw failure(400, 'BAD_REQUEST');
      }
      const now = Date.now();
      current.tabs.set(body.tabId, { visible: body.visible, at: now });
      for (const [id, tab] of current.tabs) if (now - tab.at > 60_000) current.tabs.delete(id);
      if ([...current.tabs.values()].some((tab) => tab.visible)) current.hiddenAt = undefined;
      else current.hiddenAt ??= now;
      if (canLock(security) && current.hiddenAt !== undefined && (security?.appLockTimeoutMs ?? 0) === 0) {
        current.locked = true;
      }
    }
    return { active: true, locked: Boolean(current?.locked), requestId: request.id };
  });

  app.get('/api/v1/session', async (request) => ({ ...describe(attached.get(request)), requestId: request.id }));

  app.post('/api/v1/session/login', async (request, reply) => {
    const body = request.body as { token?: unknown } | undefined;
    const security = options.securitySettings?.();
    if (mode === 'server') {
      const expected = options.authToken ?? process.env.AUTH_TOKEN;
      const supplied = typeof body?.token === 'string' ? body.token : '';
      if (
        !expected ||
        supplied.length > 4096 ||
        Buffer.byteLength(supplied) !== Buffer.byteLength(expected) ||
        !timingSafeEqual(Buffer.from(supplied), Buffer.from(expected))
      ) {
        throw failure(401, 'AUTH');
      }
    } else if (security?.appLockEnabled && security?.appLockPinHash) {
      const supplied = typeof body?.token === 'string' ? body.token : '';
      if (!verifyCredential(supplied, security)) throw failure(401, 'AUTH');
    }
    const previous = attached.get(request);
    if (previous && previous.locked) {
      previous.locked = false;
      previous.hiddenAt = undefined;
      previous.activeAt = Date.now();
      return { ...describe(previous), requestId: request.id };
    }
    if (previous) drop(previous.id);
    const current = create(reply, false);
    return { ...describe(current), requestId: request.id };
  });

  app.post('/api/v1/session/unlock', async (request, reply) => {
    const body = request.body as { token?: unknown; pin?: unknown } | undefined;
    const supplied = typeof body?.pin === 'string' ? body.pin : typeof body?.token === 'string' ? body.token : '';
    const security = options.securitySettings?.();
    if (!verifyCredential(supplied, security)) throw failure(401, 'AUTH');
    let current = attached.get(request);
    if (!current) {
      current = create(reply, false);
    } else {
      current.locked = false;
      current.hiddenAt = undefined;
      current.activeAt = Date.now();
    }
    return { ...describe(current), requestId: request.id };
  });

  app.post('/api/v1/session/lock', async (request) => {
    const current = attached.get(request);
    const security = options.securitySettings?.();
    if (current && canLock(security)) {
      current.locked = true;
    }
    return { ...describe(current), requestId: request.id };
  });

  app.post('/api/v1/session/app-lock-pin', async (request) => {
    const current = attached.get(request);
    if (!current || current.locked) throw failure(401, 'AUTH');
    const body = request.body as { pin?: unknown; currentPin?: unknown } | undefined;
    const security = options.securitySettings?.();
    if (security?.appLockPinHash) {
      const suppliedCurrent = typeof body?.currentPin === 'string' ? body.currentPin : '';
      if (!verifyCredential(suppliedCurrent, security)) throw failure(401, 'AUTH');
    }
    if (body?.pin === null || body?.pin === '') {
      options.saveAppLockPinHash?.(null);
      return { configured: false, requestId: request.id };
    }
    if (typeof body?.pin !== 'string' || body.pin.trim().length < 4 || body.pin.length > 64) {
      throw failure(400, 'BAD_REQUEST');
    }
    options.saveAppLockPinHash?.(hashAppLockPin(body.pin.trim()));
    return { configured: true, requestId: request.id };
  });

  app.post('/api/v1/session/logout', async (request, reply) => {
    const current = attached.get(request);
    if (current) drop(current.id);
    reply.header('set-cookie', [
      `hp_session=; Path=/; HttpOnly; SameSite=Strict${secure}; Max-Age=0`,
      `hp_csrf=; Path=/; SameSite=Strict${secure}; Max-Age=0`,
    ]);
    return { ...describe(), requestId: request.id };
  });

  return {
    id: (request: FastifyRequest) => attached.get(request)?.id ?? '',
    valid: (request: FastifyRequest) => {
      const value = attached.get(request);
      const security = options.securitySettings?.();
      if (!value || !sessions.has(value.id)) return false;
      if (value.expiresAt <= Date.now()) {
        drop(value.id);
        return false;
      }
      if (
        canLock(security) &&
        value.hiddenAt !== undefined &&
        Date.now() - value.hiddenAt >= (security?.appLockTimeoutMs ?? 0)
      ) {
        value.locked = true;
      }
      return !value.locked;
    },
    mode,
  };
}
