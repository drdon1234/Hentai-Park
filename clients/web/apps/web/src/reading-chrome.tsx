import {createContext,useCallback,useContext,useEffect,useRef,useState,type ReactNode} from 'react';
import {t} from './i18n.js';

const ReadingContext=createContext({mobile:false,open:false,toggle:()=>{}});
export const useReadingChrome=()=>useContext(ReadingContext);
/** Reading controls overlay the page; opening them never repaginates the text. */
export function ReadingChrome({active,children}:{active:boolean;children:ReactNode}){
 const [narrow,setNarrow]=useState(()=>matchMedia('(max-width: 839px)').matches),[open,setOpen]=useState(false),trigger=useRef<HTMLButtonElement>(null);
 const mobile=active&&narrow,toggle=useCallback(()=>setOpen(value=>!value),[]);
 useEffect(()=>{const media=matchMedia('(max-width: 839px)');const change=()=>setNarrow(media.matches);media.addEventListener('change',change);return()=>media.removeEventListener('change',change);},[]);
 useEffect(()=>{if(!mobile||!open)return;const close=(event:KeyboardEvent)=>{if(event.key==='Escape'&&!document.querySelector('dialog[open]')){setOpen(false);trigger.current?.focus();}};window.addEventListener('keydown',close);return()=>window.removeEventListener('keydown',close);},[mobile,open]);
 return <ReadingContext.Provider value={{mobile,open,toggle}}><div className={mobile?'mobile-reading-shell':'reading-shell'} data-controls-open={open}>{children}{mobile?<button ref={trigger} type="button" className="mobile-reading-trigger" aria-expanded={open} onClick={toggle} aria-label={t(open?'收起阅读工具':'打开阅读工具')} title={t('阅读工具')}><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16"/></svg></button>:null}</div></ReadingContext.Provider>;
}
