import { useEffect, useRef, useSyncExternalStore } from 'react';
import type { LibraryEntry } from './api.js';
import { downloadTaskId } from '@hentai-park/domain-model';

export type ProgressState = { position: number; duration?: number; page?: number; updatedAt: number };
export type DownloadState = { key: string; status: string; updatedAt: number };
export type DownloadTelemetrySample = {
  taskId: string;
  status?: string;
  bytes?: number;
  completedCount?: number;
  totalCount?: number;
  speed?: number | null;
};
export type SharedState = {
  collections: Record<string, LibraryEntry>;
  collectionsReady: boolean;
  downloads: Record<string, DownloadState>;
  progress: Record<string, ProgressState>;
  incognito: boolean | undefined;
  coverBlur: boolean;
  blockedWords: string[];
  notificationsEnabled: boolean;
};
export type DownloadIdentity = { source: string; workId: string; chapterId: string; variant?: string };

const STATE_KEY = 'hp-shared-state';
const CHANNEL_NAME = 'hentai-park-web';
const initialState: SharedState = {
  collections: {},
  collectionsReady: false,
  downloads: {},
  progress: {},
  incognito: undefined,
  coverBlur: false,
  blockedWords: [],
  notificationsEnabled: false,
};

export type ThemeMode = 'light' | 'dark';
function storedTheme(): ThemeMode {
  try {
    const value = window.localStorage.getItem('hp-theme');
    if (value === 'light' || value === 'dark') return value;
  } catch {
    /* Local storage is optional. */
  }
  return 'dark';
}
let theme: ThemeMode = typeof window === 'undefined' ? 'dark' : storedTheme();
const themeListeners = new Set<() => void>();
export function resolveThemePreference(value: unknown): ThemeMode {
  if (value === 'light') return 'light';
  if (value === 'dark') return 'dark';
  return typeof matchMedia === 'function' && matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}
export function setThemeMode(next: ThemeMode) {
  if (theme === next) return;
  theme = next;
  try {
    window.localStorage.setItem('hp-theme', next);
  } catch {
    /* Local storage is optional. */
  }
  themeListeners.forEach((listener) => listener());
}
export function useThemeMode() {
  return useSyncExternalStore(
    (listener) => {
      themeListeners.add(listener);
      return () => themeListeners.delete(listener);
    },
    () => theme,
    () => 'dark' as ThemeMode,
  );
}

/* Transient 1Hz download telemetry store (never triggers full-table API re-fetches) */
let telemetrySnapshot: Record<string, DownloadTelemetrySample> = {};
const telemetryListeners = new Set<() => void>();
if (typeof window !== 'undefined') {
  window.addEventListener('hp:download-telemetry', (event) => {
    const detail = (event as CustomEvent<DownloadTelemetrySample>).detail;
    if (!detail?.taskId) return;
    telemetrySnapshot = { ...telemetrySnapshot, [detail.taskId]: { ...telemetrySnapshot[detail.taskId], ...detail } };
    telemetryListeners.forEach((fn) => fn());
  });
}
export function useDownloadTelemetry() {
  return useSyncExternalStore(
    (listener) => {
      telemetryListeners.add(listener);
      return () => telemetryListeners.delete(listener);
    },
    () => telemetrySnapshot,
    () => telemetrySnapshot,
  );
}

/* Internal SPA navigation depth tracking & mobile back-gesture coordination stack */
let navDepth = 0;
export function recordInternalPush() {
  navDepth++;
}
export function getInternalNavDepth() {
  return navDepth;
}

const backDismissStack: Array<{ id: string; dismiss: () => void }> = [];
if (typeof window !== 'undefined') {
  window.addEventListener(
    'popstate',
    (event) => {
      if (navDepth > 0) navDepth = Math.max(0, navDepth - 1);
      const top = backDismissStack.pop();
      if (top) {
        event.stopImmediatePropagation();
        top.dismiss();
      }
    },
    true,
  );
}

/** Registers a modal/sheet/lightbox/drawer on the mobile back-gesture dismissal stack. */
export function useBackDismissable(active: boolean, onDismiss: () => void) {
  const callbackRef = useRef(onDismiss);
  callbackRef.current = onDismiss;
  useEffect(() => {
    if (!active || typeof window === 'undefined') return;
    const id = typeof crypto !== 'undefined' ? crypto.randomUUID() : String(Math.random());
    let closedByPop = false;
    const entry = {
      id,
      dismiss: () => {
        closedByPop = true;
        callbackRef.current();
      },
    };
    backDismissStack.push(entry);
    window.history.pushState({ ...window.history.state, hpDismissId: id }, '');
    navDepth++;
    return () => {
      const idx = backDismissStack.findIndex((item) => item.id === id);
      if (idx >= 0) backDismissStack.splice(idx, 1);
      if (!closedByPop && window.history.state?.hpDismissId === id) {
        window.history.back();
      }
    };
  }, [active]);
}

function normalizeState(value: unknown): SharedState {
  const parsed = value && typeof value === 'object' ? (value as Partial<SharedState>) : {};
  const downloads = parsed.downloads && typeof parsed.downloads === 'object' ? parsed.downloads : {};
  const progress = parsed.progress && typeof parsed.progress === 'object' ? parsed.progress : {};
  return {
    collections: parsed.collections && typeof parsed.collections === 'object' ? parsed.collections : {},
    collectionsReady: parsed.collectionsReady === true,
    downloads: Object.fromEntries(
      Object.entries(downloads).filter(([key, item]) => typeof key === 'string' && item && typeof item === 'object'),
    ) as SharedState['downloads'],
    progress: Object.fromEntries(
      Object.entries(progress).filter(([key, item]) => typeof key === 'string' && item && typeof item === 'object'),
    ) as SharedState['progress'],
    incognito: typeof parsed.incognito === 'boolean' ? parsed.incognito : undefined,
    coverBlur: parsed.coverBlur === true,
    notificationsEnabled: parsed.notificationsEnabled === true,
    blockedWords: Array.isArray(parsed.blockedWords)
      ? parsed.blockedWords.filter((x): x is string => typeof x === 'string')
      : [],
  };
}

export const tabId = typeof crypto !== 'undefined' ? crypto.randomUUID() : String(Date.now()) + Math.random();
export function createSharedStateStore() {
  let state = initialState;
  const listeners = new Set<() => void>();
  const channel = typeof window !== 'undefined' && 'BroadcastChannel' in window ? new BroadcastChannel(CHANNEL_NAME) : null;
  const notify = () => listeners.forEach((listener) => listener());
  const apply = (next: SharedState, broadcast: boolean) => {
    state = next;
    if (typeof window !== 'undefined') {
      if (broadcast) {
        try {
          window.localStorage.setItem(STATE_KEY, String(Date.now()) + Math.random());
        } catch {
          /* SSE remains authoritative when storage is unavailable. */
        }
      }
      if (broadcast) channel?.postMessage({ kind: 'invalidate' });
    }
    notify();
  };
  const onStorage = (event: StorageEvent) => {
    if (event.key === STATE_KEY) window.dispatchEvent(new Event('hp:invalidate'));
  };
  const onMessage = (event: MessageEvent) => {
    if (event.data?.kind === 'invalidate') window.dispatchEvent(new Event('hp:invalidate'));
  };
  if (typeof window !== 'undefined') window.addEventListener('storage', onStorage);
  channel?.addEventListener('message', onMessage);
  return {
    getSnapshot: () => state,
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    setState(update: Partial<SharedState> | ((current: SharedState) => SharedState), broadcast = true) {
      const next = typeof update === 'function' ? update(state) : { ...state, ...update };
      apply(normalizeState({ ...next, collections: { ...next.collections } }), broadcast);
    },
    destroy() {
      if (typeof window !== 'undefined') window.removeEventListener('storage', onStorage);
      channel?.removeEventListener('message', onMessage);
      channel?.close();
      listeners.clear();
    },
  };
}

export const sharedStateStore = createSharedStateStore();
export function useSharedState() {
  return useSyncExternalStore(sharedStateStore.subscribe, sharedStateStore.getSnapshot, () => initialState);
}
export function usePageLifecycle(onVisibility?: (visible: boolean) => void) {
  useEffect(() => {
    if (typeof document === 'undefined') return;
    const handler = () => onVisibility?.(document.visibilityState === 'visible');
    document.addEventListener('visibilitychange', handler);
    window.addEventListener('pageshow', handler);
    window.addEventListener('pagehide', handler);
    return () => {
      document.removeEventListener('visibilitychange', handler);
      window.removeEventListener('pageshow', handler);
      window.removeEventListener('pagehide', handler);
    };
  }, [onVisibility]);
}

const scrollPositions = new Map<string, number>();
export function useScrollRestoration(routeKey: string, incognito: boolean | undefined, documentScroll: boolean) {
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const previous = window.history.scrollRestoration;
    window.history.scrollRestoration = 'manual';
    if (!documentScroll)
      return () => {
        window.history.scrollRestoration = previous;
      };
    const storageKey = `hp-scroll:${routeKey}`;
    let stored: string | null = null;
    if (incognito === false) {
      try {
        stored = sessionStorage.getItem(storageKey);
      } catch {
        /* Scroll restoration falls back to this tab's memory. */
      }
    }
    const saved = Number(stored ?? scrollPositions.get(routeKey) ?? 0);
    let finished = false;
    let frame: number | undefined;
    const target = Number.isFinite(saved) ? saved : 0;
    const finish = () => {
      finished = true;
      observer.disconnect();
      if (frame !== undefined) cancelAnimationFrame(frame);
      frame = undefined;
    };
    const restore = () => {
      frame = undefined;
      if (finished) return;
      const fragment = routeKey.split('#')[1];
      if (fragment) {
        let id: string;
        try {
          id = decodeURIComponent(fragment);
        } catch {
          finish();
          return;
        }
        const anchor = document.getElementById(id);
        if (anchor) {
          let parent: HTMLElement | null = anchor;
          while (parent) {
            if (parent instanceof HTMLDetailsElement) parent.open = true;
            parent = parent.parentElement;
          }
          finish();
          anchor.scrollIntoView({ block: 'start' });
          anchor.focus({ preventScroll: true });
        }
        return;
      }
      if (target === 0 || document.documentElement.scrollHeight >= target + window.innerHeight) {
        finish();
        window.scrollTo({ top: target, behavior: 'auto' });
      }
    };
    const schedule = () => {
      if (!finished && frame === undefined) frame = requestAnimationFrame(restore);
    };
    const persist = () => {
      const top = window.scrollY;
      scrollPositions.set(routeKey, top);
      if (sharedStateStore.getSnapshot().incognito === false) {
        try {
          sessionStorage.setItem(storageKey, String(top));
        } catch {
          /* Optional scroll cache is unavailable. */
        }
      }
    };
    window.addEventListener('scroll', persist, { passive: true });
    window.addEventListener('pagehide', persist);
    const observer = new ResizeObserver(schedule);
    observer.observe(document.body);
    const timeout = setTimeout(() => {
      observer.disconnect();
      schedule();
    }, routeKey.includes('#') ? 20000 : 3000);
    schedule();
    return () => {
      clearTimeout(timeout);
      finish();
      window.removeEventListener('pagehide', persist);
      window.removeEventListener('scroll', persist);
      window.history.scrollRestoration = previous;
    };
  }, [routeKey, incognito, documentScroll]);
}

export function downloadKey(input: DownloadIdentity) {
  return downloadTaskId({ ...input, variant: input.variant ?? 'original' });
}

const pendingDownloads = new Map<string, Promise<unknown>>();
export function dedupeDownload<T>(input: DownloadIdentity, create: () => Promise<T>): Promise<T> {
  const key = downloadKey(input);
  const existing = pendingDownloads.get(key);
  if (existing) return existing as Promise<T>;
  const task = create().finally(() => pendingDownloads.delete(key));
  pendingDownloads.set(key, task);
  return task;
}

export function useMediaLifecycle(
  media: HTMLMediaElement | null,
  progressKey: string,
  onProgress?: (progress: ProgressState) => void,
) {
  useEffect(() => {
    if (!media) return;
    let lastSaved = 0;
    const save = () => {
      if (Number.isFinite(media.currentTime) && media.readyState >= 1) {
        onProgress?.({
          position: media.currentTime,
          duration: Number.isFinite(media.duration) ? media.duration : undefined,
          updatedAt: Date.now(),
        });
      }
    };
    const schedule = () => {
      if (Date.now() - lastSaved >= 2000) {
        lastSaved = Date.now();
        save();
      }
    };
    const onVisibility = () => {
      if (document.visibilityState === 'hidden') save();
    };
    media.addEventListener('timeupdate', schedule);
    media.addEventListener('pause', save);
    document.addEventListener('visibilitychange', onVisibility);
    window.addEventListener('pagehide', save);
    return () => {
      save();
      media.removeEventListener('timeupdate', schedule);
      media.removeEventListener('pause', save);
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('pagehide', save);
    };
  }, [media, progressKey, onProgress]);
}
