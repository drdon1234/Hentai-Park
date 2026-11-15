import { t } from './i18n.js';

/** POP only through an entry created by our own navigation, never into an external tab history. */
export function DesktopBack({location,navigate}:{location:string;navigate:(url:string,replace?:boolean)=>void}) {
  const [path,query=''] = location.split('#')[0]!.split('?');
  const parts=path!.split('/'),kind=parts[1],params=new URLSearchParams(query);
  const section=kind==='settings'&&params.has('section');
  if (!section && !['domain','sites','source','work','read','watch','channel','post','album','rankings','history','offline','tavern'].includes(kind??'')) return null;
  const source='/source/'+(parts[2]??'');
  const fallback=section?'/settings':kind==='work'||kind==='channel'||kind==='album'||kind==='post'?source:kind==='read'||kind==='watch'?'/work/'+[parts[2],parts[3]].join('/'):kind==='source'?'/sites':kind==='history'||kind==='tavern'?'/library':kind==='offline'?'/downloads':'/discover';
  const previous=typeof window.history.state?.hpFrom==='string'&&/^\/(?!\/)/.test(window.history.state.hpFrom)?window.history.state.hpFrom:undefined;
  return <div className="desktop-back"><a href={previous??fallback} onClick={event=>{
    if(event.button!==0||event.ctrlKey||event.metaKey||event.shiftKey||event.altKey)return;
    event.preventDefault();if(previous)window.history.back();else navigate(fallback,true);
  }}><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="M20 12H4m7-7-7 7 7 7"/></svg>{t('返回')}</a></div>;
}
