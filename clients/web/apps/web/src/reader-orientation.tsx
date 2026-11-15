import {useEffect,useState} from 'react';
import {t} from './i18n.js';
export function ReaderOrientation({value}:{value:unknown}){
 const [error,setError]=useState('');
 useEffect(()=>{setError('');if(value==='auto')screen.orientation?.unlock?.();return()=>screen.orientation?.unlock?.();},[value]);
 if(value==='auto')return null;
 const apply=async()=>{try{const orientation=screen.orientation as ScreenOrientation&{lock?:(value:string)=>Promise<void>};if(!orientation?.lock)throw Error();if(!document.fullscreenElement)await document.documentElement.requestFullscreen();await orientation.lock(String(value));setError('');}catch{setError(t('浏览器不支持锁定屏幕方向，请使用设备的方向锁定。'));}};
 return <><button className="chip" onClick={()=>void apply()}>{t('应用屏幕方向')}</button>{error?<span role="status">{error}</span>:null}</>;
}
