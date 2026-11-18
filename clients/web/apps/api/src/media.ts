import type { MediaAttachment } from './album-resource.js';
import { createHash, randomBytes } from 'node:crypto';
import dns from 'node:dns/promises';
import { mkdir, readFile, readdir, stat, unlink, writeFile } from 'node:fs/promises';
import net from 'node:net';
import { join } from 'node:path';
import {
  decodeImage,
  fetchPinnedResource,
  hasHttpProxy,
  hostAllowed,
  isPrivateAddress,
} from '@hentai-park/source-host';
import type { ImageDecrypt } from '@hentai-park/source-contract';
import { unwrapMediaResponse } from './hls-resource.js';

export interface InlineHls {
  manifest: string;
  keys: Record<string, string>;
}

export interface MediaGrant {
  playlist?: boolean;
  attachment?: MediaAttachment;
  source: string;
  resourceKey: string;
  sessionId?: string;
  url: string;
  resources: string[];
  domains: string[];
  scope?: 'session';
  expiresAt: number;
  revokedAt?: number;
  hls?: InlineHls;
  image?: boolean;
  imageDecrypt?: ImageDecrypt;
  inlineImage?: { mime: string; bytes: Uint8Array };
  inlineCaption?: string;
  fetchResource?: (
    url: string,
    options: { signal?: AbortSignal; range?: string; method?: 'GET' | 'HEAD' },
  ) => Promise<Response>;
  resolve?: (signal?: AbortSignal) => Promise<Omit<MediaGrant, 'expiresAt' | 'resources'>>;
}

export interface MediaFetch {
  status: number;
  headers: Headers;
  body: ReadableStream<Uint8Array> | null;
  signal?: AbortSignal;
}

const MIME_TO_CODE: Record<string, number> = {
  'image/jpeg': 1,
  'image/png': 2,
  'image/webp': 3,
  'image/gif': 4,
};
const CODE_TO_MIME: Record<number, string> = {
  1: 'image/jpeg',
  2: 'image/png',
  3: 'image/webp',
  4: 'image/gif',
};

export class MediaProxy {
  imageConcurrency = () => 16;
  private imageActive = 0;
  private readonly hostActive = new Map<string, number>();
  private readonly imageWaiters = new Set<() => void>();

  private async imageSlot(hostKey: string, signal?: AbortSignal) {
    const perHostMax = Math.max(4, Math.ceil(this.imageConcurrency() / 2));
    while (this.imageActive >= this.imageConcurrency() || (this.hostActive.get(hostKey) ?? 0) >= perHostMax) {
      await new Promise<void>((resolve, reject) => {
        const done = () => {
          this.imageWaiters.delete(done);
          signal?.removeEventListener('abort', cancel);
          resolve();
        };
        const cancel = () => {
          this.imageWaiters.delete(done);
          signal?.removeEventListener('abort', cancel);
          reject(signal?.reason);
        };
        this.imageWaiters.add(done);
        signal?.addEventListener('abort', cancel, { once: true });
        if (signal?.aborted) cancel();
      });
    }
    signal?.throwIfAborted();
    this.imageActive++;
    this.hostActive.set(hostKey, (this.hostActive.get(hostKey) ?? 0) + 1);
    return () => {
      this.imageActive--;
      const next = (this.hostActive.get(hostKey) ?? 1) - 1;
      if (next <= 0) this.hostActive.delete(hostKey);
      else this.hostActive.set(hostKey, next);
      for (const wake of [...this.imageWaiters]) wake();
    };
  }

  private readonly controllers = new Map<string, AbortController>();
  private readonly sessionEpochs = new Map<string, number>();
  private readonly sourceEpochs = new Map<string, number>();
  private readonly grants = new Map<string, MediaGrant>();
  private readonly resourceSets = new Map<string, Set<string>>();
  private readonly playlists = new Map<string, Set<string>>();
  private readonly resourceIds = new Map<string, Map<string, string>>();
  private readonly urlToResourceId = new Map<string, Map<string, string>>();
  private readonly fetchImpl: typeof fetch;
  private readonly now: () => number;
  private readonly lookup: typeof dns.lookup;
  private readonly validated = new Map<string, number>();
  private readonly validationLifetime = 60_000;

  // Working memory + disk LRU image cache + singleflight deduplication
  private readonly imageCache = new Map<string, { bytes: Buffer; mime: string; etag: string; expires: number; used: number }>();
  private imageCacheBytes = 0;
  private readonly imageCacheMaxBytes = 96 * 1024 * 1024;
  private readonly imageCacheLifetime = 3_600_000;
  private readonly inflightImages = new Map<string, Promise<{ bytes: Buffer; mime: string; etag: string }>>();
  private diskCacheDir?: string;
  private diskCacheLimitBytes: () => number = () => 512 * 1024 * 1024;
  private diskWritesSincePrune = 0;

  // MP4 ByteRangeCache for fast moov/head probes without duplicate upstream connections
  private readonly rangeCache = new Map<string, { status: number; headers: Array<[string, string]>; bytes: Buffer; used: number; expires: number }>();
  private rangeCacheBytes = 0;
  private readonly rangeCacheMaxBytes = 32 * 1024 * 1024;

  // Transparent refresh lock per token
  private readonly refreshingTokens = new Map<string, Promise<boolean>>();

  constructor(fetchImpl: typeof fetch = fetch, now = () => Date.now(), lookup: typeof dns.lookup = dns.lookup) {
    this.fetchImpl = fetchImpl;
    this.now = now;
    this.lookup = lookup;
  }

  configureDiskCache(directory: string, limitBytes?: () => number) {
    this.diskCacheDir = directory;
    if (limitBytes) this.diskCacheLimitBytes = limitBytes;
  }

  private async readDiskImage(cacheKey: string): Promise<{ bytes: Buffer; mime: string; etag: string } | undefined> {
    if (!this.diskCacheDir) return undefined;
    const hash = createHash('sha256').update(cacheKey).digest('hex');
    const file = join(this.diskCacheDir, `${hash}.img`);
    try {
      const raw = await readFile(file);
      if (raw.length < 2) return undefined;
      const mime = CODE_TO_MIME[raw[0]!];
      if (!mime) return undefined;
      const bytes = raw.subarray(1);
      const etag = `"${hash.slice(0, 24)}"`;
      return { bytes, mime, etag };
    } catch {
      return undefined;
    }
  }

  private writeDiskImage(cacheKey: string, bytes: Buffer, mime: string) {
    if (!this.diskCacheDir || bytes.length > 8 * 1024 * 1024) return;
    const code = MIME_TO_CODE[mime];
    if (!code) return;
    const dir = this.diskCacheDir;
    const hash = createHash('sha256').update(cacheKey).digest('hex');
    const file = join(dir, `${hash}.img`);
    void (async () => {
      try {
        await mkdir(dir, { recursive: true });
        const payload = Buffer.allocUnsafe(1 + bytes.length);
        payload[0] = code;
        bytes.copy(payload, 1);
        await writeFile(file, payload);
        if (++this.diskWritesSincePrune >= 64) {
          this.diskWritesSincePrune = 0;
          await this.pruneDiskCache();
        }
      } catch {
        // Best-effort disk cache
      }
    })();
  }

  private async pruneDiskCache() {
    if (!this.diskCacheDir) return;
    const limit = Math.max(0, Math.floor(this.diskCacheLimitBytes() * 0.5));
    if (limit <= 0) return;
    try {
      const names = await readdir(this.diskCacheDir);
      const entries: Array<{ path: string; size: number; mtimeMs: number }> = [];
      let total = 0;
      for (const name of names) {
        if (!name.endsWith('.img')) continue;
        const path = join(this.diskCacheDir, name);
        const info = await stat(path).catch(() => null);
        if (!info) continue;
        total += info.size;
        entries.push({ path, size: info.size, mtimeMs: info.mtimeMs });
      }
      if (total <= limit) return;
      entries.sort((a, b) => a.mtimeMs - b.mtimeMs);
      for (const entry of entries) {
        if (total <= limit * 0.8) break;
        await unlink(entry.path).catch(() => {});
        total -= entry.size;
      }
    } catch {
      // Ignore prune errors
    }
  }

  private storeMemoryImage(cacheKey: string, bytes: Buffer, mime: string, etag: string) {
    if (bytes.length > 6 * 1024 * 1024) return;
    const existing = this.imageCache.get(cacheKey);
    if (existing) {
      this.imageCacheBytes -= existing.bytes.length;
      this.imageCache.delete(cacheKey);
    }
    while (this.imageCache.size > 0 && (this.imageCacheBytes + bytes.length > this.imageCacheMaxBytes || this.imageCache.size >= 256)) {
      const oldestKey = this.imageCache.keys().next().value;
      if (!oldestKey) break;
      const removed = this.imageCache.get(oldestKey);
      if (removed) this.imageCacheBytes -= removed.bytes.length;
      this.imageCache.delete(oldestKey);
    }
    this.imageCache.set(cacheKey, {
      bytes: Buffer.from(bytes),
      mime,
      etag,
      expires: this.now() + this.imageCacheLifetime,
      used: this.now(),
    });
    this.imageCacheBytes += bytes.length;
  }

  private getMemoryImage(cacheKey: string) {
    const hit = this.imageCache.get(cacheKey);
    if (!hit) return undefined;
    if (hit.expires <= this.now()) {
      this.imageCacheBytes -= hit.bytes.length;
      this.imageCache.delete(cacheKey);
      return undefined;
    }
    // Refresh insertion order for O(1) LRU
    this.imageCache.delete(cacheKey);
    hit.used = this.now();
    this.imageCache.set(cacheKey, hit);
    return hit;
  }

  private async validate(input: string, domains: string[] | undefined, allowPort = false) {
    const blocked = (reason: string) =>
      Object.assign(new Error('media upstream is blocked'), {
        statusCode: 403,
        code: 'MEDIA_SOURCE_BLOCKED',
        publicError: true,
        causeCategory: 'source',
        retryable: false,
        details: { reason },
      });
    let u: URL;
    try {
      u = new URL(input);
    } catch {
      throw blocked('URL_INVALID');
    }
    if (
      u.protocol !== 'https:' ||
      u.username ||
      u.password ||
      (!allowPort && Boolean(u.port)) ||
      (domains !== undefined && !hostAllowed(u.hostname, domains))
    ) {
      throw blocked('URL_POLICY');
    }
    const policy = JSON.stringify([u.protocol, u.hostname, u.port, allowPort, domains?.slice().sort() ?? null]);
    const cachedExpires = this.validated.get(policy);
    if (cachedExpires !== undefined && cachedExpires > this.now()) return u;
    if (hasHttpProxy() && this.lookup === dns.lookup) {
      if (net.isIP(u.hostname) && isPrivateAddress(u.hostname)) throw blocked('DNS_PRIVATE');
    } else {
      const records = await this.lookup(u.hostname, { all: true });
      if (!records.length || records.some((r) => isPrivateAddress(r.address))) throw blocked('DNS_PRIVATE');
    }
    this.validated.set(policy, this.now() + this.validationLifetime);
    if (this.validated.size > 4096) {
      const cutoff = this.now();
      for (const [key, expires] of this.validated) if (expires <= cutoff) this.validated.delete(key);
    }
    return u;
  }

  async issue(input: Omit<MediaGrant, 'expiresAt' | 'resources'> & { resources?: string[]; ttlMs?: number }) {
    const epoch = input.sessionId ? (this.sessionEpochs.get(input.sessionId) ?? 0) : 0;
    const sourceEpoch = this.sourceEpochs.get(input.source) ?? 0;
    if (input.hls) {
      if (
        typeof input.hls.manifest !== 'string' ||
        Buffer.byteLength(input.hls.manifest) > 2_000_000 ||
        !input.hls.keys ||
        Object.keys(input.hls.keys).length > 32
      ) {
        throw Object.assign(new Error('invalid inline HLS'), { statusCode: 400 });
      }
      for (const [url, key] of Object.entries(input.hls.keys)) {
        await this.validate(url, input.scope === 'session' || input.image ? undefined : input.domains);
        if (typeof key !== 'string' || Buffer.from(key, 'base64').length !== 16) {
          throw Object.assign(new Error('invalid HLS key'), { statusCode: 400 });
        }
      }
    }
    const urls = [...new Set([input.url, ...(input.resources ?? [])])];
    const resources: string[] = [];
    for (const resource of urls) {
      resources.push(
        input.attachment || input.inlineImage || input.inlineCaption !== undefined
          ? 'inline'
          : (
              await this.validate(
                resource,
                input.scope === 'session' || input.image ? undefined : input.domains,
                input.image === true,
              )
            ).toString(),
      );
    }
    if (
      input.inlineImage &&
      (!['image/png', 'image/jpeg', 'image/gif', 'image/webp'].includes(input.inlineImage.mime) ||
        input.inlineImage.bytes.length > 512 * 1024)
    ) {
      throw Object.assign(new Error('invalid inline image'), { statusCode: 400 });
    }
    if (
      (this.sourceEpochs.get(input.source) ?? 0) !== sourceEpoch ||
      (input.sessionId && (this.sessionEpochs.get(input.sessionId) ?? 0) !== epoch)
    ) {
      throw Object.assign(new Error('media session was revoked'), {
        code: 'CANCELLED',
        statusCode: 499,
        publicError: true,
      });
    }
    const url = resources[0]!;
    const token = randomBytes(32).toString('base64url');
    const defaultTtl = input.image ? 1_800_000 : 7_200_000;
    const expiresAt = this.now() + Math.min(Math.max(input.ttlMs ?? defaultTtl, 1_000), 14_400_000);
    this.purgeExpired();
    this.grants.set(token, { ...input, url, resources, expiresAt });
    this.resourceSets.set(token, new Set(resources));
    this.controllers.set(token, new AbortController());
    this.resourceIds.set(token, new Map());
    this.urlToResourceId.set(token, new Map());
    this.playlists.set(token, new Set(input.playlist ? [url] : []));
    return { token, expiresAt };
  }

  close() {
    for (const token of this.grants.keys()) this.revoke(token);
  }

  async renew(token: string, sessionId: string, signal?: AbortSignal) {
    const grant = this.grants.get(token);
    if (!grant || grant.sessionId !== sessionId || grant.revokedAt || grant.expiresAt <= this.now()) {
      throw Object.assign(new Error('media token expired'), {
        code: 'NOT_FOUND',
        statusCode: 404,
        publicError: true,
      });
    }
    // Keepalive without re-scraping upstream `videos()`: upstream URL refresh is handled transparently
    // on 401/403/410 inside fetchContent so `<video>` / `hls.js` never tears down mid-playback!
    const nextExpires = this.now() + (grant.image ? 1_800_000 : 7_200_000);
    grant.expiresAt = Math.max(grant.expiresAt, nextExpires);
    if (!this.controllers.has(token)) this.controllers.set(token, new AbortController());
    signal?.throwIfAborted();
    return { token, expiresAt: grant.expiresAt, changed: false };
  }

  private async tryTransparentRefresh(token: string, grant: MediaGrant, signal?: AbortSignal): Promise<boolean> {
    if (!grant.resolve) return false;
    const existing = this.refreshingTokens.get(token);
    if (existing) return existing;
    const action = (async () => {
      try {
        const next = await grant.resolve!(signal);
        if (this.grants.get(token) !== grant) return false;
        if (next.source !== grant.source || next.resourceKey !== grant.resourceKey || next.sessionId !== grant.sessionId) {
          this.revokeResource(grant.source, grant.resourceKey);
          return false;
        }
        const canonical =
          next.attachment || next.inlineImage || next.inlineCaption !== undefined
            ? 'inline'
            : (
                await this.validate(
                  next.url,
                  next.scope === 'session' || next.image ? undefined : next.domains,
                  next.image === true,
                )
              ).toString();
        grant.url = canonical;
        grant.hls = next.hls;
        grant.fetchResource = next.fetchResource;
        grant.attachment = next.attachment;
        grant.expiresAt = Math.max(grant.expiresAt, this.now() + (grant.image ? 1_800_000 : 7_200_000));
        const set = this.resourceSets.get(token) ?? new Set(grant.resources);
        if (!set.has(canonical)) {
          set.add(canonical);
          grant.resources.push(canonical);
        }
        this.resourceSets.set(token, set);
        if (grant.playlist) this.playlists.get(token)?.add(canonical);
        return true;
      } catch (error) {
        if (['AUTH', 'CONFIG', 'BLOCKED', 'NOT_FOUND'].includes(String((error as { code?: string }).code))) {
          this.revokeResource(grant.source, grant.resourceKey);
        }
        return false;
      }
    })();
    this.refreshingTokens.set(token, action);
    try {
      return await action;
    } finally {
      this.refreshingTokens.delete(token);
    }
  }

  revoke(token: string) {
    this.controllers.get(token)?.abort();
    this.controllers.delete(token);
    this.grants.delete(token);
    this.resourceSets.delete(token);
    this.resourceIds.delete(token);
    this.urlToResourceId.delete(token);
    this.playlists.delete(token);
  }

  revokeSession(sessionId: string) {
    this.sessionEpochs.set(sessionId, (this.sessionEpochs.get(sessionId) ?? 0) + 1);
    for (const [token, grant] of this.grants) if (grant.sessionId === sessionId) this.revoke(token);
  }

  revokeResource(source: string, resourceKey: string) {
    for (const [token, grant] of this.grants) {
      if (grant.source === source && grant.resourceKey === resourceKey) this.revoke(token);
    }
  }

  revokeSource(source: string) {
    this.sourceEpochs.set(source, (this.sourceEpochs.get(source) ?? 0) + 1);
    for (const [token, grant] of this.grants) if (grant.source === source) this.revoke(token);
    for (const key of this.imageCache.keys()) {
      if (key.startsWith(`["${source}",`)) {
        const entry = this.imageCache.get(key);
        if (entry) this.imageCacheBytes -= entry.bytes.length;
        this.imageCache.delete(key);
      }
    }
  }

  purgeExpired() {
    const now = this.now();
    for (const [token, grant] of this.grants) {
      if (grant.expiresAt <= now || grant.revokedAt) this.revoke(token);
    }
    for (const [key, entry] of this.rangeCache) {
      if (entry.expires <= now) {
        this.rangeCacheBytes -= entry.bytes.length;
        this.rangeCache.delete(key);
      }
    }
  }

  async fetch(
    token: string,
    headers: HeadersInit = {},
    method = 'GET',
    resourceId?: string,
    sessionId?: string,
    signal?: AbortSignal,
  ): Promise<MediaFetch> {
    const grantSignal = this.controllers.get(token)?.signal;
    const readSignal = signal && grantSignal ? AbortSignal.any([signal, grantSignal]) : (signal ?? grantSignal);
    const grant = this.grants.get(token);
    let hostKey = grant?.source ?? 'default';
    if (grant?.image && grant.url && grant.url !== 'inline') {
      try {
        hostKey = new URL(grant.url).hostname || hostKey;
      } catch {
        // fallback to source
      }
    }
    // Fast-path cache check before acquiring upstream concurrency slot!
    if (grant?.image && !grant.revokedAt && grant.expiresAt > this.now() && (!grant.sessionId || grant.sessionId === sessionId) && !resourceId && grant.url !== 'inline') {
      const cacheKey = JSON.stringify([grant.source, grant.url, grant.imageDecrypt ?? null]);
      const memHit = this.getMemoryImage(cacheKey);
      if (memHit) {
        return { ...this.serveCachedImage(memHit, new Headers(headers), method), signal: grantSignal };
      }
      const diskHit = await this.readDiskImage(cacheKey);
      if (diskHit) {
        this.storeMemoryImage(cacheKey, diskHit.bytes, diskHit.mime, diskHit.etag);
        return { ...this.serveCachedImage(diskHit, new Headers(headers), method), signal: grantSignal };
      }
    }

    const release = grant?.image ? await this.imageSlot(hostKey, readSignal) : undefined;
    try {
      const result = await this.fetchContent(token, headers, method, resourceId, sessionId, readSignal, false);
      return { ...result, signal: grantSignal };
    } finally {
      release?.();
    }
  }

  private serveCachedImage(
    cached: { bytes: Buffer; mime: string; etag: string },
    requestHeaders: Headers,
    method: string,
  ): MediaFetch {
    const outHeaders = new Headers({
      'content-type': cached.mime,
      'content-length': String(cached.bytes.length),
      'cache-control': 'private, max-age=3600',
      'accept-ranges': 'bytes',
      etag: cached.etag,
    });
    if (!requestHeaders.get('range') && requestHeaders.get('if-none-match') === cached.etag) {
      outHeaders.delete('content-length');
      return { status: 304, headers: outHeaders, body: null };
    }
    let status = 200;
    let body: Uint8Array = cached.bytes;
    const range = requestHeaders.get('range');
    if (range && method !== 'HEAD') {
      const match = /^bytes=(\d*)-(\d*)$/.exec(range);
      const start = match?.[1] ? Number(match[1]) : match?.[2] ? Math.max(0, cached.bytes.length - Number(match[2])) : NaN;
      const end = match?.[1] && match[2] ? Math.min(cached.bytes.length - 1, Number(match[2])) : cached.bytes.length - 1;
      if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || start >= cached.bytes.length || end < start) {
        outHeaders.set('content-range', `bytes */${cached.bytes.length}`);
        outHeaders.set('content-length', '0');
        return { status: 416, headers: outHeaders, body: null };
      }
      body = cached.bytes.subarray(start, end + 1);
      status = 206;
      outHeaders.set('content-range', `bytes ${start}-${end}/${cached.bytes.length}`);
      outHeaders.set('content-length', String(body.length));
    }
    return {
      status,
      headers: outHeaders,
      body:
        method === 'HEAD'
          ? null
          : new ReadableStream({
              start(controller) {
                controller.enqueue(body);
                controller.close();
              },
            }),
    };
  }

  private async fetchContent(
    token: string,
    headers: HeadersInit = {},
    method = 'GET',
    resourceId?: string,
    sessionId?: string,
    signal?: AbortSignal,
    retried = false,
  ): Promise<MediaFetch> {
    const grant = this.grants.get(token);
    if (!grant || grant.revokedAt || grant.expiresAt <= this.now() || (grant.sessionId && grant.sessionId !== sessionId)) {
      throw Object.assign(new Error('media token expired'), { statusCode: 404 });
    }
    // Sliding TTL extension on active playback/read
    if (!grant.image) {
      grant.expiresAt = Math.max(grant.expiresAt, this.now() + 7_200_000);
    }

    const raw = resourceId ? this.resourceIds.get(token)?.get(resourceId) : grant.url;
    if (!raw) throw Object.assign(new Error('media resource is outside authorization chain'), { statusCode: 403 });
    const canonical =
      (grant.attachment || grant.inlineImage || grant.inlineCaption !== undefined) && raw === 'inline'
        ? 'inline'
        : (
            await this.validate(
              raw,
              grant.scope === 'session' || grant.image ? undefined : grant.domains,
              grant.image === true,
            )
          ).toString();
    const allowedSet = this.resourceSets.get(token);
    if (!(allowedSet ? allowedSet.has(canonical) : grant.resources.includes(canonical))) {
      throw Object.assign(new Error('media resource is outside authorization chain'), { statusCode: 403 });
    }

    const requestHeaders = new Headers(headers);
    const range = requestHeaders.get('range');

    // Image singleflight + memory/disk cache check
    if (grant.image && canonical !== 'inline' && !grant.attachment) {
      const cacheKey = JSON.stringify([grant.source, canonical, grant.imageDecrypt ?? null]);
      const memHit = this.getMemoryImage(cacheKey);
      if (memHit) return this.serveCachedImage(memHit, requestHeaders, method);

      let pending = this.inflightImages.get(cacheKey);
      if (!pending) {
        const fetchImageOnce = async (): Promise<{ bytes: Buffer; mime: string; etag: string }> => {
          const init: RequestInit = {
            method: 'GET',
            redirect: 'manual',
            signal: AbortSignal.any([
              AbortSignal.timeout(30_000),
              ...(this.controllers.has(token) ? [this.controllers.get(token)!.signal] : []),
            ]),
          };
          let response =
            this.fetchImpl !== fetch
              ? await this.fetchImpl(canonical, init)
              : grant.fetchResource
                ? await grant.fetchResource(canonical, { signal: init.signal ?? undefined, method: 'GET' })
                : await fetchPinnedResource(canonical, undefined, {
                    signal: init.signal ?? undefined,
                    method: 'GET',
                    allowPort: true,
                  });
          if ((response.status === 401 || response.status === 403 || response.status === 410) && !retried && !resourceId) {
            await response.body?.cancel().catch(() => {});
            if (await this.tryTransparentRefresh(token, grant, signal)) {
              const refreshedUrl = grant.url;
              response =
                this.fetchImpl !== fetch
                  ? await this.fetchImpl(refreshedUrl, init)
                  : grant.fetchResource
                    ? await grant.fetchResource(refreshedUrl, { signal: init.signal ?? undefined, method: 'GET' })
                    : await fetchPinnedResource(refreshedUrl, undefined, {
                        signal: init.signal ?? undefined,
                        method: 'GET',
                        allowPort: true,
                      });
            }
          }
          if (response.status >= 300 && response.status < 400) {
            await response.body?.cancel().catch(() => {});
            throw Object.assign(new Error('media redirect blocked'), { statusCode: 502 });
          }
          if (!response.ok) {
            await response.body?.cancel().catch(() => {});
            throw Object.assign(new Error('Upstream media failed'), {
              statusCode: response.status,
              code: response.status === 401 || response.status === 403 ? 'AUTH' : response.status === 404 ? 'NOT_FOUND' : 'NETWORK',
              causeCategory: 'source',
              publicError: true,
              retryable: response.status >= 500 || response.status === 404,
            });
          }
          const reader = response.body?.getReader();
          const chunks: Uint8Array[] = [];
          let size = 0;
          try {
            if (reader) {
              for (;;) {
                const next = await reader.read();
                if (next.done) break;
                size += next.value.length;
                if (size > 20 * 1024 * 1024) throw Object.assign(new Error('image too large'), { statusCode: 502 });
                chunks.push(next.value);
              }
            }
          } finally {
            await reader?.cancel().catch(() => {});
          }
          const rawBytes = Buffer.concat(chunks);
          let bytes: Buffer;
          let mime: string;
          if (response.headers.get('x-hp-image-decoded') === '1' && !grant.imageDecrypt) {
            bytes = rawBytes;
            mime = response.headers.get('content-type') || 'image/jpeg';
          } else {
            try {
              const decoded = decodeImage(rawBytes, grant.imageDecrypt);
              bytes = Buffer.from(decoded.bytes);
              mime = decoded.mime;
            } catch (error) {
              throw Object.assign(error as Error, { statusCode: 502, publicError: true, causeCategory: 'source' });
            }
          }
          const etag = `"${createHash('sha256').update(cacheKey).digest('hex').slice(0, 24)}"`;
          this.storeMemoryImage(cacheKey, bytes, mime, etag);
          this.writeDiskImage(cacheKey, bytes, mime);
          return { bytes, mime, etag };
        };
        pending = fetchImageOnce().finally(() => this.inflightImages.delete(cacheKey));
        this.inflightImages.set(cacheKey, pending);
      }
      const resolved = await pending;
      signal?.throwIfAborted();
      return this.serveCachedImage(resolved, requestHeaders, method);
    }

    // MP4 ByteRangeCache lookup for small probe/moov ranges (<= 2 MiB)
    const rangeCacheKey = !grant.image && !grant.playlist && range && method === 'GET' ? `${grant.source}|${canonical}|${range}` : undefined;
    if (rangeCacheKey) {
      const hit = this.rangeCache.get(rangeCacheKey);
      if (hit && hit.expires > this.now()) {
        hit.used = this.now();
        return {
          status: hit.status,
          headers: new Headers(hit.headers),
          body: new ReadableStream({
            start(controller) {
              controller.enqueue(hit.bytes);
              controller.close();
            },
          }),
        };
      }
    }

    const init: RequestInit = {
      method: grant.image ? 'GET' : method,
      redirect: 'manual',
      signal: AbortSignal.any([
        AbortSignal.timeout(45_000),
        ...(signal ? [signal] : []),
        ...(this.controllers.has(token) ? [this.controllers.get(token)!.signal] : []),
      ]),
    };
    if (range && !grant.image) init.headers = { range };

    const inline =
      grant.inlineCaption !== undefined
        ? new Response(init.method === 'HEAD' ? null : grant.inlineCaption, {
            headers: { 'content-type': 'text/vtt; charset=utf-8' },
          })
        : grant.inlineImage
          ? new Response(init.method === 'HEAD' ? null : Buffer.from(grant.inlineImage.bytes), {
              headers: { 'content-type': grant.inlineImage.mime },
            })
          : grant.hls && canonical === grant.url
            ? new Response(init.method === 'HEAD' ? null : grant.hls.manifest, {
                headers: { 'content-type': 'application/vnd.apple.mpegurl' },
              })
            : grant.hls?.keys[canonical]
              ? new Response(init.method === 'HEAD' ? null : Buffer.from(grant.hls.keys[canonical]!, 'base64'), {
                  headers: { 'content-type': 'application/octet-stream' },
                })
              : undefined;

    const response = grant.attachment
      ? await grant.attachment.read({
          signal: init.signal ?? undefined,
          range: grant.image ? undefined : (range ?? undefined),
          method: init.method === 'HEAD' ? 'HEAD' : 'GET',
        })
      : inline ??
        (this.fetchImpl !== fetch
          ? await this.fetchImpl(canonical, init)
          : grant.fetchResource
            ? await grant.fetchResource(canonical, {
                signal: init.signal ?? undefined,
                range: grant.image ? undefined : (range ?? undefined),
                method: init.method === 'HEAD' ? 'HEAD' : 'GET',
              })
            : await fetchPinnedResource(canonical, grant.scope === 'session' || grant.image ? undefined : grant.domains, {
                signal: init.signal ?? undefined,
                headers: range && !grant.image ? { range } : undefined,
                method: init.method === 'HEAD' ? 'HEAD' : 'GET',
                allowPort: grant.image === true,
              }));

    if (response.status >= 300 && response.status < 400) {
      await response.body?.cancel().catch(() => {});
      throw Object.assign(new Error('media redirect blocked'), { statusCode: 502 });
    }

    if (!response.ok && response.status !== 416) {
      await response.body?.cancel().catch(() => {});
      if ((response.status === 401 || response.status === 403 || response.status === 410) && !retried && !resourceId) {
        if (await this.tryTransparentRefresh(token, grant, signal)) {
          return this.fetchContent(token, headers, method, resourceId, sessionId, signal, true);
        }
      }
      throw Object.assign(new Error('Upstream media failed'), {
        statusCode: response.status,
        code: response.status === 401 || response.status === 403 ? 'AUTH' : response.status === 404 ? 'NOT_FOUND' : 'NETWORK',
        causeCategory: 'source',
        publicError: true,
        retryable: response.status >= 500 || response.status === 404,
      });
    }

    if (grant.image && response.ok) {
      const reader = response.body?.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      try {
        if (reader) {
          for (;;) {
            const next = await reader.read();
            if (next.done) break;
            size += next.value.length;
            if (size > 20 * 1024 * 1024) throw Object.assign(new Error('image too large'), { statusCode: 502 });
            chunks.push(next.value);
          }
        }
      } finally {
        await reader?.cancel().catch(() => {});
      }
      let decoded: { bytes: Uint8Array; mime: string };
      try {
        decoded = decodeImage(Buffer.concat(chunks), grant.imageDecrypt);
      } catch (error) {
        throw Object.assign(error as Error, { statusCode: 502, publicError: true, causeCategory: 'source' });
      }
      const etag = `"${createHash('sha256').update(decoded.bytes).digest('hex').slice(0, 24)}"`;
      return this.serveCachedImage({ bytes: Buffer.from(decoded.bytes), mime: decoded.mime, etag }, requestHeaders, method);
    }

    const playlistBase =
      this.fetchImpl === fetch && response.url
        ? (await this.validate(response.url, grant.scope === 'session' || grant.image ? undefined : grant.domains)).href
        : canonical;
    const isKnownPlaylist = this.playlists.get(token)?.has(canonical) ?? false;
    const decodedResponse =
      method === 'HEAD'
        ? response
        : await unwrapMediaResponse(
            response,
            isKnownPlaylist ? 2_000_000 : 32 * 1024 * 1024,
            Boolean(resourceId && !isKnownPlaylist),
          );
    const type = (decodedResponse.headers.get('content-type') ?? '').replace(
      /^binary\/octet-stream\b/i,
      'application/octet-stream',
    );
    const playlist = isKnownPlaylist || /mpegurl/i.test(type) || /\.m3u8(?:\?|$)/i.test(canonical);
    if (
      response.ok &&
      !playlist &&
      !/^(?:image\/|video\/|audio\/|text\/vtt|application\/(?:vnd\.apple\.mpegurl|x-mpegurl|mp2t|mp4|dash\+xml|octet-stream))/i.test(
        type,
      )
    ) {
      await decodedResponse.body?.cancel();
      throw Object.assign(new Error('media content type blocked'), { statusCode: 502 });
    }
    const outHeaders = new Headers(decodedResponse.headers);
    if (type) outHeaders.set('content-type', type);
    outHeaders.set('cache-control', 'private, no-store');
    if (playlist) {
      outHeaders.set('content-type', 'application/vnd.apple.mpegurl');
      outHeaders.delete('content-length');
    }

    if (method !== 'HEAD' && response.ok && playlist) {
      const reader = decodedResponse.body?.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      if (reader) {
        try {
          for (;;) {
            const next = await reader.read();
            if (next.done) break;
            size += next.value.length;
            if (size > 2_000_000) throw Object.assign(new Error('playlist too large'), { statusCode: 502 });
            chunks.push(next.value);
          }
        } finally {
          await reader.cancel().catch(() => {});
          reader.releaseLock();
        }
      }
      const text = Buffer.concat(chunks).toString('utf8');
      if (!text.trimStart().startsWith('#EXTM3U') || text.length > 2_000_000) {
        throw Object.assign(new Error('playlist too large'), { statusCode: 502 });
      }
      const ids = this.resourceIds.get(token)!;
      const reverse = this.urlToResourceId.get(token)!;
      const resSet = this.resourceSets.get(token)!;

      const authorize = async (uri: string, childPlaylist = false) => {
        const url = (
          await this.validate(new URL(uri, playlistBase).toString(), grant.scope === 'session' ? undefined : grant.domains)
        ).toString();
        if (childPlaylist) this.playlists.get(token)?.add(url);
        let id = reverse.get(url);
        if (!id) {
          // Sliding resource window for long-running 24/7 live HLS streams
          if (grant.resources.length >= 25_000) {
            const evictCount = 5_000;
            for (let i = 1; i <= evictCount && grant.resources.length > 1; i++) {
              const evictedUrl = grant.resources.splice(1, 1)[0]!;
              if (this.playlists.get(token)?.has(evictedUrl)) {
                grant.resources.push(evictedUrl);
                continue;
              }
              resSet.delete(evictedUrl);
              const evictedId = reverse.get(evictedUrl);
              if (evictedId) {
                reverse.delete(evictedUrl);
                ids.delete(evictedId);
              }
            }
          }
          id = randomBytes(16).toString('base64url');
          ids.set(id, url);
          reverse.set(url, id);
          if (!resSet.has(url)) {
            resSet.add(url);
            grant.resources.push(url);
          }
        }
        return `/api/v1/media/${token}?resource=${id}`;
      };

      const lines: string[] = [];
      let nextPlaylist = false;
      for (const line of text.split(/\r?\n/)) {
        if (!line || (line.startsWith('#') && !line.includes('URI="'))) {
          if (line.startsWith('#EXT-X-STREAM-INF:')) nextPlaylist = true;
          lines.push(line);
          continue;
        }
        if (line.startsWith('#')) {
          let rewritten = line;
          for (const match of line.matchAll(/URI="([^"]+)"/g)) {
            rewritten = rewritten.replace(
              match[0],
              `URI="${await authorize(match[1]!, /^#EXT-X-(?:MEDIA|I-FRAME-STREAM-INF):/.test(line))}"`,
            );
          }
          lines.push(rewritten);
        } else {
          lines.push(await authorize(line.trim(), nextPlaylist));
          nextPlaylist = false;
        }
      }
      const body = new TextEncoder().encode(lines.join('\n'));
      outHeaders.delete('content-length');
      outHeaders.set('content-type', 'application/vnd.apple.mpegurl');
      return {
        status: response.status,
        headers: outHeaders,
        body: new ReadableStream({
          start(controller) {
            controller.enqueue(body);
            controller.close();
          },
        }),
      };
    }

    // Populate MP4 ByteRangeCache for bounded small Range responses (<= 2 MiB, e.g. moov atom probe)
    const contentLen = Number(outHeaders.get('content-length') ?? NaN);
    if (rangeCacheKey && response.status === 206 && Number.isFinite(contentLen) && contentLen > 0 && contentLen <= 2 * 1024 * 1024 && decodedResponse.body) {
      const reader = decodedResponse.body.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      try {
        for (;;) {
          const next = await reader.read();
          if (next.done) break;
          size += next.value.length;
          if (size > 2 * 1024 * 1024) break;
          chunks.push(next.value);
        }
      } finally {
        reader.releaseLock();
      }
      const bytes = Buffer.concat(chunks);
      if (bytes.length === contentLen) {
        while (this.rangeCache.size > 0 && (this.rangeCacheBytes + bytes.length > this.rangeCacheMaxBytes || this.rangeCache.size >= 64)) {
          const oldest = this.rangeCache.keys().next().value;
          if (!oldest) break;
          const prev = this.rangeCache.get(oldest);
          if (prev) this.rangeCacheBytes -= prev.bytes.length;
          this.rangeCache.delete(oldest);
        }
        this.rangeCache.set(rangeCacheKey, {
          status: response.status,
          headers: [...outHeaders.entries()],
          bytes,
          used: this.now(),
          expires: this.now() + 600_000,
        });
        this.rangeCacheBytes += bytes.length;
      }
      return {
        status: response.status,
        headers: outHeaders,
        body: new ReadableStream({
          start(controller) {
            controller.enqueue(bytes);
            controller.close();
          },
        }),
      };
    }

    return { status: response.status, headers: outHeaders, body: decodedResponse.body };
  }
}
