import {inflateSync} from 'node:zlib';
import {contentError} from './content-model.js';
const LIMIT=12*1024*1024,MAX_RAW=64*1024*1024+16384;
const CRC=Uint32Array.from({length:256},(_,value)=>{let crc=value;for(let bit=0;bit<8;bit++)crc=(crc&1)?0xedb88320^(crc>>>1):crc>>>1;return crc>>>0;});
function crc32(bytes:Uint8Array){let crc=0xffffffff;for(const byte of bytes)crc=CRC[(crc^byte)&255]^(crc>>>8);return (crc^0xffffffff)>>>0;}
function expand(bytes:Uint8Array,max:number):Buffer{try{const result=inflateSync(bytes,{maxOutputLength:max,info:true}) as unknown as {buffer:Buffer;engine:{bytesWritten:number}};if(result.engine.bytesWritten!==bytes.byteLength)throw contentError();return result.buffer;}catch{throw contentError();}}
/** Validate the complete PNG container and bounded image stream before reading card metadata. */
export function readTavernPng(input:Uint8Array):unknown{
 const bytes=Buffer.from(input);if(bytes.length>LIMIT||!bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))throw contentError();
 let width=0,height=0,depth=0,color=0,interlace=0,header=false,palette=false,idat=false,idatEnded=false,ended=false,offset=8;
 const image:Buffer[]=[],cards=new Map<string,string>();
 while(offset<bytes.length){
  if(offset+12>bytes.length)throw contentError();const size=bytes.readUInt32BE(offset),end=offset+size+12;if(size>LIMIT||end>bytes.length)throw contentError();const type=bytes.toString('latin1',offset+4,offset+8),chunk=bytes.subarray(offset+8,end-4);
  if(!/^[A-Za-z]{4}$/.test(type)||type[2]!==type[2].toUpperCase()||crc32(bytes.subarray(offset+4,end-4))!==bytes.readUInt32BE(end-4))throw contentError();
  if(!header&&type!=='IHDR')throw contentError();if(idat&&type!=='IDAT')idatEnded=true;
  if(type==='IHDR'){
   if(header||size!==13)throw contentError();width=chunk.readUInt32BE(0);height=chunk.readUInt32BE(4);depth=chunk[8];color=chunk[9];interlace=chunk[12];
   const depths:Record<number,number[]>={0:[1,2,4,8,16],2:[8,16],3:[1,2,4,8],4:[8,16],6:[8,16]};if(!width||!height||width>16384||height>16384||width*height>40000000||!depths[color]?.includes(depth)||chunk[10]!==0||chunk[11]!==0||interlace>1)throw contentError();header=true;
  }else if(type==='PLTE'){
   if(palette||idat||![2,3,6].includes(color)||!size||size>768||size%3)throw contentError();if(color===3&&size/3>2**depth)throw contentError();palette=true;
  }else if(type==='IDAT'){
   if(idatEnded||color===3&&!palette)throw contentError();idat=true;image.push(chunk);
  }else if(type==='IEND'){
   if(size!==0||!idat||end!==bytes.length)throw contentError();ended=true;offset=end;break;
  }else if(type[0]===type[0].toUpperCase())throw contentError();
  else if(['tEXt','zTXt','iTXt'].includes(type)){
   const zero=chunk.indexOf(0);if(zero<1||zero>79)throw contentError();const keyword=chunk.toString('latin1',0,zero);if(!/^[\x20-\x7e\xa1-\xff]+$/.test(keyword)||keyword.startsWith(' ')||keyword.endsWith(' ')||keyword.includes('  '))throw contentError();
   if(['chara','ccv3'].includes(keyword)){
    // PNG permits repeated text keywords. Match the native decoder's textData
    // map: later chunks replace earlier metadata; retain the original PNG on export.
    let encoded:Buffer;
    if(type==='zTXt'){if(chunk[zero+1]!==0)throw contentError();encoded=expand(chunk.subarray(zero+2),LIMIT);}
    else if(type==='iTXt'){const flag=chunk[zero+1];if(![0,1].includes(flag)||chunk[zero+2]!==0)throw contentError();const languageEnd=chunk.indexOf(0,zero+3),translatedEnd=languageEnd<0?-1:chunk.indexOf(0,languageEnd+1);if(translatedEnd<0)throw contentError();const body=chunk.subarray(translatedEnd+1);encoded=flag?expand(body,LIMIT):body;}
    else encoded=chunk.subarray(zero+1);
    const base64=encoded.toString('ascii').replace(/[\r\n]/g,'');if(!base64||!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(base64))throw contentError();const decoded=Buffer.from(base64,'base64');if(decoded.length>LIMIT||decoded.toString('base64')!==base64)throw contentError();let json:string;try{json=new TextDecoder('utf-8',{fatal:true}).decode(decoded);}catch{throw contentError();}cards.set(keyword,json);
   }
  }
  offset=end;
 }
 if(!ended||!header||!idat||!cards.size||offset!==bytes.length)throw contentError();
 const components:Record<number,number>={0:1,2:3,3:1,4:2,6:4},bits=components[color]*depth,passes=interlace?[[0,0,8,8],[4,0,8,8],[0,4,4,8],[2,0,4,4],[0,2,2,4],[1,0,2,2],[0,1,1,2]]:[[0,0,1,1]];
 const rows:Array<{count:number;bytes:number}>=passes.map(([x,y,dx,dy])=>({count:height>y&&width>x?Math.ceil((height-y)/dy):0,bytes:width>x?Math.ceil(Math.ceil((width-x)/dx)*bits/8):0})),expected=rows.reduce((sum,pass)=>sum+pass.count*(pass.bytes+1),0);
 if(expected<1||expected>MAX_RAW)throw contentError();const decoded=expand(Buffer.concat(image),expected);if(decoded.length!==expected)throw contentError();let index=0;for(const pass of rows)for(let row=0;row<pass.count;row++){if(decoded[index]>4)throw contentError();index+=pass.bytes+1;}
 try{return JSON.parse(cards.get('ccv3')??cards.get('chara')!);}catch{throw contentError();}
}
