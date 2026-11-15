import http from 'node:http';
import type net from 'node:net';
import {connectPinnedTunnel,isPrivateAddress} from '@hentai-park/source-host';

/** TLS-transparent browser egress. Only hosts/IPs approved at Fetch interception can connect. */
export async function createBrowserTunnel(){
  const approved=new Map<string,{target:URL;address:{address:string;family:number}}>();
  const sockets=new Set<net.Socket>(),controller=new AbortController();
  const server=http.createServer((_request,response)=>{response.writeHead(403);response.end();});
  server.on('connection',socket=>{sockets.add(socket);socket.on('error',()=>{});socket.once('close',()=>sockets.delete(socket));socket.setTimeout(30000,()=>socket.destroy());});
  server.on('connect',(request,client,head)=>{void(async()=>{
    if(controller.signal.aborted||sockets.size>128)throw Error('closed');
    const target=new URL('https://'+request.url);
    if(target.username||target.password||target.pathname!=='/'||target.search||target.hash||target.port)throw Error('invalid tunnel');
    const entry=approved.get(target.host);if(!entry)throw Error('unapproved tunnel');
    const remote=await connectPinnedTunnel(entry.target,entry.address,controller.signal);
    sockets.add(remote);remote.on('error',()=>client.destroy());remote.once('close',()=>{sockets.delete(remote);client.destroy();});client.once('close',()=>remote.destroy());
    if(client.destroyed||controller.signal.aborted){remote.destroy();return;}
    client.write('HTTP/1.1 200 Connection Established\r\n\r\n');if(head.length)remote.write(head);remote.pipe(client);client.pipe(remote);
  })().catch(()=>{if(!client.destroyed)client.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');});});
  await new Promise<void>((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',()=>{server.removeListener('error',reject);resolve();});});
  const address=server.address();if(!address||typeof address==='string')throw Error('browser tunnel unavailable');
  return {server:'http://127.0.0.1:'+address.port,
    approve(target:URL,addresses:Array<{address:string;family:number}>){if(target.protocol!=='https:'||target.port||!addresses.length||addresses.some(value=>isPrivateAddress(value.address)))throw Error('invalid pinned destination');approved.set(target.host,{target,address:addresses[0]!});},
    async close(){controller.abort();approved.clear();for(const socket of sockets)socket.destroy();await new Promise<void>(resolve=>server.close(()=>resolve()));}
  };
}
