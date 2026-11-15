import {useReadingChrome} from './reading-chrome.js';
import {useState,type ReactNode} from 'react';
import {t} from './i18n.js';

/** Auxiliary reading controls stay available without displacing mobile content. */
export function ReaderTools({title,children}:{title:string;children:ReactNode}) {
  const chrome=useReadingChrome();
  const [open,setOpen]=useState(false);

  return <details className="reader-tools" open={chrome.mobile?chrome.open:open} onToggle={event=>{if(!chrome.mobile)setOpen(event.currentTarget.open);}}><summary>{title}</summary><div className="reader-tools-body">{chrome.mobile?<header className="reader-panel-heading"><strong>{title}</strong><button className="chip" onClick={chrome.toggle}>{t('关闭')}</button></header>:null}{children}</div></details>;
}
