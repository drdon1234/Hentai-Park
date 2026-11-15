import { useEffect, useRef, useState, type ReactNode } from 'react';
import { t } from './i18n.js';
import type { ApiWork, DiscoveryShelf } from './api.js';

export const categoryLabels: Record<string, string> = {feed:'吃瓜',doujin:'本子',anime:'里番',aiDrama:'AI短剧',jav:'JAV',adult:'成人视频',shortvideo:'短视频',recording:'录播',gallery:'三次元美图',illustration:'二次元美图',game:'游戏资源',onlineGame:'在线游戏',other:'创作社区',live:'直播',novel:'小说',tavern:'酒馆',asmr:'音声'};
export const domainOrder = ['feed','gallery','illustration','doujin','anime','jav','adult','shortvideo','aiDrama','recording','live','asmr','novel','tavern','onlineGame','game','other'];
export function categoryInScope(category:string,dimension:string,media:string) {
  const twoD=['doujin','anime','illustration','game'];
  const threeD=['gallery','aiDrama','jav','adult','shortvideo','recording','live','novel'];
  const dimensionMatches=dimension==='all'||(dimension==='twoD'?!threeD.includes(category):!twoD.includes(category));
  const kind=['doujin','gallery','illustration'].includes(category)?'image':['anime','aiDrama','jav','adult','shortvideo','recording','live'].includes(category)?'video':category==='asmr'?'voice':'other';
  return dimensionMatches&&(media==='all'||media===kind);
}
export const mediaLabels: Record<string, string> = { comic: '漫画', novel: '小说', video: '视频', voice: '音声', article: '文章', game: '游戏', tavern: '角色卡' };
export const domainHref = (category: string) => '/domain/' + encodeURIComponent(category);
export function shelfHref(shelf: DiscoveryShelf) {
  const base = '/source/' + encodeURIComponent(shelf.source);
  return shelf.sectionIndex !== undefined ? base : shelf.feedKey ? base + '?feed=' + encodeURIComponent(shelf.feedKey) : base;
}

/** A preview keeps the source's order; its link opens the actual source feed. */
export function ContentShelf({ shelf, renderItem, navigate, heading = true, local = false, onReachEnd }: { shelf: DiscoveryShelf; renderItem: (work: ApiWork) => ReactNode; navigate: (url: string) => void; heading?: boolean; local?: boolean; onReachEnd?: () => void }) {
  const track = useRef<HTMLDivElement>(null);
  const tail = useRef<HTMLDivElement>(null);
  const [showBlocked, setShowBlocked] = useState(false);
  const [scrollable, setScrollable] = useState(false);
  const [edges, setEdges] = useState({start:true,end:true});
  const items = showBlocked ? shelf.items : shelf.items.filter(work => !work.blocked);
  useEffect(() => {
    if (!tail.current || !onReachEnd) return;
    const observer = new IntersectionObserver(entries => { if (entries.some(entry => entry.isIntersecting)) { observer.disconnect(); onReachEnd(); } });
    observer.observe(tail.current);
    return () => observer.disconnect();
  }, [onReachEnd]);
  useEffect(() => {
    const element = track.current;
    if (!element) return;
    const cover = element.querySelector<HTMLElement>('.cover');
    const card = element.querySelector<HTMLElement>('.work-card');
    const update = () => {
      setScrollable(element.scrollWidth > element.clientWidth + 2);
      setEdges({start:Math.abs(element.scrollLeft)<2,end:Math.abs(element.scrollLeft)+element.clientWidth>=element.scrollWidth-2});
      const target = cover && cover.getBoundingClientRect().height > 0 ? cover : card;
      if (target && element.parentElement) {
        const bounds = target.getBoundingClientRect();
        element.parentElement.style.setProperty('--shelf-control-center', `${bounds.top + bounds.height / 2 - element.parentElement.getBoundingClientRect().top}px`);
      }
    };
    const observer = new ResizeObserver(update); observer.observe(element); if (cover) observer.observe(cover); if (card) observer.observe(card); update();
    element.addEventListener('scroll',update,{passive:true});
    return () => { observer.disconnect(); element.removeEventListener('scroll',update); };
  }, [items.length]);
  const move = (direction: number) => {
    const element = track.current;
    if (element) element.scrollBy({ left: direction * (getComputedStyle(element).direction === 'rtl' ? -1 : 1) * element.clientWidth * .85, behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' });
  };
  const href = shelfHref(shelf);
  return <section className="content-shelf" tabIndex={-1} id={shelf.sectionIndex === undefined ? undefined : 'section-' + shelf.source + '-' + shelf.sectionIndex} aria-label={shelf.title}>
    <div className="section-header">
      <div>{heading ? <h3>{shelf.title}</h3> : null}</div>
      <div className="shelf-actions">{scrollable ? <><button className="chip shelf-arrow" aria-label={t('向前浏览') + ' · ' + shelf.title} disabled={edges.start} onClick={() => move(-1)}><Arrow previous /></button><button className="chip shelf-arrow" aria-label={t('向后浏览') + ' · ' + shelf.title} disabled={edges.end} onClick={() => move(1)}><Arrow /></button></> : null}{!local ? <a className="shelf-entry-link" href={href} onClick={event => { if (event.button === 0 && !event.ctrlKey && !event.metaKey && !event.altKey && !event.shiftKey) { event.preventDefault(); navigate(href); } }}>{shelf.sectionIndex !== undefined || !shelf.feedKey ? t('进入站点') : t('查看完整列表')}<span className="desktop-link-arrow" aria-hidden="true"><Arrow /></span></a> : null}</div>
    </div>
    {shelf.items.some(work => work.blocked) ? <button className="chip" aria-pressed={showBlocked} onClick={() => setShowBlocked(value => !value)}>{showBlocked ? t('应用屏蔽规则') : t('临时显示原始结果')}</button> : null}
    {items.length ? <div className={'shelf-carousel'+(scrollable?' is-scrollable':'')}><button className="shelf-side shelf-side-start" aria-label={t('向前浏览')+' · '+shelf.title} disabled={edges.start} onClick={()=>move(-1)}><Arrow previous full /></button><div className={'shelf-track shelf-' + (items[0]?.mediaKind ?? 'comic')} ref={track} tabIndex={0} role="region" aria-label={shelf.title + ' · ' + t('横向浏览')} onKeyDown={event => { if (event.target !== event.currentTarget) return; if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') { event.preventDefault(); move((event.key === 'ArrowRight' ? 1 : -1) * (getComputedStyle(event.currentTarget).direction === 'rtl' ? -1 : 1)); } }}>{items.map(work => <div className="shelf-item" key={JSON.stringify([work.source, work.workId])}>{renderItem(work)}</div>)}{onReachEnd ? <div ref={tail} className="shelf-tail" aria-hidden="true" /> : null}</div><button className="shelf-side shelf-side-end" aria-label={t('向后浏览')+' · '+shelf.title} disabled={edges.end} onClick={()=>move(1)}><Arrow full /></button></div> : <p role="status">{shelf.items.length ? t('结果已被屏蔽规则过滤。') : t('此分区暂无内容')}</p>}
  </section>;
}
function Arrow({ previous = false, full = false }: { previous?: boolean; full?: boolean }) { return <svg className={previous ? 'arrow previous' : 'arrow'} width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d={full ? "M5 12h14m-7-7 7 7-7 7" : "m9 5 7 7-7 7"} /></svg>; }

export function FeatureIcon({ name }: { name: 'rankings' | 'reverse' }) {
  return <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{name === 'rankings' ? <><path d="M4 21V11h5v10M9 21V5h6v16M15 21v-7h5v7M2 21h20"/><path d="m11 2 1-1 1 1"/></> : <><rect x="3" y="3" width="14" height="14" rx="3"/><circle cx="7.5" cy="7.5" r="1"/><path d="m4 14 4-4 3 3 2-2"/><circle cx="16" cy="16" r="4"/><path d="m19 19 3 3"/></>}</svg>;
}

export function NavigationIcon({ name }: { name: string }) {
  const paths: Record<string, string> = { '/discover': 'm3 10 9-7 9 7v10H3Z M9 20v-7h6v7', '/search': 'M10 3a7 7 0 1 0 0 14 7 7 0 0 0 0-14 M15 15l6 6', '/library': 'M4 3v18 M9 3v18 M14 3v18 M18 3l4 17', '/downloads': 'M12 3v12 m-5-5 5 5 5-5 M4 17v4h16v-4', '/subscriptions': 'M5 3h14v18l-7-4-7 4Z', '/settings': 'M4 6h16 M4 12h16 M4 18h16 M8 3v6 M16 9v6 M10 15v6', '/sources': 'M3 4h18v16H3Z M3 9h18 M8 9v11' };
  return <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={paths[name] ?? paths['/discover']} /></svg>;
}
