import {createHash,createHmac,createCipheriv,createDecipheriv,randomBytes,randomUUID} from 'node:crypto';
const fail=(code:string)=>Object.assign(new Error('Invalid cryptographic operation'),{code,retryable:false});

/** Byte encodings and bounds match the shared Park native bridge. */
export function cryptoOperation(op:string,args:Record<string,unknown>):unknown {
  switch(op) {
    case 'randomBytes': {const n=Number(args.length);if(!Number.isInteger(n)||n<1||n>65536)throw fail('CONFIG');return [...randomBytes(n)];}
    case 'uuid': return randomUUID();
    case 'md5Hex': return Array.isArray(args.text)?args.text.map(value=>createHash('md5').update(String(value)).digest('hex')):createHash('md5').update(String(args.text)).digest('hex');
    case 'sha256Hex': return createHash('sha256').update(String(args.text)).digest('hex');
    case 'hmacSha256Hex': return createHmac('sha256',String(args.key)).update(String(args.text)).digest('hex');
    case 'digestBytes': {
      if(!['sha1','sha256'].includes(String(args.algorithm))||!Array.isArray(args.bytes)||args.bytes.length>2*1024*1024||args.bytes.some(value=>!Number.isInteger(value)||value<0||value>255))throw fail('CONFIG');
      return [...createHash(String(args.algorithm)).update(Buffer.from(args.bytes)).digest()];
    }
    case 'aesEcbDecrypt': {
      const key=Buffer.from(String(args.key),'utf8');if(![16,24,32].includes(key.length))throw fail('CONFIG');
      const decipher=createDecipheriv(`aes-${key.length*8}-ecb`,key,null);
      return Buffer.concat([decipher.update(Buffer.from(String(args.base64),'base64')),decipher.final()]).toString('utf8');
    }
    case 'aesGcmEncrypt':
    case 'aesGcmDecrypt': {
      const hex=(name:string,lengths?:number[],maximum=4096,empty=false)=>{
        const raw=args[name];if(typeof raw!=='string'||raw.length>maximum*2||raw.length%2||!(empty?/^[a-f0-9]*$/i:/^[a-f0-9]+$/i).test(raw)||lengths&&!lengths.includes(raw.length/2))throw fail('CONFIG');
        return Buffer.from(raw,'hex');
      };
      const encrypt=op==='aesGcmEncrypt';const key=hex('key',[16,24,32]),iv=hex('iv',[12]);
      const data=hex(encrypt?'plaintext':'ciphertext',undefined,encrypt?4080:4096,encrypt);
      const aad=args.aad===undefined?Buffer.alloc(0):hex('aad',undefined,4096,true);
      if(!encrypt&&data.length<16)throw fail('CONFIG');
      const algorithm=key.length===16?'aes-128-gcm':key.length===24?'aes-192-gcm':'aes-256-gcm';
      try {
        if(encrypt){const cipher=createCipheriv(algorithm,key,iv,{authTagLength:16});cipher.setAAD(aad);return [...Buffer.concat([cipher.update(data),cipher.final(),cipher.getAuthTag()])];}
        const decipher=createDecipheriv(algorithm,key,iv,{authTagLength:16});decipher.setAAD(aad);decipher.setAuthTag(data.subarray(-16));
        return [...Buffer.concat([decipher.update(data.subarray(0,-16)),decipher.final()])];
      } catch {throw fail('PARSE');}
    }
    default: throw fail('UNSUPPORTED');
  }
}
