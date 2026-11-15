import {t} from './i18n.js';
import { useEffect, useState } from 'react';
import { EmptyState, StatusMessage } from '@hentai-park/design-system';
import { api, allPages, ApiError } from './api.js';

function message(error: unknown) { return error instanceof ApiError ? (error.code ? error.code + '：' : '') + error.message : error instanceof Error ? error.message : t("请求失败"); }
function useRankingQuery<T>(load: (signal: AbortSignal) => Promise<T>, identity: string) {
  const [state, setState] = useState<{ data?: T; loading: boolean; error?: unknown }>({ loading: true });
  const [attempt, setAttempt] = useState(0);
  useEffect(() => { const control = new AbortController(); setState({ loading: true }); void load(control.signal).then(data => { if (!control.signal.aborted) setState({ data, loading: false }); }).catch(error => { if (!control.signal.aborted) setState({ error, loading: false }); }); return () => control.abort(); }, [identity, attempt]);
  return { ...state, retry: () => setAttempt(value => value + 1) };
}
function jump(event: React.MouseEvent, href: string, navigate: (to: string) => void) { if (event.button === 0 && !event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) { event.preventDefault(); navigate(href); } }

export function RankingsPage({ search, navigate }: { search: string; navigate: (to: string) => void }) {
  const params = new URLSearchParams(search); const source = params.get('source') ?? ''; const board = params.get('board') ?? ''; const cursor = params.get('cursor') ?? ''; const rawOptions = params.get('options') ?? '';
  let options: Record<string, unknown> = {}; let optionError = '';
  try { if (rawOptions) { const value: unknown = JSON.parse(rawOptions); if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('invalid'); options = value as Record<string, unknown>; } } catch { optionError = t("URL 中的榜单选项无效，请重新选择条件。"); }
  const [draftSource, setDraftSource] = useState(source); const [draftBoard, setDraftBoard] = useState(board); const [draftOptions, setDraftOptions] = useState(options);
  const [revision, setRevision] = useState(0);
  useEffect(() => { const changed = () => setRevision(value => value + 1); window.addEventListener('hp:server-update', changed); return () => window.removeEventListener('hp:server-update', changed); }, []);
  useEffect(() => { setDraftSource(source); setDraftBoard(board); setDraftOptions(options); }, [source, board, rawOptions]);
  const sources = useRankingQuery(() => allPages(api.sources), 'sources:' + revision);
  const eligible = (sources.data ?? []).filter(item => item.installed !== false && item.enabled && Array.isArray(item.manifest?.rankings) && item.manifest.rankings.length);
  const declarations = (key: string) => { const value = eligible.find(item => item.source === key)?.manifest?.rankings; return Array.isArray(value) ? value as Array<{ key: string; label: string; metric?: string; category?: string }> : []; };
  const activeBoard = declarations(source).find(item => item.key === board);
  const optionState = useRankingQuery(signal => draftSource && draftBoard ? api.rankingOptions(draftSource, draftBoard, signal) : Promise.resolve(null), JSON.stringify(['options', draftSource, draftBoard, revision]));
  const results = useRankingQuery(signal => source && board && !optionError ? api.rankings({ source, board, options: rawOptions || undefined, cursor: cursor || undefined, limit: 24 }, signal) : Promise.resolve(null), JSON.stringify(['rows', source, board, rawOptions, cursor, revision]));
  const target = (nextCursor?: string) => '/rankings?source=' + encodeURIComponent(source) + '&board=' + encodeURIComponent(board) + (rawOptions ? '&options=' + encodeURIComponent(rawOptions) : '') + (nextCursor ? '&cursor=' + encodeURIComponent(nextCursor) : '');
  const external = (url: string | undefined) => { try { const value = new URL(url ?? ''); return value.protocol === 'https:' && !value.username && !value.password ? value.href : undefined; } catch { return undefined; } };
  return <>
    <section className="page-header"><div><h1>{t("排行榜")}</h1><p>{t("榜单与选项来自站点声明，名次和指标保留原站含义。")}</p></div><a href="/discover" onClick={event => jump(event, '/discover', navigate)}>{t("返回发现")}</a></section>
    {sources.error ? <StatusMessage tone="danger" title={t("榜单站点读取失败")}>{message(sources.error)}<button className="chip" onClick={sources.retry}>{t("重试站点")}</button></StatusMessage> : null}
    <form className="settings-panel" aria-label={t("榜单条件")} onSubmit={event => { event.preventDefault(); const selected = { ...draftOptions }; for (const item of optionState.data?.items ?? []) if (selected[item.key] === undefined && item.default !== undefined) selected[item.key] = item.default; navigate('/rankings?source=' + encodeURIComponent(draftSource) + '&board=' + encodeURIComponent(draftBoard) + (Object.keys(selected).length ? '&options=' + encodeURIComponent(JSON.stringify(selected)) : '')); }}>
      <label>{t("榜单站点")}<select aria-label={t("榜单站点")} value={draftSource} onChange={event => { setDraftSource(event.target.value); setDraftBoard(declarations(event.target.value)[0]?.key ?? ''); setDraftOptions({}); }}><option value="">{t("选择站点")}</option>{eligible.map(item => <option key={item.source} value={item.source}>{String(item.manifest?.name ?? item.source)}</option>)}</select></label>
      <label>{t("榜单")}<select aria-label={t("榜单")} value={draftBoard} onChange={event => { setDraftBoard(event.target.value); setDraftOptions({}); }}><option value="">{t("选择榜单")}</option>{declarations(draftSource).map(item => <option key={item.key} value={item.key}>{item.label}</option>)}</select></label>
      {optionState.loading && draftBoard ? <p role="status">{t("正在加载榜单选项")}</p> : null}
      {optionState.error ? <StatusMessage tone="danger" title={t("榜单选项读取失败")}>{message(optionState.error)}<button className="chip" type="button" onClick={optionState.retry}>{t("重试榜单选项")}</button></StatusMessage> : null}
      {(optionState.data?.items ?? []).map(item => <label key={item.key}>{item.label}<select aria-label={t("榜单选项：") + item.label} value={String(draftOptions[item.key] ?? item.default ?? '')} onChange={event => { const selected = item.values.find(value => String(value.value) === event.target.value); setDraftOptions(current => { const next = { ...current }; if (selected) next[item.key] = selected.value; else delete next[item.key]; return next; }); }}><option value="">{t("来源默认")}</option>{item.values.map(value => <option key={String(value.value)} value={String(value.value)}>{value.label}</option>)}</select></label>)}
      <button className="primary-link" disabled={!draftSource || !draftBoard || optionState.loading || Boolean(optionState.error)}>{t("查看榜单")}</button>
    </form>
    {optionError ? <StatusMessage tone="danger" title={t("榜单条件无效")}>{optionError}</StatusMessage> : null}
    {activeBoard ? <div className="section-header"><h2>{activeBoard.label}</h2><span>{activeBoard.metric ?? ''}</span></div> : null}
    {!source || !board ? <EmptyState title={t("选择榜单")} detail={t("选择已启用站点及它声明的榜单，再查看真实排名。")} /> : null}
    {results.loading && source && board ? <p role="status">{t("正在加载榜单")}</p> : null}
    {results.error ? <StatusMessage tone="danger" title={t("榜单读取失败")}>{message(results.error)}<button className="chip" onClick={results.retry}>{t("重试榜单")}</button></StatusMessage> : null}
    {results.data?.items.length ? <ol className="chapter-list" aria-label={t("榜单结果")}>{results.data.items.map((item, index) => { const original = external(item.url); const work = item.kind === 'work' && item.workId ? '/work/' + [item.source, item.workId].map(encodeURIComponent).join('/') : undefined; const searchHref = item.kind === 'seller' || work ? undefined : '/search?q=' + encodeURIComponent(item.keyword ?? item.title) + '&scope=all&view=grid'; return <li key={JSON.stringify([item.source, item.kind, item.workId ?? item.url ?? item.keyword ?? item.title, index])}><span><strong>{item.rank}</strong> · {work ? <a href={work} onClick={event => jump(event, work, navigate)}>{item.title}</a> : searchHref ? <a href={searchHref} onClick={event => jump(event, searchHref, navigate)}>{item.title}</a> : <span>{item.title}</span>}<small className="chapter-state">{({ work: t("作品"), actress: t("人物"), seller: t("卖家") })[item.kind]}</small></span>{original ? <a className="chip" href={original} target="_blank" rel="noopener noreferrer">{t("打开原站：")}{item.title}</a> : null}</li>; })}</ol> : results.data && !results.loading ? <EmptyState title={t("榜单暂无结果")} detail={t("当前条件没有返回条目，可修改条件重试。")} /> : null}
    <nav className="action-row" aria-label={t("榜单分页")}>{cursor ? <a className="chip" href={target()} onClick={event => jump(event, target(), navigate)}>{t("返回榜单首页")}</a> : null}{results.data?.page.nextCursor ? <a className="chip" href={target(results.data.page.nextCursor)} onClick={event => jump(event, target(results.data!.page.nextCursor!), navigate)}>{t("下一页榜单")}</a> : null}</nav>
  </>;
}
