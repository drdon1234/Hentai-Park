import { useEffect, type ReactNode } from 'react';
import { api,request } from './api.js';
import {tabId} from './native.js';
export function AppLockGate({children}:{children:ReactNode}) {
 useEffect(()=>{const refresh=()=>{void api.session.get().then(s=>{if(!s.authenticated)window.dispatchEvent(new Event('hp:unauthorized'));}).catch(()=>{});};const activity=()=>{void request('/api/v1/session/activity',{method:'POST',body:JSON.stringify({tabId,visible:!document.hidden}),keepalive:true}).then(()=>{if(!document.hidden)refresh();}).catch(()=>{});};activity();const timer=setInterval(()=>{if(!document.hidden)activity();else refresh();},15000);document.addEventListener('visibilitychange',activity);window.addEventListener('focus',activity);return()=>{clearInterval(timer);document.removeEventListener('visibilitychange',activity);window.removeEventListener('focus',activity);};},[]);
 return children;
}
