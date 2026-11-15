import {useEffect,useState} from 'react';
import {api,allPages,type Source} from './api.js';
import {domainOrder,categoryLabels} from './browse-ui.js';
import {t} from './i18n.js';
import {languages} from '@hentai-park/domain-model';
export function CollectionPreferences({settings,onChange,kind}:{settings:Record<string,unknown>;onChange:(patch:Record<string,unknown>)=>void;kind:'home'|'sources'|'languages'}){
 const [sources,setSources]=useState<Source[]>([]),[error,setError]=useState('');
 useEffect(()=>{if(kind==='sources')void allPages(api.sources).then(setSources).catch(error=>setError(String(error.message)));},[kind]);
 const key=kind==='home'?'homeCategories':kind==='sources'?'aggregateExcluded':'translateTargets';
 const selected=Array.isArray(settings[key])?settings[key] as string[]:[];
 const order=Array.isArray(settings.domainOrder)?settings.domainOrder as string[]:[];
 const domains=[...order.filter(value=>domainOrder.includes(value)),...domainOrder.filter(value=>!order.includes(value))];
 const choices=kind==='home'?domains.map(id=>[id,t(categoryLabels[id]??id)]):kind==='sources'?sources.map(source=>[source.source,String(source.manifest?.name??source.source)]):Object.entries(languages).map(([id,info])=>[info.translationId,t(info.name)]);
 const move=(index:number,direction:number)=>{const next=[...domains];[next[index],next[index+direction]]=[next[index+direction]!,next[index]!];onChange({domainOrder:next});};
 return <fieldset><legend>{t(kind==='home'?'首页内容与顺序':kind==='sources'?'排除聚合搜索站点':'搜索翻译目标语言')}</legend>{kind==='home'?<p>{t('不勾选时显示全部内容。')}</p>:null}{error?<p role="status">{error}</p>:null}{choices.map(([id,label],index)=><div className="action-row" key={id}><label><input type="checkbox" checked={selected.includes(String(id))} onChange={event=>onChange({[key]:event.target.checked?[...selected,String(id)]:selected.filter(value=>value!==String(id))})}/>{label}</label>{kind==='home'?<><button type="button" className="chip" disabled={index===0} aria-label={label+' '+t('上移')} onClick={()=>move(index,-1)}>{t('上移')}</button><button type="button" className="chip" disabled={index===domains.length-1} aria-label={label+' '+t('下移')} onClick={()=>move(index,1)}>{t('下移')}</button></>:null}</div>)}</fieldset>;
}
