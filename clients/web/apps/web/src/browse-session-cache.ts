import { api, ApiError, type DomainEvent, type Source } from './api.js';
import { t } from './i18n.js';

type FeedPage = Awaited<ReturnType<typeof api.works>>;
type Snapshot = { pages: FeedPage[]; loading: boolean; error?: unknown };
const lifetime = 15 * 60 * 1000;
const databaseName = 'hentai-park-home-cache';
const databaseVersion = 1;
const storeName = 'feeds';
const maxPersistedFeeds = 128;
const sessions = new Map<string, BrowseSession>();
const canonical = (value: unknown): unknown => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ? Object.fromEntries(Object.entries(value).sort(([a],[b]) => a.localeCompare(b)).map(([key,item]) => [key,canonical(item)])) : value;

type PersistedFeed = { key: string; source: string; identity: string; written: number; pages: FeedPage[] };
let database: Promise<IDBDatabase | undefined> | undefined;
function openDatabase() {
  if (typeof indexedDB === 'undefined') return Promise.resolve(undefined);
  return database ??= new Promise(resolve => {
    try {
      const request = indexedDB.open(databaseName, databaseVersion);
      request.onupgradeneeded = () => request.result.createObjectStore(storeName, { keyPath: 'key' });
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => resolve(undefined);
    } catch { resolve(undefined); }
  });
}
function readPersisted(key: string) {
  return openDatabase().then(db => new Promise<PersistedFeed | undefined>(resolve => {
    if (!db) return resolve(undefined);
    try {
      const request = db.transaction(storeName, 'readonly').objectStore(storeName).get(key);
      request.onsuccess = () => resolve(request.result as PersistedFeed | undefined);
      request.onerror = () => resolve(undefined);
    } catch { resolve(undefined); }
  }));
}
function writePersisted(value: PersistedFeed) {
  void openDatabase().then(db => {
    if (!db) return;
    try {
      const store = db.transaction(storeName, 'readwrite').objectStore(storeName);
      store.put(value);
      const entries: Array<{ key: string; written: number }> = [];
      const request = store.openCursor();
      request.onsuccess = () => {
        const cursor = request.result as IDBCursorWithValue | null;
        if (cursor) {
          const item = cursor.value as PersistedFeed;
          entries.push({ key: item.key, written: Number(item.written) || 0 });
          cursor.continue();
          return;
        }
        entries.sort((a, b) => a.written - b.written);
        for (const item of entries.slice(0, Math.max(0, entries.length - maxPersistedFeeds))) store.delete(item.key);
      };
    } catch { /* Optional browser cache. */ }
  });
}
function removePersisted(source?: string) {
  void openDatabase().then(db => {
    if (!db) return;
    try {
      const transaction = db.transaction(storeName, 'readwrite'), store = transaction.objectStore(storeName);
      if (!source) { store.clear(); return; }
      const request = store.openCursor();
      request.onsuccess = () => { const cursor = request.result as IDBCursorWithValue | null; if (!cursor) return; if ((cursor.value as PersistedFeed).source === source) cursor.delete(); cursor.continue(); };
    } catch { /* Optional browser cache. */ }
  });
}
function contentFingerprint(value: unknown): string {
  const clean = (item: unknown): unknown => Array.isArray(item) ? item.map(clean) : item && typeof item === 'object' ? Object.fromEntries(Object.entries(item).filter(([key]) => key !== 'requestId').sort(([a], [b]) => a.localeCompare(b)).map(([key, child]) => [key, clean(child)])) : item;
  return JSON.stringify(clean(value));
}

/** A feed session backed by memory and IndexedDB. It retains API descriptors, never media URLs. */
export class BrowseSession {
  snapshot: Snapshot = { pages: [], loading: false };
  touched = Date.now();
  written = 0;
  scrollLeft = 0;
  private listeners = new Set<() => void>();
  private request?: AbortController;
  private generation = 0;
  private failedMore = false;
  private cursors = new Set<string>();
  private hydration: Promise<void>;
  constructor(readonly source: string, readonly identity: string, readonly feed: string, readonly filters: string) {
    const key = JSON.stringify([source, identity, feed, JSON.parse(filters)]);
    this.hydration = readPersisted(key).then(cached => {
      if (!cached || cached.identity !== identity || !Array.isArray(cached.pages) || !cached.pages.length) return;
      this.written = cached.written;
      this.update({ pages: cached.pages, loading: false });
    });
  }
  // Route changes temporarily unmount discovery. Keep the request alive so the
  // next visit can reuse the same page instead of fetching the shelf again.
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); } };
  getSnapshot = () => this.snapshot;
  private update(next: Snapshot) { this.snapshot = next; for (const listener of this.listeners) listener(); }
  pause() { this.generation++; this.request?.abort(); this.request = undefined; this.update({...this.snapshot,loading:false}); }
  reset(notify = true) { this.generation++; this.request?.abort(); this.request = undefined; this.cursors.clear(); this.written = 0; this.scrollLeft = 0; if (notify) this.update({pages:[],loading:false}); else this.snapshot = {pages:[],loading:false}; }
  async load(more = false) {
    await this.hydration;
    this.touched = Date.now();
    if (this.request) return;
    if (!more && !this.snapshot.error && this.snapshot.pages.length && Date.now() - this.written < lifetime) return;
    const cursor = more ? this.snapshot.pages.at(-1)?.page.nextCursor : undefined;
    if (more && !cursor) return;
    const generation = ++this.generation, request = this.request = new AbortController();
    this.failedMore = more;
    if (!this.snapshot.pages.length) this.update({...this.snapshot, loading:true, error:undefined});
    try {
      const page = await api.works({source:this.source,feed:this.feed,filters:this.filters,limit:20,cursor:cursor ?? undefined},request.signal);
      if (generation !== this.generation || request.signal.aborted) return;
      if (!more) this.cursors.clear();
      if (cursor) this.cursors.add(cursor);
      const repeated = page.page.nextCursor && this.cursors.has(page.page.nextCursor);
      this.written = Date.now();
      if (repeated) this.failedMore = false;
      const pages = more ? [...this.snapshot.pages, page] : [page];
      const nextError = repeated ? new Error(t('分页链接重复，请重试重新加载。')) : undefined;
      writePersisted({ key: JSON.stringify([this.source, this.identity, this.feed, JSON.parse(this.filters)]), source: this.source, identity: this.identity, written: this.written, pages });
      if (contentFingerprint(this.snapshot.pages) !== contentFingerprint(pages) || this.snapshot.error || this.snapshot.loading || nextError) {
        this.update({pages,loading:false,error:nextError});
      } else {
        this.snapshot = { ...this.snapshot, loading: false };
      }
    } catch (error) {
      if (generation !== this.generation || request.signal.aborted) return;
      const denied = error instanceof ApiError && (error.status === 401 || error.status === 403 || ['AUTH','LOGIN_REQUIRED','NOT_FOUND'].includes(error.code ?? ''));
      this.update({pages:denied ? [] : this.snapshot.pages,loading:false,error});
    } finally { if (generation === this.generation) this.request = undefined; }
  }
  get active() { return this.listeners.size > 0; }
  retry() { return this.load(this.failedMore && this.snapshot.pages.length > 0); }
}

export function browseSession(source: Source, feed: string, filters: string) {
  const identity = JSON.stringify(canonical([source.source,source.updatedAt,source.enabled,source.installed,source.manifest,feed,JSON.parse(filters)]));
  let session = sessions.get(source.source);
  if (session?.identity !== identity) { session?.reset(false); session = new BrowseSession(source.source,identity,feed,filters); sessions.set(source.source,session); }
  session.touched = Date.now();
  for (const [key,entry] of sessions) if (!entry.active && entry !== session && (Date.now() - entry.touched > lifetime || sessions.size > 64)) { entry.reset(); sessions.delete(key); }
  return session;
}

export function clearBrowseSessions(source?: string) {
  for (const entry of sessions.values()) if (!source || source === entry.source) entry.reset();
  removePersisted(source);
  window.dispatchEvent(new CustomEvent('hp:browse-invalidated',{detail:{source}}));
}

export async function clearBrowserBrowseCache() {
  for (const entry of sessions.values()) entry.reset(false);
  const db = await openDatabase();
  if (db) await new Promise<void>((resolve,reject)=>{
    const transaction=db.transaction(storeName,'readwrite');
    transaction.objectStore(storeName).clear();
    transaction.oncomplete=()=>resolve();
    transaction.onerror=()=>reject(transaction.error);
    transaction.onabort=()=>reject(transaction.error);
  });
  window.dispatchEvent(new CustomEvent('hp:browse-invalidated',{detail:{}}));
}

// These are the application settings used by the API's isWorkBlocked projection.
// Source network/plugin settings emit account.updated with payload.source instead.
const contentSettings = new Set(['blockedWords','blockedWorks','blockedAuthors','hidePreviews']);
export function handleBrowseSessionEvent(event: DomainEvent) {
  if (event.eventType === 'sync.required') { clearBrowseSessions(); return; }
  if (event.eventType !== 'plugin.installed' && event.eventType !== 'account.updated') return;
  const payload = event.payload as Record<string,unknown> | undefined;
  if (typeof payload?.source === 'string') { clearBrowseSessions(payload.source); return; }
  if (event.eventType === 'account.updated' && Array.isArray(payload?.keys) && !payload.keys.some(key=>typeof key === 'string' && contentSettings.has(key))) return;
  clearBrowseSessions();
}
