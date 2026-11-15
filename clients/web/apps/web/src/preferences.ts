import {createContext,createElement,useContext,useEffect,useRef,useState,type ReactNode} from 'react';
import {preferenceDefaults} from '@hentai-park/domain-model';
import {api} from './api.js';
import {errorMessage} from './page-ui.js';

export const PreferenceSettingsContext=createContext<Record<string,unknown>>(preferenceDefaults);
const PreferencesContext=createContext<ReturnType<typeof usePreferenceState>|undefined>(undefined);
export function PreferencesProvider({children}:{children:ReactNode}){
 const value=usePreferenceState();
 return createElement(PreferencesContext.Provider,{value},children);
}
export function usePreferences(){
 const value=useContext(PreferencesContext);
 if(!value)throw new Error('PreferencesProvider is required');
 return value;
}
function usePreferenceState(){
 const [settings,setSettings]=useState<Record<string,unknown>>(preferenceDefaults),[ready,setReady]=useState(false),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 const snapshot=useRef<{settings:Record<string,unknown>;version:number}|undefined>(undefined),saving=useRef(false),pending=useRef<Record<string,unknown>[]>([]),queue=useRef(Promise.resolve());
 useEffect(()=>{
  let live=true,running=false,again=false;
  const reload=async()=>{
   if(saving.current||pending.current.length)return;
   if(running){again=true;return;}
   running=true;
   try{const value=await api.settings();if(live&&(!snapshot.current||value.version>=snapshot.current.version)){snapshot.current=value;setSettings({...preferenceDefaults,...value.settings});setReady(true);setError('');}}
   catch(reason){if(live)setError(errorMessage(reason));}
   finally{running=false;if(live&&again){again=false;void reload();}}
  };
  const changed=(event:Event)=>{
   const types=(event as CustomEvent<{eventTypes?:string[]}>).detail?.eventTypes;
   if(event.type==='hp:server-update'&&Array.isArray(types)&&!types.some(type=>type==='account.updated'||type==='sync.required'))return;
   void reload();
  };
  void reload();window.addEventListener('hp:server-update',changed);window.addEventListener('hp:invalidate',changed);
  return()=>{live=false;window.removeEventListener('hp:server-update',changed);window.removeEventListener('hp:invalidate',changed);};
 },[]);
 const save=(patch:Record<string,unknown>)=>{if(!snapshot.current)return Promise.resolve();pending.current.push(patch);setSettings(current=>({...current,...patch}));const action=queue.current.then(async()=>{if(!snapshot.current)return;saving.current=true;setBusy(true);setError('');try{const value=await api.updateSettings(patch,snapshot.current.version);snapshot.current={settings:{...snapshot.current.settings,...value.settings},version:value.version};}catch(reason){setError(errorMessage(reason));const value=await api.settings();snapshot.current=value;}finally{pending.current.shift();setSettings({...preferenceDefaults,...snapshot.current?.settings,...Object.assign({},...pending.current)});saving.current=false;setBusy(pending.current.length>0);}});queue.current=action.catch(()=>{});return queue.current;};
 return {settings,ready,error,busy,save};
}

export function useWakeLock(enabled:boolean){
 useEffect(()=>{let disposed=false;let lock:WakeLockSentinel|undefined;const request=async()=>{if(!enabled||document.hidden||!navigator.wakeLock)return;try{const next=await navigator.wakeLock.request('screen');if(disposed)await next.release();else lock=next;}catch{/* Browser or OS may deny wake lock. */}};void request();document.addEventListener('visibilitychange',request);return()=>{disposed=true;document.removeEventListener('visibilitychange',request);void lock?.release();};},[enabled]);
}
