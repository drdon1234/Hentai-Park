import {t} from './i18n.js';
import type { DownloadIdentity } from './native.js';
import type { CapabilitySnapshot, DownloadTaskStatus, MediaKind, ReadState, DomainEvent as ModelDomainEvent, EventType, WorkTag } from '@hentai-park/domain-model';
import type { CapabilitySet } from '@hentai-park/source-contract';

const API_BASE = (((import.meta as ImportMeta & { env?: Record<string, string> }).env?.VITE_API_BASE_URL) ?? '').replace(/\/$/, '');

export type DiscoveryShelf = { key: string; source: string; sourceName?: string; category?: string; title: string; feedKey?: string; sectionIndex?: number; layout?: string; hasNext?: boolean; itemCount?: number; previewTruncated?: boolean; items: ApiWork[] };
export type PageInfo = { limit: number; nextCursor: string | null };
export type ApiEnvelope<T> = { items: T[]; page: PageInfo; requestId: string; [key: string]: unknown };
export type ApiErrorShape = { code?: string; messageKey?: string; retryable?: boolean; requestId?: string; operation?: string; causeCategory?: string; details?: unknown };
export class ApiError extends Error { code?: string; messageKey?: string; retryable = false; requestId?: string; operation?: string; causeCategory?: string; details?: unknown; status: number; constructor(message: string, status: number, shape?: ApiErrorShape) { super(message); this.name = 'ApiError'; this.status = status; Object.assign(this, shape); } }
export type Session = { sessionId: string; mode: 'local' | 'server'; authenticated: boolean; csrfToken?: string; requestId?: string };
export type Source = { source: string; enabled: boolean; installed?: boolean; availableVersion?: string; manifest?: Record<string, unknown>; updatedAt?: string; defaultOrder?: number; status?: string; error?: string };
export type VoiceNodeType = 'directory' | 'audio' | 'video' | 'subtitle' | 'image' | 'script' | 'other';
export type ApiWork = { source: string; workId: string; blocked?:boolean; previewOnly?:boolean; title: string; presentation?:'post'|'work'; sourceUrl: string; mediaKind: MediaKind; version: number; updatedAt: string;contentUpdatedAt?:string|null; category: string; tags?: WorkTag[]; cover?: string | null; coverAuthorization?: MediaTokenRequest; summary?: string | null; unreadCount?:number|null;downloaded?:boolean;coverAspect?:number;coverBlurred?:boolean;subtitle?:string;duration?:string|number;uploaded?:string;pages?:number;likes?:number;views?:number;rating?:number;badge?:string;language?:string;editions?:string[];voiceMediaForm?:string;voiceLanguageStatus?:string;workCode?:string;actors?:string[];authors?:Array<string|{name?:string;label?:string}>;capabilities: CapabilitySnapshot & CapabilitySet; voiceRoot?: { id: string; name: string; type: VoiceNodeType }; voiceSubtitles?: Record<string, string[]>; requestId?: string };
export type ApiChapter = { source: string; workId: string; chapterId: string; title: string; nodeType?: VoiceNodeType; readState: ReadState; pageProgress: number | null; videoPosition: number | null; duration: number | null; version: number; mediaAuthorization?: MediaTokenRequest | null };
export type ImageTransform = { type: 'unscramble-strips'; segments: number };
export type WebPlayer = { playerId: string; frameUrl: string; audioUrl: string; controlUrl: string; statusUrl: string; expiresAt: number };
export type WebPlayerStatus = { paused: boolean; position: number; duration: number | null; rate: number; muted: boolean; hasAudio: boolean; state: 'ready' | 'loading' | 'verification_required' | 'failed' | 'closed'; viewport: { width: number; height: number } };
export type WebPlayerControl = { action: 'play' | 'pause' | 'seek' | 'rate' | 'click' | 'key' | 'close'; position?: number; rate?: number; x?: number; y?: number; key?: string };
export type ArticleBlock = {type:'text';text:string}|{type:'image';mediaAuthorization:MediaTokenRequest}|{type:'video';id:string;previewAuthorization?:MediaTokenRequest};
export type AlbumMedia={hiddenByPreferences?:boolean;id:string;type:'image'|'video';order?:number;previewOnly:boolean;blurred:boolean;mediaAuthorization:MediaTokenRequest;previewAuthorization?:MediaTokenRequest};
export type AlbumItem={blocked?:boolean;id:string;source:string;title:string;text:string;date:string;presentation:'post'|'work';locked:boolean;coverBlurred:boolean;media:AlbumMedia[]};
export type ReaderPayload = ApiChapter & { workTitle: string; category: string;liveChatAvailable?:boolean; webPlayer?: WebPlayer; blocks?:ArticleBlock[];tagLinks?:Array<{name:string;url:string}>; pages?: Array<{ mediaAuthorization: MediaTokenRequest; index: number; alt?: string; width?: number; height?: number; transform?: ImageTransform }>; mediaKind: MediaKind; content?: string; paragraphs?:string[];textOffset?:number;textLength?:number; subtitles?: Array<{ mediaAuthorization: MediaTokenRequest; label: string; language?: string }> };
export type MediaTokenRequest = { source: string; resourceKey: string; authorizationId: string };
export type DownloadTask = {recording?:{durationSeconds:number;stopRequested:boolean};mediaKind?:string; taskId: string; source: string; workId: string; chapterId: string; variant: string; workTitle: string; chapterTitle: string; speed: number | null; createdAt: string; status: DownloadTaskStatus; completedCount: number; totalCount: number; bytes: number; failureCode: string | null; recoverable: boolean; updatedAt: string; version: number; requestId?: string };
export type Subscription = { subscriptionId: string; source: string; dimension: string; target: string; enabled: boolean; notify: boolean; baseline: string | null; lastSuccess: string | null; nextDue: string | null; lastCheckedAt: string | null; lastError: string | null; intervalMs: number | null; failures: number; version: number; updatedAt: string };
export type LibraryEntry = { source: string; workId: string; favorite: boolean; favoritedAt?:string|null; categoryIds: string[]; version: number; updatedAt: string };
export type DomainEvent = Omit<Partial<ModelDomainEvent<Record<string, unknown>>>, 'eventType'> & { eventType: EventType | 'sync.required' };
export type HistoryEntry = { nodeType?: VoiceNodeType | null; source: string; workId: string; chapterId?: string | null; chapterTitle?: string | null; page?: number | null; pageCount?: number | null; position?: number | null; duration?:number|null;readState?:ReadState|null;updatedAt?: string };
export type ReverseMatch = { source: string; title: string; keyword?: string; url?: string; description?: string; similarity?: number; uncertain?: boolean; details?: Record<string, unknown>; episode?: string | number; from?: number; to?: number; images?: Array<{ label?: string; similarity?: number; mediaAuthorization: MediaTokenRequest }> };

function uuid() { if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID(); return String(Date.now()) + '-' + Math.random().toString(36).slice(2); }
function requestKey() { return uuid(); }
let csrfToken = '';
let currentSessionId = '';
let documentActive = true;
if (typeof window !== 'undefined') {
  window.addEventListener('pagehide', () => { documentActive = false; });
  window.addEventListener('pageshow', () => {
    const resumed = !documentActive;
    documentActive = true;
    if (resumed) window.dispatchEvent(new Event('hp:resume-read'));
  });
}
export function requestErrorMessage(code?: string) {
  switch (code) {
    case 'NETWORK': case 'HTTP': return t('连接失败，请稍后重试。');
    case 'TIMEOUT': return t('请求超时，请重试。');
    case 'CANCELLED': return t('请求已取消。');
    case 'AUTH': case 'LOGIN_REQUIRED': case 'UNAUTHORIZED': return t('请登录后重试。');
    case 'VERIFICATION_REQUIRED': case 'CLOUDFLARE': return t('请完成站点验证后重试。');
    case 'BLOCKED': case 'FORBIDDEN': case 'PERMISSION_DENIED': return t('当前没有访问此内容的权限。');
    case 'NOT_FOUND': return t('内容不存在或已被移除。');
    case 'RATE_LIMITED': return t('请求过于频繁，请稍后重试。');
    case 'CONFLICT': case 'VERSION_CONFLICT': return t('内容已发生变化，请刷新后重试。');
    case 'UNSUPPORTED': case 'INCOMPATIBLE': return t('此站点暂不支持该操作。');
    case 'MEDIA_SOURCE_BLOCKED': return t('图片或媒体来源地址未通过安全校验，请检查站点或网络设置。');
    case 'VALIDATION': case 'VALIDATION_ERROR': case 'BAD_REQUEST': return t('提交的内容无效，请检查后重试。');
    case 'CONFIRM_REQUIRED': return t('请确认此操作后继续。');
    default: return t('请求失败，请稍后重试。');
  }
}
export async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  if (!documentActive && !init.keepalive) throw new DOMException('The document is inactive', 'AbortError');
  const headers = new Headers(init.headers); headers.set('Accept', 'application/json'); headers.set('x-request-id', uuid());
  if (init.body && !(init.body instanceof FormData)) headers.set('Content-Type', 'application/json');
  if (typeof document !== 'undefined') { const cookie = document.cookie.split(';').map((part) => part.trim()).find((part) => part.startsWith('hp_csrf=')); if (cookie) csrfToken = cookie.slice('hp_csrf='.length); }
  if (init.method && init.method !== 'GET' && csrfToken) headers.set('x-csrf-token', csrfToken);
  const response = await fetch(API_BASE + path, { ...init, headers, credentials: 'include' });
  const body = await response.json().catch((error: unknown) => { if (error instanceof Error && error.name === 'AbortError') throw error; return null; }) as T | { error?: ApiErrorShape } | null;
  const responseRequestId = response.headers.get('x-request-id') ?? undefined;
  if (!response.ok) { const shape = body && typeof body === 'object' && 'error' in body ? body.error : undefined; if (response.status === 401 && shape?.causeCategory !== 'source' && typeof window !== 'undefined') { if (!path.endsWith('/session/login')) window.dispatchEvent(new Event('hp:unauthorized')); } throw new ApiError(requestErrorMessage(shape?.code), response.status, { ...shape, requestId: shape?.requestId ?? responseRequestId }); }
  if (body && typeof body === 'object' && 'csrfToken' in body) csrfToken = String(body.csrfToken ?? '');
  if (body && typeof body === 'object' && 'sessionId' in body && 'authenticated' in body && body.authenticated === true) { const next = String(body.sessionId); if (currentSessionId && currentSessionId !== next) window.dispatchEvent(new Event('hp:session-rotated')); currentSessionId = next; }
  if (path.endsWith('/session/logout')) { csrfToken = ''; currentSessionId = ''; window.dispatchEvent(new Event('hp:unauthorized')); }
  if (response.ok && !path.startsWith('/api/v1/web-player/') && init.method && init.method !== 'GET' && !['/search', '/reverse-search', '/media/tokens', '/backup/export', '/backup/import/preview', '/filter-options', '/session/activity'].some((suffix) => path.endsWith(suffix)) && typeof window !== 'undefined') { let keys: string[] | undefined; if (path === '/api/v1/settings' && typeof init.body === 'string') { try { const parsed = JSON.parse(init.body) as { settings?: unknown }; if (parsed.settings && typeof parsed.settings === 'object' && !Array.isArray(parsed.settings)) keys = Object.keys(parsed.settings); } catch { /* The request body was already accepted by the server. */ } } window.dispatchEvent(new CustomEvent('hp:committed', { detail: { path, keys } })); }
  return body as T;
}
function query(params: Record<string, string | number | undefined>) { const q = new URLSearchParams(); for (const [key, value] of Object.entries(params)) if (value !== undefined && (value !== '' || key === 'categories')) q.set(key, String(value)); const text = q.toString(); return text ? '?' + text : ''; }
export function webPlayerUrl(raw: string, resource: 'status' | 'control' | 'frames' | 'audio') { const url = new URL(raw, window.location.origin); if (url.origin !== window.location.origin || !new RegExp('^/api/v1/web-player/[^/]+/' + resource + '$').test(url.pathname) || url.search || url.hash || url.username || url.password) throw new Error(t("网页播放器资源地址无效。")); return url.pathname; }
const enc = encodeURIComponent;

export const api = {
  activity: () => request('/api/v1/session/activity',{method:'POST'}),
  session: { get: () => request<Session>('/api/v1/session'), login: (token = '') => request<Session>('/api/v1/session/login', { method: 'POST', body: JSON.stringify({ token, requestKey: requestKey() }) }), logout: () => request<Session>('/api/v1/session/logout', { method: 'POST', body: JSON.stringify({ requestKey: requestKey() }) }) },
  discovery: (params: { limit?: number; cursor?: string; source?: string; category?: string; categories?: string } = {}, signal?: AbortSignal) => request<ApiEnvelope<ApiWork>&{shelves:DiscoveryShelf[]}>('/api/v1/discovery' + query(params), { signal }),
  sources: (params: { limit?: number; cursor?: string } = {}) => request<ApiEnvelope<Source>>('/api/v1/sources' + query(params)),
  source: (source: string, signal?:AbortSignal) => request<Source>('/api/v1/sources/' + enc(source), {signal}),
  sourceFilterOptions: (source:string,body:Record<string,unknown>,signal?:AbortSignal) => request<{items:Array<{value:string|number|boolean;label:string;color?:string}>}>('/api/v1/sources/'+enc(source)+'/filter-options',{method:'POST',body:JSON.stringify(body),signal}),
  sourceAction: (source: string, action: 'enable' | 'update' | 'login' | 'verify', body: Record<string, unknown> = {}) => request<Record<string, unknown>>('/api/v1/sources/' + enc(source) + '/' + action, { method: 'POST', body: JSON.stringify({ ...body, requestKey: requestKey() }) }),
  search: (body: { query: string;keywords?:string[];sources?:string[];mediaKind?:string;category?:string; scope?: string; source?: string; filters?: WorkTag['filters']; cursor?: string; limit?: number; requestGeneration?: number }, signal?: AbortSignal) => request<ApiEnvelope<ApiWork>>('/api/v1/search', { method: 'POST', body: JSON.stringify({ ...body, requestGeneration: body.requestGeneration ?? 0 }), signal }),
  reverseSearch: (body: { source: string; contentBase64: string; mimeType: 'image/png' } | { cursor: string }, signal?: AbortSignal) => request<ApiEnvelope<ReverseMatch>>('/api/v1/reverse-search', { method: 'POST', body: JSON.stringify(body), signal }),
  works: (params: { source?: string; category?: string; order?: string; feed?: string; link?:string; filters?: string; cursor?: string; limit?: number } = {}, signal?: AbortSignal) => request<ApiEnvelope<ApiWork> & {sections?:Array<{key:string;title:string;items:ApiWork[]}>}>('/api/v1/works' + query(params), { signal }),
  rankings: (params:{source:string;board:string;options?:string;cursor?:string;limit?:number},signal?:AbortSignal)=>request<ApiEnvelope<{source:string;rank:number;title:string;kind:'work'|'actress'|'seller';workId?:string;url?:string;keyword?:string}>>('/api/v1/rankings'+query(params),{signal}),
  rankingOptions: (source:string,board:string,signal?:AbortSignal)=>request<{items:Array<{key:string;label:string;default?:string|number;values:Array<{value:string|number|boolean;label:string}>}>}>('/api/v1/sources/'+enc(source)+'/rankings/'+enc(board)+'/options',{signal}),
  work: (source: string, workId: string, signal?: AbortSignal) => request<ApiWork>('/api/v1/works/' + enc(source) + '/' + enc(workId), { signal }),
  chapters: (source: string, workId: string, params: { directoryId?: string; cursor?: string; limit?: number } = {}, signal?: AbortSignal) => request<ApiEnvelope<ApiChapter>>('/api/v1/works/' + enc(source) + '/' + enc(workId) + '/chapters' + query(params), { signal }),
  album:(source:string,scope:string,cursor?:string,signal?:AbortSignal)=>request<ApiEnvelope<AlbumItem>>('/api/v1/albums/'+enc(source)+query({scope,cursor}),{signal}),
  articleMedia:(source:string,workId:string,mediaId:string,signal?:AbortSignal,showBlocked=false)=>request<ReaderPayload>('/api/v1/articles/'+[source,workId,'media',mediaId].map(enc).join('/')+(showBlocked?'?showBlocked=true':''),{signal}),
  reader: (source: string, workId: string, chapterId: string, signal?: AbortSignal, showBlocked=false) => request<ReaderPayload>('/api/v1/reader/' + enc(source) + '/' + enc(workId) + '/' + enc(chapterId)+query({showBlocked:showBlocked?'true':undefined}), { signal }),
  library: (params: { cursor?: string; limit?: number } = {}) => request<ApiEnvelope<LibraryEntry>>('/api/v1/library' + query(params)),
  setLibrary: (body: { source: string; workId: string; favorite?: boolean; categoryIds?: string[]; version?: number }) => request<LibraryEntry>('/api/v1/library', { method: 'POST', body: JSON.stringify({ ...body, requestKey: requestKey() }) }),
  history: (params: { cursor?: string; limit?: number; source?: string; workId?: string; resume?: boolean; categories?: string; category?: string; uniqueWorks?: boolean } = {}) => request<ApiEnvelope<HistoryEntry>>('/api/v1/history' + query({...params,resume:params.resume ? 'true' : undefined,uniqueWorks:params.uniqueWorks ? 'true' : undefined})),
  saveHistory: (source: string, workId: string, chapterId: string, body: { page?: number; pageCount?: number; position?: number; duration?: number; textOffset?:number;textLength?:number;version?: number }) => request<(HistoryEntry & { saved: true; version:number }) | { saved: false }>('/api/v1/history/' + enc(source) + '/' + enc(workId) + '/' + enc(chapterId), { method: 'PATCH', body: JSON.stringify({ ...body, requestKey: requestKey() }), keepalive: true }),
  downloads: (params: { cursor?: string; limit?: number } = {}) => request<ApiEnvelope<DownloadTask>>('/api/v1/downloads' + query(params)),
  createDownload: (input: DownloadIdentity) => request<DownloadTask>('/api/v1/downloads', { method: 'POST', body: JSON.stringify({ ...input, requestKey: requestKey() }) }),
  downloadAction: (id: string, action: 'pause' | 'resume' | 'retry' | 'cancel') => request<DownloadTask>('/api/v1/downloads/' + enc(id) + '/' + action, { method: 'POST', body: JSON.stringify({ requestKey: requestKey() }) }),
  deleteDownload: (id: string) => request<Record<string, unknown>>('/api/v1/downloads/' + enc(id), { method: 'DELETE', body: JSON.stringify({ requestKey: requestKey() }) }),
  subscriptions: (params: { cursor?: string; limit?: number } = {}) => request<ApiEnvelope<Subscription> & { unreadCount?: number; unreadEventIds?: string[] }>('/api/v1/subscriptions' + query(params)),
  createSubscription: (body: Pick<Subscription, 'source' | 'dimension' | 'target' | 'enabled' | 'notify'>) => request<Subscription>('/api/v1/subscriptions', { method: 'POST', body: JSON.stringify({ ...body, requestKey: requestKey() }) }),
  updateSubscription: (id: string, body: Partial<Subscription>) => request<Subscription>('/api/v1/subscriptions/' + enc(id), { method: 'PATCH', body: JSON.stringify({ ...body, requestKey: requestKey() }) }),
  deleteSubscription: (id: string, keepEvents = true) => request<Record<string, unknown>>('/api/v1/subscriptions/' + enc(id), { method: 'DELETE', body: JSON.stringify({ keepEvents, requestKey: requestKey() }) }),
  checkSubscription: (id: string) => request<Record<string, unknown>>('/api/v1/subscriptions/' + enc(id) + '/check', { method: 'POST', body: JSON.stringify({ requestKey: requestKey() }) }),
  readEvents: (eventIds: string[]) => request<Record<string, unknown>>('/api/v1/events/read', { method: 'POST', body: JSON.stringify({ eventIds, requestKey: requestKey() }) }),
  settings: () => request<{ settings: Record<string, unknown>; version: number }>('/api/v1/settings'),
  updateSettings: (settings: Record<string, unknown>, version?: number) => request<{ settings: Record<string, unknown>; version: number }>('/api/v1/settings', { method: 'PATCH', body: JSON.stringify({ settings, version, requestKey: requestKey() }) }),
  backupExport: async (include?: string[]) => { const { requestId: _requestId, ...backup } = await request<Record<string, unknown>>('/api/v1/backup/export', { method: 'POST', body: JSON.stringify({ include, requestKey: requestKey() }) }); return backup; },
  backupPreview: (backup: Record<string, unknown>) => request<{partitions: Record<string,{incoming:number;added:number;replaced:number;retained:number;conflicts:number}>;totals:{incoming:number;added:number;replaced:number;retained:number;conflicts:number};restoredSourcesDisabled:boolean;preview:true;canImport:true}>('/api/v1/backup/import/preview', {method:'POST',body:JSON.stringify({backup})}),
  backupImport: (backup: Record<string, unknown>) => request<Record<string, unknown>>('/api/v1/backup/import', { method: 'POST', body: JSON.stringify({ backup, requestKey: requestKey() }) }),
  diagnostics: () => request<Record<string, unknown>>('/api/v1/diagnostics'),
  webPlayerStatus: (url: string, signal?: AbortSignal) => request<WebPlayerStatus>(webPlayerUrl(url, 'status'), { signal }),
  webPlayerControl: (url: string, body: WebPlayerControl, keepalive = false, signal?: AbortSignal) => request<Record<string, unknown>>(webPlayerUrl(url, 'control'), { method: 'POST', body: JSON.stringify({ ...body, requestKey: requestKey() }), keepalive, signal }),
  mediaToken: (input: MediaTokenRequest, signal?: AbortSignal) => request<{ token: string; expiresAt:number }>('/api/v1/media/tokens', { method: 'POST', body: JSON.stringify(input), signal }),
};

export async function allPages<T>(load: (params: { cursor?: string; limit: number }) => Promise<ApiEnvelope<T>>) {
  const items: T[] = []; const seen = new Set<string>(); let cursor: string | undefined;
  do { const page = await load({ cursor, limit: 200 }); items.push(...page.items); const next = page.page?.nextCursor; if (!next) break; if (seen.has(next)) throw new Error(t("服务端返回了重复分页游标")); seen.add(next); cursor = next; } while (cursor);
  return items;
}

export function mediaUrl(token: string, resource?: string) { return API_BASE + '/api/v1/media/' + enc(token) + (resource ? '?resource=' + enc(resource) : ''); }
export function subscribeEvents(onEvent: (event: DomainEvent) => void, signal?: AbortSignal) {
  let lastEventId = ''; let stopped = false; let retry = 500; let timer: ReturnType<typeof setTimeout> | undefined;
  let active: AbortController | undefined; let generation = 0; const seen = new Set<string>();
  const run = async () => {
    if (stopped || !documentActive || signal?.aborted || (typeof document !== 'undefined' && document.hidden)) return;
    const current = ++generation;
    active = new AbortController();
    try {
      const response = await fetch(API_BASE + '/api/v1/events', { headers: { Accept: 'text/event-stream', ...(lastEventId ? { 'Last-Event-ID': lastEventId } : {}) }, credentials: 'include', signal: active.signal });
      if (response.status === 401) window.dispatchEvent(new Event('hp:unauthorized'));
      if (!response.ok || !response.body) throw new Error(t("事件连接失败（") + response.status + '）');
      retry = 500; const reader = response.body.getReader(); const decoder = new TextDecoder(); let buffer = '';
      try {
        while (!stopped && documentActive && current === generation) {
          const next = await reader.read(); if (stopped || !documentActive || current !== generation || next.done) break; buffer += decoder.decode(next.value, { stream: true });
          const blocks = buffer.split(/\r?\n\r?\n/); buffer = blocks.pop() ?? '';
          for (const block of blocks) {
            const lines = block.split(/\r?\n/); const field = (name: string) => lines.filter((line) => line.startsWith(name + ':')).map((line) => line.slice(name.length + 1).replace(/^ /, '')).join('\n');
            const id = field('id'); const data = field('data'); if (!data) continue;
            let event: DomainEvent; try { const eventType = field('event') as DomainEvent['eventType']; if (!eventType) throw new Error('missing event field'); event = { ...JSON.parse(data), eventType }; } catch { onEvent({ eventType: 'sync.required' }); continue; }
            const key = event.eventId ?? id; if (key && seen.has(key)) { if (id) lastEventId = id; continue; }
            onEvent(event); if (id) lastEventId = id;
            if (key) { seen.add(key); if (seen.size > 1000) seen.delete(seen.values().next().value!); }
          }
        }
      } finally { await reader.cancel().catch(() => undefined); reader.releaseLock(); }
    } catch { if (stopped || !documentActive || signal?.aborted) return; }
    if (current === generation) active = undefined;
    if (!stopped && documentActive && current === generation) { timer = setTimeout(() => void run(), retry); retry = Math.min(retry * 2, 10000); }
  };
  const suspend = () => { generation++; active?.abort(); if (timer) clearTimeout(timer); timer = undefined; };
  const reconnect = () => {
    if (stopped || !documentActive || signal?.aborted) return;
    if (typeof document !== 'undefined' && document.hidden) { suspend(); return; }
    if (active && !active.signal.aborted) return;
    suspend(); timer = setTimeout(() => void run(), 0);
  };
  const stop = () => { stopped = true; suspend(); signal?.removeEventListener('abort', stop); if (typeof window !== 'undefined') { window.removeEventListener('online', reconnect); window.removeEventListener('pageshow', reconnect); window.removeEventListener('pagehide', suspend); document.removeEventListener('visibilitychange', reconnect); } };
  signal?.addEventListener('abort', stop, { once: true });
  if (typeof window !== 'undefined') { window.addEventListener('online', reconnect); window.addEventListener('pageshow', reconnect); window.addEventListener('pagehide', suspend); document.addEventListener('visibilitychange', reconnect); }
  void run(); return stop;
}
