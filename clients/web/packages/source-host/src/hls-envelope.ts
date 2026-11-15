import {inflateSync} from 'node:zlib';
const invalid=()=>Object.assign(new Error('Invalid media envelope'),{code:'PARSE',statusCode:502,publicError:true,causeCategory:'source',retryable:false});
/** Shared protocol decoder; bounds the decoded data before parsing or decryption. */
export function unwrapHlsResource(input:Uint8Array,maxBytes:number):Buffer {
 const bytes=Buffer.from(input);if(!bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))){if(bytes.length>maxBytes)throw invalid();return bytes;}
 for(let offset=8;offset+12<=bytes.length;){const length=bytes.readUInt32BE(offset);if(length>64*1024*1024||offset+12+length>bytes.length)throw invalid();if(bytes.toString('ascii',offset+4,offset+8)==='roUd'){if(length<1)throw invalid();const flag=bytes[offset+8];if(flag&~1)throw invalid();const payload=bytes.subarray(offset+9,offset+8+length);let out:Buffer;try{out=flag&1?inflateSync(payload,{maxOutputLength:maxBytes}):payload;}catch{throw invalid();}if(!out.length||out.length>maxBytes)throw invalid();return out;}offset+=length+12;}throw invalid();
}
