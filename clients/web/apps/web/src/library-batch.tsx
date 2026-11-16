import {useRef,useState} from 'react';
import {api,allPages,request,type LibraryEntry} from './api.js';
import {t} from './i18n.js';

async function allWorkChapters(item:LibraryEntry){
 const pending:Array<string|undefined>=[undefined],visited=new Set<string>(),chapters:Awaited<ReturnType<typeof api.chapters>>['items']=[];
 while(pending.length){
  const directoryId=pending.shift();
  const directory=await allPages(params=>api.chapters(item.source,item.workId,{...params,directoryId}));
  for(const chapter of directory){
   if(chapter.nodeType==='directory'){
    if(visited.has(chapter.chapterId)||visited.size>=1000)throw new Error(t('操作未完成，请重试。'));
    visited.add(chapter.chapterId);pending.push(chapter.chapterId);
   }else chapters.push(chapter);
  }
 }
 return chapters;
}

export function LibraryBatch({items,categories,onComplete}:{items:LibraryEntry[];categories:Record<string,string>;onComplete:(failed:LibraryEntry[])=>void}){
 const dialog=useRef<HTMLDialogElement>(null);
 const [chosen,setChosen]=useState<string[]>([]),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const run=async(action:'category'|'read')=>{
  if(busy||!items.length)return;
  setBusy(true);setError('');
  const failed:LibraryEntry[]=[];
  for(const item of items){
   try{
    if(action==='category')await api.setLibrary({source:item.source,workId:item.workId,categoryIds:[...new Set([...item.categoryIds,...chosen])],version:item.version});
    else{
     const chapters=await allWorkChapters(item);
     const eligible=chapters.filter(chapter=>chapter.nodeType!=='other'&&chapter.readState!=='read');
     for(let offset=0;offset<eligible.length;offset+=200){
      const batch=eligible.slice(offset,offset+200);
      await request('/api/v1/works/'+encodeURIComponent(item.source)+'/'+encodeURIComponent(item.workId)+'/chapters/read-state',{method:'POST',body:JSON.stringify({chapters:batch.map(chapter=>({chapterId:chapter.chapterId,version:chapter.version})),readState:'read',requestKey:crypto.randomUUID()})});
     }
    }
   }catch{failed.push(item);}
  }
  onComplete(failed);window.dispatchEvent(new Event('hp:invalidate'));
  if(failed.length)setError(t('部分操作失败，失败项仍处于选中状态。'));else dialog.current?.close();
  setBusy(false);
 };
 return <><button className="chip" disabled={busy} onClick={()=>{setChosen([]);setError('');dialog.current?.showModal();}}>{t('分类')}</button><button className="chip" disabled={busy} onClick={()=>void run('read')}>{t('标为已读')}</button><dialog ref={dialog} onCancel={event=>{if(busy)event.preventDefault();}}><h2>{t('选择分类')}</h2><fieldset disabled={busy}><legend className="sr-only">{t('选择分类')}</legend>{Object.entries(categories).map(([id,name])=><label key={id}><input type="checkbox" checked={chosen.includes(id)} onChange={event=>setChosen(current=>event.target.checked?[...current,id]:current.filter(value=>value!==id))}/>{name}</label>)}</fieldset>{error?<p role="alert">{error}</p>:null}<div className="action-row"><button className="chip" disabled={busy} onClick={()=>dialog.current?.close()}>{t('取消')}</button><button className="primary-link" disabled={busy||!chosen.length} onClick={()=>void run('category')}>{t('保存分类')}</button></div></dialog>{error&&!dialog.current?.open?<p role="alert">{error}</p>:null}</>;
}
