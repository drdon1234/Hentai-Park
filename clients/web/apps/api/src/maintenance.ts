import {mkdir,readdir,writeFile,rename,unlink,readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import type {DatabaseSync} from 'node:sqlite';
import {exportBackup} from './backup.js';
/** Local scheduled work. Source updates are checked only; installation still needs review. */
export class Maintenance {
 private timer:ReturnType<typeof setInterval>|undefined;private running:Promise<void>|undefined;private abort=new AbortController();
 constructor(private db:DatabaseSync,private directory:string,private library:(signal:AbortSignal)=>Promise<unknown>,private sources:(signal:AbortSignal)=>Promise<unknown>,private notify:(id:string)=>void=()=>{},private snapshot:()=>Promise<unknown>=async()=>exportBackup(db)){}
 private read(key:string,fallback:unknown){const row=this.db.prepare('SELECT value_json FROM app_settings WHERE key=?').get(key);return row?JSON.parse(String(row.value_json)):fallback;}
 private write(key:string,value:unknown){this.db.prepare('INSERT INTO app_settings(key,value_json,updated_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json,updated_at=excluded.updated_at').run(key,JSON.stringify(value),new Date().toISOString());}
 start(){this.timer=setInterval(()=>void this.tick(),60000);this.timer.unref();void this.tick();}
 tick(){if(this.running)return this.running;this.running=this.run().finally(()=>{this.running=undefined;});return this.running;}
 async stop(){if(this.timer)clearInterval(this.timer);this.abort.abort();await this.running;}
 private async run(){
  for(const [name,hours,action] of [['Backup',Number(this.read('autoBackupHours',24)),()=>this.backup()],['Library',Number(this.read('libraryUpdateHours',0)),()=>this.library(this.abort.signal)],['Source',this.read('autoSourceUpdates',true)?12:0,()=>this.sources(this.abort.signal)]] as const){
   if(this.abort.signal.aborted)return;const elapsed=Date.now()-Number(this.read('last'+name+'Update',0));if(hours<=0||elapsed>=0&&elapsed<hours*3600000)continue;
   try{const result=await action();this.write('last'+name+'Update',Date.now());this.write('maintenance'+name,{at:new Date().toISOString(),status:'completed',result});}
   catch(error){if(this.abort.signal.aborted)return;this.write('maintenance'+name,{at:new Date().toISOString(),status:'failed',code:(error as {code?:string}).code??'MAINTENANCE_FAILED'});this.write('last'+name+'Update',Date.now());}
  }
  if(this.read('deleteAfterRead',false)!==true)return;
  const rows=this.db.prepare("SELECT d.task_id,d.resource_key FROM download_tasks d JOIN chapters c USING(source,work_id,chapter_id) WHERE d.source<>'_local' AND d.status='completed' AND c.read_state='read' AND d.recording_json IS NULL AND NOT EXISTS(SELECT 1 FROM deletion_intents i WHERE i.task_id=d.task_id)").all();
  for(const row of rows){const id=String(row.task_id);this.db.prepare('INSERT OR IGNORE INTO deletion_intents(intent_id,resource_key,task_id,status,requested_at) VALUES(?,?,?,?,?)').run(randomUUID(),String(row.resource_key),id,'pending',new Date().toISOString());this.notify(id);}
 }
 private async backup(){const dir=join(this.directory,'automatic-backups');await mkdir(dir,{recursive:true});const filename='backup-'+Date.now()+'-'+randomUUID()+'.json',temp=join(dir,filename+'.tmp'),body=JSON.stringify(await this.snapshot());await writeFile(temp,body,{mode:0o600});JSON.parse(await readFile(temp,'utf8'));await rename(temp,join(dir,filename));const files=(await readdir(dir)).filter(name=>/^backup-\d+-[a-f0-9-]+\.json$/.test(name)).sort().reverse();for(const name of files.slice(Number(this.read('autoBackupKeep',3))))await unlink(join(dir,name));return {filename,bytes:Buffer.byteLength(body)};}
}
