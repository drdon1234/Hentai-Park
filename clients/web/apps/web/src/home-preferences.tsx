import {useEffect,useId,useRef,useState} from 'react';
import {api,allPages,ApiError,type Source} from './api.js';
import {errorMessage,useServerVersion} from './page-ui.js';
import {t} from './i18n.js';

type Snapshot={settings:Record<string,unknown>;version:number};
const ids=(value:unknown):string[]=>Array.isArray(value)?value.filter((item):item is string=>typeof item==='string'):[];
export function useHomePreferences(){
  const version=useServerVersion(['account.updated']);
  const [snapshot,setSnapshot]=useState<Snapshot>();const latest=useRef<Snapshot|undefined>(undefined);
  const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState('');
  const alive=useRef(true),busy=useRef(false);
  const accept=(value:Snapshot)=>{if(alive.current&&(!latest.current||value.version>=latest.current.version)){latest.current=value;setSnapshot(value);}};
  const reload=async()=>{try{accept(await api.settings());if(alive.current)setError('');}catch(reason){if(alive.current)setError(errorMessage(reason));throw reason;}finally{if(alive.current)setLoading(false);}};
  useEffect(()=>{alive.current=true;void reload().catch(()=>undefined);return()=>{alive.current=false;};},[version]);
  const save=async(key:'homeSourceOrder'|'homeHiddenSources',change:(values:string[])=>string[])=>{
    if(busy.current)throw Error(t('正在保存，请稍候。'));
    busy.current=true;setSaving(true);setError('');
    try{
      const before=latest.current??await api.settings();const values=change(ids(before.settings[key]));
      const result=await api.updateSettings({[key]:values},before.version);
      accept({settings:{...before.settings,...result.settings},version:result.version});
    }catch(reason){
      if(reason instanceof ApiError&&reason.status===409){await reload().catch(()=>undefined);const conflict=Error(t('首页偏好已在其他页面变更，请确认后重新保存。'));if(alive.current)setError(conflict.message);throw conflict;}
      if(alive.current)setError(errorMessage(reason));throw reason;
    }finally{busy.current=false;if(alive.current)setSaving(false);}
  };
  return {order:ids(snapshot?.settings.homeSourceOrder),hidden:ids(snapshot?.settings.homeHiddenSources),loading,error,saving,reload,
    chooseSource:(source:string)=>save('homeSourceOrder',values=>[source,...values.filter(value=>value!==source)]),
    toggleHidden:(source:string)=>save('homeHiddenSources',values=>values.includes(source)?values.filter(value=>value!==source):[...values,source])};
}

export function HomeSourcePicker({sources,preferences,label}:{sources:Source[];preferences:ReturnType<typeof useHomePreferences>;label?:string}){
  const titleId=useId();
  const dialog=useRef<HTMLDialogElement>(null),trigger=useRef<HTMLButtonElement>(null);
  const [selected,setSelected]=useState(''),[error,setError]=useState('');
  const available=sources.filter(source=>source.enabled&&source.installed!==false);
  const open=()=>{setSelected(preferences.order.find(id=>available.some(source=>source.source===id))??available[0]?.source??'');setError('');dialog.current?.showModal();};
  const save=async()=>{try{await preferences.chooseSource(selected);dialog.current?.close();}catch(reason){setError(errorMessage(reason));}};
  return <><button ref={trigger} type="button" className="home-source-picker-trigger" aria-label={label??t('选择展示站点')} title={label??t('选择展示站点')} disabled={preferences.loading||!available.length} onClick={open}><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16M8 3v6m8 0v6m-6 0v6"/></svg></button><dialog ref={dialog} className="home-source-dialog" aria-labelledby={titleId} onCancel={event=>{if(preferences.saving)event.preventDefault();}} onClose={()=>trigger.current?.focus()}><form onSubmit={event=>{event.preventDefault();void save();}}><h2 id={titleId}>{label??t('选择展示站点')}</h2><p>{t('所选站点将在此内容域中优先展示。')}</p><fieldset disabled={preferences.saving}><legend>{t('站点')}</legend>{available.map(source=><label key={source.source}><input type="radio" name={titleId} value={source.source} checked={selected===source.source} onChange={()=>setSelected(source.source)}/>{String(source.manifest?.name??source.source)}</label>)}</fieldset>{error?<p role="alert">{error}</p>:null}<div className="action-row"><button type="button" className="chip" disabled={preferences.saving} onClick={()=>dialog.current?.close()}>{t('取消')}</button><button className="primary-link" disabled={preferences.saving||!available.some(source=>source.source===selected)}>{t(preferences.saving?'正在保存…':'保存')}</button></div></form></dialog></>;
}

export function SourceOrderPreferences({settings,onChange}:{settings:Record<string,unknown>;onChange:(patch:Record<string,unknown>)=>void}){
 const [sources,setSources]=useState<Source[]>([]),[error,setError]=useState('');
 useEffect(()=>{void allPages(api.sources).then(setSources).catch(reason=>setError(errorMessage(reason)));},[]);
 const saved=ids(settings.homeSourceOrder);
 const position=new Map(saved.map((id,index)=>[id,index]));
 const ordered=[...sources].sort((a,b)=>(position.get(a.source)??Number.MAX_SAFE_INTEGER)-(position.get(b.source)??Number.MAX_SAFE_INTEGER)||(a.defaultOrder??Number.MAX_SAFE_INTEGER)-(b.defaultOrder??Number.MAX_SAFE_INTEGER)||a.source.localeCompare(b.source));
 const move=(index:number,direction:number)=>{const next=ordered.map(item=>item.source);[next[index],next[index+direction]]=[next[index+direction]!,next[index]!];onChange({homeSourceOrder:next});};
 return <fieldset><legend>{t('站点顺序')}</legend><p>{t('使用按钮调整首页各域中的站点顺序。')}</p>{error?<p role="status">{error}</p>:null}{ordered.map((source,index)=><div className="action-row" key={source.source}><span>{String(source.manifest?.name??source.source)}</span><button type="button" className="chip" disabled={index===0} aria-label={String(source.manifest?.name??source.source)+' '+t('上移')} onClick={()=>move(index,-1)}>{t('上移')}</button><button type="button" className="chip" disabled={index===ordered.length-1} aria-label={String(source.manifest?.name??source.source)+' '+t('下移')} onClick={()=>move(index,1)}>{t('下移')}</button></div>)}</fieldset>;
}
