import {useEffect,useState} from 'react';
import {request} from './api.js';
import {usePreferences} from './preferences.js';
import {useLanguage,t} from './i18n.js';
export function TagPackReminder({source}:{source:string}){
 const prefs=usePreferences(),locale=useLanguage(),[missing,setMissing]=useState(false);
 useEffect(()=>{let active=true;void request<{items:Array<{source:string;locale:string}>}>('/api/v1/tag-packs').then(value=>{if(active)setMissing(!value.items.some(item=>item.source===source&&item.locale===locale));}).catch(()=>{});return()=>{active=false;};},[source,locale]);
 if(!missing||!prefs.ready||prefs.settings.tagDownloadReminders!==true||(prefs.settings.tagDownloadIgnoredSources as string[]|undefined)?.includes(source))return null;
 return <p role="status">{t('此站点尚未安装当前语言的标签词包。')} <a href="/settings?section=search">{t('查看标签词包')}</a> <button className="chip" onClick={()=>void prefs.save({tagDownloadIgnoredSources:[...((prefs.settings.tagDownloadIgnoredSources??[]) as string[]),source]})}>{t('不再提醒此站点')}</button></p>;
}
