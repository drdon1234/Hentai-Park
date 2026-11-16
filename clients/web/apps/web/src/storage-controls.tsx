import {useEffect,useState} from 'react';
import {api} from './api.js';
import {clearBrowserBrowseCache} from './browse-session-cache.js';
import {clearBrowserCoverCache} from './cover-image.js';
import {t} from './i18n.js';

export function StorageControls(){
 const [busy,setBusy]=useState(false),[notice,setNotice]=useState(''),[stats,setStats]=useState<{databaseBytes:number;downloadBytes:number;backupBytes:number;backupCount:number}>();
 useEffect(()=>{void api.storage().then(setStats).catch(()=>undefined);},[]);
 const size=(value:number)=>{if(value>=1073741824)return (value/1073741824).toFixed(1)+' GiB';if(value>=1048576)return (value/1048576).toFixed(1)+' MiB';if(value>=1024)return (value/1024).toFixed(1)+' KiB';return value+' B';};
 const clear=async(action:()=>Promise<void>)=>{
  setBusy(true);setNotice('');
  try{await action();setNotice(t('缓存已清除'));}catch{setNotice(t('操作未完成，请重试。'));}finally{setBusy(false);}
 };
 const deleteRead=async()=>{setBusy(true);setNotice('');try{const result=await api.deleteReadDownloads();setNotice(t('已加入删除队列')+' · '+result.count);window.dispatchEvent(new Event('hp:invalidate'));}catch{setNotice(t('操作未完成，请重试。'));}finally{setBusy(false);}};
 return <section><h3>{t('浏览器缓存')}</h3><p>{t('仅清除当前浏览器中的缓存，不删除收藏或下载。')}</p><div className="action-row"><button className="chip" disabled={busy} onClick={()=>void clear(clearBrowserBrowseCache)}>{t('清除主页数据缓存')}</button><button className="chip" disabled={busy} onClick={()=>void clear(clearBrowserCoverCache)}>{t('清除封面缓存')}</button><button className="chip" disabled={busy} onClick={()=>void deleteRead()}>{t('删除已读章节的下载')}</button></div>{stats?<dl className="storage-stats"><div><dt>{t('书库数据库')}</dt><dd>{size(stats.databaseBytes)}</dd></div><div><dt>{t('全部下载')}</dt><dd>{size(stats.downloadBytes)}</dd></div><div><dt>{t('备份文件')}</dt><dd>{size(stats.backupBytes)} · {stats.backupCount}</dd></div></dl>:null}{notice?<p role="status">{notice}</p>:null}</section>;
}
