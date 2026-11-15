import { api, ApiError, type DomainEvent, type Source } from './api.js';
import { t } from './i18n.js';

type FeedPage = Awaited<ReturnType<typeof api.works>>;
type Snapshot = { pages: FeedPage[]; loading: boolean; error?: unknown };
const lifetime = 15 * 60 * 1000;
const sessions = new Map<string, BrowseSession>();
const canonical = (value: unknown): unknown => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ? Object.fromEntries(Object.entries(value).sort(([a],[b]) => a.localeCompare(b)).map(([key,item]) => [key,canonical(item)])) : value;

/** A tab-local feed session. It retains API descriptors, never media tokens or URLs. */
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
  constructor(readonly source: string, readonly identity: string, readonly feed: string, readonly filters: string) {}
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); if (!this.listeners.size && this.request) { this.generation++; this.request.abort(); this.request = undefined; this.snapshot = {...this.snapshot, loading:false}; } }; };
  getSnapshot = () => this.snapshot;
  private update(next: Snapshot) { this.snapshot = next; for (const listener of this.listeners) listener(); }
  pause() { this.generation++; this.request?.abort(); this.request = undefined; this.update({...this.snapshot,loading:false}); }
  reset(notify = true) { this.generation++; this.request?.abort(); this.request = undefined; this.cursors.clear(); this.written = 0; this.scrollLeft = 0; if (notify) this.update({pages:[],loading:false}); else this.snapshot = {pages:[],loading:false}; }
  async load(more = false) {
    this.touched = Date.now();
    if (this.request) return;
    if (!more && !this.snapshot.error && this.snapshot.pages.length && Date.now() - this.written < lifetime) return;
    const cursor = more ? this.snapshot.pages.at(-1)?.page.nextCursor : undefined;
    if (more && !cursor) return;
    const generation = ++this.generation, request = this.request = new AbortController();
    this.failedMore = more;
    this.update({...this.snapshot, loading:true, error:undefined});
    try {
      const page = await api.works({source:this.source,feed:this.feed,filters:this.filters,limit:20,cursor:cursor ?? undefined},request.signal);
      if (generation !== this.generation || request.signal.aborted) return;
      if (!more) this.cursors.clear();
      if (cursor) this.cursors.add(cursor);
      const repeated = page.page.nextCursor && this.cursors.has(page.page.nextCursor);
      this.written = Date.now();
      if (repeated) this.failedMore = false;
      this.update({pages:more ? [...this.snapshot.pages,page] : [page],loading:false,error:repeated ? new Error(t('分页链接重复，请重试重新加载。')) : undefined});
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
  window.dispatchEvent(new CustomEvent('hp:browse-invalidated',{detail:{source}}));
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
