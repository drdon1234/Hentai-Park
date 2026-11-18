import { chromium, type Browser, type BrowserContext, type Page } from 'playwright';
import dns from 'node:dns/promises';
import { isAbsolute } from 'node:path';
import {
  NetworkBroker,
  validateNetworkUrl,
  redirectRequest,
  hostAllowed,
  type NetworkRequest,
  type NetworkResponse,
} from '@hentai-park/source-host';
import { toPluginError, toAbortError, type PluginManifest, type PluginError } from '@hentai-park/source-contract';
import { interceptRequests } from './interception.js';
import type { BrowserCookie } from './index.js';
import { createBrowserTunnel } from './browser-tunnel.js';
import { getSourceUserAgent } from './user-agent.js';

export interface GuardedContextOptions {
  domains: string[];
  browserNetwork?: boolean;
  prepareRequest?: (request: NetworkRequest) => Promise<Record<string, string>>;
  response?: (request: { url: string; method: string }, response: NetworkResponse) => Promise<void>;
  navigationDomains?: string[];
  frameDomains?: string[];
  resourceDomains?: string[];
  maxResourceBytes?: number;
  resourceUrls?: Set<string>;
  cookies?: BrowserCookie[];
  storageState?: Awaited<ReturnType<BrowserContext['storageState']>>;
  /** Server-derived per-game profile path; never accepted from a client request. */
  userDataDirectory?: string;
  executablePath?: string;
  signal?: AbortSignal;
  allowPopups?: boolean;
  allowDeclaredWebSockets?: boolean;
  relaxStaticSubresources?: boolean;
  lookup?: typeof dns.lookup;
  transport?: (request: NetworkRequest, domains: string[]) => Promise<NetworkResponse>;
}

export interface GuardedPageContext {
  context: BrowserContext;
  page: Page;
  readonly activePage: Page;
  readonly lastError?: PluginError;
  resetError(): void;
  close(): Promise<void>;
}

const failure = (code: string) =>
  Object.assign(new Error('Controlled browser operation failed'), {
    code,
    retryable: ['NETWORK', 'TIMEOUT', 'RATE_LIMITED'].includes(code),
  });

const MAX_ACTIVE_CONTEXTS = 16;
let activeContexts = 0;
const contextWaiters: Array<{ wake: () => void; cancel: () => void }> = [];

async function acquireContextSlot(signal?: AbortSignal): Promise<void> {
  signal?.throwIfAborted();
  if (activeContexts < MAX_ACTIVE_CONTEXTS) {
    activeContexts++;
    return;
  }
  if (contextWaiters.length >= 64) throw failure('RATE_LIMITED');
  await new Promise<void>((resolve, reject) => {
    const waiter = {
      wake: () => {
        signal?.removeEventListener('abort', waiter.cancel);
        resolve();
      },
      cancel: () => {
        const idx = contextWaiters.indexOf(waiter);
        if (idx >= 0) contextWaiters.splice(idx, 1);
        reject(toAbortError(signal!));
      },
    };
    contextWaiters.push(waiter);
    signal?.addEventListener('abort', waiter.cancel, { once: true });
  });
}

function releaseContextSlot() {
  const next = contextWaiters.shift();
  if (next) {
    next.wake();
  } else {
    activeContexts = Math.max(0, activeContexts - 1);
  }
}

interface SharedBrowserEntry {
  browser: Browser;
  tunnel: Awaited<ReturnType<typeof createBrowserTunnel>>;
  refs: number;
  idleTimer?: ReturnType<typeof setTimeout>;
  launching?: Promise<void>;
}

const sharedBrowsers = new Map<string, SharedBrowserEntry>();
let sharedMutation: Promise<unknown> = Promise.resolve();

function withSharedLock<T>(fn: () => Promise<T>): Promise<T> {
  const p = sharedMutation.then(fn);
  sharedMutation = p.then(
    () => undefined,
    () => undefined,
  );
  return p;
}

const STEALTH_INIT_SCRIPT = `(() => {
  try {
    Object.defineProperty(navigator, 'webdriver', { get: () => false, configurable: true });
    if (navigator.userAgentData && Array.isArray(navigator.userAgentData.brands)) {
      const cleanBrands = navigator.userAgentData.brands.map(b => ({
        brand: String(b.brand || '').replace(/HeadlessChrome/gi, 'Google Chrome'),
        version: b.version
      }));
      Object.defineProperty(navigator.userAgentData, 'brands', { get: () => cleanBrands });
    }
    if (!window.chrome) {
      Object.defineProperty(window, 'chrome', { value: { runtime: {} }, configurable: true });
    }
  } catch {}
})();`;

const CHROMIUM_STEALTH_ARGS = [
  '--autoplay-policy=no-user-gesture-required',
  '--disable-blink-features=AutomationControlled',
  '--disable-quic',
  '--force-webrtc-ip-handling-policy=disable_non_proxied_udp',
];

async function acquireSharedBrowser(executablePath?: string): Promise<{
  browser: Browser;
  tunnel: Awaited<ReturnType<typeof createBrowserTunnel>>;
  release: () => Promise<void>;
}> {
  const key = executablePath ?? process.env.PLAYWRIGHT_EXECUTABLE_PATH ?? 'default';
  return withSharedLock(async () => {
    let entry = sharedBrowsers.get(key);
    if (entry && !entry.browser.isConnected()) {
      clearTimeout(entry.idleTimer);
      await entry.tunnel.close().catch(() => {});
      sharedBrowsers.delete(key);
      entry = undefined;
    }
    if (!entry) {
      const tunnel = await createBrowserTunnel();
      try {
        const browser = await chromium.launch({
          headless: true,
          executablePath: executablePath ?? process.env.PLAYWRIGHT_EXECUTABLE_PATH,
          proxy: { server: tunnel.server, bypass: '<-loopback>' },
          args: [...CHROMIUM_STEALTH_ARGS, '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1'],
        });
        entry = { browser, tunnel, refs: 0 };
        browser.on('disconnected', () => {
          if (sharedBrowsers.get(key) === entry) {
            clearTimeout(entry?.idleTimer);
            void tunnel.close().catch(() => {});
            sharedBrowsers.delete(key);
          }
        });
        sharedBrowsers.set(key, entry);
      } catch (err) {
        await tunnel.close().catch(() => {});
        throw err;
      }
    }
    clearTimeout(entry.idleTimer);
    entry.idleTimer = undefined;
    entry.refs++;
    let released = false;
    return {
      browser: entry.browser,
      tunnel: entry.tunnel,
      release: async () => {
        if (released) return;
        released = true;
        await withSharedLock(async () => {
          const current = sharedBrowsers.get(key);
          if (!current || current !== entry) return;
          current.refs = Math.max(0, current.refs - 1);
          if (current.refs === 0) {
            current.idleTimer = setTimeout(() => {
              void withSharedLock(async () => {
                const target = sharedBrowsers.get(key);
                if (target === current && target.refs === 0) {
                  sharedBrowsers.delete(key);
                  await target.browser.close().catch(() => {});
                  await target.tunnel.close().catch(() => {});
                }
              });
            }, 5 * 60 * 1000);
            current.idleTimer.unref();
          }
        });
      },
    };
  });
}

/** A browser context with no network path outside the shared checked HTTP boundary. */
export async function createGuardedContext(options: GuardedContextOptions): Promise<GuardedPageContext> {
  await acquireContextSlot(options.signal);
  let sharedLease: Awaited<ReturnType<typeof acquireSharedBrowser>> | undefined;
  let dedicatedTunnel: Awaited<ReturnType<typeof createBrowserTunnel>> | undefined;
  let dedicatedBrowser: Browser | undefined;
  let context: BrowserContext | undefined;
  let closed = false;
  let lastError: PluginError | undefined;
  let closing: Promise<void> | undefined;
  const controllers = new Set<AbortController>();
  const popupStack: Page[] = [];

  const close = () => {
    if (closing) return closing;
    closed = true;
    releaseContextSlot();
    for (const controller of controllers) {
      controller.abort(options.signal?.aborted ? options.signal.reason : undefined);
    }
    controllers.clear();
    options.signal?.removeEventListener('abort', cancel);
    closing = (async () => {
      try {
        await context?.close().catch(() => {});
      } finally {
        try {
          await dedicatedBrowser?.close().catch(() => {});
        } finally {
          try {
            await dedicatedTunnel?.close().catch(() => {});
          } finally {
            await sharedLease?.release().catch(() => {});
          }
        }
      }
    })();
    return closing;
  };

  const cancel = () => {
    void close().catch(() => {});
  };
  options.signal?.addEventListener('abort', cancel, { once: true });

  try {
    if (
      options.maxResourceBytes !== undefined &&
      (!Number.isSafeInteger(options.maxResourceBytes) ||
        options.maxResourceBytes < 1 ||
        options.maxResourceBytes > 128 * 1024 * 1024)
    ) {
      throw failure('CONFIG');
    }
    if (
      options.userDataDirectory !== undefined &&
      (typeof options.userDataDirectory !== 'string' || !isAbsolute(options.userDataDirectory) || options.storageState !== undefined)
    ) {
      throw failure('CONFIG');
    }

    let tunnel: Awaited<ReturnType<typeof createBrowserTunnel>> | undefined;
    if (options.browserNetwork) {
      if (options.transport) throw failure('CONFIG');
      if (!options.userDataDirectory) {
        sharedLease = await acquireSharedBrowser(options.executablePath);
        tunnel = sharedLease.tunnel;
      } else {
        dedicatedTunnel = await createBrowserTunnel();
        tunnel = dedicatedTunnel;
      }
    } else if (!options.userDataDirectory) {
      dedicatedBrowser = await chromium.launch({
        headless: true,
        executablePath: options.executablePath ?? process.env.PLAYWRIGHT_EXECUTABLE_PATH,
        args: CHROMIUM_STEALTH_ARGS,
      });
    }

    if (closed) {
      throw options.signal?.aborted ? toAbortError(options.signal) : failure('CANCELLED');
    }

    const storage = options.storageState;
    const storageDomains = [...options.domains, ...(options.navigationDomains ?? [])];
    if (storage) {
      if (
        typeof storage !== 'object' ||
        Buffer.byteLength(JSON.stringify(storage)) > 1024 * 1024 ||
        storage.cookies.length > 1000 ||
        storage.origins.length > 64
      ) {
        throw failure('CONFIG');
      }
      for (const cookie of storage.cookies) {
        if (!hostAllowed(cookie.domain.replace(/^\./, ''), storageDomains)) throw failure('BLOCKED');
      }
      for (const item of storage.origins) {
        const url = new URL(item.origin);
        if (
          url.origin !== item.origin ||
          url.protocol !== 'https:' ||
          url.username ||
          url.password ||
          url.port ||
          !hostAllowed(url.hostname, storageDomains) ||
          item.localStorage.length > 1000
        ) {
          throw failure('BLOCKED');
        }
      }
    }
    if (options.cookies?.some((cookie) => !hostAllowed(cookie.domain.replace(/^\./, ''), options.domains))) {
      throw failure('BLOCKED');
    }

    if (options.userDataDirectory) {
      const launchNetwork = tunnel
        ? {
            proxy: { server: tunnel.server, bypass: '<-loopback>' },
            args: [...CHROMIUM_STEALTH_ARGS, '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1'],
          }
        : { args: CHROMIUM_STEALTH_ARGS };
      context = await chromium.launchPersistentContext(options.userDataDirectory, {
        headless: true,
        executablePath: options.executablePath ?? process.env.PLAYWRIGHT_EXECUTABLE_PATH,
        ...launchNetwork,
        serviceWorkers: 'block',
        acceptDownloads: false,
        viewport: { width: 960, height: 540 },
        deviceScaleFactor: 1,
        userAgent: getSourceUserAgent(),
      });
    } else {
      const hostBrowser = sharedLease?.browser ?? dedicatedBrowser!;
      context = await hostBrowser.newContext({
        serviceWorkers: 'block',
        acceptDownloads: false,
        viewport: { width: 960, height: 540 },
        deviceScaleFactor: 1,
        storageState: storage,
        userAgent: getSourceUserAgent(),
      });
    }

    if (closed) {
      throw options.signal?.aborted ? toAbortError(options.signal) : failure('CANCELLED');
    }

    await context.addInitScript(STEALTH_INIT_SCRIPT);
    if (options.cookies?.length) await context.addCookies(options.cookies);

    await context.routeWebSocket('**/*', (route) => {
      if (options.allowDeclaredWebSockets) {
        try {
          const wsUrl = new URL(route.url());
          if (
            wsUrl.protocol === 'wss:' &&
            !wsUrl.username &&
            !wsUrl.password &&
            !wsUrl.port &&
            hostAllowed(wsUrl.hostname, [...options.domains, ...(options.navigationDomains ?? [])])
          ) {
            // Validate public DNS before permitting WebSocket handshake (e.g. wss://*.web.telegram.org/apiws)
            void validateNetworkUrl('https://' + wsUrl.hostname + '/', options.domains, options.lookup ?? dns.lookup)
              .then((pinned) => {
                if (tunnel) tunnel.approve(pinned.target, pinned.addresses);
                route.connectToServer();
              })
              .catch(() => route.close());
            return;
          }
        } catch {}
      }
      route.close();
    });

    const attachInterception = async (targetPage: Page) => {
      targetPage.on('download', (download) => {
        void download.cancel();
      });
      targetPage.on('dialog', (dialog) => {
        void dialog.dismiss();
      });
      await interceptRequests(
        await context!.newCDPSession(targetPage),
        async (route) => {
          const controller = new AbortController();
          controllers.add(controller);
          const request = route.request();
          try {
            if (closed) throw options.signal?.aborted ? toAbortError(options.signal) : failure('CANCELLED');
            if ((request.redirectCount?.() ?? 0) > 5) throw failure('BLOCKED');
            const nested = Boolean(request.frame().parentFrame());
            const isStaticAsset =
              Boolean(tunnel) &&
              options.relaxStaticSubresources === true &&
              !request.isNavigationRequest() &&
              ['script', 'stylesheet', 'font', 'image'].includes(request.resourceType());

            const domains =
              (!request.isNavigationRequest() && options.resourceUrls?.has(request.url())) || isStaticAsset
                ? undefined
                : request.isNavigationRequest()
                  ? nested
                    ? [...options.domains, ...(options.navigationDomains ?? []), ...(options.frameDomains ?? [])]
                    : (options.navigationDomains ?? options.domains)
                  : [
                      ...options.domains,
                      ...(options.navigationDomains ?? []),
                      ...(options.frameDomains ?? []),
                      ...(options.resourceDomains ?? []),
                    ];

            const pinned = await validateNetworkUrl(request.url(), domains, options.lookup ?? dns.lookup);
            let headers = await request.allHeaders();
            let body = request.postDataBuffer();
            if (body && body.length > 2 * 1024 * 1024) throw failure('BLOCKED');
            const previous = request.redirectedFrom?.();
            if (previous) {
              const response = await previous.response();
              if (response) {
                const next = redirectRequest(
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
                if (next.method !== request.method()) throw failure('BLOCKED');
                headers = next.headers ?? {};
                body = next.bodyBase64 === undefined ? null : Buffer.from(next.bodyBase64, 'base64');
              }
            }
            const input: NetworkRequest = {
              url: request.url(),
              method: request.method(),
              headers,
              bodyBase64: body?.toString('base64'),
              responseType: 'base64',
              followRedirects: false,
              signal: AbortSignal.any([
                controller.signal,
                AbortSignal.timeout(30000),
                ...(options.signal ? [options.signal] : []),
              ]),
            };
            if (tunnel) {
              tunnel.approve(pinned.target, pinned.addresses);
              await route.continueRequest!(options.prepareRequest ? await options.prepareRequest(input) : headers);
              return;
            }
            const effectiveDomains = domains ?? [pinned.target.hostname];
            const result = options.transport
              ? await options.transport(input, effectiveDomains)
              : await new NetworkBroker(
                  { domains: effectiveDomains } as PluginManifest,
                  undefined,
                  undefined,
                  undefined,
                  undefined,
                  options.maxResourceBytes ?? 32 * 1024 * 1024,
                ).request(input);
            const bytes = Buffer.from(result.body, 'base64');
            if (bytes.length > (options.maxResourceBytes ?? 32 * 1024 * 1024)) throw failure('PARSE');
            await route.fulfill({ status: result.status, headers: result.headers, body: bytes });
          } catch (error) {
            lastError = toPluginError(error);
            await route.abort().catch(() => {});
          } finally {
            controllers.delete(controller);
          }
        },
        (url) => context!.cookies([url]),
        undefined,
        undefined,
        tunnel
          ? {
              maxBytes: options.maxResourceBytes ?? 32 * 1024 * 1024,
              captureUrls: options.resourceUrls,
              response: options.response,
              error: (error) => {
                lastError = toPluginError(error);
              },
            }
          : undefined,
      );
    };

    const page = await context.newPage();
    page.on('popup', (popup) => {
      if (!options.allowPopups) {
        void popup.close().catch(() => {});
        return;
      }
      popupStack.push(popup);
      popup.once('close', () => {
        const idx = popupStack.indexOf(popup);
        if (idx >= 0) popupStack.splice(idx, 1);
      });
      void popup.setViewportSize({ width: 960, height: 540 }).catch(() => {});
      void attachInterception(popup).catch(() => {
        void popup.close().catch(() => {});
      });
    });

    await attachInterception(page);
    options.signal?.throwIfAborted();

    return {
      context,
      page,
      get activePage() {
        for (let i = popupStack.length - 1; i >= 0; i--) {
          const p = popupStack[i]!;
          if (!p.isClosed()) return p;
        }
        return page;
      },
      get lastError() {
        return lastError;
      },
      resetError() {
        lastError = undefined;
      },
      close,
    };
  } catch (error) {
    await close();
    throw options.signal?.aborted ? toAbortError(options.signal) : error;
  }
}
