import fs from 'node:fs/promises';
import path from 'node:path';
import { getQuickJS, type QuickJSHandle } from 'quickjs-emscripten';
import { randomBytes, randomUUID } from 'node:crypto';
import { TextDecoder as HostTextDecoder, TextEncoder as HostTextEncoder } from 'node:util';
import { cryptoOperation } from './crypto.js';
import { fileURLToPath } from 'node:url';
import { CAPABILITY_NAMES, operationCapability } from '@hentai-park/source-contract';
import { normalizeRuntimeManifest, legacyInvocation, normalizePluginError } from '@hentai-park/source-runtime';
import type { PluginManifest } from '@hentai-park/source-contract';

const argument = (name: string) => {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
};
const pluginPath = argument('--plugin');
const runtimePath =
  argument('--runtime') ?? fileURLToPath(new URL('../../../assets/runtime/park_runtime.js', import.meta.url));

const engine = await getQuickJS();
const engineRuntime = engine.newRuntime();
// 256 MiB heap & 2 MiB stack to accommodate large JS bundle parsers (e.g. x.js) and deep HTML trees
engineRuntime.setMemoryLimit(256 * 1024 * 1024);
engineRuntime.setMaxStackSize(2 * 1024 * 1024);

const startupDeadline = Date.now() + 10000;
const requestDeadlines = new Map<string, number>();
const abortedInvocations = new Set<string>();
let runtimeLoaded = false;
let deadline = startupDeadline;
let executionInterrupted = false;

engineRuntime.setInterruptHandler(() => {
  if (Date.now() > deadline) executionInterrupted = true;
  return executionInterrupted;
});

function executionTimeout() {
  return Object.assign(new Error('isolated execution deadline exceeded'), {
    code: 'TIMEOUT',
    retryable: true,
    details: { reason: 'RECEIVE_TIMEOUT' },
  });
}

function prepareExecution() {
  if (executionInterrupted) throw executionTimeout();
  const active = requestDeadlines.size ? Math.min(...requestDeadlines.values()) : undefined;
  deadline = runtimeLoaded ? (active ?? Date.now() + 2000) : Math.min(startupDeadline, active ?? startupDeadline);
}

const context = engineRuntime.newContext();
const hostEncoder = new HostTextEncoder();

function engineError() {
  return Object.assign(new Error('isolated JavaScript execution failed'), { code: 'PARSE' });
}

function run(source: string, filename = 'plugin.js'): string | undefined {
  prepareExecution();
  const result = context.evalCode(source, filename, { type: 'global' });
  if (result.error) {
    result.error.dispose();
    throw executionInterrupted ? executionTimeout() : engineError();
  }
  try {
    if (executionInterrupted) throw executionTimeout();
    return context.typeof(result.value) === 'string' ? context.getString(result.value) : undefined;
  } finally {
    result.value.dispose();
  }
}

function callGlobalJson(fnHandle: QuickJSHandle, ...args: string[]): string | undefined {
  prepareExecution();
  const handles = args.map((value) => context.newString(value));
  try {
    const result = context.callFunction(fnHandle, context.undefined, ...handles);
    if (result.error) {
      result.error.dispose();
      throw executionInterrupted ? executionTimeout() : engineError();
    }
    try {
      if (executionInterrupted) throw executionTimeout();
      return context.typeof(result.value) === 'string' ? context.getString(result.value) : undefined;
    } finally {
      result.value.dispose();
    }
  } finally {
    for (const h of handles) h.dispose();
  }
}

function installNativePrimitives() {
  const btoaFn = context.newFunction('__hostBtoa', (inputHandle) => {
    const str = context.getString(inputHandle);
    for (let i = 0; i < str.length; i++) {
      if (str.charCodeAt(i) > 0xff) {
        throw new Error('InvalidCharacterError: The string to be encoded contains characters outside of the Latin1 range.');
      }
    }
    return context.newString(Buffer.from(str, 'latin1').toString('base64'));
  });
  context.setProp(context.global, '__hostBtoa', btoaFn);
  btoaFn.dispose();

  const atobFn = context.newFunction('__hostAtob', (inputHandle) => {
    const str = context.getString(inputHandle).replace(/[\t\n\f\r ]+/g, '');
    if (str.length % 4 === 1 || /[^+/0-9A-Za-z=]/.test(str)) {
      throw new Error('InvalidCharacterError: The string to be decoded is not correctly encoded.');
    }
    return context.newString(Buffer.from(str, 'base64').toString('latin1'));
  });
  context.setProp(context.global, '__hostAtob', atobFn);
  atobFn.dispose();

  // Full WHATWG/ICU charset support (UTF-8, EUC-JP, Shift-JIS, GBK, GB18030, Big5, Windows-1252, etc.)
  const decodeFn = context.newFunction('__hostTextDecode', (labelHandle, base64Handle, flagsHandle) => {
    const label = context.getString(labelHandle) || 'utf-8';
    const base64 = context.getString(base64Handle);
    const flags = Number(context.getNumber(flagsHandle) || 0);
    const decoder = new HostTextDecoder(label, {
      fatal: Boolean(flags & 1),
      ignoreBOM: Boolean(flags & 2),
    });
    const bytes = base64 ? Buffer.from(base64, 'base64') : Buffer.alloc(0);
    return context.newString(decoder.decode(bytes));
  });
  context.setProp(context.global, '__hostTextDecode', decodeFn);
  decodeFn.dispose();

  const verifyLabelFn = context.newFunction('__hostNormalizeEncoding', (labelHandle) => {
    const label = context.getString(labelHandle) || 'utf-8';
    const decoder = new HostTextDecoder(label);
    return context.newString(decoder.encoding);
  });
  context.setProp(context.global, '__hostNormalizeEncoding', verifyLabelFn);
  verifyLabelFn.dispose();

  const encodeFn = context.newFunction('__hostTextEncode', (strHandle) => {
    const str = context.getString(strHandle);
    return context.newString(Buffer.from(hostEncoder.encode(str)).toString('base64'));
  });
  context.setProp(context.global, '__hostTextEncode', encodeFn);
  encodeFn.dispose();

  const randomHexFn = context.newFunction('__hostRandomBase64', (lenHandle) => {
    const n = Math.max(0, Math.min(65536, Math.floor(context.getNumber(lenHandle) || 0)));
    return context.newString(n > 0 ? randomBytes(n).toString('base64') : '');
  });
  context.setProp(context.global, '__hostRandomBase64', randomHexFn);
  randomHexFn.dispose();

  const uuidFn = context.newFunction('__hostRandomUUID', () => context.newString(randomUUID()));
  context.setProp(context.global, '__hostRandomUUID', uuidFn);
  uuidFn.dispose();
}

function jobs() {
  for (let round = 0; round < 32; round++) {
    prepareExecution();
    const result = engineRuntime.executePendingJobs(1024);
    if (result.error) {
      result.error.dispose();
      throw executionInterrupted ? executionTimeout() : engineError();
    }
    if (executionInterrupted) throw executionTimeout();
    if (result.value <= 0) break;
  }
}

let settleFn: QuickJSHandle | undefined;
let drainOutFn: QuickJSHandle | undefined;
let drainResultsFn: QuickJSHandle | undefined;
let invokeEntryFn: QuickJSHandle | undefined;

function read<T>(source: string): T {
  return JSON.parse(String(run(`JSON.stringify(${source})`))) as T;
}

function send(message: unknown) {
  const id = (message as { id?: string }).id;
  if (id) {
    requestDeadlines.delete(id);
    abortedInvocations.delete(id);
  }
  process.stdout.write(JSON.stringify(message) + '\n');
}

let manifest: PluginManifest;
let loaded: Promise<void>;
const network = new Map<string, { bridgeId: string; invocationId?: string }>();
let stopped = false;

function fail(code: string, message: string) {
  return Object.assign(new Error(message), { code });
}

async function load() {
  if (!pluginPath) throw fail('CONFIG', 'plugin path missing');
  const source = await fs.readFile(pluginPath, 'utf8');
  if (Buffer.byteLength(source) > 8 * 1024 * 1024) throw fail('PARSE', 'plugin exceeds size limit');
  const polyfill = await fs.readFile(path.join(path.dirname(runtimePath), 'polyfills.js'), 'utf8');

  installNativePrimitives();
  run(
    `globalThis.btoa = s => __hostBtoa(String(s));
    globalThis.atob = s => __hostAtob(String(s));
    function __bytesToB64(input) {
      if (!input) return '';
      const u8 = ArrayBuffer.isView(input)
        ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength)
        : input instanceof ArrayBuffer
          ? new Uint8Array(input)
          : new Uint8Array(0);
      if (u8.byteLength === 0) return '';
      let bin = '';
      const step = 0x8000;
      for (let i = 0; i < u8.length; i += step) {
        bin += String.fromCharCode.apply(null, u8.subarray(i, i + step));
      }
      return __hostBtoa(bin);
    }
    function __b64ToBytes(b64) {
      if (!b64) return new Uint8Array(0);
      const bin = __hostAtob(b64);
      const out = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
      return out;
    }
    globalThis.TextDecoder = class TextDecoder {
      constructor(label = 'utf-8', options = {}) {
        this.encoding = __hostNormalizeEncoding(String(label).trim());
        this.fatal = Boolean(options && options.fatal);
        this.ignoreBOM = Boolean(options && options.ignoreBOM);
      }
      decode(input) {
        if (input === undefined) return '';
        const flags = (this.fatal ? 1 : 0) | (this.ignoreBOM ? 2 : 0);
        return __hostTextDecode(this.encoding, __bytesToB64(input), flags);
      }
    };
    globalThis.TextEncoder = class TextEncoder {
      get encoding() { return 'utf-8'; }
      encode(input = '') {
        return __b64ToBytes(__hostTextEncode(String(input)));
      }
    };
    if (!globalThis.crypto) {
      globalThis.crypto = Object.freeze({
        randomUUID: () => __hostRandomUUID(),
        getRandomValues(typedArray) {
          if (!ArrayBuffer.isView(typedArray) || typedArray.byteLength > 65536) {
            throw new TypeError('Failed to execute getRandomValues');
          }
          const raw = __b64ToBytes(__hostRandomBase64(typedArray.byteLength));
          new Uint8Array(typedArray.buffer, typedArray.byteOffset, typedArray.byteLength).set(raw);
          return typedArray;
        },
      });
    }
    globalThis.__bridge = {
      out: [],
      pending: new Map(),
      results: new Map(),
      sequence: 0,
      settle(id, isError, payloadJson) {
        const pending = __bridge.pending.get(id);
        if (!pending) return;
        __bridge.pending.delete(id);
        const value = JSON.parse(payloadJson);
        if (isError === '1') {
          pending.reject(Object.assign(new Error(value.message || 'host operation failed'), value));
        } else {
          pending.resolve(value);
        }
      },
      drainOut() {
        if (__bridge.out.length === 0) return '[]';
        const out = __bridge.out;
        __bridge.out = [];
        return JSON.stringify(out);
      },
      drainResults() {
        if (__bridge.results.size === 0) return '[]';
        const out = [...__bridge.results.values()];
        __bridge.results.clear();
        return JSON.stringify(out);
      },
      invoke(payloadJson) {
        const p = JSON.parse(payloadJson);
        Promise.resolve().then(async () => {
          if (!globalThis.__setupPromise) {
            globalThis.__setupPromise = Park.setup(p.manifestKey, p.state, { waitForInit: true }).catch(err => {
              globalThis.__setupPromise = undefined;
              throw err;
            });
          }
          await globalThis.__setupPromise;
          const result = globalThis.__modern && !p.special
            ? { ok: true, value: await __definition[p.method].call(__definition, p.rawParams) }
            : await Park.invoke(p.manifestKey, p.pathName, p.args, p.id);
          if (!result.ok) throw result.error;
          await __definition.store?.flush?.();
          if (p.account && (p.operation === 'login' || p.operation === 'enableManaged')) {
            const status = await Park.invoke(p.manifestKey, 'account.status', [], p.id);
            if (!status.ok) throw status.error;
            return status.value;
          }
          return p.account && p.operation === 'logout' ? { loggedIn: false } : result.value;
        }).then(
          result => __bridge.results.set(p.id, { id: p.id, result }),
          error => __bridge.results.set(p.id, {
            id: p.id,
            error: {
              code: error?.code || 'PARSE',
              message: 'Plugin operation failed',
              status: error?.status,
              retryable: error?.retryable,
              diagnostics: error?.diagnostics,
              details: error?.details,
            },
          })
        );
      }
    };
    globalThis.__call = (operation, args) => new Promise((resolve, reject) => {
      const id = String(++__bridge.sequence);
      __bridge.pending.set(id, { resolve, reject });
      __bridge.out.push({ id, operation, args });
    });
    globalThis.setTimeout = (callback, delay, ...args) => {
      const id = ++__bridge.sequence;
      __call('sleep', { delay: Math.max(0, Math.min(Number(delay) || 0, 30000)), timer: id }).then(() => callback(...args));
      return id;
    };
    globalThis.clearTimeout = id => __bridge.out.push({ id: String(++__bridge.sequence), operation: 'clearTimer', args: { timer: id } });
    globalThis.console = Object.freeze({ log(){}, error(){}, warn(){}, info(){} });`,
    'bridge-init.js',
  );

  const bridgeObj = context.getProp(context.global, '__bridge');
  settleFn = context.getProp(bridgeObj, 'settle');
  drainOutFn = context.getProp(bridgeObj, 'drainOut');
  drainResultsFn = context.getProp(bridgeObj, 'drainResults');
  invokeEntryFn = context.getProp(bridgeObj, 'invoke');
  bridgeObj.dispose();

  run(polyfill, 'polyfills.js');
  run(await fs.readFile(runtimePath, 'utf8'), 'park_runtime.js');
  run(
    `Park.__native = Object.freeze({
      request: args => __call('request', args),
      chatRequest: args => __call('chatRequest', args),
      crypto: (op, args) => __call('crypto', { op, args }),
      cookies: (op, args) => __call('cookies', { op, args }),
      persist: (source, data, flush) => __call('persist', { source, data, flush }),
      log(){},
    });`,
    'native-binding.js',
  );

  const normalized = source.replace(/^\s*export\s+default\s+/, 'globalThis.__moduleExport = ');
  run(normalized, 'plugin.js');
  run(
    `if (globalThis.__moduleExport) {
      const x = __moduleExport;
      globalThis.__modern = !!(x.manifest || x.implementation);
      globalThis.__definition = x.implementation ? { ...x.manifest, ...x.implementation } : x.manifest ? { ...x.manifest, ...x } : x;
      if (__modern) Park.register(__definition);
    } else {
      globalThis.__definition = Park.__pending;
    }
    if (!__definition) throw Error('plugin did not register');`,
    'register.js',
  );

  const raw = read<Record<string, unknown>>(
    '({...Park.manifest(__definition.key),account:__definition.account?{...Park.manifest(__definition.key).account,registerUrl:__definition.account.registerUrl}:null,navigationDomains:__definition.navigationDomains,frameDomains:__definition.frameDomains})',
  );
  const declared = read<Record<string, unknown>>('__definition.capabilities || {}');
  const available = read<Record<string, boolean>>(
    `Object.fromEntries(${JSON.stringify(CAPABILITY_NAMES)}.map(k=>[k,typeof __definition[k]==='function']))`,
  );
  manifest = normalizeRuntimeManifest(raw, declared, available);
  runtimeLoaded = true;
}

const timers = new Map<number, ReturnType<typeof setTimeout>>();
const state: Record<string, unknown> = {};

function settle(id: string, error: unknown, result?: unknown) {
  if (!settleFn) return;
  const payload = error ? normalizePluginError(error) : (result ?? null);
  callGlobalJson(settleFn, id, error ? '1' : '0', JSON.stringify(payload));
}

function drain() {
  if (stopped || !drainOutFn || !drainResultsFn) return;
  try {
    for (let cycle = 0; cycle < 16; cycle++) {
      jobs();
      const rawMessages = callGlobalJson(drainOutFn) ?? '[]';
      const messages = JSON.parse(rawMessages) as Array<{
        id: string;
        operation: string;
        args: Record<string, unknown>;
      }>;
      let progressed = false;
      for (const m of messages) {
        progressed = true;
        try {
          if (m.operation === 'request') {
            const invocationId = typeof m.args?.invocation === 'string' ? m.args.invocation : undefined;
            if (invocationId && abortedInvocations.has(invocationId)) {
              settle(m.id, { code: 'CANCELLED', details: { reason: 'CANCELLED' } });
              continue;
            }
            const id = randomUUID();
            network.set(id, { bridgeId: m.id, invocationId });
            send({ id, type: 'network', request: m.args });
          } else if (m.operation === 'sleep') {
            const timerId = Number(m.args.timer);
            const timer = setTimeout(() => {
              timers.delete(timerId);
              settle(m.id, null);
              drain();
            }, Number(m.args.delay));
            timers.set(timerId, timer);
          } else if (m.operation === 'clearTimer') {
            const timerId = Number(m.args.timer);
            clearTimeout(timers.get(timerId));
            timers.delete(timerId);
          } else if (m.operation === 'crypto') {
            settle(m.id, null, cryptoOperation(String(m.args.op), m.args.args as Record<string, unknown>));
          } else if (m.operation === 'persist' || m.operation === 'cookies' || m.operation === 'chatRequest') {
            const id = randomUUID();
            network.set(id, { bridgeId: m.id });
            send({ id, type: 'native', operation: m.operation, args: m.args });
          } else {
            settle(m.id, fail('UNSUPPORTED', 'unknown host operation'));
          }
        } catch (error) {
          settle(m.id, error);
        }
      }

      jobs();
      const rawResults = callGlobalJson(drainResultsFn) ?? '[]';
      const results = JSON.parse(rawResults) as Array<{ id: string; result?: unknown; error?: unknown }>;
      for (const result of results) {
        progressed = true;
        if (!abortedInvocations.has(result.id)) {
          send(result.error ? { id: result.id, error: normalizePluginError(result.error) } : result);
        } else {
          requestDeadlines.delete(result.id);
          abortedInvocations.delete(result.id);
        }
      }
      if (!progressed) break;
    }
  } catch (error) {
    send({ id: '__runtime__', error: normalizePluginError(error) });
    process.exit(1);
  }
}

let setup = false;

async function handle(line: string) {
  let msg: {
    id?: string;
    deadlineAt?: number;
    method?: string;
    result?: unknown;
    error?: unknown;
    params?: {
      method?: string;
      params?: unknown;
      expectedManifest?: PluginManifest;
      id?: string;
      operation?: string;
      values?: Record<string, string>;
      stateSnapshot?: Record<string, unknown>;
      page?: { url: string; html: string };
      query?: {
        scope: 'feed' | 'search';
        feed?: string;
        filter: string;
        values?: Record<string, string | number | boolean>;
        keyword?: string;
      };
    };
  };
  try {
    msg = JSON.parse(line);
  } catch {
    return;
  }
  if (!msg.id) return;

  try {
    if (msg.method === 'abortInvocation') {
      requestDeadlines.delete(msg.id);
      abortedInvocations.add(msg.id);
      for (const [netId, entry] of network.entries()) {
        if (entry.invocationId === msg.id) {
          network.delete(netId);
          settle(entry.bridgeId, { code: 'CANCELLED', details: { reason: 'CANCELLED' } });
        }
      }
      drain();
      return;
    }

    if (msg.method && msg.method !== 'cancel') {
      const now = Date.now();
      const requested = msg.deadlineAt;
      if (typeof requested !== 'number' || !Number.isSafeInteger(requested) || requested <= 0) {
        throw fail('CONFIG', 'invalid execution deadline');
      }
      requestDeadlines.set(msg.id, Math.min(requested, now + 300000));
      if (requestDeadlines.get(msg.id)! <= now) throw executionTimeout();
    }

    await loaded;

    if (network.has(msg.id)) {
      const entry = network.get(msg.id)!;
      network.delete(msg.id);
      settle(entry.bridgeId, msg.error, msg.result);
      drain();
      return;
    }

    if (msg.method === 'cancel') {
      stopped = true;
      for (const t of timers.values()) clearTimeout(t);
      process.exit(0);
    }

    if (msg.method === 'manifest') {
      send({ id: msg.id, result: manifest });
      return;
    }

    if (msg.method === 'accountMethods') {
      send({
        id: msg.id,
        result: read(
          "Object.fromEntries(['login','status','logout','enableManaged'].map(key=>[key,typeof __definition.account?.[key]==='function']))",
        ),
      });
      return;
    }

    const account = msg.method === 'account';
    const reverseResult = msg.method === 'reverseSearchResult';
    const filterOptions = msg.method === 'filterOptions';
    if (!msg.params || (!account && !reverseResult && !filterOptions && (msg.method !== 'invoke' || !msg.params.method))) {
      throw fail('CONFIG', 'invalid invocation');
    }
    if (
      account &&
      (!manifest.account ||
        !['login', 'status', 'logout', 'enableManaged'].includes(msg.params.operation ?? '') ||
        (msg.params.operation === 'enableManaged' && manifest.account?.managedAccount !== true))
    ) {
      throw fail('UNSUPPORTED', 'account operation is unavailable');
    }
    if (
      reverseResult &&
      (manifest.capabilities?.reverseSearch !== true || !read<boolean>("typeof __definition.reverseSearchResult==='function'"))
    ) {
      throw fail('UNSUPPORTED', 'reverse search result parser is unavailable');
    }
    if (filterOptions) {
      const query = msg.params.query;
      const declarations =
        query?.scope === 'feed'
          ? manifest.feeds?.find((value) => value.key === query.feed)?.options
          : query?.scope === 'search'
            ? manifest.searchFilters
            : undefined;
      if (
        !declarations?.some((value) => value.dynamic === true && value.key === query?.filter) ||
        !read<boolean>("typeof __definition.filterOptions==='function'")
      ) {
        throw fail('UNSUPPORTED', 'dynamic filter query is unavailable');
      }
    }
    if (
      reverseResult &&
      (!msg.params.page ||
        typeof msg.params.page.url !== 'string' ||
        typeof msg.params.page.html !== 'string' ||
        Buffer.byteLength(msg.params.page.html, 'utf8') > 4 * 1024 * 1024)
    ) {
      throw fail('CONFIG', 'invalid reverse search page');
    }
    if (!setup) Object.assign(state, msg.params.stateSnapshot ?? {});

    const expected = msg.params.expectedManifest;
    if (expected && (expected.key !== manifest.key || expected.version !== manifest.version)) {
      throw fail('INVALID_MANIFEST', 'loaded plugin identity mismatch');
    }

    const method = account
      ? 'account.' + msg.params.operation
      : reverseResult
        ? 'reverseSearchResult'
        : filterOptions
          ? 'filterOptions'
          : msg.params.method!;

    if (
      !account &&
      !reverseResult &&
      !filterOptions &&
      (!operationCapability(method) || manifest.capabilities?.[operationCapability(method)!] !== true)
    ) {
      throw fail('UNSUPPORTED', 'capability not declared');
    }

    const invocation = account
      ? { path: method, args: [msg.params.values ?? {}] }
      : reverseResult
        ? { path: 'reverseSearchResult', args: [msg.params.page] }
        : filterOptions
          ? { path: 'filterOptions', args: [msg.params.query] }
          : legacyInvocation(manifest, method, msg.params.params);

    callGlobalJson(
      invokeEntryFn!,
      JSON.stringify({
        id: msg.id,
        manifestKey: manifest.key,
        state,
        special: Boolean(account || reverseResult || filterOptions || method.includes('.')),
        method,
        rawParams: msg.params.params ?? null,
        pathName: invocation.path,
        args: invocation.args,
        account,
        operation: msg.params.operation ?? null,
      }),
    );
    setup = true;
    drain();
  } catch (error) {
    send({ id: msg.id, error: normalizePluginError(error) });
  }
}

process.stdin.setEncoding('utf8');
let buffer = '';
process.stdin.on('data', (chunk) => {
  buffer += chunk;
  if (buffer.length > 32 * 1024 * 1024) {
    process.exit(1);
  }
  let i;
  while ((i = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, i);
    buffer = buffer.slice(i + 1);
    void handle(line);
  }
});

loaded = load();
loaded.catch((error) => {
  send({ id: '__startup__', error: normalizePluginError(error) });
  process.exit(1);
});

process.once('exit', () => {
  settleFn?.dispose();
  drainOutFn?.dispose();
  drainResultsFn?.dispose();
  invokeEntryFn?.dispose();
  context.dispose();
  engineRuntime.dispose();
});

// Low-frequency safety net only when in-flight requests exist (0% idle CPU spin)
const safetyTimer = setInterval(() => {
  if (manifest && requestDeadlines.size > 0) drain();
}, 100);
safetyTimer.unref();

process.stdin.on('end', () => {
  clearInterval(safetyTimer);
  for (const timer of timers.values()) clearTimeout(timer);
  process.exit(0);
});
