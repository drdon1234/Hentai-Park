import { createDecipheriv } from 'node:crypto';
import type { ImageDecrypt } from '@hentai-park/source-contract';

export function decodeImage(input:Uint8Array,decrypt?:ImageDecrypt):{bytes:Buffer;mime:string} {
  if(input.byteLength>20*1024*1024)throw Object.assign(new Error('Image exceeds size limit'),{code:'PARSE'});
  const format=(data:Buffer)=>data.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))?'image/png':data[0]===255&&data[1]===216&&data[2]===255?'image/jpeg':['GIF87a','GIF89a'].includes(data.subarray(0,6).toString())?'image/gif':data.subarray(0,4).toString()==='RIFF'&&data.subarray(8,12).toString()==='WEBP'?'image/webp':data.subarray(4,8).toString()==='ftyp'&&['avif','avis'].includes(data.subarray(8,12).toString())?'image/avif':undefined;
  let bytes=Buffer.from(input);let mime=format(bytes);
  if(!mime&&decrypt){try{const key=Buffer.from(decrypt.key,'utf8');const iv=Buffer.from(decrypt.iv,'utf8');if(![16,24,32].includes(key.length)||iv.length!==16)throw Error();const cipher=createDecipheriv(`aes-${key.length*8}-cbc`,key,iv);bytes=Buffer.concat([cipher.update(bytes),cipher.final()]);mime=format(bytes);}catch{throw Object.assign(new Error('Image decryption failed'),{code:'PARSE'});}}
  if(!mime)throw Object.assign(new Error('Image format is invalid'),{code:'PARSE'});
  return {bytes,mime};
}
