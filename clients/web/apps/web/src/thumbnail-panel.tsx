import {useEffect,useRef,useState} from 'react';
import {request,mediaUrl,type MediaTokenRequest} from './api.js';
import {useMediaGrant} from './media-grant.js';
import {t} from './i18n.js';
export type Thumbnail={index?:number;width?:number;height?:number;offsetX?:number;offsetY?:number;mediaAuthorization:MediaTokenRequest};
function ThumbnailImage({item,href,navigate}:{item:Thumbnail;href?:string;navigate?:(href:string)=>void}) {
 const [attempt,setAttempt]=useState(0),[failed,setFailed]=useState(false);const grant=useMediaGrant(item.mediaAuthorization,attempt);
 if(grant.error||failed)return <button className="chip" onClick={()=>{setFailed(false);setAttempt(n=>n+1);}}>{t('重试图片')}</button>;
 if(!grant.token)return <span role="status">{t('正在读取图片')}</span>;
 const url=mediaUrl(grant.token),alt=t('页面预览')+(item.index===undefined?'':' '+(item.index+1));
 const image=item.width&&item.height?<svg role="img" aria-label={alt} viewBox={`${item.offsetX??0} ${item.offsetY??0} ${item.width} ${item.height}`} style={{width:'100%',aspectRatio:item.width/item.height}}><image href={url} onError={()=>setFailed(true)}/></svg>:<img src={url} alt={alt} loading="lazy" onError={()=>setFailed(true)}/>;
 return href?<a className="work-thumbnail-link" href={href} aria-label={t('阅读第')+((item.index??0)+1)+t('页')} onClick={event=>{if(navigate&&event.button===0&&!event.ctrlKey&&!event.metaKey&&!event.shiftKey&&!event.altKey){event.preventDefault();navigate(href);}}}>{image}</a>:image;
}
export function ThumbnailPanel({source,workId,available,total,readHref,navigate,initialItems}:{initialItems:Thumbnail[];source:string;workId:string;available:boolean;total?:number;readHref?:string;navigate?:(href:string)=>void}) {
 const [items,setItems]=useState<Thumbnail[]>([]),[visible,setVisible]=useState(20),[hasNext,setHasNext]=useState(available),[page,setPage]=useState(1),[busy,setBusy]=useState(false),[error,setError]=useState(''),[attempt,setAttempt]=useState(0);const active=useRef<AbortController|undefined>(undefined);
 const sentinel=useRef<HTMLDivElement>(null),[automatic,setAutomatic]=useState(false);
 const base='/api/v1/works/'+[source,workId].map(encodeURIComponent).join('/');
 useEffect(()=>{active.current?.abort();setItems(initialItems);setPage(1);setVisible(20);setAutomatic(false);setError('');setBusy(false);setHasNext(available&&(total===undefined||initialItems.length<total));return()=>active.current?.abort();},[base,available,total,initialItems,attempt]);
 const more=async()=>{setAutomatic(true);if(visible<items.length){setVisible(n=>n+40);return;}const abort=new AbortController();active.current?.abort();active.current=abort;setBusy(true);setError('');try{const value=await request<{items:Thumbnail[];hasNext:boolean}>(base+'/thumbnails?page='+page,{signal:abort.signal});if(abort.signal.aborted)return;const identity=(row:Thumbnail)=>JSON.stringify([row.index,row.mediaAuthorization.resourceKey,row.offsetX,row.offsetY]);const seen=new Set(items.map(identity));const fresh=value.items.filter(row=>!seen.has(identity(row))&&Boolean(seen.add(identity(row))));if(!fresh.length&&value.hasNext)throw new Error(t('来源未返回新的页面预览，请重试。'));setItems(previous=>[...previous,...fresh]);setVisible(n=>n+value.items.length);setPage(n=>n+1);setHasNext(value.hasNext);}catch(reason){if(!abort.signal.aborted)setError(String(reason));}finally{if(!abort.signal.aborted)setBusy(false);}};
 useEffect(()=>{const target=sentinel.current;if(!target||!automatic||busy||error||!(visible<items.length||hasNext))return;const observer=new IntersectionObserver(entries=>{if(entries.some(entry=>entry.isIntersecting)){observer.disconnect();void more();}},{rootMargin:'200px'});observer.observe(target);return()=>observer.disconnect();},[automatic,busy,error,visible,items.length,hasNext]);
 if(!items.length&&!available&&!error)return null;
 return <section className="work-thumbnail-section"><h2>{t('页面预览')}</h2><div className="work-thumbnail-grid">{items.slice(0,visible).map((item,index)=><figure key={item.index??index}><ThumbnailImage item={item} href={readHref&&item.index!==undefined?readHref+'?page='+(item.index+1):undefined} navigate={navigate}/> {item.index===undefined?null:<figcaption>{item.index+1}</figcaption>}</figure>)}</div><div ref={sentinel}/>{busy?<p role="status">{t("正在读取页面预览")}</p>:null}{error?<p role="status">{error}<button className="chip" onClick={()=>void more()}>{t('重试')}</button></p>:null}{visible<items.length||hasNext?<button className="chip" disabled={busy} onClick={()=>void more()}>{t('加载更多预览')}</button>:null}</section>;
}
