import {useEffect,useRef,useState} from 'react';
import {api,request,type MediaTokenRequest} from './api.js';
/** Renew against the server-owned resource identity; URLs never come from the player. */
export function useMediaGrant(authorization:MediaTokenRequest|undefined|null,generation:number,onChange?:()=>void){
  const [token,setToken]=useState<string>(),[error,setError]=useState<string>();
  const changing=useRef(onChange);changing.current=onChange;
  useEffect(()=>{const controller=new AbortController();let timer:ReturnType<typeof setTimeout>|undefined;setToken(undefined);setError(undefined);
    const accept=(grant:{token:string;expiresAt:number})=>{if(controller.signal.aborted)return;setToken(grant.token);timer=setTimeout(()=>{void request<{token:string;expiresAt:number;changed:boolean}>('/api/v1/media/'+encodeURIComponent(grant.token)+'/renew',{method:'POST',body:'{}',signal:controller.signal}).then(next=>{if(controller.signal.aborted)return;if(next.changed)changing.current?.();accept(next);}).catch(fail);},Math.max(1000,grant.expiresAt-Date.now()-15000));};
    const fail=(reason:unknown)=>{if(!controller.signal.aborted)setError(reason instanceof Error?reason.message:String(reason));};
    if(authorization)void api.mediaToken(authorization,controller.signal).then(accept).catch(fail);
    return()=>{controller.abort();if(timer)clearTimeout(timer);};
  },[authorization,generation]);
  return {token,error};
}
