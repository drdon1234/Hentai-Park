import {validatePreferences} from '@hentai-park/domain-model';
import { DatabaseSync, type SQLInputValue } from 'node:sqlite';
import { isDeepStrictEqual } from 'node:util';
import { createHash,randomUUID } from 'node:crypto';
import { validateManifest,isSourceKey,sourceContract } from '@hentai-park/source-contract';
import type {PluginManifest} from '@hentai-park/source-contract';
import {normalizeConnectionEndpoint,validateConnectionSecrets} from './tavern-connections.js';
import {validateWorldbookTermPack} from './worldbook-terms.js';
import {tavernSettings as validateTavernConfiguration} from './tavern-prompt.js';
type Row = Record<string, unknown>;
export interface TavernConnectionSecretSnapshot {connection_id:string;api_key:string;key_endpoint:string;updated_at:string;version:number;}
export interface PreparedTavernConnectionSecret {connection_id:string;secret_cipher:string;key_endpoint:string;updated_at:string;version:number;}
type Validator = (value: unknown, field: string) => SQLInputValue;
type Table = {
    table: string;
    key: string[];
    fields: Record<string, Validator>;
    updated?: string;
};
const maxRows = 100000;
const sensitive = /(?:password|passwd|secret|credential|authorization|cookie|token|api[_-]?key|private[_-]?key|appLockHash|session)/i;
const transient = /^(?:mediaAuthorization|mediaToken|signedUrl|signature|hls|lease|leaseOwner|leaseGeneration|verificationHtml|contentBase64|packagePath|pluginPath|script|bodyBase64|__proto__|constructor|prototype)$/i;
function invalid(field: string): never { throw Object.assign(new Error(`Invalid backup field: ${field}`), { statusCode: 400, code: 'BAD_REQUEST', causeCategory: 'validation', retryable: false }); }
function object(value: unknown, field: string): Row {
    if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).length > 256)
        invalid(field);
    return value as Row;
}
function text(value: unknown, field: string, max = 4096): string {
    if (typeof value !== 'string' || value.length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value))
        invalid(field);
    return value;
}
const required: Validator = (value, field) => {
    const result = text(value, field, 512);
    if (!result || /[\r\n\t]/.test(result))
        invalid(field);
    return result;
};
const source: Validator = (value, field) => {
    const result = String(required(value, field));
    if (!isSourceKey(result))
        invalid(field);
    return result;
};
const identifier: Validator = (value, field) => {
    const result = String(required(value, field));
    return result;
};
const resource: Validator = (value, field) => text(value, field, 20000) || invalid(field);
const subscriptionTarget:Validator=(value,field)=>{const result=text(value,field,16384);if(!result||/[\r\n\t]/.test(result))invalid(field);return result;};
const variant: Validator = (value, field) => { const result = String(identifier(value, field)); if (result.length > 128 || /^[A-Za-z][A-Za-z0-9+.-]*:|^\/\//.test(result))
    invalid(field); return result; };
const timestamp: Validator = (value, field) => {
    const result = text(value, field, 64);
    if (!/^\d{4}-\d{2}-\d{2}T/.test(result) || !Number.isFinite(Date.parse(result)))
        invalid(field);
    return result;
};
const string: Validator = (value, field) => text(value, field, 128000);
const integer: Validator = (value, field) => {
    if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0)
        invalid(field);
    return value;
};
const number: Validator = (value, field) => {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0)
        invalid(field);
    return value;
};
const bool: Validator = (value, field) => {
    if (value !== true && value !== false && value !== 0 && value !== 1)
        invalid(field);
    return value === true || value === 1 ? 1 : 0;
};
const nullable = (validate: Validator): Validator => (value, field) => value === null ? null : validate(value, field);
const enumOf = (values: string[]): Validator => (value, field) => values.includes(String(value)) && typeof value === 'string' ? value : invalid(field);
function stableUrl(value: unknown, field: string): string {
    const raw = text(value, field, 16384);
    let url: URL;
    try {
        url = new URL(raw);
    }
    catch {
        invalid(field);
    }
    if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hostname === 'localhost' || url.hostname.endsWith('.local') || /^\d+\.\d+\.\d+\.\d+$/.test(url.hostname) || url.hostname.includes(':') || [...url.searchParams.keys()].some(key => /token|sign|key|auth|expires|x-amz|x-goog|policy/i.test(key)))
        invalid(field);
    return raw;
}
function clean(value: unknown, field: string, exporting = false, allowSecrets = false, depth = 0): unknown {
    if (depth > 16)
        invalid(field);
    if (value === null || typeof value === 'boolean' || typeof value === 'number' && Number.isFinite(value))
        return value;
    if (typeof value === 'string') {
        text(value, field, 256000);
        if (/^https?:\/\//i.test(value)) {
            try {
                return stableUrl(value, field);
            }
            catch (error) {
                if (exporting)
                    return null;
                throw error;
            }
        }
        return value;
    }
    if (Array.isArray(value)) {
        if (value.length > 20000)
            invalid(field);
        return value.map((item, index) => clean(item, `${field}[${index}]`, exporting, allowSecrets, depth + 1));
    }
    const row = object(value, field);
    const result: Row = {};
    for (const [key, item] of Object.entries(row)) {
        if (transient.test(key) || !allowSecrets && sensitive.test(key)) {
            if (exporting)
                continue;
            invalid(`${field}.${key}`);
        }
        result[key] = clean(item, `${field}.${key}`, exporting, allowSecrets, depth + 1);
    }
    return result;
}
function jsonValue(value: unknown, field: string, allowSecrets = false): string {
    const encoded = text(value, field, 2000000);
    let parsed: unknown;
    try {
        parsed = JSON.parse(encoded);
    }
    catch {
        invalid(field);
    }
    return JSON.stringify(clean(parsed, field, false, allowSecrets));
}
const json: Validator = (value, field) => jsonValue(value, field);
const tavernSettings:Validator=(value,field)=>{
    if(typeof value!=='string'||Buffer.byteLength(value)>128000)invalid(field);let parsed:Row;try{parsed=object(JSON.parse(value),field);}catch{invalid(field);}
    const allowed=['userName','persona','worldbookIds','contextTokens','maxTokens','temperature'];if(Object.keys(parsed).some(key=>!allowed.includes(key)))invalid(field);
    for(const key of ['userName','persona'])if(parsed[key]!==undefined&&(typeof parsed[key]!=='string'||String(parsed[key]).length>(key==='persona'?20000:256)||/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(String(parsed[key]))))invalid(field);
    if(parsed.worldbookIds!==undefined&&(!Array.isArray(parsed.worldbookIds)||parsed.worldbookIds.length>100||parsed.worldbookIds.some(id=>typeof id!=='string'||!id||id.length>512)))invalid(field);
    for(const key of ['contextTokens','maxTokens'])if(parsed[key]!==undefined&&(!Number.isSafeInteger(parsed[key])||Number(parsed[key])<1||Number(parsed[key])>2000000))invalid(field);
    if(parsed.temperature!==undefined&&(typeof parsed.temperature!=='number'||!Number.isFinite(parsed.temperature)||parsed.temperature<0||parsed.temperature>2))invalid(field);
    try{return JSON.stringify(validateTavernConfiguration(parsed));}catch{invalid(field);}
};
const connectionId:Validator=(value,field)=>text(value,field,128)||invalid(field);
const connectionEndpoint:Validator=(value,field)=>{try{return normalizeConnectionEndpoint(value);}catch{invalid(field);}};
const bindingEndpoint:Validator=(value,field)=>value===''?'':connectionEndpoint(value,field);
const connectionKey:Validator=(value,field)=>{const key=text(value,field,4096);if(/[\r\n\t]/.test(key))invalid(field);return key;};
const bounded=(min:number,max:number,whole=true):Validator=>(value,field)=>{if(typeof value!=='number'||!Number.isFinite(value)||value<min||value>max||whole&&!Number.isSafeInteger(value))invalid(field);return value;};
const termPayload:Validator=(value,field)=>{if(typeof value!=='string'||Buffer.byteLength(value)>8*1024*1024)invalid(field);try{return JSON.stringify(validateWorldbookTermPack(JSON.parse(value)));}catch{invalid(field);}};
const capabilities: Validator = (value, field) => {
    const encoded = jsonValue(value, field);
    const row = object(JSON.parse(encoded), field);
    if (Object.entries(row).some(([key,item])=>key==='capturedAt'?typeof item!=='string'||!Number.isFinite(Date.parse(item)):key==='sourceVersion'?typeof item!=='string':typeof item!=='boolean'))
        invalid(field);
    return encoded;
};
function ordinarySourceSettings(manifest:PluginManifest,value:unknown,exporting=false):Row{
    const settings=object(value,'sourceSettings.settings'),result:Row={};
    for(const [key,item]of Object.entries(settings)){const declaration=manifest.settings?.find(setting=>setting.key===key);if(!declaration){if(exporting)continue;invalid('sourceSettings.key');}if(declaration.type==='password'||sensitive.test(key)||key==='managedAccount'&&manifest.account?.managedAccount===true){if(exporting)continue;invalid('sourceSettings.secret');}result[key]=item;}
    return result;
}
const manifest: Validator = (value, field) => {
    const parsed = object(JSON.parse(jsonValue(value, field, true)), field);
    try {
        validateManifest(parsed);
    }
    catch {
        invalid(field);
    }
    return JSON.stringify(parsed);
};
const common = { updated_at: timestamp, version: integer };
const tables: Record<string, Table> = {
    sourceRegistry: { table: 'source_registry', key: ['source'], updated: 'updated_at', fields: { source, manifest_json: manifest, enabled: bool, updated_at: timestamp } },
    sourceSettings: { table: 'source_settings', key: ['source'], updated: 'updated_at', fields: { source, settings_json: json, updated_at: timestamp } },
        works: { table: 'works', key: ['source', 'work_id'], updated: 'updated_at', fields: { source, work_id: identifier, title: (v, f) => text(v, f, 2048) || invalid(f), cover: nullable(stableUrl), media_kind: enumOf([...sourceContract.mediaKinds]), category: required, source_category: nullable(string), summary: nullable(string), source_url: stableUrl, capability_json: capabilities, source_version: nullable(string), content_updated_at:nullable(timestamp), ...common, metadata_json: json } },
    chapters: { table: 'chapters', key: ['source', 'work_id', 'chapter_id'], fields: {text_offset:nullable(integer),node_type:nullable(enumOf(['audio','video','subtitle','image','script','other'])),node_metadata_json:json, source, work_id: identifier, chapter_id: identifier, title: (v, f) => text(v, f, 2048) || invalid(f), sort: number, read_state: enumOf(['unread', 'reading', 'read']), page_progress: nullable(integer), video_position: nullable(number), duration: nullable(number), progress_updated_at: nullable(timestamp), version: integer } },
    categories: { table: 'categories', key: ['id'], updated: 'updated_at', fields: { id: identifier, name: required, sort:number, created_at: timestamp, ...common } },
    history: { table: 'history', key: ['scope_key'], updated: 'updated_at', fields: { source, work_id: identifier, chapter_id: nullable(identifier), chapter_title: nullable(string), page: nullable(integer), page_count: nullable(integer), position: nullable(number), updated_at: timestamp, scope_key: resource } },
    novelNotes:{table:'novel_notes',key:['id'],updated:'updated_at',fields:{id:identifier,source,work_id:identifier,chapter_id:identifier,offset:integer,end_offset:integer,quote:string,note:string,bookmark:bool,...common}},
    tavernAssets:{table:'tavern_assets',key:['asset_id'],updated:'updated_at',fields:{asset_id:identifier,source,work_id:identifier,kind:enumOf(['character','lorebook']),format:enumOf(['json','png']),data_json:json,...common}},
    tavernConversations:{table:'tavern_conversations',key:['conversation_id'],updated:'updated_at',fields:{conversation_id:identifier,asset_id:identifier,messages_json:json,settings_json:tavernSettings,...common}},
    tavernConnections:{table:'tavern_connections',key:['connection_id'],updated:'updated_at',fields:{connection_id:connectionId,endpoint:connectionEndpoint,model:(value,field)=>text(value,field,200).trim()||invalid(field),temperature:bounded(0,2,false),max_tokens:bounded(1,32768),context_tokens:bounded(1024,2000000),updated_at:timestamp,version:bounded(1,Number.MAX_SAFE_INTEGER)}},
    worldbookTerms:{table:'worldbook_term_packs',key:['locale'],updated:'updated_at',fields:{locale:enumOf(['zh-Hans','zh-Hant','en','ja','ko','es','ru','ar']),pack_version:required,payload_json:termPayload,updated_at:timestamp,version:bounded(1,Number.MAX_SAFE_INTEGER)}},
    tavernConnectionSecrets:{table:'tavern_connections',key:['connection_id'],updated:'updated_at',fields:{connection_id:connectionId,api_key:connectionKey,key_endpoint:bindingEndpoint,updated_at:timestamp,version:bounded(1,Number.MAX_SAFE_INTEGER)}},
    library: { table: 'work_collections', key: ['source', 'work_id'], updated: 'updated_at', fields: { source, work_id: identifier, favorite: bool, favorited_at: nullable(timestamp), category_ids_json: json, ...common, resource_key: resource } },
    subscriptions: { table: 'subscriptions', key: ['subscription_id'], updated: 'updated_at', fields: { subscription_id: identifier, source, dimension: identifier, target: subscriptionTarget, resource_key: resource, enabled: bool, notify: bool, baseline: nullable(string), last_success: nullable(timestamp), next_due: nullable(timestamp), failures: integer, context_hash: nullable(string), deleted_at:nullable(timestamp), ...common } },
    subscriptionSeen: { table: 'subscription_seen', key: ['subscription_id', 'content_id'], fields: { subscription_id: identifier, content_id: required, observed_at: timestamp, content_version: nullable(string) } },
    subscriptionEvents: { table: 'subscription_events', key: ['event_id'], fields: { event_id: identifier, subscription_id: identifier, content_id: required, observed_at: timestamp, content_version: nullable(string), payload_json: nullable(json),content_key:nullable(string) } },
    subscriptionEventTargets:{table:'subscription_event_targets',key:['event_id','subscription_id'],fields:{event_id:identifier,subscription_id:identifier}},
    eventReadStates: { table: 'event_read_states', key: ['event_id'], fields: { event_id: identifier, read_at: timestamp } },
    settings: { table: 'app_settings', key: ['key'], updated: 'updated_at', fields: { key: identifier, value_json: json, updated_at: timestamp } },
    accounts: { table: 'source_accounts', key: ['source'], updated: 'updated_at', fields: { source, account_json: (value, field) => jsonValue(value, field, true), updated_at: timestamp } },
    downloads: { table: 'download_tasks', key: ['task_id'], fields: { recording_json:nullable(json),task_id: resource, source, work_id: identifier, chapter_id: identifier, variant, resource_key: resource, idempotency_key: resource, status: enumOf(['queued', 'running', 'paused', 'completed', 'failed', 'cancelling', 'cancelled']), completed_count: integer, total_count: integer, bytes: integer, speed: nullable(number), failure_code: nullable(required), retry_count: integer, recoverable: bool, created_at: timestamp, ...common } },
};
const defaults = ['sourceRegistry', 'sourceSettings', 'works', 'chapters', 'categories', 'history', 'novelNotes', 'tavernAssets', 'tavernConversations','tavernConnections','worldbookTerms', 'library', 'subscriptions', 'subscriptionSeen', 'subscriptionEvents', 'subscriptionEventTargets', 'eventReadStates', 'settings'];
function includes(value: unknown): string[] {
    if (!Array.isArray(value) || value.length > 32 || value.some(item => typeof item !== 'string' || !(item in tables) && item !== 'cookies') || new Set(value).size !== value.length)
        invalid('include');
    return value as string[];
}
function fieldsRow(row: Row, descriptor: Table, name: string): Row {
    const fields = Object.keys(descriptor.fields);
    if (Object.keys(row).some(key => !fields.includes(key)))
        invalid(name);
    const result: Row = {};
    for (const field of fields) {
        if (!(field in row))
            invalid(`${name}.${field}`);
        result[field] = descriptor.fields[field]!(row[field], `${name}.${field}`);
    }
    if(name==='settings'){try{validatePreferences({[String(result.key)]:JSON.parse(String(result.value_json))});}catch{invalid('settings.'+result.key);}}
    if(name==='settings'&&result.key==='novelSpeechRate'){
        const rate=JSON.parse(String(result.value_json));
        if(typeof rate!=='number'||!Number.isFinite(rate)||rate<0.5||rate>2)invalid('settings.novelSpeechRate');
    }
    return result;
}
function checkReferences(db: DatabaseSync, name: string, row: Row) {
    const require = (table: string, columns: string[], values: unknown[]) => {
        if (!db.prepare(`SELECT 1 FROM ${table} WHERE ${columns.map(column => `${column}=?`).join(' AND ')}`).get(...values as SQLInputValue[]))
            invalid(`${name}.reference`);
    };
    if (['sourceSettings', 'accounts', 'subscriptions', 'cookies'].includes(name))
        require('source_registry', ['source'], [row.source]);
    if(name==='sourceSettings'){const manifest=JSON.parse(String(db.prepare('SELECT manifest_json FROM source_registry WHERE source=?').get(String(row.source))!.manifest_json));ordinarySourceSettings(manifest,JSON.parse(String(row.settings_json)));}
    if(name==='tavernConversations')require('tavern_assets',['asset_id'],[row.asset_id]);
    if(name==='tavernConnectionSecrets')require('tavern_connections',['connection_id'],[row.connection_id]);
    if(name==='worldbookTerms'){const payload=JSON.parse(String(row.payload_json));if(payload.locale!==row.locale||payload.version!==row.pack_version)invalid('worldbookTerms.identity');}
    if(name==='novelNotes')require('chapters',['source','work_id','chapter_id'],[row.source,row.work_id,row.chapter_id]);
    if (['chapters', 'history', 'library', 'downloads'].includes(name))
        require('works', ['source', 'work_id'], [row.source, row.work_id]);
    if (name === 'history') {
        if (row.scope_key !== JSON.stringify([row.source, row.work_id, row.chapter_id]))
            invalid('history.scope_key');
        if (row.chapter_id !== null)
            require('chapters', ['source', 'work_id', 'chapter_id'], [row.source, row.work_id, row.chapter_id]);
    }
    if (name === 'library') {
        if (row.resource_key !== `collection:${JSON.stringify([row.source, row.work_id])}`)
            invalid('library.resource_key');
        const ids: unknown = JSON.parse(String(row.category_ids_json));
        if (!Array.isArray(ids))
            invalid('library.category_ids_json');
        // Category associations are IDs in the library contract; names are optional metadata.
        for (const id of ids)
            identifier(id, 'categoryId');
    }
    if (name === 'subscriptions' && row.resource_key !== `subscription:${JSON.stringify([row.source, row.dimension, row.target])}`)
        invalid('subscriptions.resource_key');
    if (name === 'downloads') {
        require('chapters', ['source', 'work_id', 'chapter_id'], [row.source, row.work_id, row.chapter_id]);
        if (row.resource_key !== `download:${JSON.stringify([row.source, row.work_id, row.chapter_id, row.variant])}`)
            invalid('downloads.resource_key');
    }
    if (['subscriptionSeen', 'subscriptionEvents'].includes(name))
        require('subscriptions', ['subscription_id'], [row.subscription_id]);
    if(name==='subscriptionEvents'&&row.content_key!==null){const subscription=db.prepare('SELECT source FROM subscriptions WHERE subscription_id=?').get(String(row.subscription_id));const payload=row.payload_json?JSON.parse(String(row.payload_json)):{};const expected=createHash('sha256').update(JSON.stringify([subscription!.source,payload.kind??'work',row.content_id])).digest('hex');if(row.content_key!==expected||payload.source!==undefined&&payload.source!==subscription!.source||payload.contentId!==undefined&&payload.contentId!==row.content_id)invalid('subscriptionEvents.content_key');}
    if(name==='subscriptionEventTargets'){require('subscriptions',['subscription_id'],[row.subscription_id]);require('subscription_events',['event_id'],[row.event_id]);}
    if (name === 'eventReadStates')
        require('domain_events', ['event_id'], [row.event_id]);
}
function upsert(db: DatabaseSync, descriptor: Table, row: Row) {
    if(['worldbook_term_packs','tavern_connections'].includes(descriptor.table)){
        const key=descriptor.key[0]!,prior=db.prepare(`SELECT * FROM ${descriptor.table} WHERE ${key}=?`).get(String(row[key]));
        if(prior&&String(row.updated_at)>=String(prior.updated_at)){const changed=Object.keys(descriptor.fields).some(field=>![key,'version','updated_at'].includes(field)&&row[field]!==prior[field]);row.version=Math.max(Number(row.version),Number(prior.version)+(changed?1:0));}
    }
    if (descriptor.table === 'chapters') {
        const prior = db.prepare('SELECT * FROM chapters WHERE source=? AND work_id=? AND chapter_id=?').get(String(row.source), String(row.work_id), String(row.chapter_id)) as Row | undefined;
        if (prior && String(prior.progress_updated_at ?? '') > String(row.progress_updated_at ?? ''))
            for (const field of ['read_state', 'page_progress', 'video_position', 'duration', 'text_offset','progress_updated_at'])
                row[field] = prior[field];
    }
    if (descriptor.table === 'source_settings' || descriptor.table === 'source_accounts') {
        const field = descriptor.table === 'source_settings' ? 'settings_json' : 'account_json';
        const prior = db.prepare(`SELECT ${field} FROM ${descriptor.table} WHERE source=?`).get(String(row.source)) as Row | undefined;
        if (prior)
            row[field] = JSON.stringify({ ...object(JSON.parse(String(prior[field])), field), ...object(JSON.parse(String(row[field])), field) });
    }
    if (descriptor.table === 'download_tasks') {
        const prior = db.prepare('SELECT * FROM download_tasks WHERE source=? AND work_id=? AND chapter_id=? AND variant=?').get(String(row.source), String(row.work_id), String(row.chapter_id), String(row.variant));
        if (prior)
            return;
    }
    const columns = Object.keys(descriptor.fields);
    const update = columns.filter(column => !descriptor.key.includes(column));
    const where = descriptor.updated ? ` WHERE excluded.${descriptor.updated}>=${descriptor.table}.${descriptor.updated}` : '';
    const conflict=update.length?`DO UPDATE SET ${update.map(column => `${column}=excluded.${column}`).join(',')}${where}`:'DO NOTHING';
    db.prepare(`INSERT INTO ${descriptor.table}(${columns.join(',')}) VALUES(${columns.map(() => '?').join(',')}) ON CONFLICT(${descriptor.key.join(',')}) ${conflict}`).run(...columns.map(column => row[column]) as SQLInputValue[]);
}
export function exportBackup(db: DatabaseSync, include: string[] = defaults, privateSnapshots?:Record<string,Row>,sourceSettingsSnapshots?:Record<string,{settings:Row;updatedAt:string}>,connectionSecretSnapshots?:TavernConnectionSecretSnapshot[]): Row {
    const selected = includes(include);
    const payload: Row = { manifest: { format: 'hentai-park-web-backup', version: 1, createdAt: new Date().toISOString(), includes: selected } };
    for (const name of selected) {
        if(name==='tavernConnectionSecrets'){
            const stored=db.prepare('SELECT connection_id,secret_cipher FROM tavern_connections').all();
            if(connectionSecretSnapshots===undefined&&stored.some(row=>Boolean(row.secret_cipher)))invalid('tavernConnectionSecrets.snapshotRequired');
            const rows=(connectionSecretSnapshots??[]).map((row,index)=>fieldsRow(row as unknown as Row,tables[name]!,name+'['+index+']'));
            try{validateConnectionSecrets(rows);}catch{invalid(name);}
            const ids=new Set(rows.map(row=>String(row.connection_id)));if(stored.some(row=>Boolean(row.secret_cipher)&&!ids.has(String(row.connection_id)))||rows.some(row=>!stored.some(record=>record.connection_id===row.connection_id)))invalid('tavernConnectionSecrets.snapshot');payload[name]=rows;continue;
        }
        if (name === 'cookies') {
            const rows=privateSnapshots?Object.entries(privateSnapshots).map(([source,state])=>({source,account_json:JSON.stringify(state),updated_at:new Date().toISOString()})):db.prepare('SELECT * FROM source_accounts').all() as unknown as Row[];
            payload.cookies = rows.flatMap(row => { const account = object(JSON.parse(String(row.account_json)), 'account'); return account.cookies === undefined ? [] : [{ source: row.source, cookies: clean(account.cookies, 'cookies', true, true), updated_at: row.updated_at }]; });
            continue;
        }
        const descriptor = tables[name]!;
        const rows:Row[] = name==='accounts'&&privateSnapshots?Object.entries(privateSnapshots).map(([source,state])=>({source,account_json:JSON.stringify(state),updated_at:new Date().toISOString()})):name==='sourceSettings'&&sourceSettingsSnapshots?Object.entries(sourceSettingsSnapshots).map(([source,state])=>({source,settings_json:JSON.stringify(state.settings),updated_at:state.updatedAt})):db.prepare(`SELECT ${Object.keys(descriptor.fields).join(',')} FROM ${descriptor.table}`).all() as unknown as Row[];
        payload[name] = rows.filter(row => name !== 'settings' || !String(row.key).startsWith('__') && !sensitive.test(String(row.key))).filter(row => name !== 'eventReadStates' || !!db.prepare('SELECT 1 FROM subscription_events WHERE event_id=?').get(String(row.event_id))).map(row => {
            const result:Row = { ...row };
            if(name==='sourceSettings'){const manifest=JSON.parse(String(db.prepare('SELECT manifest_json FROM source_registry WHERE source=?').get(String(row.source))?.manifest_json??'null'));if(!manifest)invalid('sourceSettings.source');result.settings_json=JSON.stringify(ordinarySourceSettings(manifest,JSON.parse(String(row.settings_json)),true));}
            for (const [key, value] of Object.entries(result)) {
                if (key.endsWith('_json') && value !== null) {
                    let parsed = JSON.parse(String(value));
                    if (name === 'accounts') {
                        parsed = { ...object(parsed, 'account') };
                        delete parsed.cookies;
                    }
                    result[key] = name==='tavernConversations'&&key==='settings_json'?tavernSettings(JSON.stringify(parsed),`${name}.${key}`):name==='worldbookTerms'&&key==='payload_json'?termPayload(JSON.stringify(parsed),`${name}.${key}`):JSON.stringify(clean(parsed, `${name}.${key}`, true, name === 'accounts' || key === 'manifest_json'));
                }
                else if (key === 'cover' && value !== null) {
                    try {
                        result[key] = stableUrl(value, 'cover');
                    }
                    catch {
                        result[key] = null;
                    }
                }
            }
            return fieldsRow(result, descriptor, name);
        });
    }
    return payload;
}
function connectionPreparations(rows:Row[],input:PreparedTavernConnectionSecret[]|undefined){
    try{validateConnectionSecrets(rows);}catch{invalid('tavernConnectionSecrets');}
    if(!rows.length){if(input?.length)invalid('tavernConnectionSecrets.preparation');return new Map<string,PreparedTavernConnectionSecret>();}
    if(!Array.isArray(input)||input.length!==rows.length)invalid('tavernConnectionSecrets.preparation');
    const prepared=new Map<string,PreparedTavernConnectionSecret>();
    for(const item of input){const row=object(item,'tavernConnectionSecrets.preparation');if(Object.keys(row).some(key=>!['connection_id','secret_cipher','key_endpoint','updated_at','version'].includes(key)))invalid('tavernConnectionSecrets.preparation');const plain=rows.find(value=>value.connection_id===row.connection_id);if(!plain||prepared.has(String(row.connection_id))||row.key_endpoint!==plain.key_endpoint||row.updated_at!==plain.updated_at||row.version!==plain.version||typeof row.secret_cipher!=='string'||row.secret_cipher.length>32768||Boolean(row.secret_cipher)!==Boolean(plain.api_key))invalid('tavernConnectionSecrets.preparation');
        if(row.secret_cipher){try{const cipher=object(JSON.parse(row.secret_cipher),'cipher');if(Object.keys(cipher).some(key=>!['iv','tag','data'].includes(key))||typeof cipher.iv!=='string'||typeof cipher.tag!=='string'||typeof cipher.data!=='string'||Buffer.from(cipher.iv,'base64').length!==12||Buffer.from(cipher.tag,'base64').length!==16||!Buffer.from(cipher.data,'base64').length)invalid('cipher');}catch{invalid('tavernConnectionSecrets.cipher');}}
        prepared.set(String(row.connection_id),row as unknown as PreparedTavernConnectionSecret);
    }return prepared;
}
function mergeBackup(db: DatabaseSync, value: unknown, observe?: (name:string,before:Row|undefined,incoming:Row,after:Row|undefined,remapped:boolean)=>void,connectionSecrets?:PreparedTavernConnectionSecret[]): {
    imported: true;
    counts: Record<string, number>;
    restoredSourcesDisabled: boolean;
} {
    const backup = object(value, 'backup');
    const manifestValue = object(backup.manifest, 'manifest');
    if (manifestValue.format !== 'hentai-park-web-backup' || manifestValue.version !== 1)
        invalid('manifest');
    timestamp(manifestValue.createdAt, 'manifest.createdAt');
    const names = Object.keys(backup).filter(key => key !== 'manifest');
    const selected = includes(names);
    if (manifestValue.includes !== undefined) {
        const declared = includes(manifestValue.includes);
        if (declared.length !== selected.length || declared.some(name => !selected.includes(name)))
            invalid('manifest.includes');
    }
    const prepared: Record<string, Row[]> = {};
    let total = 0;
    for (const name of selected) {
        const rows = backup[name];
        if (!Array.isArray(rows) || (total += rows.length) > maxRows)
            invalid(name);
        const unique = new Set<string>();
        prepared[name] = rows.map((value, index) => {
            const row = object(value, `${name}[${index}]`);
            if (name === 'cookies') {
                if (Object.keys(row).some(key => !['source', 'cookies', 'updated_at'].includes(key)))
                    invalid(name);
                return { source: source(row.source, 'cookies.source'), cookies: clean(row.cookies, 'cookies', false, true), updated_at: timestamp(row.updated_at, 'cookies.updated_at') };
            }
            const descriptor = tables[name]!;
            const result = fieldsRow(row, descriptor, name);
            if (name === 'settings' && (String(result.key).startsWith('__') || sensitive.test(String(result.key))))
                invalid('settings.key');
            const identity = JSON.stringify(descriptor.key.map(key => result[key]));
            if (unique.has(identity))
                invalid(`${name}.duplicate`);
            unique.add(identity);
            if (name === 'sourceRegistry') {
                const parsed = JSON.parse(String(result.manifest_json));
                if (parsed.key !== result.source)
                    invalid('sourceRegistry.source');
                result.enabled = 0;
            }
            if (name === 'downloads') {
                result.status = result.status === 'cancelled' ? 'cancelled' : 'failed';
                result.failure_code = 'BACKUP_FILES_NOT_INCLUDED';
                result.recoverable = result.recording_json===null?1:0;
                result.completed_count = 0;
                result.bytes = 0;
                result.speed = null;
            }
            return result;
        });
    }
    const encrypted=connectionPreparations(prepared.tavernConnectionSecrets??[],connectionSecrets);
    const counts: Record<string, number> = {};
    const savepoint = `backup_${randomUUID().replaceAll('-', '')}`;
    db.exec(`SAVEPOINT ${savepoint}`);
    try {
        const subscriptionIds = new Map<string, string>();
        const remappedSubscriptions = new Set<string>();
        for (const row of prepared.subscriptions ?? []) {
            const existing = db.prepare('SELECT subscription_id FROM subscriptions WHERE source=? AND dimension=? AND target=?').get(String(row.source), String(row.dimension), String(row.target)) as Row | undefined;
            if (existing && existing.subscription_id !== row.subscription_id) {
                subscriptionIds.set(String(row.subscription_id), String(existing.subscription_id));
                remappedSubscriptions.add(String(existing.subscription_id));
                row.subscription_id = existing.subscription_id;
            }
        }
        for (const name of ['subscriptionSeen', 'subscriptionEvents','subscriptionEventTargets'])
            for (const row of prepared[name] ?? [])
                row.subscription_id = subscriptionIds.get(String(row.subscription_id)) ?? row.subscription_id;
        const eventIds=new Map<string,string>(),retainedEvents=new Set<string>();
        for(const row of prepared.subscriptionEvents??[]){if(!row.content_key)continue;const existing=db.prepare('SELECT event_id,subscription_id FROM subscription_events WHERE content_key=?').get(String(row.content_key));if(existing&&existing.event_id!==row.event_id){eventIds.set(String(row.event_id),String(existing.event_id));retainedEvents.add(String(existing.event_id));row.event_id=existing.event_id;row.subscription_id=existing.subscription_id;}}
        for(const name of ['subscriptionEventTargets','eventReadStates'])for(const row of prepared[name]??[])row.event_id=eventIds.get(String(row.event_id))??row.event_id;
        for (const name of [...Object.keys(tables), 'cookies']) {
            const rows = prepared[name];
            if (!rows)
                continue;
            const descriptor = tables[name];
            counts[name] = 0;
            for (const row of rows) {
                const before=observe?mergeSnapshot(db,name,row):undefined;
                const incoming=observe?structuredClone(name==='tavernConnectionSecrets'?encrypted.get(String(row.connection_id))! as unknown as Row:row):undefined;
                checkReferences(db, name, row);
                if (name === 'subscriptionEvents') {
                    const existing = db.prepare('SELECT aggregate_type,aggregate_id FROM domain_events WHERE event_id=?').get(String(row.event_id)) as Row | undefined;
                    if (existing && (existing.aggregate_type !== 'subscription' || existing.aggregate_id !== row.subscription_id))
                        invalid('subscriptionEvents.event_id');
                }
                if(name==='tavernConnectionSecrets'){
                    const secret=encrypted.get(String(row.connection_id))!;
                    db.prepare('UPDATE tavern_connections SET secret_cipher=?,key_endpoint=?,updated_at=?,version=MAX(version,?)+1 WHERE connection_id=? AND updated_at<=?').run(secret.secret_cipher,secret.key_endpoint,secret.updated_at,secret.version,secret.connection_id,secret.updated_at);
                }
                else if (name === 'cookies') {
                    const prior = db.prepare('SELECT account_json FROM source_accounts WHERE source=?').get(String(row.source)) as Row | undefined;
                    const account = prior ? object(JSON.parse(String(prior.account_json)), 'account') : {};
                    db.prepare('INSERT INTO source_accounts(source,account_json,updated_at) VALUES(?,?,?) ON CONFLICT(source) DO UPDATE SET account_json=excluded.account_json,updated_at=excluded.updated_at').run(String(row.source), JSON.stringify({ ...account, cookies: row.cookies }), String(row.updated_at));
                }
                else {
                    if(name!=='subscriptionEvents'||!retainedEvents.has(String(row.event_id)))upsert(db, descriptor!, row);
                    if (name === 'subscriptionEvents' && !db.prepare('SELECT 1 FROM domain_events WHERE event_id=?').get(String(row.event_id))) {
                        const sequence = Number((db.prepare('SELECT COALESCE(MAX(sequence),0)+1 AS n FROM domain_events').get() as Row).n);
                        const eventVersion = Number((db.prepare("SELECT COALESCE(MAX(event_version),0)+1 AS n FROM domain_events WHERE aggregate_type='subscription' AND aggregate_id=?").get(String(row.subscription_id)) as Row).n);
                        const version = Number((db.prepare('SELECT version FROM subscriptions WHERE subscription_id=?').get(String(row.subscription_id)) as Row).version);
                        db.prepare("INSERT INTO domain_events(event_id,sequence,event_type,aggregate_type,aggregate_id,aggregate_version,event_version,created_at,payload_json) VALUES(?,?,'subscription.updated','subscription',?,?,?,?,?)").run(String(row.event_id), sequence, String(row.subscription_id), version, eventVersion, String(row.observed_at), JSON.stringify({ subscriptionId: row.subscription_id, contentId: row.content_id, contentVersion: row.content_version }));
                        db.prepare('INSERT INTO event_outbox(event_id) VALUES(?)').run(String(row.event_id));
                    }
                }
                counts[name]!++;
                if(observe)observe(name,before,incoming!,mergeSnapshot(db,name,row),name==='subscriptions'&&remappedSubscriptions.has(String(row.subscription_id)));
            }
        }
        if (prepared.settings?.length) {
            const prior = db.prepare("SELECT value_json FROM app_settings WHERE key='__version'").get() as Row | undefined;
            const version = Number(prior ? JSON.parse(String(prior.value_json)) : 0) + 1;
            db.prepare("INSERT INTO app_settings(key,value_json,updated_at) VALUES('__version',?,?) ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json,updated_at=excluded.updated_at").run(JSON.stringify(version), new Date().toISOString());
        }
        db.exec(`RELEASE ${savepoint}`);
        return { imported: true, counts, restoredSourcesDisabled: !!prepared.sourceRegistry?.length };
    }
    catch (error) {
        db.exec(`ROLLBACK TO ${savepoint}`);
        db.exec(`RELEASE ${savepoint}`);
        throw error;
    }
}


export function importBackup(db:DatabaseSync,value:unknown,connectionSecrets?:PreparedTavernConnectionSecret[]){return mergeBackup(db,value,undefined,connectionSecrets);}

/** Both preview and commit call this before touching the real database or private store. */
export async function preparePrivateBackup(db:DatabaseSync,value:unknown,validatePrivate:(manifest:PluginManifest,payload:unknown,options:{includeAccounts?:boolean;includeCookies?:boolean})=>unknown){
    try{
    const backup=object(value,'backup');const states=new Map<string,Row>();
    if(backup.tavernConnectionSecrets!==undefined){if(!Array.isArray(backup.tavernConnectionSecrets))invalid('tavernConnectionSecrets');const rows=backup.tavernConnectionSecrets.map((row,index)=>fieldsRow(object(row,'tavernConnectionSecrets'),tables.tavernConnectionSecrets!,'tavernConnectionSecrets['+index+']'));validateConnectionSecrets(rows);}
    const getManifest=(key:string):PluginManifest=>{const imported=Array.isArray(backup.sourceRegistry)?backup.sourceRegistry.find((row:Row)=>row.source===key):undefined;const current=db.prepare('SELECT manifest_json FROM source_registry WHERE source=?').get(key);const encoded=imported?.manifest_json??current?.manifest_json;if(typeof encoded!=='string')invalid('private.source');const manifest=JSON.parse(encoded);validateManifest(manifest);return manifest;};
    for(const item of Array.isArray(backup.sourceSettings)?backup.sourceSettings:[]){const row=object(item,'sourceSettings'),key=String(source(row.source,'sourceSettings.source')),manifest=getManifest(key),settings=ordinarySourceSettings(manifest,JSON.parse(String(row.settings_json)));await validatePrivate(manifest,{source:key,settings},{includeAccounts:true});}
    for(const item of Array.isArray(backup.accounts)?backup.accounts:[]){const row=object(item,'accounts');const key=String(source(row.source,'accounts.source'));states.set(key,{...object(JSON.parse(String(row.account_json)),'account'),source:key});}
    for(const item of Array.isArray(backup.cookies)?backup.cookies:[]){const row=object(item,'cookies');const key=String(source(row.source,'cookies.source'));states.set(key,{...states.get(key),source:key,cookies:row.cookies});}
    for(const [key,state]of states){const manifest=getManifest(key);await validatePrivate(manifest,state,{includeAccounts:state.data!==undefined||state.settings!==undefined,includeCookies:state.cookies!==undefined});}
    }catch{invalid('private');}
}

export interface BackupPartitionPreview {incoming:number;added:number;replaced:number;retained:number;conflicts:number;}
const emptyPreview=():BackupPartitionPreview=>({incoming:0,added:0,replaced:0,retained:0,conflicts:0});
function mergeSnapshot(db:DatabaseSync,name:string,row:Row):Row|undefined{
    if(name==='tavernConnectionSecrets')return db.prepare('SELECT connection_id,secret_cipher,key_endpoint,updated_at,version FROM tavern_connections WHERE connection_id=?').get(String(row.connection_id)) as Row|undefined;
    if(name==='cookies'){const record=db.prepare('SELECT account_json,updated_at FROM source_accounts WHERE source=?').get(String(row.source));if(!record)return undefined;const account=object(JSON.parse(String(record.account_json)),'account');return {source:row.source,cookies:account.cookies??null,updated_at:record.updated_at};}
    const descriptor=tables[name]!;const keys=name==='downloads'?['source','work_id','chapter_id','variant']:descriptor.key;
    return db.prepare(`SELECT ${Object.keys(descriptor.fields).join(',')} FROM ${descriptor.table} WHERE ${keys.map(key=>key+'=?').join(' AND ')}`).get(...keys.map(key=>row[key]) as SQLInputValue[]) as Row|undefined;
}
function hasConflict(name:string,before:Row,incoming:Row):boolean{
    const keys=tables[name]?.key??['source'];
    return Object.keys(incoming).some(field=>{
        if(keys.includes(field)||['updated_at','created_at','observed_at','read_at','progress_updated_at','version'].includes(field))return false;
        if((name==='sourceSettings'&&field==='settings_json')||(name==='accounts'&&field==='account_json')){const prior=object(JSON.parse(String(before[field])),field),next=object(JSON.parse(String(incoming[field])),field);return Object.entries(next).some(([key,value])=>key in prior&&!isDeepStrictEqual(prior[key],value));}
        if(field.endsWith('_json')&&before[field]!==null&&incoming[field]!==null)return !isDeepStrictEqual(JSON.parse(String(before[field])),JSON.parse(String(incoming[field])));
        return !isDeepStrictEqual(before[field],incoming[field]);
    });
}
/** Read-only snapshot: merge simulation never writes a page, WAL frame or event to the real database. */
function previewDatabase(db:DatabaseSync):DatabaseSync{
    const scratch=new DatabaseSync(':memory:');
    try{scratch.exec('PRAGMA temp_store=MEMORY;PRAGMA journal_mode=MEMORY;PRAGMA foreign_keys=OFF');const names=[...new Set([...Object.values(tables).map(table=>table.table),'domain_events','event_outbox'])];
        for(const table of names){const schema=db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name=?").get(table);if(!schema?.sql)invalid('database.schema');scratch.exec(String(schema.sql));}
        scratch.exec('BEGIN');
        for(const table of names){const columns=(db.prepare(`PRAGMA table_info(${table})`).all() as unknown as Row[]).map(column=>String(column.name));const insert=scratch.prepare(`INSERT INTO ${table}(${columns.join(',')}) VALUES(${columns.map(()=>'?').join(',')})`);for(const row of db.prepare(`SELECT ${columns.join(',')} FROM ${table}`).iterate())insert.run(...columns.map(column=>row[column]) as SQLInputValue[]);}
        for(const table of names)for(const index of db.prepare("SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name=? AND sql IS NOT NULL").all(table))scratch.exec(String(index.sql));
        scratch.exec('COMMIT;PRAGMA foreign_keys=ON');return scratch;
    }catch(error){scratch.close();throw error;}
}
export function previewBackupImport(db:DatabaseSync,value:unknown,connectionSecrets?:PreparedTavernConnectionSecret[]){
    const scratch=previewDatabase(db);const partitions:Record<string,BackupPartitionPreview>={};
    try{const result=mergeBackup(scratch,value,(name,before,incoming,after,remapped)=>{const summary=partitions[name]??=emptyPreview();summary.incoming++;if(!before)summary.added++;else if(isDeepStrictEqual(before,after))summary.retained++;else summary.replaced++;if(before&&(remapped||hasConflict(name,before,incoming)))summary.conflicts++;},connectionSecrets);
        for(const name of Object.keys(result.counts))partitions[name]??=emptyPreview();
        const totals=emptyPreview();for(const summary of Object.values(partitions))for(const key of Object.keys(totals) as Array<keyof BackupPartitionPreview>)totals[key]+=summary[key];
        return {preview:true as const,canImport:true as const,partitions,totals,restoredSourcesDisabled:result.restoredSourcesDisabled};
    }finally{scratch.close();}
}
