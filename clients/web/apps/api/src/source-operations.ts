import { readFile } from 'node:fs/promises';
import { resolve, relative, isAbsolute } from 'node:path';
import { permissionChanges, type SourceHost } from '@hentai-park/source-host';
import type { BrowserWorker } from '@hentai-park/browser-worker';
import type { PluginManifest } from '@hentai-park/source-contract';
type Row = Record<string, unknown>;
export interface SourcePackage { source: string; version: string; sha256: string; file: string; manifest: PluginManifest; }
const fail = (code: string, statusCode = 400) => Object.assign(new Error(code), { code,statusCode,publicError:true,causeCategory:'source',retryable:false });
export class SourceOperations {
  private readonly active = new Map<string, Promise<Row>>();
  private readonly filterCache = new Map<string, { expires:number;items:Array<{value:string|number|boolean;label:string;color?:string}> }>();
  constructor(readonly host: SourceHost, readonly browser: BrowserWorker, readonly packages: SourcePackage[], private readonly packageDirectory: string) {for(const item of packages){const installed=host.registry.get(item.source);if(installed?.sha256===item.sha256)installed.manifest=structuredClone(item.manifest);}}
  available() { const values=this.packages.map(value=>{const installed=this.host.registry.get(value.source);return {source:value.source,manifest:installed?.manifest??value.manifest,installed:Boolean(installed),enabled:installed?.enabled??false,version:installed?.version,availableVersion:value.version,candidate:{manifest:value.manifest,version:value.version,sha256:value.sha256,permissions:permissionChanges(installed?.manifest,value.manifest)}};});for(const installed of this.host.registry.list())if(!values.some(value=>value.source===installed.source))values.push({source:installed.source,manifest:installed.manifest,installed:true,enabled:installed.enabled,version:installed.version,availableVersion:installed.version,candidate:{manifest:installed.manifest,version:installed.version,sha256:installed.sha256??'',permissions:permissionChanges(installed.manifest,installed.manifest)}});return values; }
  settings(source:string){return this.host.getSettings(source);}
  async updateSettings(source:string,body:Row){if(Object.keys(body).some(key=>!['settings','version','requestKey'].includes(key))||!body.settings||typeof body.settings!=='object'||Array.isArray(body.settings)||!Number.isSafeInteger(body.version))throw fail('BAD_REQUEST');const current=await this.host.getSettings(source);if(this.host.registry.get(source)?.manifest.account?.managedAccount===true&&(body.settings as Row).managedAccount!==current.settings.managedAccount)throw fail('CONFIRM_REQUIRED',409);return this.host.updateSettings(source,body.settings as Row,body.version as number);}
  async accountStatus(source:string,signal?:AbortSignal){return {account:await this.host.account(source,'status',{}, {signal})};}
  async filterOptions(source:string,body:Row,signal?:AbortSignal){
    const record=this.host.registry.get(source);if(!record?.enabled)throw fail('CONFIG',409);
    if(Object.keys(body).some(key=>!['scope','feed','filter','keyword','values'].includes(key))||!['feed','search'].includes(String(body.scope))||typeof body.filter!=='string'||body.feed!==undefined&&typeof body.feed!=='string'||body.keyword!==undefined&&typeof body.keyword!=='string'||body.values!==undefined&&(!body.values||typeof body.values!=='object'||Array.isArray(body.values)))throw fail('BAD_REQUEST');
    const settingsVersion=(await this.host.getSettings(source)).version;
    const key=JSON.stringify([source,record.version,settingsVersion,record.packagePath,body.scope,body.feed??null,body.filter,body.keyword??null,Object.entries(body.values??{}).sort(([a],[b])=>a.localeCompare(b))]);const now=Date.now();for(const [id,value]of this.filterCache)if(value.expires<=now)this.filterCache.delete(id);const cached=this.filterCache.get(key);if(cached)return {items:cached.items};
    const raw=await this.host.filterOptions(source,body,{signal});if(!Array.isArray(raw)||raw.length>500)throw fail('PARSE',502);const seen=new Set<string>();
    const items=raw.map(value=>{if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(key=>!['value','label','color'].includes(key))||!(typeof value.value==='string'&&value.value.length<=512&&!/[\u0000-\u001f\u007f]/.test(value.value)||typeof value.value==='number'&&Number.isFinite(value.value)||typeof value.value==='boolean')||typeof value.label!=='string'||!value.label||value.label.length>256||/[\u0000-\u001f\u007f]/.test(value.label)||value.color!==undefined&&(typeof value.color!=='string'||!/^#[a-f0-9]{6}$/i.test(value.color))||seen.has(typeof value.value+':'+String(value.value)))throw fail('PARSE',502);seen.add(typeof value.value+':'+String(value.value));return {value:value.value as string|number|boolean,label:value.label as string,...(value.color===undefined?{}:{color:value.color as string})};});
    if(this.filterCache.size>=512)this.filterCache.delete(this.filterCache.keys().next().value!);this.filterCache.set(key,{items,expires:now+120000});return {items};
  }
  async execute(source: string, operation: 'enable'|'update'|'login'|'verify'|'logout'|'managed', body: Row, signal?: AbortSignal): Promise<Row> {
    const fields=operation==='enable'?['enabled','requestKey']:operation==='update'?['action','requestKey','expectedSha256','expectedVersion','expectedCurrentVersion']:operation==='login'?['credentials','requestKey']:operation==='logout'?['requestKey']:operation==='managed'?['confirmed','enabled','requestKey']:['url','selector','requestKey'];if(Object.keys(body).some(key=>!fields.includes(key)))throw fail('BAD_REQUEST');
    if (operation === 'enable') { if(typeof body.enabled!=='boolean')throw fail('BAD_REQUEST'); await this.host.setEnabled(source,body.enabled); return {source,enabled:body.enabled,status:'completed'}; }
    if (operation === 'update') {
      if(this.active.has(source))throw fail('CONFLICT',409);
      const pending = (async()=>{
        if(body.action==='rollback'){await this.host.rollback(source);return {source,status:'completed',action:'rollback'};}
        if(body.action!==undefined && !['install','update'].includes(String(body.action)))throw fail('BAD_REQUEST');
        const item=this.packages.find(value=>value.source===source);if(!item)throw fail('NOT_FOUND',404);
        if((body.expectedSha256!==undefined&&body.expectedSha256!==item.sha256)||(body.expectedVersion!==undefined&&body.expectedVersion!==item.version)||(Object.hasOwn(body,'expectedCurrentVersion')&&body.expectedCurrentVersion!==(this.host.registry.get(source)?.version??null)))throw fail('CONFLICT',409);
        const path=resolve(this.packageDirectory,item.file);const rel=relative(resolve(this.packageDirectory),path);if(rel.startsWith('..')||isAbsolute(rel))throw fail('BLOCKED',403);
        await this.host.install(source,path,item.manifest,item.sha256);return {source,status:'completed',action:body.action ?? 'update',version:item.version};
      })(); this.active.set(source,pending);try{return await pending;}finally{this.active.delete(source);}
    }
    const record=this.host.registry.get(source);if(!record || !record.enabled)throw fail('CONFIG',409);
    const manifest=record.manifest;
    if(operation==='logout'||operation==='managed'){
      if(operation==='managed'&&body.enabled!==undefined&&typeof body.enabled!=='boolean')throw fail('BAD_REQUEST');
      if(operation==='managed'&&body.enabled!==false&&body.confirmed!==true)throw fail('CONFIRM_REQUIRED',409);
      if(!manifest.account||operation==='managed'&&manifest.account.managedAccount!==true)throw fail('UNSUPPORTED',422);
      if(operation==='managed'&&body.enabled===false){const current=await this.host.getSettings(source);await this.host.updateSettings(source,{...current.settings,managedAccount:false},current.version);return {source,operation,status:'completed',account:await this.host.account(source,'status',{}, {signal})};}
      if(operation==='managed'){const snapshot=await this.host.exportPrivateState(source,{includeAccounts:true});const data=snapshot.data as Row|undefined;if(data?.credentials)throw fail('CONFIG',409);const current=await this.host.getSettings(source);await this.host.updateSettings(source,{...current.settings,managedAccount:true},current.version);}
      try{const account=await this.host.account(source,operation==='managed'?'enableManaged':'logout',{}, {signal});return {source,operation,status:'completed',account};}catch(error){if(operation==='managed'){const current=await this.host.getSettings(source);await this.host.updateSettings(source,{...current.settings,managedAccount:false},current.version);}throw error;}
    }
    if(operation==='verify'&&((body.url!==undefined&&body.url!==manifest.homepage)||(body.selector!==undefined&&body.selector!==manifest.network?.confirmation?.selector)))throw fail('BAD_REQUEST');
    if(operation==='login') {
      if(!manifest.account)throw fail('UNSUPPORTED',422);
      const credentials=body.credentials;
      if(!credentials||typeof credentials!=='object'||Array.isArray(credentials))throw fail('BAD_REQUEST');
      if(Object.keys(credentials).length>100)throw fail('BAD_REQUEST');
      const values:Record<string,string>={};
      for(const [key,value] of Object.entries(credentials)){const allowed=manifest.account.type==='cookies'?/^[!#$%&'*+.^_`|~0-9A-Za-z-]{1,128}$/.test(key):manifest.account.fields?.some(field=>field.key===key);if(!allowed||typeof value!=='string'||value.length>16384||manifest.account.type==='cookies'&&/[\u0000-\u0020\u007f;,]/.test(value))throw fail('BAD_REQUEST');values[key]=value;}
      if(Buffer.byteLength(JSON.stringify(values))>128000)throw fail('BAD_REQUEST');
      const account=await this.host.loginBrowser(source,await this.host.browserCookies(source),values,{signal});
      if(!account.loggedIn&&!(account.verified===false&&account.configured===true))throw fail('LOGIN_REQUIRED',409);
      return {source,operation,status:'completed',account};
    }
    const url=manifest.network?.confirmation ? manifest.homepage : undefined;
    if(!url)throw fail('UNSUPPORTED',422);
    const id=this.browser.create({domains:manifest.domains,navigationDomains:[...(manifest.navigationDomains ?? manifest.domains),...(manifest.account?.loginDomains ?? [])],frameDomains:manifest.frameDomains,mediaDomains:manifest.media?.domains,imageNetworkDomains:manifest.imageNetwork?.domains});
    try {
      const session=this.browser.get(id);await session.setCookies(await this.host.browserCookies(source));const result=await session.confirmation(url,manifest.network!.confirmation!,signal);
      // Navigation text alone is never proof that an account was authenticated.

      const cookies=await this.browser.get(id).cookies();
      for(const name of manifest.network?.confirmation?.requiredCookies??[])if(!cookies.some(c=>c.name===name&&c.value))throw fail('VERIFICATION_REQUIRED',409);
      await this.host.setCookies(source,cookies);
      return {source,operation,status:'completed',verification:result.verification};
    }finally{await this.browser.cancel(id);}
  }
}
export async function readSourcePackages(path: string): Promise<SourcePackage[]> { const raw=JSON.parse(await readFile(path,'utf8'));if(!Array.isArray(raw))throw fail('INVALID_MANIFEST');return raw as SourcePackage[]; }
