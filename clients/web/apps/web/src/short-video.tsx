import {usePreferences} from './preferences.js';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { api } from './api.js';
import { t } from './i18n.js';
import { StateView, useAsync } from './page-ui.js';
import {useSharedState} from './native.js';
import {workIdentityKey} from '@hentai-park/domain-model';

export default function ShortVideoPage({ source, manifest, navigate, renderReader }: { source: string; manifest: Record<string, unknown>; navigate: (href: string) => void; renderReader: (parts: string[],active:boolean) => ReactNode }) {
  const prefs=usePreferences();
  const params = new URLSearchParams(window.location.search);
  const feed = params.get('feed') ?? undefined, link = params.get('link') ?? undefined, filters = params.get('filters') ?? undefined;
  const cursor = params.get('cursor') ?? undefined, requestedWork = params.get('work') ?? undefined;
  const scope = JSON.stringify([source, feed, link, filters]);
  const trail = useRef<Array<{cursor?:string;work?:string}>>([]), priorScope = useRef(scope);
  if (priorScope.current !== scope) { priorScope.current = scope; trail.current = []; }
  const list = useAsync(async signal => ({scope, cursor, page: await api.works({source, feed, link, filters, cursor, limit:24}, signal)}), [scope, cursor], undefined, { cacheKey: 'short-video-list:' + JSON.stringify([scope, cursor]) });
  const page = list.data?.scope === scope && list.data.cursor === cursor ? list.data.page : undefined;
  const listLoading = list.loading || Boolean(list.data && !page);
  const items = page?.items ?? [];
  const workId = requestedWork ?? items[0]?.workId;
  const index = items.findIndex(item => item.workId === workId);
  const href = (work?: string, nextCursor: string | null | undefined = cursor, listMode = false) => {
    const query = new URLSearchParams();
    for (const [key, value] of Object.entries({feed,link,filters,cursor:nextCursor,work,view:listMode?'list':undefined})) if (value !== undefined && value !== null) query.set(key,value);
    return '/source/' + encodeURIComponent(source) + (query.size ? '?' + query.toString() : '');
  };
  const previous = index > 0 ? href(items[index-1]!.workId) : undefined;
  const next = index >= 0 && index + 1 < items.length ? href(items[index+1]!.workId) : undefined;
  const nextCursor = page?.page.nextCursor;
  const nextPage = () => { if (nextCursor) { trail.current.push({cursor,work:items.at(-1)?.workId}); navigate(href(undefined,nextCursor)); } };
  const previousPage = () => { const previous = trail.current.pop(); if (previous) navigate(href(previous.work,previous.cursor ?? null)); };
  const step = (direction: number) => { if (listLoading || list.error) return; if (direction < 0) { if (previous) navigate(previous); else previousPage(); } else if (next) navigate(next); else nextPage(); };
  const stepRef = useRef(step); stepRef.current = step;
  const surface = useRef<HTMLElement>(null), touch = useRef<{x:number;y:number} | null>(null);
  useEffect(() => { surface.current?.focus({preventScroll:true}); }, [workId]);
  const isInteractive = (target: EventTarget | null) => target instanceof Element && Boolean(target.closest('input,textarea,select,button,a,video,audio,[contenteditable="true"],[role="slider"],[role="dialog"]'));
  const blocksSwipe = (target: EventTarget | null) => target instanceof Element && (Boolean(target.closest('input,textarea,select,button,a,[contenteditable="true"],[role="slider"],[role="dialog"],.media-control-layer,.media-settings')));
  useEffect(() => {
    const key = (event: KeyboardEvent) => { if (event.defaultPrevented || event.repeat || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey || isInteractive(event.target) || !surface.current?.contains(document.activeElement)) return; if (event.key==='ArrowUp' || event.key==='ArrowDown') { event.preventDefault(); stepRef.current(event.key==='ArrowUp' ? -1 : 1); } };
    window.addEventListener('keydown',key); return ()=>window.removeEventListener('keydown',key);
  }, []);
  const follow = (event: React.MouseEvent<HTMLAnchorElement>) => { if (event.button!==0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return; event.preventDefault(); navigate(event.currentTarget.getAttribute('href')!); };
  return <section ref={surface} className="short-video-page" tabIndex={0} aria-label={t('短视频浏览')} onTouchStart={event=>{if(event.touches.length!==1 || blocksSwipe(event.target)) {touch.current=null;return;} const point=event.touches[0]!;touch.current={x:point.clientX,y:point.clientY};}} onTouchEnd={event=>{const start=touch.current;touch.current=null;const point=event.changedTouches[0];if(!start || !point || event.touches.length)return;const dy=point.clientY-start.y,dx=point.clientX-start.x;if(Math.abs(dy)>90 && Math.abs(dy)>Math.abs(dx)*2)step(dy<0?1:-1);}} onTouchCancel={()=>{touch.current=null;}}>
    <header className="short-video-header"><h1>{String(manifest.name ?? source)}</h1><nav className="action-row" aria-label={t('短视频导航')}><a href={href(workId,cursor,true)} onClick={follow}>{t('列表')}</a>{workId ? <a href={'/work/'+[source,workId].map(encodeURIComponent).join('/')} onClick={follow}>{t('作品详情')}</a> : null}</nav></header>
    <StateView loading={listLoading && !requestedWork} error={requestedWork ? undefined : list.error} empty={!items.length && !workId}>{prefs.ready?(index>=0?items.slice(Math.max(0,index-Number(prefs.settings.shortVideoRetainedCount)),index+1+Number(prefs.settings.shortVideoPreloadCount)).map(item=><ShortVideoSlot key={item.workId} source={source} workId={item.workId} active={item.workId===workId} renderReader={renderReader}/>):workId?<ShortVideoSlot key={workId} source={source} workId={workId} active renderReader={renderReader}/>:null):null}</StateView>
    {requestedWork && list.error ? <StateView loading={false} error={list.error} empty={false}>{null}</StateView> : null}
    {!listLoading && (!list.error || requestedWork) ? <nav className="short-video-controls" aria-label={t('切换短视频')}>{previous ? <a className="chip" href={previous} onClick={follow}>{t('上一条')}</a> : trail.current.length ? <button className="chip" disabled={Boolean(list.error)} onClick={previousPage}>{t('上一页')}</button> : <button className="chip" disabled>{t('上一条')}</button>}<span role="status">{index>=0 ? (index+1)+' / '+items.length : t('单条播放')}</span>{next ? <a className="chip" href={next} onClick={follow}>{t('下一条')}</a> : nextCursor ? <button className="chip" onClick={nextPage}>{t('加载下一页')}</button> : <button className="chip" disabled>{t(list.error ? '下一条' : '已到末尾')}</button>}</nav> : null}
  </section>;
}

function ShortVideoSlot({source,workId,active,renderReader}:{source:string;workId:string;active:boolean;renderReader:(parts:string[],active:boolean)=>ReactNode}){
 const content=useAsync(async signal=>{const work=await api.work(source,workId,signal);if(work.capabilities.metadataOnly)return undefined;const chapters=await api.chapters(source,workId,{},signal);const chapter=chapters.items.find(item=>!item.nodeType||item.nodeType==='video');if(!chapter)throw Error(t('此作品没有可播放的视频'));return {work,chapter};},[source,workId],undefined,{cacheKey:'short-video-work:'+JSON.stringify([source,workId])});
 const shared=useSharedState(),entry=shared.collections[workIdentityKey({source,id:workId})];const [busy,setBusy]=useState(false),[notice,setNotice]=useState('');
 const saveFavorite=async()=>{if(!content.data||busy)return;setBusy(true);setNotice('');try{await api.setLibrary({source,workId,favorite:!entry?.favorite,version:entry?.version??0});window.dispatchEvent(new Event('hp:invalidate'));}catch(error){setNotice(error instanceof Error?error.message:t('操作未完成，请重试。'));}finally{setBusy(false);}}; const download=async()=>{if(!content.data||busy)return;setBusy(true);setNotice('');try{await api.createDownload({source,workId,chapterId:content.data.chapter.chapterId,variant:'original'});window.dispatchEvent(new Event('hp:invalidate'));setNotice(t('已加入下载队列'));}catch(error){setNotice(error instanceof Error?error.message:t('操作未完成，请重试。'));}finally{setBusy(false);}};
 return <div hidden={!active} data-short-video={workId} aria-hidden={!active}><StateView loading={content.loading} error={content.error} empty={false}>{content.data&&(active||content.data.work.capabilities.videos)?<div className="short-video-stage"><header className="short-video-overlay"><h2>{content.data.work.title}</h2><p>{content.data.work.subtitle??content.data.chapter.title??''}</p><div className="action-row"><button className="chip" disabled={busy||!shared.collectionsReady} aria-pressed={entry?.favorite===true} onClick={()=>void saveFavorite()}>{t(entry?.favorite?'已收藏':'收藏')}</button>{content.data.work.capabilities.videos?<button className="chip" disabled={busy} onClick={()=>void download()}>{t('下载')}</button>:null}<a className="chip" href={'/work/'+[source,workId].map(encodeURIComponent).join('/')}>{t('打开作品')}</a></div>{notice?<p role="status">{notice}</p>:null}</header>{renderReader([source,workId,content.data.chapter.chapterId].map(encodeURIComponent),active)}</div>:null}</StateView></div>;
}
