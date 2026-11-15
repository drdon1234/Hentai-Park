import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from 'react';
import { type ApiWork, type Source, type DiscoveryShelf } from './api.js';
import { ContentShelf } from './browse-ui.js';
import { errorMessage } from './page-ui.js';
import { t, pluginText } from './i18n.js';

import {usePreferences} from './preferences.js';
import { browseSession } from './browse-session-cache.js';

/** Each displayed source owns its request and cursor, just as an Android feed session does. */
export function HomeSource({ source, visible, directory, hiddenWorks = false, saving = false, onToggleHidden, navigate, renderItem }: {
  source: Source; visible: boolean; directory: boolean;
  hiddenWorks?: boolean; saving?: boolean; onToggleHidden?: () => void;
  navigate: (url: string) => void; renderItem: (work: ApiWork) => ReactNode;
}) {
  const prefs=usePreferences();directory=directory||prefs.settings.dataSavingMode!=='off';
  const root = useRef<HTMLElement>(null);
  const [activated, setActivated] = useState(false);
  const manifest = source.manifest ?? {};
  const feeds = manifest.feeds as Array<{key:string;label?:string;options?:Array<{key:string;default?:unknown}>}> | undefined;
  const feed = String(manifest.defaultFeed ?? feeds?.[0]?.key ?? '');
  const filters = JSON.stringify(Object.fromEntries((feeds?.find(item => item.key === feed)?.options ?? []).filter(option => option.default !== undefined).map(option => [option.key,option.default])));
  const identity = JSON.stringify([source.source,source.updatedAt,source.enabled,source.installed,source.manifest,feed,filters]);
  const session = useMemo(() => browseSession(source,feed,filters),[identity]);
  const snapshot = useSyncExternalStore(session.subscribe,session.getSnapshot);
  const {pages,loading,error} = snapshot;
  const canLoad = prefs.ready && !directory && !hiddenWorks && (manifest.capabilities as Record<string,unknown> | undefined)?.feed === true && !!feed;
  const name = pluginText(manifest, String(manifest.name ?? source.source));
  const href = '/source/' + encodeURIComponent(source.source);

  useEffect(() => {
    const element = root.current;
    if (!element || !visible || !canLoad || activated) return;
    const observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) { setActivated(true); observer.disconnect(); }
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, [visible, canLoad, activated]);

  // Navigation replaces views, but successful pages belong to the shared source session.
  useEffect(() => { if (activated && visible && canLoad && !error) void session.load(); if ((!visible || !canLoad) && session.getSnapshot().loading) session.pause(); }, [activated,visible,canLoad,session,snapshot,error]);
  useLayoutEffect(() => {
    if (!visible || !canLoad) return;
    const track = root.current?.querySelector<HTMLElement>('.shelf-track');
    if (!track) return;
    track.scrollLeft = session.scrollLeft;
    const save = () => { if (track.isConnected && track.getClientRects().length) session.scrollLeft = track.scrollLeft; };
    track.addEventListener('scroll',save,{passive:true});
    return () => { track.removeEventListener('scroll',save); };
  }, [session,pages.length,visible,canLoad]);

  const items: ApiWork[] = [];
  const seen = new Set<string>();
  for (const page of pages) {
    const sections = page.sections;
    const grouped = new Set(sections?.flatMap(section => section.items.map(item => item.workId)) ?? []);
    // Android's home preview appends section items in source order to one shelf.
    // Full source pages retain their section boundaries and real pagination.
    const ordered = [...(sections?.flatMap(section => section.items) ?? []), ...page.items.filter(item => !grouped.has(item.workId))];
    for (const item of ordered) { const key=JSON.stringify([item.source,item.workId]); if (!seen.has(key)) { seen.add(key); items.push(item); } }
  }
  const shelf: DiscoveryShelf = {key:source.source,source:source.source,feedKey:feed,title:name,items};
  const nextCursor = pages.at(-1)?.page.nextCursor;
  const loadNext = useCallback(() => { if (nextCursor) void session.load(true); }, [nextCursor,session]);
  if(directory)return <a className="source-directory-card" href={href} hidden={!visible} onClick={event=>{if(event.button===0&&!event.ctrlKey&&!event.metaKey&&!event.shiftKey&&!event.altKey){event.preventDefault();navigate(href);}}}><span>{name}</span><svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="m9 5 7 7-7 7"/></svg></a>;
  return <section ref={root} hidden={!visible} className="source-shelves" data-home-source={source.source} aria-busy={loading}>
    <div className="section-header source-heading"><h2><a href={href} onClick={event => {if(event.button===0&&!event.ctrlKey&&!event.metaKey&&!event.shiftKey&&!event.altKey){event.preventDefault();navigate(href);}}}>{name}</a></h2><div className="source-heading-actions">{!directory && (manifest.capabilities as Record<string,unknown> | undefined)?.feed === true && onToggleHidden ? <button className="source-visibility" disabled={saving} aria-pressed={hiddenWorks} aria-label={t(hiddenWorks ? '显示该站点的作品并自动加载' : '隐藏该站点的作品并停止自动加载')} title={t(hiddenWorks ? '显示该站点的作品并自动加载' : '隐藏该站点的作品并停止自动加载')} onClick={onToggleHidden}><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>{hiddenWorks?<path d="m3 3 18 18"/>:null}</svg></button>:null}<a href={href} onClick={event => {if(event.button===0&&!event.ctrlKey&&!event.metaKey&&!event.shiftKey&&!event.altKey){event.preventDefault();navigate(href);}}}>{t('进入站点')}</a></div></div>
    {canLoad ? <>
      {pages.length ? <ContentShelf shelf={shelf} heading={false} local navigate={navigate} renderItem={renderItem} onReachEnd={visible && nextCursor && !loading && !error ? loadNext : undefined} /> : null}
      {!pages.length && (!activated || loading) ? <p className="source-feed-status" role="status">{t('正在加载')}</p> : null}
      {error ? <div className="source-feed-status" role="status"><p>{errorMessage(error)}</p><button className="chip" onClick={() => void session.retry()}>{t('重试')}</button></div> : null}
    </> : !directory && !hiddenWorks && (manifest.capabilities as Record<string,unknown> | undefined)?.subscription ? <div className="source-feed-actions"><a className="chip" href={'/channel/' + encodeURIComponent(source.source)} onClick={event => {if(event.button===0&&!event.ctrlKey&&!event.metaKey&&!event.shiftKey&&!event.altKey){event.preventDefault();navigate(event.currentTarget.getAttribute('href')!);}}}>{t('打开频道')}</a><p className="muted">{t('此站点不提供公开推荐，使用上方的可用入口浏览。')}</p></div> : !directory && !hiddenWorks ? <p className="muted">{t((manifest.capabilities as Record<string,unknown> | undefined)?.reverseSearch || (manifest.capabilities as Record<string,unknown> | undefined)?.metadataSearch || manifest.rankingOnly ? '此站点不提供公开推荐，使用上方的可用入口浏览。' : '此来源不提供公开目录，可从已收藏作品或作品直达链接进入。')}</p> : null}
  </section>;
}
