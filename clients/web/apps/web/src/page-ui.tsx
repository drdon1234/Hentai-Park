import { useEffect, useState, type ReactNode } from 'react';
import { EmptyState, StatusMessage } from '@hentai-park/design-system';
import { ApiError } from './api.js';
import { t } from './i18n.js';

const asyncCache = new Map<string, { data: unknown; written: number }>();
function cacheAsync(key: string, data: unknown) {
  asyncCache.set(key, { data, written: Date.now() });
  while (asyncCache.size > 128) asyncCache.delete(asyncCache.keys().next().value!);
}
if (typeof window !== 'undefined') window.addEventListener('hp:browse-invalidated', () => asyncCache.clear());
export function errorMessage(error: unknown) { if (error instanceof ApiError) return error.message; return error instanceof Error ? error.message : t("无法加载内容"); }

export function useAsync<T>(load: (signal: AbortSignal) => Promise<T>, deps: React.DependencyList, releaseDiscarded?: (data: T) => void, options?: { refreshKey?: unknown; cacheKey?: string }) {
  const [attempt, setAttempt] = useState(0);
  const [resumeRefresh, setResumeRefresh] = useState(0);
  const keys = [...deps, attempt];
  const refreshKey = options?.refreshKey;
  const sameKeys = (other: React.DependencyList) => other.length === keys.length && keys.every((value,index)=>Object.is(value,other[index]));
  const cacheKey = options?.cacheKey;
  const cached = cacheKey ? asyncCache.get(cacheKey) : undefined;
  const [state, setState] = useState<{ data?: T; loading: boolean; refreshing?: boolean; error?: unknown; keys: React.DependencyList; refreshKey?: unknown }>({ data: cached?.data as T | undefined, loading: cached?.data === undefined, refreshing: cached?.data !== undefined, keys, refreshKey });
  useEffect(() => { const retry = () => setAttempt((value) => value + 1); window.addEventListener('hp:retry-read', retry); return () => window.removeEventListener('hp:retry-read', retry); }, []);
  useEffect(() => { const resume = () => { if (state.loading || state.refreshing || state.error) { if (state.data !== undefined && !releaseDiscarded) setResumeRefresh(value=>value+1); else setAttempt(value=>value+1); } }; window.addEventListener('hp:resume-read', resume); return () => window.removeEventListener('hp:resume-read', resume); }, [state.loading, state.refreshing, state.error, state.data, Boolean(releaseDiscarded)]);
  useEffect(() => { let active = true; let resolvedData: T | undefined; const abort = new AbortController(); setState(previous => { const data = !releaseDiscarded && sameKeys(previous.keys) ? previous.data : (cacheKey ? asyncCache.get(cacheKey)?.data as T | undefined : undefined); return { data, loading: data === undefined, refreshing: data !== undefined, keys, refreshKey }; }); void load(abort.signal).then((data) => { if (cacheKey) cacheAsync(cacheKey, data); if (active) { resolvedData = data; setState({ data, loading: false, refreshing: false, error: undefined, keys, refreshKey }); } else releaseDiscarded?.(data); }).catch((error) => { if (active) setState(previous => ({ data: !releaseDiscarded && sameKeys(previous.keys) ? previous.data : (cacheKey ? asyncCache.get(cacheKey)?.data as T | undefined : undefined), loading: false, refreshing: false, error, keys, refreshKey })); }); return () => { active = false; abort.abort(); if (resolvedData !== undefined) releaseDiscarded?.(resolvedData); }; }, [...deps, attempt, refreshKey, resumeRefresh]);
  if (!sameKeys(state.keys)) return {data:undefined,loading:true,refreshing:false,error:undefined};
  if (!Object.is(state.refreshKey,refreshKey)) { const data = releaseDiscarded ? undefined : state.data; return {data,loading:data===undefined,refreshing:data!==undefined,error:undefined}; }
  return state;
}

export function PageHeader({ title, description, children }: { title: string; description?: string; children?: ReactNode }) { return <section className="page-header"><div><h1>{title}</h1>{description ? <p>{description}</p> : null}</div>{children ? <div className="page-header-actions">{children}</div> : null}</section>; }
export function StateView({ loading, error, empty, emptyDetail, emptyAction, children }: { loading?: boolean; error?: unknown; empty?: boolean; emptyDetail?: string; emptyAction?: ReactNode; children: ReactNode }) { if (loading) return <StatusMessage title={t("正在加载")} />; if (error) return <StatusMessage tone="danger" title={t("无法加载内容")}><p>{errorMessage(error)}</p><div className="action-row">{error instanceof ApiError && error.causeCategory === 'source' && /AUTH|LOGIN|VERIFICATION|CLOUDFLARE/.test(error.code ?? '') ? <a className="chip" href="/sources">{t("前往站点登录或验证")}</a> : null}<button className="chip" onClick={() => window.dispatchEvent(new Event('hp:retry-read'))}>{t("重试加载")}</button></div></StatusMessage>; if (empty) return <EmptyState title={t("暂无内容")} detail={emptyDetail ?? t("可调整筛选条件，或返回上一级继续浏览。")} action={emptyAction} />; return <>{children}</>; }

export function useServerVersion(events?: readonly string[]) { const [version, setVersion] = useState(0); useEffect(() => { let timer: ReturnType<typeof setTimeout> | undefined; const invalidate = (event: Event) => { const detail = (event as CustomEvent<{eventTypes?: unknown;path?:string;keys?:unknown}>).detail; const visualSettings=['theme','seedColor','language','desktopScale']; if (event.type === 'hp:committed' && detail?.path === '/api/v1/settings' && Array.isArray(detail.keys) && detail.keys.length>0 && detail.keys.every((key)=>typeof key==='string' && visualSettings.includes(key))) return; const types = detail?.eventTypes; if (events && event.type === 'hp:server-update' && Array.isArray(types) && types.every(value=>typeof value==='string') && !types.includes('sync.required') && !types.some(type=>events.includes(type))) return; if (timer) clearTimeout(timer); timer = setTimeout(() => setVersion((value) => value + 1), 100); }; for (const name of ['hp:server-update', 'hp:committed', 'hp:invalidate']) window.addEventListener(name, invalidate); return () => { if (timer) clearTimeout(timer); for (const name of ['hp:server-update', 'hp:committed', 'hp:invalidate']) window.removeEventListener(name, invalidate); }; }, [JSON.stringify(events)]); return version; }
