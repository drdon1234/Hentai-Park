import http from 'node:http';
import {toAbortError} from '@hentai-park/source-contract';
import https from 'node:https';
import tls from 'node:tls';
import dns from 'node:dns/promises';
import net from 'node:net';
import {isPrivateAddress,HostError} from './index.js';
interface ProxyConfiguration {url:URL;allowLocal:boolean;}
let configuration:ProxyConfiguration|undefined;
/** Instance deployment configuration only; never populated from plugin or API input. */
export function configureHttpProxy(value?:string,options:{allowLocal?:boolean}={}){
  if(!value){configuration=undefined;return;}let url:URL;try{url=new URL(value);}catch{throw new HostError('CONFIG','invalid instance HTTP proxy');}
  if(!['http:','https:'].includes(url.protocol)||url.pathname!=='/'||url.search||url.hash||url.hostname.length>253||url.username.length>2048||url.password.length>2048)throw new HostError('CONFIG','invalid instance HTTP proxy');configuration={url,allowLocal:options.allowLocal===true};
}
/** Connect only to an already validated IP. TLS remains owned by the caller. */
export async function connectPinnedTunnel(target:URL,address:{address:string;family:number},signal?:AbortSignal):Promise<net.Socket>{
  signal?.throwIfAborted();
  if(isPrivateAddress(address.address))throw new HostError('BLOCKED','private proxy destination');
  const config=configuration;
  if(!config)return new Promise((resolve,reject)=>{
    const socket=net.connect({host:address.address,port:Number(target.port||443),family:address.family,signal});
    socket.once('error',reject);socket.setTimeout(30000,()=>socket.destroy(new HostError('TIMEOUT','pinned connection timeout')));
    socket.once('connect',()=>resolve(socket));
  });
  const endpoints=await dns.lookup(config.url.hostname,{all:true});
  if(!endpoints.length||!config.allowLocal&&endpoints.some(endpoint=>isPrivateAddress(endpoint.address)))throw new HostError('BLOCKED','local instance proxy requires explicit deployment permission');
  const endpoint=endpoints[0]!,authority=target.hostname+':'+Number(target.port||443);
  const headers:Record<string,string>={host:authority};
  if(config.url.username||config.url.password)headers['proxy-authorization']='Basic '+Buffer.from(decodeURIComponent(config.url.username)+':'+decodeURIComponent(config.url.password)).toString('base64');
  return new Promise((resolve,reject)=>{
    const transport=config.url.protocol==='https:'?https:http;
    const request=transport.request({hostname:config.url.hostname,port:Number(config.url.port||(config.url.protocol==='https:'?443:80)),servername:config.url.hostname,method:'CONNECT',path:authority,headers,signal,timeout:30000,agent:false,lookup:(_host,opts,done)=>done(null,opts.all?endpoints:endpoint.address,endpoint.family)});
    request.once('error',reject);request.once('timeout',()=>request.destroy(new HostError('TIMEOUT','instance proxy connection timeout')));
    request.once('connect',(response,socket,head)=>{if(response.statusCode!==200||head.length){socket.destroy();reject(new HostError('NETWORK','instance proxy tunnel rejected'));return;}resolve(socket);});request.end();
  });
}
export function pinnedProxyAgent(target:URL,address:{address:string;family:number},signal?:AbortSignal):https.Agent|undefined{
  if(!configuration)return undefined;
  const agent=new https.Agent({keepAlive:false,maxSockets:1});
  agent.createConnection=(_options,callback)=>{
    void connectPinnedTunnel(target,address,signal).then(socket=>{
      const secure=tls.connect({socket,servername:target.hostname,rejectUnauthorized:true,ALPNProtocols:['http/1.1']});
      let settled=false;const finish=(error?:Error)=>{if(settled)return;settled=true;callback?.(error??null,secure);};
      const cancel=()=>{const error=toAbortError(signal!);secure.destroy(Object.assign(new HostError(error.code,error.message,error.details as Record<string,unknown>|undefined),{retryable:error.retryable}));};
      signal?.addEventListener('abort',cancel,{once:true});secure.once('close',()=>signal?.removeEventListener('abort',cancel));
      secure.once('error',finish);secure.once('secureConnect',()=>finish());
      secure.setTimeout(30000,()=>secure.destroy(new HostError('TIMEOUT','instance proxy TLS timeout')));
      if(signal?.aborted)cancel();
    },error=>callback?.(error,null as unknown as tls.TLSSocket));return undefined;
  };
  return agent;
}
