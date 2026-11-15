import {useEffect,useState} from 'react';
import {request} from './api.js';
import {t} from './i18n.js';
export function MaintenanceStatus(){
 const [value,setValue]=useState<Record<string,{at:string;status:string;result?:{updates?:Array<{entry:{key:string;version:string}}>}}>>({}),[error,setError]=useState(''),[files,setFiles]=useState<string[]>([]);
 useEffect(()=>{void request<{items:string[]}>('/api/v1/maintenance/backups').then(value=>setFiles(value.items)).catch(error=>setError(String(error.message)));void request<typeof value>('/api/v1/maintenance').then(setValue).catch(error=>setError(String(error.message)));},[]);
 return <details><summary>{t('自动任务状态')}</summary>{Object.entries(value).map(([key,item])=>item?<p key={key}>{t(key==='backup'?'备份':key==='library'?'收藏更新':'站点更新')} · {new Date(item.at).toLocaleString()} · {t(item.status==='completed'?'已完成':'失败')}{item.result?.updates?.map(update=><a key={update.entry.key} href={'/source/'+encodeURIComponent(update.entry.key)}>{update.entry.key} · {update.entry.version}</a>)}</p>:null)}{error?<p role="status">{error}</p>:null}<ul>{files.map(name=><li key={name}><a href={'/api/v1/maintenance/backups/'+encodeURIComponent(name)} download>{name}</a></li>)}</ul></details>;
}
