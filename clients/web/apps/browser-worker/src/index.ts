import { confirmPage } from './confirmation.js';
import { getSourceUserAgent } from './user-agent.js';
import { interceptRequests, type ProtocolSession } from './interception.js';
import { createBrowserTunnel } from './browser-tunnel.js';
export { createGuardedContext, type GuardedPageContext, type GuardedContextOptions } from './guarded-context.js';
export { BrowserNetworkExecutor } from './network-executor.js';
export { fetchBrowserResource } from './resource-fetch.js';
import { randomUUID } from 'node:crypto';
import dns from 'node:dns/promises';
import { access } from 'node:fs/promises';
import { NetworkBroker, hostAllowed, isPrivateAddress, redirectRequest, validateNetworkUrl } from '@hentai-park/source-host';
import { toAbortError } from '@hentai-park/source-contract';
import type { PluginManifest, NetworkConfirmation } from '@hentai-park/source-contract';
import type { NetworkRequest, NetworkResponse } from '@hentai-park/source-host';

export interface ReverseSearchDescriptor {
  url: string;
  uploadUrl: string;
  fileField: string;
  resultPath: string;
  resultQuery: string;
  resultParams?: Record<string, string>;
  resultSelector?: string;
  emptySelector?: string;
  emptyText?: string;
}
export interface ReverseSearchImage {
  base64: string;
  mimeType: string;
}
export interface ReverseSearchPage {
  url: string;
  html: string;
}
export type WebVideoCommand = {
  action: 'state' | 'play' | 'pause' | 'seek' | 'rate' | 'click' | 'move' | 'key';
  position?: number;
  rate?: number;
  x?: number;
  y?: number;
  key?: string;
};
export interface WebVideoState {
  state: 'ready' | 'loading' | 'verification_required' | 'failed' | 'closed';
  paused: boolean;
  position: number;
  duration: number | null;
  rate: number;
  muted: boolean;
  hasAudio: boolean;
  viewport: { width: number; height: number };
}
export type BrowserTransport = (request: NetworkRequest, domains: string[]) => Promise<NetworkResponse>;
export interface BrowserDependencies {
  lookup?: typeof dns.lookup;
  transport?: BrowserTransport;
}
export type BrowserState =
  | 'idle'
  | 'navigating'
  | 'verification_required'
  | 'ready'
  | 'cancelled'
  | 'closed'
  | 'failed';
export interface BrowserManifest {
  domains: string[];
  navigationDomains?: string[];
  frameDomains?: string[];
  mediaDomains?: string[];
  imageNetworkDomains?: string[];
  sessionMedia?: boolean;
}
export interface BrowserResult {
  url: string;
  title?: string;
  text?: string;
  state: BrowserState;
  verification?: 'ready' | 'required';
}
export interface BrowserPage {
  goto(url: string, options?: { waitUntil?: string; timeout?: number }): Promise<unknown>;
  title(): Promise<string>;
  textContent(selector: string): Promise<string | null>;
  setInputFiles(selector: string, file: string | string[]): Promise<void>;
  url(): string;
  close(): Promise<void>;
  uploadImage?(input: { uploadUrl: string; fileField: string; image: ReverseSearchImage }): Promise<void>;
  waitResultUrl?(path: string, query: string): Promise<void>;
  waitReverseSearchResult?(
    condition: Pick<ReverseSearchDescriptor, 'resultSelector' | 'emptySelector' | 'emptyText'>,
  ): Promise<void>;
  readHtml?(): Promise<string>;
  confirmation?(
    declaration: NetworkConfirmation,
    act: boolean,
  ): Promise<{ gate: boolean; ready: boolean; acted: boolean; navigated?: boolean }>;
  webPlayback?(command: WebVideoCommand): Promise<WebVideoState>;
  webFrame?(): Promise<Buffer>;
  webAudio?(action: 'start' | 'read' | 'stop'): Promise<{ chunks: string[]; active: boolean }>;
}
export interface BrowserRoute {
  request(): {
    url(): string;
    resourceType(): string;
    isNavigationRequest(): boolean;
    frame(): {
      parentFrame(): unknown;
      url(): string;
    };
    headers(): Record<string, string>;
    allHeaders(): Promise<Record<string, string>>;
    method(): string;
    postData(): string | null;
    postDataBuffer(): Buffer | null;
    redirectCount?(): number;
    redirectedFrom?(): {
      url(): string;
      method(): string;
      postDataBuffer(): Buffer | null;
      response(): Promise<{ status(): number } | null>;
    } | null;
  };
  continueRequest?(headers: Record<string, string>): Promise<void>;
  abort(reason?: string): Promise<void>;
  fulfill(response: { status: number; headers: Record<string, string>; body: Buffer }): Promise<void>;
}
export interface BrowserCookie {
  name: string;
  value: string;
  domain: string;
  path: string;
  expires: number;
  httpOnly: boolean;
  secure: boolean;
  sameSite?: 'Strict' | 'Lax' | 'None';
}
export interface BrowserContext {
  newPage(): Promise<BrowserPage>;
  close(): Promise<void>;
  route?(pattern: string, handler: (route: BrowserRoute) => Promise<void>): Promise<void>;
  cookies?(): Promise<BrowserCookie[]>;
  addCookies?(cookies: BrowserCookie[]): Promise<void>;
  approveTunnel?(target: URL, addresses: Array<{ address: string; family: number }>): void;
}
export type BrowserFactory = () => Promise<BrowserContext>;
export class BrowserWorkerError extends Error {
  constructor(
    readonly code: 'BLOCKED' | 'CANCELLED' | 'TIMEOUT' | 'BROWSER_ERROR' | 'VERIFICATION_REQUIRED' | 'ENVIRONMENT',
    message: string,
  ) {
    super(message);
    this.name = 'BrowserWorkerError';
  }
}

function browserAbortError(signal: AbortSignal) {
  const error = toAbortError(signal);
  return Object.assign(new BrowserWorkerError(error.code === 'TIMEOUT' ? 'TIMEOUT' : 'CANCELLED', error.message), {
    retryable: error.retryable,
    details: error.details,
  });
}

export async function checkUrl(raw: string, domains: string[] | undefined, lookup: typeof dns.lookup = dns.lookup) {
  try {
    const { target } = await validateNetworkUrl(raw, domains, lookup);
    return target;
  } catch (error) {
    const code = error && typeof error === 'object' && 'code' in error ? String(error.code) : 'BLOCKED';
    throw new BrowserWorkerError(code === 'BLOCKED' ? 'BLOCKED' : 'BLOCKED', error instanceof Error ? error.message : 'blocked URL');
  }
}

export async function checkUrlWithAddresses(raw: string, domains: string[] | undefined, lookup: typeof dns.lookup = dns.lookup) {
  try {
    return await validateNetworkUrl(raw, domains, lookup);
  } catch (error) {
    throw new BrowserWorkerError('BLOCKED', error instanceof Error ? error.message : 'blocked URL');
  }
}

export function parseVerificationResult(value: unknown): { state: 'ready' | 'required'; text?: string } {
  if (typeof value === 'string') return value.trim() ? { state: 'ready', text: value } : { state: 'required' };
  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    const text = typeof record.text === 'string' ? record.text : undefined;
    if (record.verified === true || record.state === 'ready') return { state: 'ready', text };
  }
  return { state: 'required' };
}

export class BrowserSession {
  state: BrowserState = 'idle';
  readonly id = randomUUID();
  private context?: BrowserContext;
  private page?: BrowserPage;
  private reverseSearchActive = false;
  private webVideoActive = false;
  private confirmationActive = false;
  private requests = new Set<AbortController>();
  private opening?: Promise<BrowserPage>;
  private releasing?: Promise<void>;
  private closing?: Promise<void>;

  constructor(
    private readonly manifest: BrowserManifest,
    private readonly factory: BrowserFactory,
    private readonly lookup: typeof dns.lookup = dns.lookup,
    private readonly transport?: BrowserTransport,
  ) {}

  private signal(signal?: AbortSignal) {
    if (this.state === 'closed') throw new BrowserWorkerError('BROWSER_ERROR', 'browser session is closed');
    if (signal?.aborted) throw browserAbortError(signal);
  }

  private async operation<T>(action: () => Promise<T>, signal?: AbortSignal, timeoutMs = 30000): Promise<T> {
    this.signal(signal);
    let timer: ReturnType<typeof setTimeout> | undefined;
    let abort: () => void = () => {};
    const interruption = new Promise<never>((_, reject) => {
      abort = () => {
        void this.releaseAfterFailure();
        reject(browserAbortError(signal!));
      };
      signal?.addEventListener('abort', abort, { once: true });
      timer = setTimeout(() => {
        void this.releaseAfterFailure();
        reject(new BrowserWorkerError('TIMEOUT', 'browser operation timed out'));
      }, timeoutMs);
    });
    try {
      return await Promise.race([action(), interruption]);
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
    }
  }

  private async ensurePage() {
    this.signal();
    if (this.page) return this.page;
    if (!this.opening) {
      this.opening = this.initializePage().finally(() => {
        this.opening = undefined;
      });
    }
    return this.opening;
  }

  private async initializePage() {
    if (!this.context) {
      const context = await this.factory();
      if (this.state === 'closed' || this.state === 'cancelled') {
        await context.close();
        throw new BrowserWorkerError('CANCELLED', 'browser operation cancelled');
      }
      this.context = context;
      if (!context.route) {
        await this.releaseAfterFailure();
        throw new BrowserWorkerError('ENVIRONMENT', 'browser request interception is unavailable');
      }
      await context.route('**/*', async (route) => {
        const request = route.request();
        const controller = new AbortController();
        this.requests.add(controller);
        let challenge = false;
        try {
          const host = new URL(request.url()).hostname;
          const frame = request.frame();
          challenge =
            (this.webVideoActive || this.confirmationActive || this.reverseSearchActive) &&
            host === 'challenges.cloudflare.com' &&
            Boolean(frame.parentFrame()) &&
            (request.isNavigationRequest() || new URL(frame.url()).hostname === 'challenges.cloudflare.com');
        } catch {}

        try {
          const publicMedia =
            this.webVideoActive &&
            this.manifest.sessionMedia &&
            !request.isNavigationRequest() &&
            ['media', 'image', 'xhr', 'fetch'].includes(request.resourceType());

          // Allow public HTTPS static subresources (script/stylesheet/font/image, e.g. gstatic.com for Google Lens)
          // when backed by real Chromium browser tunnel while keeping strict main-frame/iframe domain isolation!
          const tunnelBacked = Boolean(context.approveTunnel) && !this.transport;
          const staticSubresource =
            tunnelBacked &&
            !request.isNavigationRequest() &&
            ['script', 'stylesheet', 'font', 'image'].includes(request.resourceType());

          const domains =
            publicMedia || staticSubresource
              ? undefined
              : challenge
                ? ['challenges.cloudflare.com']
                : this.reverseSearchActive
                  ? this.manifest.domains
                  : request.isNavigationRequest()
                    ? request.frame().parentFrame()
                      ? [...this.manifest.domains, ...(this.manifest.navigationDomains ?? []), ...(this.manifest.frameDomains ?? [])]
                      : (this.manifest.navigationDomains ?? this.manifest.domains)
                    : [
                        ...this.manifest.domains,
                        ...(this.manifest.navigationDomains ?? []),
                        ...(this.manifest.frameDomains ?? []),
                        ...(this.manifest.mediaDomains ?? []),
                        ...(this.manifest.imageNetworkDomains ?? []),
                      ];

          const pinned = await checkUrlWithAddresses(request.url(), domains, this.lookup);
          const body = request.postDataBuffer();
          let headers = await request.allHeaders();
          let redirectedBody = body;
          if ((request.redirectCount?.() ?? 0) > 5) throw new BrowserWorkerError('BLOCKED', 'redirect limit exceeded');

          const previous = request.redirectedFrom?.();
          if (previous) {
            const response = await previous.response();
            if (response) {
              const redirected = redirectRequest(
                {
                  url: previous.url(),
                  method: previous.method(),
                  headers,
                  bodyBase64: previous.postDataBuffer()?.toString('base64'),
                  followRedirects: true,
                },
                new URL(previous.url()),
                new URL(request.url()),
                response.status(),
              );
              if (redirected.method !== request.method()) throw new BrowserWorkerError('BLOCKED', 'redirect method mismatch');
              headers = redirected.headers ?? {};
              redirectedBody = redirected.bodyBase64 === undefined ? null : Buffer.from(redirected.bodyBase64, 'base64');
            }
          }

          // Real Chromium TLS/HTTP2 tunnel path (preserves cookies, Turnstile, and streaming media natively!)
          if (tunnelBacked && route.continueRequest) {
            context.approveTunnel!(pinned.target, pinned.addresses);
            await route.continueRequest(headers);
            return;
          }

          let mediaWindow: { start: number; end: number } | undefined;
          if (this.webVideoActive && request.resourceType() === 'media' && request.method() === 'GET') {
            const entry = Object.entries(headers).find(([name]) => name.toLowerCase() === 'range');
            if (entry) {
              const match = /^bytes=(\d+)-(\d*)$/i.exec(entry[1]);
              if (!match) throw new BrowserWorkerError('BLOCKED', 'unsupported media Range');
              const start = Number(match[1]);
              const requestedEnd = match[2] ? Number(match[2]) : Number.MAX_SAFE_INTEGER;
              if (!Number.isSafeInteger(start) || !Number.isSafeInteger(requestedEnd) || start < 0 || requestedEnd < start) {
                throw new BrowserWorkerError('BLOCKED', 'invalid media Range');
              }
              const end = Math.min(requestedEnd, start + 8 * 1024 * 1024 - 1);
              delete headers[entry[0]];
              headers.range = `bytes=${start}-${end}`;
              mediaWindow = { start, end };
            }
          }

          const effectiveDomains = domains ?? [pinned.target.hostname];
          const input: NetworkRequest = {
            url: request.url(),
            method: request.method(),
            headers,
            bodyBase64: redirectedBody?.toString('base64'),
            responseType: 'base64',
            followRedirects: false,
            signal: controller.signal,
          };
          const result = this.transport
            ? await this.transport(input, effectiveDomains)
            : await new NetworkBroker({ domains: effectiveDomains } as PluginManifest).request(input);
          const bytes = Buffer.from(result.body, 'base64');
          if (mediaWindow) {
            if (bytes.length > 8 * 1024 * 1024) throw new BrowserWorkerError('BROWSER_ERROR', 'upstream ignored bounded media Range');
            if (result.status === 206) {
              const range = Object.entries(result.headers).find(([name]) => name.toLowerCase() === 'content-range')?.[1];
              const match = range && /^bytes (\d+)-(\d+)\/(\d+)$/.exec(range);
              if (
                !match ||
                Number(match[1]) !== mediaWindow.start ||
                Number(match[2]) > mediaWindow.end ||
                Number(match[2]) < mediaWindow.start ||
                !Number.isSafeInteger(Number(match[3])) ||
                Number(match[3]) <= Number(match[2]) ||
                bytes.length !== Number(match[2]) - mediaWindow.start + 1
              ) {
                throw new BrowserWorkerError('BROWSER_ERROR', 'invalid bounded media response');
              }
            }
          }
          await route.fulfill({ status: result.status, headers: result.headers, body: bytes });
        } catch {
          await route.abort('blockedbyclient').catch(() => {});
        } finally {
          this.requests.delete(controller);
        }
      });
    }
    this.page ??= await this.context.newPage();
    return this.page;
  }

  private async releaseAfterFailure() {
    if (this.releasing) return this.releasing;
    for (const controller of this.requests) controller.abort();
    this.requests.clear();
    const context = this.context;
    this.page = undefined;
    this.context = undefined;
    this.releasing = (async () => {
      try {
        await context?.close();
      } catch {}
    })();
    try {
      await this.releasing;
    } finally {
      this.releasing = undefined;
    }
  }

  async navigate(rawUrl: string, signal?: AbortSignal): Promise<BrowserResult> {
    this.signal(signal);
    const domains = this.manifest.navigationDomains ?? this.manifest.domains;
    const url = await checkUrl(rawUrl, domains, this.lookup);
    this.state = 'navigating';
    const onAbort = () => {
      void this.close();
    };
    signal?.addEventListener('abort', onAbort, { once: true });
    try {
      const page = await this.ensurePage();
      const response = await page.goto(url.toString(), { waitUntil: 'domcontentloaded', timeout: 25000 });
      if (response && typeof response === 'object' && 'status' in response && typeof response.status === 'function') {
        const status = response.status();
        if (status >= 400 && !((this.webVideoActive || this.confirmationActive) && (status === 401 || status === 403))) {
          throw new BrowserWorkerError(
            status === 401 || status === 403 ? 'VERIFICATION_REQUIRED' : 'BROWSER_ERROR',
            'upstream browser navigation failed',
          );
        }
      }
      this.signal(signal);
      const finalUrl = await checkUrl(page.url(), domains, this.lookup);
      this.state =
        response &&
        typeof response === 'object' &&
        'status' in response &&
        typeof response.status === 'function' &&
        [401, 403].includes(response.status())
          ? 'verification_required'
          : 'ready';
      return { url: finalUrl.toString(), title: await page.title(), state: this.state };
    } catch (error) {
      if (signal?.aborted) {
        this.state = 'cancelled';
        await this.releaseAfterFailure();
        throw browserAbortError(signal);
      }
      this.state = 'failed';
      await this.releaseAfterFailure();
      if (error instanceof BrowserWorkerError) throw error;
      if (error instanceof Error && /timeout/i.test(error.message)) {
        throw new BrowserWorkerError('TIMEOUT', 'browser navigation timed out');
      }
      throw new BrowserWorkerError('BROWSER_ERROR', 'browser navigation failed');
    } finally {
      signal?.removeEventListener('abort', onAbort);
    }
  }

  async upload(rawUrl: string, selector: string, file: string, signal?: AbortSignal): Promise<BrowserResult> {
    this.signal(signal);
    if (!selector || selector.length > 256 || /[\r\n]/.test(selector) || !file || file.length > 4096) {
      throw new BrowserWorkerError('BLOCKED', 'invalid upload input');
    }
    await this.navigate(rawUrl, signal);
    try {
      await this.operation(() => this.page!.setInputFiles(selector, file), signal);
      return {
        url: (await checkUrl(this.page!.url(), this.manifest.navigationDomains ?? this.manifest.domains, this.lookup)).toString(),
        state: this.state,
      };
    } catch (error) {
      await this.releaseAfterFailure();
      throw error instanceof BrowserWorkerError ? error : new BrowserWorkerError('BROWSER_ERROR', 'browser upload failed');
    }
  }

  async readText(selector = 'body', signal?: AbortSignal): Promise<BrowserResult> {
    this.signal(signal);
    if (!selector || selector.length > 256 || /[\r\n]/.test(selector)) {
      throw new BrowserWorkerError('BLOCKED', 'invalid text selector');
    }
    if (!this.page) throw new BrowserWorkerError('BROWSER_ERROR', 'browser page is not ready');
    const text = await this.operation(() => this.page!.textContent(selector), signal);
    const url = await checkUrl(this.page!.url(), this.manifest.navigationDomains ?? this.manifest.domains, this.lookup);
    return { url: url.toString(), text: text ?? '', state: this.state };
  }

  async verify(rawUrl: string, readySelector: string, signal?: AbortSignal): Promise<BrowserResult> {
    this.signal(signal);
    if (!readySelector || readySelector.length > 256 || /[\r\n]/.test(readySelector)) {
      throw new BrowserWorkerError('BLOCKED', 'invalid verification selector');
    }
    const result = await this.navigate(rawUrl, signal);
    try {
      const parsed = parseVerificationResult(await this.operation(() => this.page!.textContent(readySelector), signal));
      this.signal(signal);
      if (parsed.state !== 'ready') {
        this.state = 'verification_required';
        throw new BrowserWorkerError('VERIFICATION_REQUIRED', 'verification is required');
      }
      return { ...result, text: parsed.text, verification: parsed.state };
    } catch (error) {
      await this.releaseAfterFailure();
      throw error;
    }
  }

  async confirmation(rawUrl: string, declaration: NetworkConfirmation, signal?: AbortSignal): Promise<BrowserResult> {
    const selectors = [
      declaration?.selector,
      declaration?.readySelector,
      declaration?.auto?.clickSelector,
      declaration?.auto?.checkSelector,
      ...Object.values(declaration?.auto?.birthDate ?? {}),
    ];
    if (
      !declaration?.selector ||
      selectors.some((value) => value !== undefined && (typeof value !== 'string' || !value || value.length > 1024 || /[\r\n]/.test(value)))
    ) {
      throw new BrowserWorkerError('BLOCKED', 'invalid confirmation declaration');
    }
    this.confirmationActive = true;
    try {
      return await this.operation(
        async () => {
          const result = await this.navigate(rawUrl, signal);
          if (!this.page?.confirmation) throw new BrowserWorkerError('ENVIRONMENT', 'browser confirmation is unavailable');
          let attempted = false;
          const deadline = Date.now() + 25000;
          while (Date.now() < deadline) {
            this.signal(signal);
            const state = await this.page.confirmation(declaration, !attempted);
            if (!state || typeof state.gate !== 'boolean' || typeof state.ready !== 'boolean' || typeof state.acted !== 'boolean') {
              throw new BrowserWorkerError('BROWSER_ERROR', 'invalid confirmation result');
            }
            if (!state.gate && state.ready) {
              this.state = 'ready';
              return {
                ...result,
                url: (await checkUrl(this.page.url(), this.manifest.navigationDomains ?? this.manifest.domains, this.lookup)).href,
                state: this.state,
                verification: 'ready',
              };
            }
            if ((state.gate && !declaration.auto) || (state.gate && !attempted && !state.acted)) {
              throw new BrowserWorkerError('VERIFICATION_REQUIRED', 'declared confirmation requires interaction');
            }
            attempted = state.navigated ? false : attempted || state.acted;
            await new Promise((resolve) => setTimeout(resolve, 100));
          }
          throw new BrowserWorkerError('VERIFICATION_REQUIRED', 'declared confirmation was not satisfied');
        },
        signal,
        30000,
      );
    } catch (error) {
      await this.releaseAfterFailure();
      throw error;
    } finally {
      this.confirmationActive = false;
    }
  }

  async cookies(): Promise<BrowserCookie[]> {
    if (this.webVideoActive) throw new BrowserWorkerError('BLOCKED', 'web player Cookie export is forbidden');
    if (!this.context?.cookies) throw new BrowserWorkerError('ENVIRONMENT', 'browser cookie extraction is unavailable');
    return (await this.context.cookies()).filter((cookie) =>
      hostAllowed(cookie.domain.replace(/^\./, ''), this.manifest.domains),
    );
  }

  async setCookies(cookies: BrowserCookie[]) {
    if (this.webVideoActive) throw new BrowserWorkerError('BLOCKED', 'web player Cookie import is forbidden');
    await this.ensurePage();
    if (!this.context?.addCookies) throw new BrowserWorkerError('ENVIRONMENT', 'browser Cookie import is unavailable');
    if (
      !Array.isArray(cookies) ||
      cookies.length > 1000 ||
      cookies.some((cookie) => !cookie || typeof cookie.domain !== 'string' || !hostAllowed(cookie.domain.replace(/^\./, ''), this.manifest.domains))
    ) {
      throw new BrowserWorkerError('BLOCKED', 'Cookie is outside source domains');
    }
    await this.context.addCookies(cookies);
  }

  async reverseSearch(
    descriptor: ReverseSearchDescriptor,
    image: ReverseSearchImage,
    signal?: AbortSignal,
  ): Promise<ReverseSearchPage> {
    this.signal(signal);
    const text = (value: unknown, max: number) =>
      typeof value === 'string' && value.length > 0 && value.length <= max && !/[\u0000-\u001f\u007f]/.test(value);
    if (
      !descriptor ||
      !text(descriptor.fileField, 128) ||
      !/^[A-Za-z_][A-Za-z0-9_.-]*$/.test(descriptor.fileField) ||
      !text(descriptor.resultPath, 2048) ||
      !descriptor.resultPath.startsWith('/') ||
      descriptor.resultPath.startsWith('//') ||
      /[?#\\]/.test(descriptor.resultPath) ||
      !text(descriptor.resultQuery, 128) ||
      !/^[A-Za-z_][A-Za-z0-9_.-]*$/.test(descriptor.resultQuery)
    ) {
      throw new BrowserWorkerError('BLOCKED', 'invalid reverse search descriptor');
    }
    for (const value of [descriptor.resultSelector, descriptor.emptySelector]) {
      if (value !== undefined && !text(value, 1024)) throw new BrowserWorkerError('BLOCKED', 'invalid reverse search selector');
    }
    if (
      (descriptor.emptyText !== undefined && !text(descriptor.emptyText, 256)) ||
      Boolean(descriptor.emptySelector) !== Boolean(descriptor.emptyText) ||
      (!descriptor.resultSelector && !descriptor.emptySelector)
    ) {
      throw new BrowserWorkerError('BLOCKED', 'reverse search readiness conditions are invalid');
    }
    if (
      descriptor.resultParams !== undefined &&
      (!descriptor.resultParams ||
        typeof descriptor.resultParams !== 'object' ||
        Array.isArray(descriptor.resultParams) ||
        Object.entries(descriptor.resultParams).length > 8 ||
        Object.entries(descriptor.resultParams).some(
          ([key, value]) =>
            !text(key, 128) || key === descriptor.resultQuery || typeof value !== 'string' || value.length > 256 || /[\u0000-\u001f\u007f]/.test(value),
        ))
    ) {
      throw new BrowserWorkerError('BLOCKED', 'reverse search result parameters are invalid');
    }
    if (
      !image ||
      !['image/png', 'image/jpeg', 'image/webp', 'image/gif'].includes(image.mimeType) ||
      typeof image.base64 !== 'string' ||
      image.base64.length > 12000000 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(image.base64)
    ) {
      throw new BrowserWorkerError('BLOCKED', 'reverse search image is invalid');
    }
    const bytes = Buffer.from(image.base64, 'base64');
    if (!bytes.length || bytes.length > 8 * 1024 * 1024 || bytes.toString('base64') !== image.base64) {
      throw new BrowserWorkerError('BLOCKED', 'reverse search image exceeds limit');
    }
    await checkUrl(descriptor.url, this.manifest.domains, this.lookup);
    await checkUrl(descriptor.uploadUrl, this.manifest.domains, this.lookup);
    this.reverseSearchActive = true;
    try {
      return await this.operation(
        async () => {
          await this.navigate(descriptor.url, signal);
          const page = this.page!;
          if (!page.uploadImage || !page.waitResultUrl || !page.waitReverseSearchResult || !page.readHtml) {
            throw new BrowserWorkerError('ENVIRONMENT', 'browser reverse search operations are unavailable');
          }
          await page.uploadImage({ uploadUrl: descriptor.uploadUrl, fileField: descriptor.fileField, image });
          await page.waitResultUrl(descriptor.resultPath, descriptor.resultQuery);
          let result = await checkUrl(page.url(), this.manifest.domains, this.lookup);
          if (result.pathname !== descriptor.resultPath || !result.searchParams.get(descriptor.resultQuery)?.trim()) {
            throw new BrowserWorkerError('BROWSER_ERROR', 'reverse search result URL does not match');
          }
          const merged = new URL(result);
          for (const [key, value] of Object.entries(descriptor.resultParams ?? {})) merged.searchParams.set(key, value);
          if (merged.href !== result.href) {
            await this.navigate(merged.href, signal);
            result = await checkUrl(page.url(), this.manifest.domains, this.lookup);
          }
          if (
            result.pathname !== descriptor.resultPath ||
            !result.searchParams.get(descriptor.resultQuery)?.trim() ||
            Object.entries(descriptor.resultParams ?? {}).some(([key, value]) => result.searchParams.get(key) !== value)
          ) {
            throw new BrowserWorkerError('BROWSER_ERROR', 'reverse search result parameters were lost');
          }
          await page.waitReverseSearchResult(descriptor);
          const html = await page.readHtml();
          if (Buffer.byteLength(html, 'utf8') > 4 * 1024 * 1024) {
            throw new BrowserWorkerError('BROWSER_ERROR', 'reverse search HTML exceeds limit');
          }
          const finalUrl = await checkUrl(page.url(), this.manifest.domains, this.lookup);
          if (
            finalUrl.pathname !== descriptor.resultPath ||
            !finalUrl.searchParams.get(descriptor.resultQuery)?.trim() ||
            finalUrl.searchParams.get(descriptor.resultQuery) !== result.searchParams.get(descriptor.resultQuery) ||
            Object.entries(descriptor.resultParams ?? {}).some(([key, value]) => finalUrl.searchParams.get(key) !== value)
          ) {
            throw new BrowserWorkerError('BROWSER_ERROR', 'reverse search result changed during read');
          }
          return { url: finalUrl.href, html };
        },
        signal,
        40000,
      );
    } catch (error) {
      this.state = signal?.aborted ? 'cancelled' : 'failed';
      await this.releaseAfterFailure();
      if (error instanceof BrowserWorkerError) throw error;
      throw new BrowserWorkerError('BROWSER_ERROR', 'browser reverse search failed');
    }
  }

  async webVideo(rawUrl: string, signal?: AbortSignal): Promise<BrowserResult> {
    if (!this.webVideoActive) {
      await this.opening?.catch(() => {});
      await this.releaseAfterFailure();
    }
    this.webVideoActive = true;
    return this.navigate(rawUrl, signal);
  }

  async webPlayback(command: WebVideoCommand = { action: 'state' }, signal?: AbortSignal): Promise<WebVideoState> {
    if (!this.webVideoActive || !this.page?.webPlayback) {
      throw new BrowserWorkerError('BROWSER_ERROR', 'web player is not open');
    }
    if (
      !['state', 'play', 'pause', 'seek', 'rate', 'click', 'move', 'key'].includes(command.action) ||
      (command.action === 'seek' && (!Number.isFinite(command.position) || command.position! < 0)) ||
      (command.action === 'rate' && (!Number.isFinite(command.rate) || command.rate! < 0.25 || command.rate! > 4)) ||
      (['click', 'move'].includes(command.action) &&
        (!Number.isFinite(command.x) || !Number.isFinite(command.y) || command.x! < 0 || command.y! < 0 || command.x! > 1280 || command.y! > 720)) ||
      (command.action === 'key' &&
        !['Space', 'Enter', 'Escape', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'KeyK', 'KeyM', 'KeyF'].includes(command.key ?? ''))
    ) {
      throw new BrowserWorkerError('BLOCKED', 'unsupported web player command');
    }
    const value = await this.operation(() => this.page!.webPlayback!(command), signal);
    if (
      !value ||
      !['ready', 'loading', 'verification_required', 'failed', 'closed'].includes(value.state) ||
      typeof value.paused !== 'boolean' ||
      typeof value.muted !== 'boolean' ||
      typeof value.hasAudio !== 'boolean' ||
      !Number.isFinite(value.position) ||
      value.position < 0 ||
      value.position > 315360000 ||
      (value.duration !== null && (!Number.isFinite(value.duration) || value.duration < 0 || value.duration > 315360000)) ||
      !Number.isFinite(value.rate) ||
      value.rate < 0.0625 ||
      value.rate > 16
    ) {
      throw new BrowserWorkerError('BROWSER_ERROR', 'invalid web player state');
    }
    return {
      state: value.state === 'loading' && this.state === 'verification_required' ? 'verification_required' : value.state,
      paused: value.paused,
      position: value.position,
      duration: value.duration,
      rate: value.rate,
      muted: value.muted,
      hasAudio: value.hasAudio,
      viewport: value.viewport ?? { width: 960, height: 540 },
    };
  }

  async webFrame(signal?: AbortSignal) {
    if (!this.webVideoActive || !this.page?.webFrame) throw new BrowserWorkerError('BROWSER_ERROR', 'web player is not open');
    return this.operation(() => this.page!.webFrame!(), signal);
  }

  async webAudio(action: 'start' | 'read' | 'stop', signal?: AbortSignal) {
    if (!this.webVideoActive || !this.page?.webAudio) throw new BrowserWorkerError('BROWSER_ERROR', 'web player is not open');
    return this.operation(() => this.page!.webAudio!(action), signal);
  }

  async close() {
    if (this.closing) return this.closing;
    this.state = 'closed';
    for (const controller of this.requests) controller.abort();
    this.closing = (async () => {
      await this.opening?.catch(() => {});
      await this.releaseAfterFailure();
    })();
    await this.closing;
  }
}

export class BrowserWorker {
  private readonly sessions = new Map<string, BrowserSession>();
  constructor(
    private readonly factory: BrowserFactory,
    private readonly maxSessions = 24,
    private readonly dependencies: BrowserDependencies = {},
  ) {}
  create(manifest: BrowserManifest) {
    if (this.sessions.size >= this.maxSessions) {
      throw new BrowserWorkerError('BROWSER_ERROR', 'browser session limit reached');
    }
    const session = new BrowserSession(manifest, this.factory, this.dependencies.lookup, this.dependencies.transport);
    this.sessions.set(session.id, session);
    return session.id;
  }
  get(id: string) {
    const session = this.sessions.get(id);
    if (!session) throw new BrowserWorkerError('BROWSER_ERROR', 'browser session not found');
    return session;
  }
  async reverseSearch(
    id: string,
    descriptor: ReverseSearchDescriptor,
    image: ReverseSearchImage,
    signal?: AbortSignal,
  ) {
    return this.get(id).reverseSearch(descriptor, image, signal);
  }
  async cancel(id: string) {
    const session = this.sessions.get(id);
    if (!session) return;
    this.sessions.delete(id);
    await session.close();
  }
  async restart() {
    await this.close();
  }
  async close() {
    await Promise.all([...this.sessions.values()].map((s) => s.close()));
    this.sessions.clear();
  }
  size() {
    return this.sessions.size;
  }
}

export interface PlaywrightOptions {
  executablePath?: string;
  headless?: boolean;
}
export interface PlaywrightEnvironment {
  executablePath: string;
  packageVersion?: string;
}

interface PlaywrightPage extends BrowserPage, Pick<import('playwright').Page, 'evaluateHandle' | 'waitForLoadState'> {
  route?: (url: string, handler: (route: unknown) => unknown) => Promise<void>;
  evaluate<R, A>(code: (argument: A) => R | Promise<R>, argument: A): Promise<R>;
  waitForURL(predicate: (url: URL) => boolean, options: { timeout: number; waitUntil?: string }): Promise<void>;
  setInputFiles(
    selector: string,
    file: string | string[] | { name: string; mimeType: string; buffer: Buffer },
  ): Promise<void>;
  frames(): PlaywrightFrame[];
  isClosed(): boolean;
  screenshot(options: { type: 'jpeg'; quality: number; timeout: number }): Promise<Buffer>;
  mouse: { click(x: number, y: number): Promise<void>; move(x: number, y: number): Promise<void> };
  keyboard: { press(key: string): Promise<void> };
}
interface PlaywrightFrame {
  evaluate<R, A>(code: (argument: A) => R | Promise<R>, argument: A): Promise<R>;
}
interface PlaywrightContext {
  newCDPSession(page: PlaywrightPage): Promise<ProtocolSession>;
  newPage(): Promise<PlaywrightPage>;
  close(): Promise<void>;
  cookies(urls?: string[]): Promise<BrowserCookie[]>;
  addCookies(cookies: BrowserCookie[]): Promise<void>;
  addInitScript(script: string): Promise<void>;
  route(pattern: string, handler: (route: BrowserRoute) => Promise<void>): Promise<void>;
  routeWebSocket(pattern: string, handler: (socket: { close(): void }) => void): Promise<void>;
  on(event: 'page', handler: (page: PlaywrightPage) => void): void;
}
interface PlaywrightBrowser {
  newContext(options?: unknown): Promise<PlaywrightContext>;
  close(): Promise<void>;
  on(event: 'disconnected', handler: () => void): void;
}
interface PlaywrightModule {
  chromium: {
    executablePath(): string;
    launch(options?: unknown): Promise<PlaywrightBrowser>;
  };
  version?: string;
}

export async function checkPlaywrightEnvironment(options: PlaywrightOptions = {}): Promise<PlaywrightEnvironment> {
  let playwright: PlaywrightModule;
  try {
    const importer = Function('return import("playwright")') as () => Promise<PlaywrightModule>;
    playwright = await importer();
  } catch {
    throw new BrowserWorkerError('ENVIRONMENT', 'Playwright package is unavailable');
  }
  const executablePath = options.executablePath ?? playwright.chromium.executablePath();
  if (!executablePath) throw new BrowserWorkerError('ENVIRONMENT', 'Playwright browser executable is not configured');
  try {
    await access(executablePath);
  } catch {
    throw new BrowserWorkerError('ENVIRONMENT', 'Playwright browser executable is missing');
  }
  return { executablePath, packageVersion: playwright.version };
}

export async function playwrightFactory(options: PlaywrightOptions = {}): Promise<BrowserContext> {
  const environment = await checkPlaywrightEnvironment(options);
  let browser: PlaywrightBrowser | undefined;
  let tunnel: Awaited<ReturnType<typeof createBrowserTunnel>> | undefined;
  try {
    const importer = Function('return import("playwright")') as () => Promise<PlaywrightModule>;
    const playwright = await importer();
    tunnel = await createBrowserTunnel();
    browser = await playwright.chromium.launch({
      headless: options.headless ?? true,
      executablePath: environment.executablePath,
      proxy: { server: tunnel.server, bypass: '<-loopback>' },
      args: [
        '--autoplay-policy=no-user-gesture-required',
        '--disable-blink-features=AutomationControlled',
        '--disable-quic',
        '--force-webrtc-ip-handling-policy=disable_non_proxied_udp',
        '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',
      ],
    });
    let disconnected = false;
    browser.on('disconnected', () => {
      disconnected = true;
    });
    const context = await browser.newContext({
      serviceWorkers: 'block',
      acceptDownloads: false,
      viewport: { width: 960, height: 540 },
      deviceScaleFactor: 1,
      userAgent: getSourceUserAgent(),
    });
    await context.addInitScript(`(() => {
      try {
        Object.defineProperty(navigator, 'webdriver', { get: () => false, configurable: true });
        if (!window.chrome) Object.defineProperty(window, 'chrome', { value: { runtime: {} }, configurable: true });
      } catch {}
    })();`);
    await context.routeWebSocket('**/*', (socket) => socket.close());
    const pages = new Set<PlaywrightPage>();
    let creatingPage = false;
    context.on('page', (page) => {
      if (!creatingPage) void page.close().catch(() => {});
    });
    let closed = false;
    let routeHandler: ((route: BrowserRoute) => Promise<void>) | undefined;

    return {
      approveTunnel: (target, addresses) => tunnel?.approve(target, addresses),
      route: async (_pattern, handler) => {
        routeHandler = handler;
      },
      cookies: () => context.cookies(),
      addCookies: (cookies) => context.addCookies(cookies),
      async newPage() {
        if (closed) throw new BrowserWorkerError('BROWSER_ERROR', 'browser context is closed');
        creatingPage = true;
        let page: PlaywrightPage;
        try {
          page = await context.newPage();
          pages.add(page);
          if (!routeHandler) throw new BrowserWorkerError('ENVIRONMENT', 'request interception is unavailable');
          await interceptRequests(await context.newCDPSession(page), routeHandler, (url) => context.cookies([url]));
        } finally {
          creatingPage = false;
        }
        const alive = () => {
          if (closed || disconnected || page.isClosed()) {
            throw new BrowserWorkerError('BROWSER_ERROR', 'browser playback process exited');
          }
        };
        const videoFrame = async () => {
          alive();
          for (const frame of page.frames().slice(0, 32)) {
            try {
              if (await frame.evaluate(() => Boolean(document.querySelector('video')), undefined)) return frame;
            } catch {
              alive();
            }
          }
          return undefined;
        };
        let audioFrame: PlaywrightFrame | undefined;
        return {
          goto: (url, opts) => page.goto(url, opts),
          title: () => page.title(),
          textContent: (selector) => page.textContent(selector),
          setInputFiles: (selector, file) => page.setInputFiles(selector, file),
          url: () => page.url(),
          close: () => page.close(),
          async uploadImage(input) {
            const id = 'hp-upload-' + randomUUID();
            await page.evaluate(
              ({ id, url, field }) => {
                const form = document.createElement('form');
                form.id = id;
                form.method = 'POST';
                form.enctype = 'multipart/form-data';
                form.action = url;
                form.target = '_self';
                const file = document.createElement('input');
                file.id = id + '-file';
                file.type = 'file';
                file.name = field;
                form.appendChild(file);
                (document.body ?? document.documentElement).appendChild(form);
              },
              { id, url: input.uploadUrl, field: input.fileField },
            );
            const extension: { [key: string]: string } = {
              'image/png': 'png',
              'image/jpeg': 'jpg',
              'image/gif': 'gif',
              'image/webp': 'webp',
            };
            await page.setInputFiles('#' + id + '-file', {
              name: 'query.' + extension[input.image.mimeType],
              mimeType: input.image.mimeType,
              buffer: Buffer.from(input.image.base64, 'base64'),
            });
            await page.evaluate((id) => {
              const form = document.getElementById(id);
              if (!(form instanceof HTMLFormElement)) throw Error('upload form disappeared');
              HTMLFormElement.prototype.submit.call(form);
            }, id);
          },
          waitResultUrl: (path, query) =>
            page.waitForURL((url) => url.pathname === path && Boolean(url.searchParams.get(query)?.trim()), {
              timeout: 25000,
              waitUntil: 'domcontentloaded',
            }),
          async waitReverseSearchResult(condition) {
            let previous = '';
            let stableSince = 0;
            const deadline = Date.now() + 25000;
            while (Date.now() < deadline) {
              const snapshot = await page.evaluate(({ resultSelector, emptySelector, emptyText }) => {
                if (resultSelector) {
                  const nodes = document.querySelectorAll(resultSelector);
                  const links = Array.from(nodes).filter(
                    (node) => node.tagName === 'A' && node.getAttribute('href')?.trim(),
                  );
                  if (links.length) {
                    return {
                      ready: true,
                      key: JSON.stringify({
                        kind: 'links',
                        count: links.length,
                        items: links.slice(0, 64).map((node) => [node.getAttribute('href'), node.textContent?.slice(0, 2048)]),
                      }),
                    };
                  }
                }
                if (emptySelector && emptyText) {
                  const empty = document.querySelector(emptySelector);
                  const text = empty?.textContent?.replace(/\s+/g, ' ').trim();
                  if (text?.includes(emptyText.replace(/\s+/g, ' ').trim())) {
                    return { ready: true, key: JSON.stringify({ kind: 'empty', text: text.slice(0, 4096) }) };
                  }
                }
                return { ready: false, key: '' };
              }, condition);
              if (snapshot.ready) {
                if (snapshot.key !== previous) {
                  previous = snapshot.key;
                  stableSince = Date.now();
                } else if (Date.now() - stableSince >= 500) {
                  return;
                }
              } else {
                previous = '';
                stableSince = 0;
              }
              await new Promise((resolve) => setTimeout(resolve, 100));
            }
            throw new BrowserWorkerError('TIMEOUT', 'reverse search results did not become stable');
          },
          async readHtml() {
            return page.evaluate(() => {
              if (!document.documentElement) throw Error('result document is missing');
              const html = '<!doctype html>' + document.documentElement.outerHTML;
              if (new TextEncoder().encode(html).byteLength > 4 * 1024 * 1024) throw Error('result document exceeds limit');
              return html;
            }, undefined);
          },
          async confirmation(declaration, act) {
            return confirmPage(page, declaration, act);
          },
          webFrame: () => {
            alive();
            return page.screenshot({ type: 'jpeg', quality: 82, timeout: 8000 });
          },
          async webPlayback(command) {
            alive();
            if (command.action === 'move') await page.mouse.move(command.x!, command.y!);
            if (command.action === 'click') await page.mouse.click(command.x!, command.y!);
            if (command.action === 'key') await page.keyboard.press(command.key!);
            const frame = await videoFrame();
            if (!frame) {
              return {
                state: 'loading',
                paused: true,
                position: 0,
                duration: null,
                rate: 1,
                muted: false,
                hasAudio: false,
                viewport: { width: 960, height: 540 },
              };
            }
            const state = await frame.evaluate(async (cmd) => {
              const video = document.querySelector('video')!;
              if (cmd.action === 'play') {
                video.muted = false;
                await video.play();
              }
              if (cmd.action === 'pause') video.pause();
              if (cmd.action === 'seek') {
                video.currentTime = Math.max(
                  0,
                  Math.min(cmd.position!, Number.isFinite(video.duration) ? video.duration : cmd.position!),
                );
              }
              if (cmd.action === 'rate') video.playbackRate = cmd.rate!;
              const extended = video as HTMLVideoElement & { webkitAudioDecodedByteCount?: number };
              return {
                state: video.error ? 'failed' : video.readyState >= 2 ? 'ready' : 'loading',
                paused: video.paused,
                position: Number.isFinite(video.currentTime) ? video.currentTime : 0,
                duration: Number.isFinite(video.duration) ? video.duration : null,
                rate: video.playbackRate,
                muted: video.muted,
                hasAudio: (extended.webkitAudioDecodedByteCount ?? 0) > 0,
              };
            }, command);
            return { ...state, state: state.state as WebVideoState['state'], viewport: { width: 960, height: 540 } };
          },
          async webAudio(action) {
            alive();
            if (action === 'start') {
              if (audioFrame) {
                await audioFrame
                  .evaluate(() => {
                    const state = (globalThis as unknown as { __hpWebAudio?: { recorder: MediaRecorder; stream: MediaStream } }).__hpWebAudio;
                    if (state) {
                      if (state.recorder.state !== 'inactive') state.recorder.stop();
                      state.stream.getTracks().forEach((track) => track.stop());
                    }
                  }, undefined)
                  .catch(() => {});
              }
              audioFrame = await videoFrame();
              if (!audioFrame) throw new BrowserWorkerError('BROWSER_ERROR', 'web page has no audio player');
              await audioFrame.evaluate(() => {
                const video = document.querySelector('video') as HTMLVideoElement & { captureStream?: () => MediaStream };
                if (!video?.captureStream || !MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) {
                  throw Error('web page audio capture is unavailable');
                }
                const source = video.captureStream();
                const tracks = source.getAudioTracks().map((track) => track.clone());
                source.getTracks().forEach((track) => track.stop());
                if (!tracks.length) throw Error('web page has no accessible audio track');
                const stream = new MediaStream(tracks);
                const recorder = new MediaRecorder(stream, { mimeType: 'audio/webm;codecs=opus', audioBitsPerSecond: 96000 });
                const state = { recorder, stream, chunks: [] as string[], error: false };
                (globalThis as unknown as { __hpWebAudio: typeof state }).__hpWebAudio = state;
                recorder.ondataavailable = (event) => {
                  void event.data.arrayBuffer().then((buffer) => {
                    if (!buffer.byteLength) return;
                    const bytes = new Uint8Array(buffer);
                    let binary = '';
                    for (let i = 0; i < bytes.length; i += 8192) {
                      binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
                    }
                    if (state.chunks.length >= 128) state.chunks.shift();
                    state.chunks.push(btoa(binary));
                  });
                };
                recorder.start(80);
              }, undefined);
              return { chunks: [], active: true };
            }
            if (!audioFrame) return { chunks: [], active: false };
            return audioFrame.evaluate((act) => {
              const holder = globalThis as unknown as {
                __hpWebAudio?: { recorder: MediaRecorder; stream: MediaStream; chunks: string[]; error: boolean };
              };
              const state = holder.__hpWebAudio;
              if (!state) return { chunks: [], active: false };
              if (act === 'stop') {
                if (state.recorder.state !== 'inactive') state.recorder.stop();
                state.stream.getTracks().forEach((track) => track.stop());
                delete holder.__hpWebAudio;
                return { chunks: [], active: false };
              }
              const chunks = state.chunks.splice(0);
              return { chunks, active: state.recorder.state !== 'inactive' };
            }, action);
          },
        };
      },
      async close() {
        if (closed) return;
        closed = true;
        let firstError: unknown;
        await Promise.all(
          [...pages].map(async (page) => {
            try {
              await page.close();
            } catch (error) {
              firstError ??= error;
            }
          }),
        );
        try {
          await context.close();
        } catch (error) {
          firstError ??= error;
        }
        try {
          await browser?.close();
        } catch (error) {
          firstError ??= error;
        }
        try {
          await tunnel?.close();
        } catch (error) {
          firstError ??= error;
        }
        if (firstError) throw firstError;
      },
    };
  } catch (error) {
    await browser?.close().catch(() => {});
    await tunnel?.close().catch(() => {});
    if (error instanceof BrowserWorkerError) throw error;
    throw new BrowserWorkerError('ENVIRONMENT', 'Playwright browser failed to launch');
  }
}
