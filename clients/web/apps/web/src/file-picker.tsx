import {useRef,useState,type ChangeEventHandler} from 'react';

export function FilePicker({label,accept,disabled,onChange,id}:{label:string;accept:string;disabled?:boolean;onChange:ChangeEventHandler<HTMLInputElement>;id?:string}){
 const input=useRef<HTMLInputElement>(null),[name,setName]=useState('');
 return <span className="file-picker"><input ref={input} type="file" accept={accept} disabled={disabled} hidden aria-label={label} onChange={event=>{setName(event.currentTarget.files?.[0]?.name??'');onChange(event);}}/><button id={id} className="chip" type="button" disabled={disabled} onClick={()=>input.current?.click()}>{label}</button>{name?<span className="file-picker-name" title={name} aria-live="polite">{name}</span>:null}</span>;
}
