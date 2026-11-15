import {useSyncExternalStore} from 'react';
export const languageNames:Record<string,string>={'zh-Hans':'简体中文','zh-Hant':'繁體中文',en:'English',ja:'日本語',ko:'한국어',es:'Español',ru:'Русский',ar:'العربية'};
const loaders=import.meta.glob('./locales/*.json',{import:'default'});
let language='zh-Hans';const messages=new Map<string,Record<string,string>>(),listeners=new Set<()=>void>();let generation=0;
export function getLanguage(){return language;}
export async function setLanguage(next:string){
  if(!next){const preferred=navigator.languages.find(value=>/^zh|^en|^ja|^ko|^es|^ru|^ar/i.test(value))??'zh-Hans';next=/^zh/i.test(preferred)?/Hant|TW|HK|MO/i.test(preferred)?'zh-Hant':'zh-Hans':preferred.split('-')[0]!.toLowerCase();}
  if(!Object.hasOwn(languageNames,next))return;const active=++generation;
  if(next!=='zh-Hans'&&!messages.has(next)){const load=loaders['./locales/'+next+'.json'];if(load)messages.set(next,await load() as Record<string,string>);}
  if(active!==generation)return;language=next;document.documentElement.lang=next;document.documentElement.dir=next==='ar'?'rtl':'ltr';for(const notify of listeners)notify();
}
export function useLanguage(){return useSyncExternalStore(listener=>{listeners.add(listener);return()=>listeners.delete(listener);},getLanguage,getLanguage);}
export function t(key:string,params?:Record<string,string|number>){const dictionary=messages.get(language),canonical=key.trim(),start=key.indexOf(canonical);let value=dictionary&&canonical&&Object.hasOwn(dictionary,canonical)&&typeof dictionary[canonical]==='string'?key.slice(0,start)+dictionary[canonical]+key.slice(start+canonical.length):key;for(const [name,replacement]of Object.entries(params??{}))value=value.replaceAll('{'+name+'}',String(replacement));return value;}
export function pluginText(manifest:Record<string,unknown>,key:string){const i18n=manifest.i18n as Record<string,Record<string,string>>|undefined,value=i18n?.[language]?.[key];return typeof value==='string'?value:t(key);}
