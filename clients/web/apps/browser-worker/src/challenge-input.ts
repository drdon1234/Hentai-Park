import type {Page} from 'playwright';

/** Android's bounded standard challenge input, with DOM identity and hit testing. */
export async function clickChallengeCheckbox(page:Page,url:string,generation:number,signal:AbortSignal):Promise<boolean>{
  const session=await page.context().newCDPSession(page);let objectId:string|undefined,pressed=false;
  const current=()=>!signal.aborted&&!page.isClosed()&&page.url()===url;
  try{
    if(!current())return false;
    const {root}=await session.send('DOM.getDocument',{depth:-1,pierce:true});const ids:number[]=[];let budget=20000;
    const visit=(node:any,depth=0)=>{if(!node||--budget<0||depth>64)return;
      if(node.nodeName==='IFRAME'){const attrs=node.attributes??[];for(let i=0;i+1<attrs.length;i+=2)if(attrs[i]==='src')try{const target=new URL(attrs[i+1]);if(target.protocol==='https:'&&target.hostname==='challenges.cloudflare.com'&&!target.port&&!target.username&&!target.password&&target.pathname.startsWith('/cdn-cgi/challenge-platform/')&&typeof node.nodeId==='number')ids.push(node.nodeId);}catch{}}
      for(const child of [...(node.children??[]),...(node.shadowRoots??[])])visit(child,depth+1);visit(node.contentDocument,depth+1);
    };visit(root);if(!current()||budget<0||ids.length!==1)return false;
    objectId=(await session.send('DOM.resolveNode',{nodeId:ids[0]!})).object.objectId;if(!objectId)return false;
    const check=async()=>{if(!current())return undefined;const result=await session.send('Runtime.callFunctionOn',{objectId,functionDeclaration:`function(expected,generation){
      if(!this.isConnected||this.ownerDocument!==document||location.href!==expected||performance.timeOrigin!==generation||document.readyState!=='complete')return null;
      const u=new URL(this.src);if(u.protocol!=='https:'||u.hostname!=='challenges.cloudflare.com'||u.port||u.username||u.password||!u.pathname.startsWith('/cdn-cgi/challenge-platform/'))return null;
      const r=this.getBoundingClientRect(),x=r.x+28,y=r.y+r.height/2;
      if(r.width<290||r.width>310||r.height<60||r.height>85||r.x<0||r.y<0||r.right>innerWidth||r.bottom>innerHeight)return null;
      for(let node=this;node;node=node.parentElement||node.getRootNode().host){const s=getComputedStyle(node);if(s.visibility!=='visible'||s.display==='none'||Number(s.opacity)===0)return null;}
      let node=this;for(let depth=0;depth<64;depth++){const root=node.getRootNode();if(!root.elementFromPoint||root.elementFromPoint(x,y)!==node)return null;if(root===document)return {x,y,width:innerWidth,height:innerHeight};node=root.host;if(!node)return null;}return null;
    }`,arguments:[{value:url},{value:generation}],returnByValue:true});return current()?result.result.value as {x:number;y:number;width:number;height:number}|undefined:undefined;};
    const point=await check();if(!point)return false;
    await session.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:point.x,y:point.y,buttons:0});
    const final=await check();if(!final||JSON.stringify(point)!==JSON.stringify(final)||!current())return false;
    pressed=true;await session.send('Input.dispatchMouseEvent',{type:'mousePressed',x:point.x,y:point.y,button:'left',clickCount:1,buttons:1});
    await session.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:current()?point.x:-1,y:current()?point.y:-1,button:'left',clickCount:1,buttons:0});pressed=false;return current();
  }catch(error){if(signal.aborted)throw error;return false;}
  finally{if(pressed)await session.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:-1,y:-1,button:'left',buttons:0}).catch(()=>{});if(objectId)await session.send('Runtime.releaseObject',{objectId}).catch(()=>{});await session.detach().catch(()=>{});}
}
