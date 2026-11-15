import { DatabaseSync } from 'node:sqlite';
import { createHash, createDecipheriv, randomUUID } from 'node:crypto';
import { closeSync, existsSync, lstatSync, mkdirSync, openSync, readSync, realpathSync, rmSync, statSync } from 'node:fs';
import { mkdir, open, rename, rm } from 'node:fs/promises';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { decodeImage,unwrapHlsResource } from '@hentai-park/source-host';
export interface PendingTask {
    task_id: string;
    status: string;
}
export function recoverPendingTasks(db: DatabaseSync): PendingTask[] {
    return db.prepare("SELECT task_id,status FROM download_tasks WHERE status IN ('queued','running','cancelling')").all() as unknown as PendingTask[];
}
const DOWNLOAD_TRANSITIONS: Record<string, readonly string[]> = {
    pause: ['running'],
    resume: ['paused'],
    retry: ['failed'],
    cancel: ['queued', 'running', 'paused', 'failed'],
};
export function transitionDownloadStatus(db: DatabaseSync, taskId: string, operation: keyof typeof DOWNLOAD_TRANSITIONS, now = new Date()) {
    const row = db.prepare('SELECT status,recoverable,version,recording_json FROM download_tasks WHERE task_id=?').get(taskId) as {
        status?: string;
        recoverable?: number;
        version?: number;
        recording_json?:string|null;
    } | undefined;
    if (!row)
        throw Object.assign(new Error('Download task not found'), { code: 'NOT_FOUND' });
    if (!DOWNLOAD_TRANSITIONS[operation].includes(String(row.status)))
        throw Object.assign(new Error(`Invalid download transition ${operation}`), { code: 'INVALID_STATE' });
    if (operation === 'retry' && Number(row.recoverable) !== 1)
        throw Object.assign(new Error('Download task is not recoverable'), { code: 'NOT_RECOVERABLE' });
    const target = operation === 'pause' ? 'paused' : operation === 'resume' ? row.recording_json?'queued':'running' : operation === 'retry' ? 'queued' : 'cancelling';
    db.prepare("UPDATE download_tasks SET status=?,retry_count=retry_count+?,speed=NULL,bytes=(SELECT COALESCE(SUM(bytes),0) FROM download_files WHERE task_id=download_tasks.task_id AND status='completed'),updated_at=?,version=version+1 WHERE task_id=?").run(target, operation === 'retry' ? 1 : 0, now.toISOString(), taskId);
    db.prepare('UPDATE task_leases SET cancellation_requested=1,lease_expires_at=? WHERE task_id=?').run(now.toISOString(), taskId);
    return target;
}
export function acquireLease(db: DatabaseSync, taskId: string, owner: string, ttlMs = 30000) {
    const now = new Date();
    const expires = new Date(now.getTime() + ttlMs).toISOString();
    db.exec('BEGIN IMMEDIATE');
    try {
        const task = db.prepare('SELECT status FROM download_tasks WHERE task_id=?').get(taskId) as {
            status?: string;
        } | undefined;
        if (!task)
            throw Object.assign(new Error('Task not found'), { code: 'TASK_NOT_FOUND' });
        if (!['queued', 'running'].includes(String(task.status)))
            throw Object.assign(new Error('Task is not active'), { code: 'TASK_NOT_ACTIVE' });
        const row = db.prepare('SELECT lease_owner,lease_expires_at,lease_generation FROM task_leases WHERE task_id=?').get(taskId) as {
            lease_owner?: string;
            lease_expires_at?: string;
            lease_generation?: number;
        } | undefined;
        if (row && new Date(row.lease_expires_at ?? 0).getTime() > now.getTime())
            throw Object.assign(new Error('Lease is still active'), { code: 'LEASE_HELD' });
        const generation = (row?.lease_generation ?? 0) + 1;
        db.prepare(`INSERT INTO task_leases(task_id,lease_owner,lease_expires_at,heartbeat_at,lease_generation) VALUES(?,?,?,?,?) ON CONFLICT(task_id) DO UPDATE SET lease_owner=excluded.lease_owner,lease_expires_at=excluded.lease_expires_at,heartbeat_at=excluded.heartbeat_at,lease_generation=excluded.lease_generation,cancellation_requested=0`).run(taskId, owner, expires, now.toISOString(), generation);
        {
            db.prepare("UPDATE download_tasks SET status='running',speed=NULL,bytes=(SELECT COALESCE(SUM(bytes),0) FROM download_files WHERE task_id=download_tasks.task_id AND status='completed'),updated_at=?,version=version+1 WHERE task_id=?").run(now.toISOString(), taskId);
            recordEvent(db, 'download.statusChanged', 'download', taskId, { taskId, status: 'running' });
        }
        db.exec('COMMIT');
        return { taskId, leaseOwner: owner, leaseExpiresAt: expires, leaseGeneration: generation };
    }
    catch (e) {
        db.exec('ROLLBACK');
        throw e;
    }
}
export function assertLease(db: DatabaseSync, taskId: string, owner: string, generation: number, now = new Date()) {
    const row = db.prepare('SELECT lease_owner,lease_expires_at,lease_generation,cancellation_requested FROM task_leases WHERE task_id=?').get(taskId) as {
        lease_owner?: string;
        lease_expires_at?: string;
        lease_generation?: number;
        cancellation_requested?: number;
    } | undefined;
    const task = db.prepare('SELECT status FROM download_tasks WHERE task_id=?').get(taskId) as {
        status?: string;
    } | undefined;
    if (!row || task?.status !== 'running' || row.lease_owner !== owner || row.lease_generation !== generation || Number(row.cancellation_requested) !== 0 || new Date(row.lease_expires_at ?? 0).getTime() <= now.getTime() || db.prepare("SELECT 1 FROM deletion_intents WHERE task_id=? AND status='pending'").get(taskId))
        throw Object.assign(new Error('Lease fencing check failed'), { code: 'LEASE_FENCED' });
    return true;
}
export function releaseLeases(db: DatabaseSync, owner: string, now = new Date()) {
    const result = db.prepare('UPDATE task_leases SET lease_expires_at=?,recovered_at=? WHERE lease_owner=?').run(now.toISOString(), now.toISOString(), owner);
    return Number(result.changes);
}
export function canonicalDownloadPath(downloadDir: string, task: {
    task_id: unknown;
    resource_key: unknown;
}, file: {
    resource_key: unknown;
    path?: unknown;
}, extension?: 'bin' | 'm3u8') {
    const taskId = runtimeText(task.task_id, 'taskId', 4096), resourceKey = runtimeText(task.resource_key, 'resourceKey', 4096), fileKey = runtimeText(file.resource_key, 'fileResourceKey', 8192);
    const prefix = `${resourceKey}:file:`;
    if (!fileKey.startsWith(prefix))
        throw permanent('DOWNLOAD_PATH_INVALID');
    const raw = fileKey.slice(prefix.length);
    if (!/^(?:0|[1-9]\d{0,4})$/.test(raw) || Number(raw) > 20000)
        throw permanent('DOWNLOAD_PATH_INVALID');
    const folder = join(resolve(downloadDir), createHash('sha256').update(taskId).digest('hex')), stem = String(Number(raw)).padStart(6, '0');
    const bin = safePath(downloadDir, join(folder, `${stem}.bin`)), manifest = safePath(downloadDir, join(folder, `${stem}.m3u8`));
    if (extension !== undefined) {
        if (extension !== 'bin' && extension !== 'm3u8')
            throw permanent('DOWNLOAD_PATH_INVALID');
        return extension === 'bin' ? bin : manifest;
    }
    const candidates = [bin, manifest].filter(path => existsSync(path));
    if (candidates.length > 1)
        throw permanent('DOWNLOAD_PATH_INVALID');
    if (candidates.length === 1)
        return candidates[0]!;
    // The previous absolute root is never inspected. Only its filename can describe the expected extension.
    const basename = typeof file.path === 'string' ? file.path.replaceAll('\\', '/').split('/').at(-1) : undefined;
    const match = basename === `${stem}.bin` ? 'bin' : basename === `${stem}.m3u8` ? 'm3u8' : undefined;
    if (!match)
        throw permanent('DOWNLOAD_PATH_INVALID');
    return match === 'bin' ? bin : manifest;
}
function markFileFailure(db: DatabaseSync, taskId: string, code: string, recoverable: boolean) { const now = new Date().toISOString(); const result = db.prepare("UPDATE download_tasks SET status='failed',speed=NULL,bytes=(SELECT COALESCE(SUM(bytes),0) FROM download_files WHERE task_id=download_tasks.task_id AND status='completed'),failure_code=?,recoverable=?,updated_at=?,version=version+1 WHERE task_id=? AND status!='cancelled' AND (status!='failed' OR failure_code IS NOT ?)").run(code, recoverable ? 1 : 0, now, taskId, code); if (Number(result.changes))
    recordEvent(db, 'download.statusChanged', 'download', taskId, { taskId, status: 'failed', failureCode: code }); }
export function reconcileDeletionIntents(db: DatabaseSync, downloadDir?: string, removeFile?: (path: string) => void, canDelete: (taskId: string) => boolean = () => true) {
    const intents = db.prepare("SELECT intent_id,resource_key,task_id FROM deletion_intents WHERE status='pending' ORDER BY requested_at").all() as unknown as Array<Record<string, unknown>>;
    let completed = 0;
    db.exec('BEGIN IMMEDIATE');
    try {
        for (const intent of intents) {
            const resourceKey = typeof intent.resource_key === 'string' ? intent.resource_key : '';
            const taskId = typeof intent.task_id === 'string' ? intent.task_id : null;
            if (taskId && !canDelete(taskId))
                continue;
            const task = taskId ? db.prepare('SELECT task_id,resource_key FROM download_tasks WHERE task_id=?').get(taskId) as {
                task_id: unknown;
                resource_key: unknown;
            } | undefined : undefined;
            const files = db.prepare('SELECT * FROM download_files WHERE resource_key=? OR task_id=?').all(resourceKey, taskId) as unknown as Array<Record<string, unknown>>;
            const paths: string[] = [];
            let invalidPath = false;
            for (const file of files) {
                try {
                    if (!downloadDir || !task)
                        throw permanent('DOWNLOAD_PATH_INVALID');
                    paths.push(canonicalDownloadPath(downloadDir, task, { resource_key: file.resource_key, path: file.path }));
                }
                catch {
                    invalidPath = true;
                    break;
                }
            }
            if (invalidPath) {
                if (taskId)
                    markFileFailure(db, taskId, 'DOWNLOAD_PATH_INVALID', false);
                continue;
            }
            for (const [index, file] of files.entries()) {
                if (paths[index]) {
                    if (!removeFile)
                        throw permanent('FILE_REMOVER_UNAVAILABLE');
                    removeFile(paths[index]!);
                }
                if (typeof file.id === 'number')
                    db.prepare('DELETE FROM download_files WHERE id=?').run(file.id);
            }
            if (taskId)
                db.prepare('DELETE FROM download_tasks WHERE task_id=?').run(taskId);
            if (typeof intent.intent_id !== 'string')
                continue;
            db.prepare("UPDATE deletion_intents SET status='completed',completed_at=? WHERE intent_id=?").run(new Date().toISOString(), intent.intent_id);
            if (taskId)
                recordEvent(db, 'download.statusChanged', 'download', taskId, { taskId });
            completed += 1;
        }
        db.exec('COMMIT');
    }
    catch (error) {
        try {
            db.exec('ROLLBACK');
        }
        catch { }
        throw error;
    }
    return completed;
}
export function reconcileDownloadFiles(db: DatabaseSync, downloadDir: string | undefined, fileExists: (path: string) => boolean = existsSync, verifyHashes = true) {
    const files = db.prepare('SELECT f.*,t.resource_key AS task_resource_key FROM download_files f JOIN download_tasks t ON t.task_id=f.task_id').all() as unknown as Array<Record<string, unknown>>;
    let missing = 0;
    db.exec('BEGIN IMMEDIATE');
    try {
        for (const file of files) {
            let path: string;
            try {
                if (!downloadDir)
                    throw permanent('DOWNLOAD_PATH_INVALID');
                path = canonicalDownloadPath(downloadDir, { task_id: file.task_id, resource_key: file.task_resource_key }, { resource_key: file.resource_key, path: file.path });
            }
            catch {
                missing++;
                db.prepare("UPDATE download_files SET status='pending',updated_at=? WHERE id=?").run(new Date().toISOString(), Number(file.id));
                markFileFailure(db, String(file.task_id), 'DOWNLOAD_PATH_INVALID', false);
                continue;
            }
            if (file.path !== path)
                db.prepare('UPDATE download_files SET path=?,updated_at=? WHERE id=?').run(path, new Date().toISOString(), Number(file.id));
            if (file.status !== 'completed')
                continue;
            let exists = fileExists(path);
            if (exists && existsSync(path)) {
                exists = statSync(path).size === Number(file.bytes);
                const checkpoint = db.prepare('SELECT checkpoint_json FROM restore_checkpoints WHERE task_id=?').get(String(file.task_id)) as Record<string, unknown> | undefined;
                const hashes = checkpoint ? JSON.parse(String(checkpoint.checkpoint_json)).hashes as Record<string, string> | undefined : undefined;
                if (exists && verifyHashes && hashes?.[String(file.resource_key)])
                    exists = fileDigest(path) === hashes[String(file.resource_key)];
            }
            if (!exists) {
                missing += 1;
                db.prepare("UPDATE download_files SET status='pending',updated_at=? WHERE id=?").run(new Date().toISOString(), file.id as number);
                if (typeof file.task_id === 'string')
                    markFileFailure(db, file.task_id, 'FILE_MISSING', true);
            }
        }
        db.exec('COMMIT');
    }
    catch (error) {
        try {
            db.exec('ROLLBACK');
        }
        catch { }
        throw error;
    }
    return missing;
}
export function appendOutboxEvent(db: DatabaseSync, event: {
    eventId: string;
    sequence: number;
    eventType: string;
    aggregateType: string;
    aggregateId: string;
    aggregateVersion: number;
    eventVersion: number;
    payload: unknown;
}) {
    db.exec('BEGIN IMMEDIATE');
    try {
        appendOutboxEventInTransaction(db, event);
        db.exec('COMMIT');
    }
    catch (error) {
        db.exec('ROLLBACK');
        throw error;
    }
}
function appendOutboxEventInTransaction(db: DatabaseSync, event: {
    eventId: string;
    sequence: number;
    eventType: string;
    aggregateType: string;
    aggregateId: string;
    aggregateVersion: number;
    eventVersion: number;
    payload: unknown;
}) { const now = new Date().toISOString(); db.prepare('INSERT INTO domain_events(event_id,sequence,event_type,aggregate_type,aggregate_id,aggregate_version,event_version,created_at,payload_json) VALUES(?,?,?,?,?,?,?,?,?)').run(event.eventId, event.sequence, event.eventType, event.aggregateType, event.aggregateId, event.aggregateVersion, event.eventVersion, now, JSON.stringify(event.payload)); db.prepare('INSERT INTO event_outbox(event_id) VALUES(?)').run(event.eventId); }
function recordEvent(db: DatabaseSync, eventType: string, aggregateType: string, aggregateId: string, payload: unknown, eventId = randomUUID()) {
    const sequence = Number((db.prepare('SELECT COALESCE(MAX(sequence),0)+1 AS value FROM domain_events').get() as {
        value: number;
    }).value);
    const eventVersion = Number((db.prepare('SELECT COALESCE(MAX(event_version),0)+1 AS value FROM domain_events WHERE aggregate_type=? AND aggregate_id=?').get(aggregateType, aggregateId) as {
        value: number;
    }).value);
    const row = aggregateType === 'download' ? db.prepare('SELECT version FROM download_tasks WHERE task_id=?').get(aggregateId) : db.prepare('SELECT version FROM subscriptions WHERE subscription_id=?').get(aggregateId);
    appendOutboxEventInTransaction(db, { eventId, sequence, eventType, aggregateType, aggregateId, aggregateVersion: Number((row as {
            version?: number;
        } | undefined)?.version ?? eventVersion), eventVersion, payload });
}
export function claimOutbox(db: DatabaseSync, limit = 100) {
    const rows = db.prepare('SELECT o.event_id,e.sequence,e.event_type,e.aggregate_type,e.aggregate_id,e.payload_json FROM event_outbox o JOIN domain_events e ON e.event_id=o.event_id WHERE o.published_at IS NULL ORDER BY e.sequence LIMIT ?').all(limit) as unknown as Array<Record<string, unknown>>;
    return rows;
}
export function markOutboxPublished(db: DatabaseSync, eventId: string) {
    db.prepare('UPDATE event_outbox SET published_at=?,attempts=attempts+1 WHERE event_id=? AND published_at IS NULL').run(new Date().toISOString(), eventId);
}
export function deliverOnce(db: DatabaseSync, eventId: string, consumerId: string) {
    const result = db.prepare('INSERT OR IGNORE INTO event_deliveries(event_id,consumer_id,delivered_at) VALUES(?,?,?)').run(eventId, consumerId, new Date().toISOString());
    return Number(result.changes) === 1;
}
export interface ObservedContent {contentId:string;contentVersion?:string;kind?:string;title?:string;workId?:string;chapterId?:string;}
export function checkSubscription(db: DatabaseSync, subscriptionId: string, observed: readonly ObservedContent[]) {
    db.exec('BEGIN IMMEDIATE');
    try {
        const now = new Date().toISOString();
        const subscription = db.prepare('SELECT baseline,source,notify FROM subscriptions WHERE subscription_id=? AND enabled=1').get(subscriptionId) as {
            baseline: string | null;source:string;notify:number;
        } | undefined;
        if (!subscription) {
            db.exec('COMMIT');
            return;
        }
        const newItems: ObservedContent[] = [];
        for (const item of observed) {
            runtimeText(item.contentId, 'contentId');
            if (item.contentVersion !== undefined)
                runtimeText(item.contentVersion, 'contentVersion');
            const identity=JSON.stringify([item.kind??'work',item.contentId]);
            const result = db.prepare('INSERT OR IGNORE INTO subscription_seen(subscription_id,content_id,observed_at,content_version) VALUES(?,?,?,?)').run(subscriptionId, identity, now, item.contentVersion ?? null);
            if (Number(result.changes) === 1)
                newItems.push(item);
        }
        db.prepare("UPDATE subscriptions SET baseline=COALESCE(baseline,?),last_success=?,failures=0,updated_at=?,version=version+1 WHERE subscription_id=?").run(now, now, now, subscriptionId);
        if (subscription.baseline !== null)
            for (const item of newItems) {
                const contentKey=createHash('sha256').update(JSON.stringify([subscription.source,item.kind??'work',item.contentId])).digest('hex');
                const prior=db.prepare('SELECT event_id FROM subscription_events WHERE content_key=?').get(contentKey);
                if(prior){db.prepare('INSERT OR IGNORE INTO subscription_event_targets VALUES(?,?)').run(prior.event_id,subscriptionId);if(subscription.notify===1){const existing=db.prepare('SELECT payload_json FROM subscription_events WHERE event_id=?').get(prior.event_id);const payload=JSON.parse(String(existing?.payload_json??'{}'));if(payload.notify!==true){payload.notify=true;db.prepare('UPDATE subscription_events SET payload_json=? WHERE event_id=?').run(JSON.stringify(payload),prior.event_id);recordEvent(db,'subscription.updated','subscription',subscriptionId,{...payload,eventId:prior.event_id});}}continue;}
                const eventId = randomUUID();
                const payload={...item,source:subscription.source,subscriptionId,notify:subscription.notify===1};
                db.prepare('INSERT INTO subscription_events(event_id,subscription_id,content_id,observed_at,content_version,payload_json,content_key) VALUES(?,?,?,?,?,?,?)').run(eventId, subscriptionId, item.contentId, now, item.contentVersion ?? null, JSON.stringify(payload),contentKey);
                db.prepare('INSERT INTO subscription_event_targets VALUES(?,?)').run(eventId,subscriptionId);
                recordEvent(db, 'subscription.updated', 'subscription', subscriptionId, payload, eventId);
            }
        db.prepare('INSERT INTO subscription_checks(subscription_id,checked_at,success) VALUES(?,?,1)').run(subscriptionId, now);
        recordEvent(db, 'subscription.updated', 'subscription', subscriptionId, { subscriptionId, kind: 'check', success: true, checkedAt: now });
        db.exec('COMMIT');
    }
    catch (error) {
        db.exec('ROLLBACK');
        throw error;
    }
}
export interface WorkerSchedulerOptions {
    owner?: string;
    intervalMs?: number;
    leaseTtlMs?: number;
    maxConcurrentTasks?: number;
    downloadSettings?:()=>{siteConcurrency:number;taskConcurrency:number;pageConcurrency:number};
    taskTimeoutMs?: number;
    subscriptionTimeoutMs?: number;
    subscriptionIntervalMs?: number;
    subscriptionSettings?:()=>{enabled:boolean;intervalMs:number};
    downloadDir?: string;
    outboxBatchSize?: number;
    processTask?: (task: PendingTask, lease: TaskLease, signal?: AbortSignal) => Promise<void> | void;
    downloadAdapter?: DownloadTaskAdapter;
    pollSubscription?: (subscription: Record<string, unknown>) => Promise<readonly {
        contentId: string;
        contentVersion?: string;
    }[]>;
    subscriptionAdapter?: SubscriptionAdapter;
    publishEvent?: (event: Record<string, unknown>) => Promise<void> | void;
    removeFile?: (path: string) => void;
    fileExists?: (path: string) => boolean;
    onError?: (error: unknown) => void;
}
export interface TaskLease {
    taskId: string;
    leaseOwner: string;
    leaseExpiresAt: string;
    leaseGeneration: number;
}
export interface DownloadTaskAdapter {
    execute(task: Record<string, unknown>, context: DownloadContext): Promise<DownloadResult>;
}
export interface DownloadContext {
    lease: TaskLease;
    assertLease: () => void;
    signal?: AbortSignal;
}
interface DownloadEntry {
    url: string;
    kind: string;
    data?: Uint8Array;
    key?: Uint8Array;
    iv?: Uint8Array;
    mediaContext?:string;image?:boolean;
    transform?:unknown;format?:string;blockIndex?:number;previewOnly?:boolean;
    identity?:string;
    recording?:{sequence:number;duration:number;discontinuity?:boolean;map?:boolean;initialization?:string;codec?:string;volume?:number};
    attachment?:{read(options:{signal?:AbortSignal;method?:'GET'|'HEAD';range?:string}):Promise<Response>};
}
export interface DownloadResult {
    status: 'completed' | 'retryable_failure' | 'permanent_failure';
    completedCount?: number;
    totalCount?: number;
    bytes?: number;
    failureCode?: string;
}
export interface SubscriptionAdapter {
    fetch(subscription: Record<string, unknown>, options?: {
        signal?: AbortSignal;
    }): Promise<readonly ObservedContent[]|SubscriptionBatch>;
}
export interface SubscriptionBatch {items:ObservedContent[];complete:boolean;cursor?:string;context?:string;visited?:string[];}
export interface SourceHostInvoker {
    artifact?:string;
    manifest?: {
        type?: string;
        category?: string;
        metadataOnly?: boolean;
        capabilities?: Record<string, boolean | undefined>;
        imageDecrypt?: Parameters<typeof decodeImage>[1];
    };
    invoke(method: string, params: unknown, options?: {
        signal?: AbortSignal;
        timeoutMs?: number;
    }): Promise<unknown>;
    fetchResource?(url: string, options?: {
        signal?: AbortSignal;
        mediaContext?:string;image?:boolean;
    }): Promise<Response>;
    mediaContext?(row:unknown):string|undefined;
    subscriptionContext?():Promise<string>;
    downloadPlan?(workId:string,nodeId:string,options:{signal?:AbortSignal;variant?:string}):Promise<{entries:Array<{url?:string;identity?:string;blockIndex?:number;previewOnly?:boolean;kind:string;data?:Uint8Array;format?:string;hls?:{manifest:string;keys:Record<string,string>};transform?:unknown;mediaContext?:string;attachment?:DownloadEntry['attachment']}>;release?:()=>Promise<void>}>;
}
export type SourceHostResolver = (source: string) => SourceHostInvoker | undefined;
export class SourceHostDownloadAdapter implements DownloadTaskAdapter {
    private readonly resolve: SourceHostResolver;
    private readonly options?: {
        db: DatabaseSync;
        downloadDir: string;
        maxFileBytes?: number;
        pageConcurrency?:()=>number;
        recordingVolumeSegments?:number;
    };
    constructor(resolve: SourceHostResolver, options?: {
        db: DatabaseSync;
        downloadDir: string;
        maxFileBytes?: number;
        pageConcurrency?:()=>number;
        recordingVolumeSegments?:number;
    }) { this.resolve = resolve; this.options = options; }
    async execute(task: Record<string, unknown>, context: DownloadContext): Promise<DownloadResult> {
        context.assertLease();
        const source = runtimeText(task.source, 'source');
        const recording=task.recording_json?JSON.parse(String(task.recording_json)) as {durationSeconds:number;maxBytes:number;stopRequested?:boolean}:undefined;
        const host:SourceHostInvoker|undefined = recording?.stopRequested?{manifest:{type:'video',category:'live'},invoke:async()=>{throw permanent('RECORDING_STOPPED');},fetchResource:async()=>{throw permanent('RECORDING_STOPPED');}}:this.resolve(source);
        if (!host)
            throw retryable('SOURCE_HOST_UNAVAILABLE');
        if (!this.options || !host.fetchResource || !host.manifest)
            throw permanent('DOWNLOAD_STORAGE_UNAVAILABLE');
        if(recording&&(!Number.isSafeInteger(recording.durationSeconds)||recording.durationSeconds<1||recording.durationSeconds>3600||!Number.isSafeInteger(recording.maxBytes)||recording.maxBytes<1024||recording.maxBytes>2*1024*1024*1024||host.manifest.category!=='live'))throw permanent('INVALID_RECORDING');
        if (host.manifest.metadataOnly || host.manifest.category === 'live'&&!recording)
            throw permanent('UNSUPPORTED');
        const workId = runtimeText(task.work_id, 'workId');
        const chapterId = runtimeText(task.chapter_id, 'chapterId');
        const variant = runtimeText(task.variant, 'variant', 128);
        if (/^[A-Za-z][A-Za-z0-9+.-]*:|^\/\//.test(variant))
            throw permanent('INVALID_VARIANT');
        const resourceKey = runtimeText(task.resource_key, 'resourceKey', 4096);
        const params = { source, workId, chapterId };
        const options = { signal: context.signal };
        let entries: DownloadEntry[];
        let releasePlan:(()=>Promise<void>)|undefined;
        try {
            const work=this.options.db.prepare('SELECT media_kind,metadata_json FROM works WHERE source=? AND work_id=?').get(source,workId);
            const node=this.options.db.prepare('SELECT node_type,node_metadata_json FROM chapters WHERE source=? AND work_id=? AND chapter_id=?').get(source,workId,chapterId);
            const kind=String(work?.media_kind??host.manifest.type);
            if(recording){entries=[];}
            else if(kind==='article'||kind==='mixed'||work&&JSON.parse(String(work.metadata_json??'{}')).presentation==='post'||node&&(typeof JSON.parse(String(node.node_metadata_json??'{}')).postMediaId==='string'||JSON.parse(String(node.node_metadata_json??'{}')).postText===true)){
                if(!host.downloadPlan)throw permanent('UNSUPPORTED');const plan=await host.downloadPlan(workId,chapterId,{...options,variant});let released=false;releasePlan=async()=>{if(released)return;released=true;await plan.release?.();};if(!Array.isArray(plan.entries)||!plan.entries.length||plan.entries.length>20000)throw permanent('SOURCE_PROTOCOL_ERROR');entries=[];for(const entry of plan.entries){if(entry.format==='hls'){const group=await hlsEntries(host,runtimeText(entry.url,'url',16384),context,undefined,entry.mediaContext,entry.hls,false,entries.length);entries.push(...group.map(file=>({...file,...(file.kind==='manifest'?{blockIndex:entry.blockIndex,previewOnly:entry.previewOnly}:{} )}))); }else{if(!['image','video','audio','data','script','subtitle'].includes(entry.kind)||!entry.url&&!entry.attachment&&!entry.data)throw permanent('SOURCE_PROTOCOL_ERROR');entries.push({...entry,kind:entry.kind==='data'?['txt','text'].includes(entry.format??'')?'script':'attachment':entry.kind,url:entry.url??''});}if(entries.length>20000)throw permanent('HLS_LIMIT');}
            }
            else if(kind==='novel'){
                const body=await host.invoke('textChapter',params,options) as Record<string,unknown>;
                if(!body||!Array.isArray(body.paragraphs)||!body.paragraphs.length||body.paragraphs.some(p=>typeof p!=='string'||!p||/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(p))||JSON.stringify(body.paragraphs).length>2_000_000)throw permanent('SOURCE_PROTOCOL_ERROR');
                entries=[{url:'',identity:chapterId,kind:'novel',format:'json',data:Buffer.from(JSON.stringify({title:typeof body.title==='string'?body.title:'',paragraphs:body.paragraphs}))}];
            }
            else if(node?.node_type&&['subtitle','script','image','other'].includes(String(node.node_type))){
                const resource=await host.invoke('voiceResource',{...params,nodeId:chapterId},options) as Record<string,unknown>;
                entries=[{url:runtimeText(resource.url,'url',16384),identity:chapterId,kind:node.node_type==='image'?'image':node.node_type==='subtitle'?'subtitle':node.node_type==='other'?'attachment':'script',format:typeof resource.format==='string'?resource.format:undefined}];
            }
            else if (kind === 'comic') {
                const raw = await host.invoke('chapter', params, options) as Record<string, unknown>;
                if (!raw || !Array.isArray(raw.pages) || !raw.pages.length || raw.pages.length > 20000)
                    throw permanent('SOURCE_PROTOCOL_ERROR');
                entries = [];
                for (let index = 0; index < raw.pages.length; index++) {
                    context.assertLease();
                    let page:Record<string,unknown> = typeof raw.pages[index]==='string'?{url:raw.pages[index]}:raw.pages[index] as Record<string, unknown>;
                    if (!page || typeof page !== 'object')
                        throw permanent('SOURCE_PROTOCOL_ERROR');
                    if (!page.url && page.token !== undefined)
                        page = await host.invoke('resolveImage', { ...params, index, token: page.token, retry: 0 }, options) as Record<string, unknown>;
                    entries.push({ url: runtimeText(page.url, 'url', 16384),identity:typeof page.id==='string'?runtimeText(page.id,'page.id'):undefined, kind: 'image',transform:page.transform,mediaContext:host.mediaContext?.(page) });
                }
            }
            else if (kind === 'video' || kind === 'voice'||node?.node_type==='audio'||node?.node_type==='video') {
                const raw = await host.invoke('videos', params, options);
                if (!Array.isArray(raw) || !raw.length)
                    throw permanent('SOURCE_PROTOCOL_ERROR');
                const candidates = raw.filter((item): item is Record<string, unknown> => !!item && typeof item === 'object');
                const selected = variant === 'original' || variant === 'stream' ? candidates.find(item => item.preferred === true) ?? candidates[0] : candidates.find(item => String(item.quality) === variant || item.label === variant);
                if (!selected)
                    throw permanent('UNSUPPORTED_VARIANT');
                const url = runtimeText(selected.url, 'url', 16384);
                const mediaContext=host.mediaContext?.(selected);
                entries = selected.format === 'hls' ? await hlsEntries(host, url, context, typeof selected.quality === 'number' ? selected.quality : undefined,mediaContext,selected.hls as {manifest:string;keys:Record<string,string>}|undefined) : [{ url,identity:chapterId, kind:node?.node_type==='audio'||kind==='voice'?'audio':'video',format:typeof selected.format==='string'?selected.format:undefined,mediaContext }];
            }
            else
                throw permanent('UNSUPPORTED');
        }
        catch (error) {
            await releasePlan?.();
            throw classifySourceError(error);
        }
        try{
        const db = this.options.db;
        const taskId = runtimeText(task.task_id, 'taskId', 4096);
        // Resume only an unchanged complete plan. This checks plan identity and local
        // integrity; it does not claim remote URLs are immutable snapshots.
        const stablePlan=entries.every(entry=>entry.data!==undefined||entry.url.length>0||entry.identity!==undefined);
        const planContext=await host.subscriptionContext?.();let planFingerprint=createHash('sha256').update(JSON.stringify([host.artifact??null,planContext??null,source,workId,chapterId,variant,entries.map(entry=>({identity:entry.identity,url:entry.url,kind:entry.kind,format:entry.format,transform:entry.transform,blockIndex:entry.blockIndex,previewOnly:entry.previewOnly,data:entry.data?createHash('sha256').update(entry.data).digest('hex'):undefined}))])).digest('hex');
        const checkpointRow=db.prepare('SELECT checkpoint_json FROM restore_checkpoints WHERE task_id=?').get(taskId);const checkpoint=checkpointRow?JSON.parse(String(checkpointRow.checkpoint_json)):undefined;
        if(recording?.stopRequested&&typeof checkpoint?.planFingerprint==='string')planFingerprint=checkpoint.planFingerprint;
        const existingFiles=db.prepare('SELECT resource_key,path FROM download_files WHERE task_id=?').all(taskId) as {resource_key:string;path:string}[];
        if(recording&&!recording.stopRequested&&existingFiles.length&&checkpoint?.planFingerprint!==planFingerprint)throw permanent('RECORDING_CONTEXT_CHANGED');
        if(!recording&&task.status!=='completed'&&existingFiles.length&&(checkpoint?.planFingerprint!==planFingerprint||!stablePlan)){context.assertLease();for(const file of existingFiles){const path=canonicalDownloadPath(this.options!.downloadDir,{task_id:taskId,resource_key:resourceKey},file);await rm(path,{force:true});}db.exec('SAVEPOINT reset_plan');try{context.assertLease();db.prepare('DELETE FROM download_files WHERE task_id=?').run(taskId);db.prepare('DELETE FROM restore_checkpoints WHERE task_id=?').run(taskId);db.prepare('UPDATE download_tasks SET completed_count=0,total_count=0,bytes=0 WHERE task_id=?').run(taskId);db.exec('RELEASE reset_plan');}catch(error){db.exec('ROLLBACK TO reset_plan;RELEASE reset_plan');throw error;}}
        const folder = join(resolve(this.options!.downloadDir), createHash('sha256').update(taskId).digest('hex'));
        mkdirSync(this.options!.downloadDir, { recursive: true });
        safePath(this.options!.downloadDir, folder);
        await mkdir(folder, { recursive: true });
        let bytes = 0;
        let count = 0;
        let received=0,currentReceived=0,lastReceived=0,lastSample=performance.now();const inflight=new Map<number,number>();
        const transferAbort=new AbortController();
        const transferSignal=context.signal?AbortSignal.any([context.signal,transferAbort.signal]):transferAbort.signal;
        const sample=()=>{const at=performance.now(),elapsed=at-lastSample;if(elapsed<1000)return;const speed=Math.max(0,Math.round((received-lastReceived)*1000/elapsed));
            db.exec('BEGIN IMMEDIATE');try{context.assertLease();aborted(transferSignal);const committed=Number((db.prepare("SELECT COALESCE(SUM(bytes),0) AS bytes FROM download_files WHERE task_id=? AND status='completed'").get(taskId) as {bytes:number}).bytes);const total=committed+currentReceived;const prior=db.prepare('SELECT bytes,speed,total_count FROM download_tasks WHERE task_id=?').get(taskId) as {bytes:number;speed:number|null;total_count:number};
                if(prior.bytes!==total||prior.speed!==speed||prior.total_count!==entries.length){const now=new Date().toISOString();db.prepare('UPDATE download_tasks SET bytes=?,speed=?,total_count=?,updated_at=?,version=version+1 WHERE task_id=?').run(total,speed,entries.length,now,taskId);recordEvent(db,'download.statusChanged','download',taskId,{taskId,resourceKey,status:'running',bytes:total,speed,totalCount:entries.length});}db.exec('COMMIT');lastSample=at;lastReceived=received;
            }catch(error){db.exec('ROLLBACK');throw error;}
        };
        const progress=setInterval(()=>{try{sample();}catch(error){transferAbort.abort(error);}},1000);
        progress.unref();
        const receiveFor=(index:number)=>(size:number)=>{aborted(transferSignal);context.assertLease();received+=size;inflight.set(index,(inflight.get(index)??0)+size);currentReceived=[...inflight.values()].reduce((a,b)=>a+b,0);};
        const transfer=async(index:number)=>{
            const receive=receiveFor(index);
            context.assertLease();
            aborted(context.signal);
            const entry = entries[index]!;
            const fileKey = `${resourceKey}:file:${index}`;
            const path = canonicalDownloadPath(this.options!.downloadDir, { task_id: taskId, resource_key: resourceKey }, { resource_key: fileKey }, entry.kind === 'manifest' ? 'm3u8' : 'bin');
            const prior = db.prepare('SELECT path,bytes,status FROM download_files WHERE resource_key=? AND task_id=?').get(fileKey, taskId) as Record<string, unknown> | undefined;
            const priorHash=db.prepare('SELECT checkpoint_json FROM restore_checkpoints WHERE task_id=?').get(taskId);const expectedHash=priorHash?JSON.parse(String(priorHash.checkpoint_json)).hashes?.[fileKey]:undefined;
            if (prior?.status === 'completed' && prior.path === path && existsSync(path) && statSync(path).size === Number(prior.bytes)&&typeof expectedHash==='string'&&fileDigest(path)===expectedHash&&(!entry.data||expectedHash===createHash('sha256').update(entry.data).digest('hex'))) {
                bytes += Number(prior.bytes);
                count++;
                return;
            }
            const part = safePath(this.options!.downloadDir, `${path}.${context.lease.leaseGeneration}.part`);
            let size = 0;
            const hash = createHash('sha256');
            try {
                let response = entry.data ? new Response(entry.data as BodyInit) : entry.attachment?await entry.attachment.read({signal:transferSignal}):await host.fetchResource!(entry.url, {...options,signal:transferSignal,mediaContext:entry.mediaContext,image:entry.kind==='image'});
                if (entry.key) {
                    const cipher = unwrapHlsResource(await limitedBody(response, 32 * 1024 * 1024, transferSignal,receive),32*1024*1024);
                    const decipher = createDecipheriv('aes-128-cbc', entry.key, entry.iv!);
                    response = new Response(Buffer.concat([decipher.update(cipher), decipher.final()]));
                }
                else if(entry.kind==='segment')response=new Response(unwrapHlsResource(await limitedBody(response,32*1024*1024,transferSignal,receive),32*1024*1024) as BodyInit);
                if (response.status !== 200 || !response.body) {
                    await response.body?.cancel();
                    throw response.status === 401 ? permanent('LOGIN_REQUIRED') : retryable(`MEDIA_HTTP_${response.status}`);
                }
                const type = response.headers.get('content-type')?.split(';')[0]?.toLowerCase() ?? '';
                if (!entry.data&&(type === 'text/html' || type === 'application/json' || entry.kind === 'image' && type && !type.startsWith('image/') && type !== 'application/octet-stream' && type !== 'binary/octet-stream')) {
                    await response.body.cancel();
                    throw permanent('MEDIA_CONTENT_TYPE');
                }
                const max = entry.kind === 'image' ? 20 * 1024 * 1024 : entry.kind === 'segment' ? 32 * 1024 * 1024 : this.options!.maxFileBytes ?? 512 * 1024 * 1024;
                const expected = response.headers.get('content-length');
                if (expected !== null && (!/^\d+$/.test(expected) || Number(expected) > max)) {
                    await response.body.cancel();
                    throw permanent('MEDIA_TOO_LARGE');
                }
                if (entry.kind === 'image') {
                    const encoded = await limitedBody(response, 20 * 1024 * 1024, transferSignal,receive);
                    let decoded: ReturnType<typeof decodeImage>;
                    try {
                        decoded = decodeImage(encoded, host.manifest!.imageDecrypt);
                    }
                    catch (error) {
                        throw classifySourceError(error);
                    }
                    response = new Response(decoded.bytes as BodyInit, { headers: { 'content-type': decoded.mime } });
                }
                if (!response.body)
                    throw permanent('MEDIA_EMPTY');
                const file = await open(part, 'w');
                const reader = response.body.getReader();
                const cancelRead = () => { void reader.cancel().catch(() => undefined); };
                transferSignal.addEventListener('abort', cancelRead, { once: true });
                try {
                    while (true) {
                        context.assertLease();
                        aborted(context.signal);
                        aborted(transferSignal);
                        const chunk = await reader.read();
                        if (chunk.done)
                            break;
                        size += chunk.value.length;
                        if(recording&&entry.kind!=='manifest'&&bytes+size>recording.maxBytes-Math.min(1024*1024,Math.floor(recording.maxBytes/2)))throw permanent('RECORDING_BUDGET');
                        if (size > max||recording&&bytes+size>recording.maxBytes)
                            throw permanent('MEDIA_TOO_LARGE');
                        if(!entry.data&&!entry.key&&entry.kind!=='image'&&entry.kind!=='segment')receive(chunk.value.length);
                        hash.update(chunk.value);
                        await file.writeFile(chunk.value);
                    }
                    await file.sync();
                }
                finally {
                    transferSignal.removeEventListener('abort', cancelRead);
                    await reader.cancel().catch(() => undefined);
                    await file.close();
                }
                aborted(transferSignal);
                if (!size || entry.kind !== 'image' && expected !== null && Number(expected) !== size)
                    throw retryable('MEDIA_TRUNCATED');
                context.assertLease();
                aborted(context.signal);
                safePath(this.options!.downloadDir, path);
                await rename(part, path);
                db.exec('BEGIN IMMEDIATE');
                try {
                    context.assertLease();
                    const now = new Date().toISOString();
                    db.prepare("INSERT INTO download_files(task_id,resource_key,path,status,bytes,created_at,updated_at) VALUES(?,?,?,'completed',?,?,?) ON CONFLICT(resource_key) DO UPDATE SET path=excluded.path,status='completed',bytes=excluded.bytes,updated_at=excluded.updated_at").run(taskId, fileKey, path, size, now, now);
                    db.prepare('UPDATE download_files SET metadata_json=? WHERE task_id=? AND resource_key=?').run(JSON.stringify({kind:entry.kind,format:entry.format,transform:entry.transform,recording:entry.recording,blockIndex:entry.blockIndex,previewOnly:entry.previewOnly}),taskId,fileKey);
                    const cp = db.prepare('SELECT checkpoint_json FROM restore_checkpoints WHERE task_id=?').get(taskId) as Record<string, unknown> | undefined;
                    const hashes = cp ? JSON.parse(String(cp.checkpoint_json)).hashes ?? {} : {};
                    hashes[fileKey] = hash.digest('hex');
                    db.prepare('INSERT INTO restore_checkpoints(task_id,checkpoint_json,updated_at) VALUES(?,?,?) ON CONFLICT(task_id) DO UPDATE SET checkpoint_json=excluded.checkpoint_json,updated_at=excluded.updated_at').run(taskId, JSON.stringify({ hashes,planFingerprint }), now);
                    db.prepare('UPDATE download_tasks SET completed_count=?,total_count=?,bytes=?,updated_at=?,version=version+1 WHERE task_id=?').run(count + 1, entries.length, bytes + size, now, taskId);
                    recordEvent(db, 'download.statusChanged', 'download', taskId, { taskId, resourceKey, completedCount: count + 1, totalCount: entries.length, bytes: bytes + size });
                    db.exec('COMMIT');
                }
                catch (error) {
                    db.exec('ROLLBACK');
                    throw error;
                }
                bytes += size;
                inflight.delete(index);currentReceived=[...inflight.values()].reduce((a,b)=>a+b,0);
                count++;
            }
            catch (error) {
                await rm(part, { force: true });
                throw error;
            }
        };
        try{if(recording){
            const recorded=db.prepare("SELECT * FROM download_files WHERE task_id=? ORDER BY id").all(taskId);
            let elapsed=0;for(const file of recorded){const metadata=JSON.parse(String(file.metadata_json));if(!metadata.recording)throw permanent('INVALID_RECORDING_CHECKPOINT');canonicalDownloadPath(this.options!.downloadDir,{task_id:taskId,resource_key:resourceKey},{resource_key:String(file.resource_key),path:String(file.path)});if(metadata.kind!=='manifest'&&(file.status!=='completed'||!existsSync(String(file.path))||statSync(String(file.path)).size!==Number(file.bytes)||checkpoint?.hashes?.[String(file.resource_key)]!==fileDigest(String(file.path))))throw permanent('RECORDING_FILES_MISSING');entries.push({url:'',kind:String(metadata.kind),recording:metadata.recording});elapsed+=Number(metadata.recording.duration);if(file.status==='completed'){bytes+=Number(file.bytes);count++;}}
            const volumeLimit=Math.floor(this.options.recordingVolumeSegments??20000);if(volumeLimit<1||volumeLimit>20000)throw permanent('INVALID_RECORDING_LIMIT');
            const stopped=()=>Boolean(JSON.parse(String(db.prepare('SELECT recording_json FROM download_tasks WHERE task_id=?').get(taskId)?.recording_json??'{}')).stopRequested);
            const writeVolume=async(volume:number)=>{
                const parts=entries.map((entry,index)=>({entry,index})).filter(({entry})=>entry.kind==='segment'&&entry.recording?.volume===volume);const segments=parts.filter(({entry})=>!entry.recording?.map);if(!segments.length)return;
                const lines=['#EXTM3U','#EXT-X-VERSION:'+(parts.some(({entry})=>entry.recording?.map)?6:3),'#EXT-X-TARGETDURATION:'+Math.ceil(Math.max(...segments.map(({entry})=>entry.recording!.duration))),'#EXT-X-MEDIA-SEQUENCE:0','#EXT-X-PLAYLIST-TYPE:VOD'];
                for(const {entry,index}of parts){const name=String(index).padStart(6,'0')+'.bin';if(entry.recording?.discontinuity)lines.push('#EXT-X-DISCONTINUITY');if(entry.recording?.map)lines.push('#EXT-X-MAP:URI="'+name+'"');else lines.push('#EXTINF:'+entry.recording!.duration+',',name);}lines.push('#EXT-X-ENDLIST');
                let index=entries.findIndex(entry=>entry.kind==='manifest'&&entry.recording?.volume===volume);const entry:DownloadEntry={url:'',kind:'manifest',format:'hls',recording:{sequence:0,duration:0,volume},data:Buffer.from(lines.join('\n'))};
                if(index<0){index=entries.length;entries.push(entry);}else{const prior=db.prepare("SELECT bytes FROM download_files WHERE task_id=? AND resource_key=? AND status='completed'").get(taskId,resourceKey+':file:'+index);if(prior){bytes-=Number(prior.bytes);count--;}entries[index]=entry;}
                await transfer(index);
            };
            let volume=entries.reduce((max,entry)=>Math.max(max,entry.recording?.volume??0),0),volumeSegments=entries.filter(entry=>entry.kind==='segment'&&!entry.recording?.map&&entry.recording?.volume===volume).length;
            let initialization=entries.filter(entry=>entry.kind==='segment'&&!entry.recording?.map).at(-1)?.recording?.initialization,codec=entries.filter(entry=>entry.kind==='segment'&&!entry.recording?.map).at(-1)?.recording?.codec;
            let lastSequence:number|undefined,first=true,pendingBoundary=false,budgetReached=false,durationReached=false,lastAdvance=performance.now(),deadline=performance.now()+60000+Math.max(0,recording.durationSeconds-elapsed)*1000;
            while(elapsed<recording.durationSeconds&&performance.now()<deadline&&!stopped()&&!budgetReached&&!durationReached){
                context.assertLease();aborted(context.signal);
                const candidates=await host.invoke('videos',params,{signal:context.signal}) as Array<Record<string,unknown>>;
                if(!Array.isArray(candidates))throw permanent('SOURCE_PROTOCOL_ERROR');const supported=candidates.filter(value=>value?.format==='hls'),selected=supported.find(value=>value.preferred===true)??supported[0];if(!selected||selected.audio!==undefined)throw permanent('UNSUPPORTED_LIVE_RECORDING_FORMAT');
                const fresh=await hlsEntries(host,runtimeText(selected.url,'url',16384),context,undefined,host.mediaContext?.(selected),selected.hls as {manifest:string;keys:Record<string,string>}|undefined,true);
                const segments=fresh.filter(entry=>entry.recording&&!entry.recording.map);if(!segments.length)throw permanent('SOURCE_PROTOCOL_ERROR');const latest=segments.at(-1)!.recording!.sequence;
                const reset=lastSequence!==undefined&&latest<lastSequence;
                if(lastSequence===undefined||reset){lastSequence=latest;lastAdvance=performance.now();if(reset)pendingBoundary=true;}
                const selectedSegments=reset?[]:segments.filter(entry=>entry.recording!.sequence>lastSequence!);
                for(const segment of selectedSegments){
                    if(stopped()||elapsed>=recording.durationSeconds||performance.now()>=deadline)break;
                    const info=segment.recording!,boundary=info.discontinuity||pendingBoundary||first&&recorded.length>0||info.sequence!==lastSequence!+1||initialization!==info.initialization||codec!==info.codec||volumeSegments>=volumeLimit;
                    if(elapsed+info.duration>recording.durationSeconds){durationReached=true;break;}if(entries.length>=200000){budgetReached=true;break;}
                    if(boundary&&volumeSegments){volume++;volumeSegments=0;}const discontinuity=Boolean(boundary&&entries.some(entry=>entry.kind==='segment'&&!entry.recording?.map));
                    if(!volumeSegments&&info.initialization){const init=fresh.find(entry=>entry.recording?.map&&entry.recording.initialization===info.initialization);if(!init)throw permanent('SOURCE_PROTOCOL_ERROR');entries.push({...init,recording:{...init.recording!,volume}});await transfer(entries.length-1);}
                    entries.push({...segment,recording:{...info,volume,discontinuity}});try{await transfer(entries.length-1);}catch(error){if(errorCode(error,'')!=='RECORDING_BUDGET'||!entries.slice(0,-1).some(entry=>entry.kind==='segment'&&!entry.recording?.map))throw error;entries.pop();budgetReached=true;break;}
                    elapsed+=info.duration;lastSequence=info.sequence;initialization=info.initialization;codec=info.codec;volumeSegments++;lastAdvance=performance.now();pendingBoundary=false;if(first){deadline=performance.now()+Math.max(0,recording.durationSeconds-elapsed)*1000+1000;first=false;}await writeVolume(volume);
                }
                if(fresh.at(-1)?.data&&new TextDecoder().decode(fresh.at(-1)!.data).includes('#EXT-X-ENDLIST')||bytes>=recording.maxBytes)break;
                if(performance.now()-lastAdvance>60000)throw retryable('LIVE_STALLED');await abortableDelay(Math.min(1000,Math.max(20,deadline-performance.now())),context.signal);
            }
            if(!entries.some(entry=>entry.kind==='segment'&&!entry.recording?.map))throw permanent('RECORDING_EMPTY');
            for(const value of new Set(entries.filter(entry=>entry.kind==='segment').map(entry=>entry.recording!.volume!)))await writeVolume(value);
        }else{const parallel=Math.min(16,Math.max(1,Math.floor(this.options.pageConcurrency?.()??1)));let next=0;let firstFailure:unknown;const results=await Promise.allSettled(Array.from({length:Math.min(parallel,entries.length)},async()=>{while(next<entries.length){const index=next++;try{for(let attempt=0;;attempt++){try{await transfer(index);break;}catch(error){const code=errorCode(error,'UNKNOWN');if(attempt>=2||transferSignal.aborted||!entries[index]!.url||entries[index]!.attachment||!['NETWORK','ECONNRESET','ETIMEDOUT','EPIPE','TIMEOUT','MEDIA_TRUNCATED'].includes(code)||(error as {retryable?:boolean})?.retryable===false)throw error;inflight.delete(index);currentReceived=[...inflight.values()].reduce((a,b)=>a+b,0);await abortableDelay(250*(attempt+1),transferSignal);}}}catch(error){if(!transferAbort.signal.aborted)firstFailure=error;transferAbort.abort(error);throw error;}}}));const failure=results.find(result=>result.status==='rejected');if(failure?.status==='rejected')throw firstFailure??failure.reason;}
        return { status: 'completed', completedCount: count, totalCount: entries.length, bytes };
        }finally{clearInterval(progress);resetTransferProgress(db,context.lease);await releasePlan?.();}
        }catch(error){await releasePlan?.();throw error;}
    }
}
export class SourceHostSubscriptionAdapter implements SubscriptionAdapter {
    private readonly resolve: SourceHostResolver;
    constructor(resolve: SourceHostResolver) { this.resolve = resolve; }
    async fetch(subscription: Record<string, unknown>, options: {
        signal?: AbortSignal;
    } = {}) {
        const source = runtimeText(subscription.source, 'source');
        const host = this.resolve(source);
        if (!host)
            throw retryable('SOURCE_HOST_UNAVAILABLE');
        const dimension = runtimeText(subscription.dimension, 'dimension');
        const target = runtimeText(subscription.target, 'target',16384);
        const result: ObservedContent[] = [];
        const seen = new Set<string>();
        const saved=subscription.scan_state as {cursor?:string;items?:ObservedContent[];context?:string;visited?:string[]}|undefined;
        const context=await host.subscriptionContext?.()??createHash('sha256').update(JSON.stringify(host.manifest??{})).digest('hex');
        const unchanged=!subscription.context_hash||subscription.context_hash===context;
        if(saved?.context===context)for(const item of saved.items??[]){result.push(item);seen.add(JSON.stringify([item.kind??'work',item.contentId]));}
        let cursor: string | undefined=saved?.context===context?saved.cursor:undefined;
        const visited=new Set(saved?.context===context?saved.visited??[]:[]);
        const known=new Set(unchanged&&Array.isArray(subscription.known_ids)?subscription.known_ids as string[]:[]);
        for (let page = 0; page < 3; page++) {
            aborted(options.signal);
            let raw: unknown;
            try {
                raw = await host.invoke('subscriptionUpdates', { source, dimension, target, cursor }, options);
            }
            catch (error) {
                throw classifySourceError(error);
            }
            if(host.subscriptionContext&&await host.subscriptionContext()!==context)throw permanent('CANCELLED');
            if (!raw || typeof raw !== 'object' || Array.isArray(raw))
                throw permanent('SOURCE_PROTOCOL_ERROR');
            const response = raw as Record<string, unknown>;
            if (!Array.isArray(response.items)||response.items.length>20000||typeof response.hasNext!=='boolean'||response.windowed!==undefined&&typeof response.windowed!=='boolean')
                throw permanent('SOURCE_PROTOCOL_ERROR');
            for (const item of response.items) {
                if (!item || typeof item !== 'object' || Array.isArray(item))
                    throw permanent('SOURCE_PROTOCOL_ERROR');
                const value = item as Record<string, unknown>;
                if (value.source !== undefined && value.source !== source)
                    throw permanent('SOURCE_IDENTITY_MISMATCH');
                if (!['work', 'post', 'chapter'].includes(String(value.kind)))
                    throw permanent('SOURCE_PROTOCOL_ERROR');
                const contentId = runtimeText(value.id, 'contentId');
                const identity=JSON.stringify([String(value.kind),contentId]);
                if (!seen.has(identity)) {
                    seen.add(identity);
                    result.push({ contentId,kind:String(value.kind),title:typeof value.title==='string'?value.title.slice(0,2048):undefined,workId:value.workId===undefined?undefined:runtimeText(value.workId,'workId'),chapterId:value.chapterId===undefined?undefined:runtimeText(value.chapterId,'chapterId'), ...(value.contentVersion === undefined ? {} : { contentVersion: runtimeText(value.contentVersion, 'contentVersion') }) });
                }
                if (result.length > 20000)
                    throw permanent('SUBSCRIPTION_LIMIT');
            }
            if (!response.hasNext||response.windowed===true&&(!subscription.baseline||!unchanged?page===2:response.items.length>0&&response.items.every(item=>known.has(JSON.stringify([(item as Record<string,unknown>).kind,(item as Record<string,unknown>).id])))))
                return {items:result,complete:true,context};
            const next = runtimeText(response.cursor, 'cursor', 4096);
            if (next === cursor||visited.has(next)||visited.size>=20000)
                throw permanent('SOURCE_CURSOR_STALLED');
            visited.add(next);
            cursor = next;
        }
        return {items:result,complete:false,cursor,context,visited:[...visited]};
    }
}
function runtimeText(value: unknown, name: string, max = 512): string {
    if (typeof value !== 'string' || value.length === 0 || value.length > max || /[\u0000-\u001f\u007f]/.test(value))
        throw permanent(`INVALID_${name.toUpperCase()}`);
    return value;
}
function aborted(signal?: AbortSignal) {
    if (signal?.aborted)
        throw signal.reason ?? permanent('CANCELLED');
}
async function abortableDelay(ms:number,signal?:AbortSignal){aborted(signal);await new Promise<void>((resolve,reject)=>{const timer=setTimeout(done,ms);function done(){signal?.removeEventListener('abort',cancel);resolve();}function cancel(){clearTimeout(timer);signal?.removeEventListener('abort',cancel);reject(signal?.reason??permanent('CANCELLED'));}signal?.addEventListener('abort',cancel,{once:true});});}
function fileDigest(path: string) {
    const hash = createHash('sha256');
    const descriptor = openSync(path, 'r');
    try {
        const chunk = Buffer.allocUnsafe(65536);
        let count = 0;
        while ((count = readSync(descriptor, chunk, 0, chunk.length, null)) > 0)
            hash.update(chunk.subarray(0, count));
        return hash.digest('hex');
    }
    finally {
        closeSync(descriptor);
    }
}
function safePath(root: string, candidate: string) {
    const base = resolve(root);
    const target = resolve(candidate);
    const rel = relative(base, target);
    if (!rel || rel === '..' || rel.startsWith(`..${sep}`) || isAbsolute(rel))
        throw permanent('DOWNLOAD_PATH_FORBIDDEN');
    let ancestor = base;
    if (existsSync(base) && lstatSync(base).isSymbolicLink())
        throw permanent('DOWNLOAD_PATH_FORBIDDEN');
    for (const part of rel.split(sep)) {
        ancestor = join(ancestor, part);
        if (existsSync(ancestor) && lstatSync(ancestor).isSymbolicLink())
            throw permanent('DOWNLOAD_PATH_FORBIDDEN');
    }
    if (existsSync(base)) {
        let existing = target;
        while (!existsSync(existing))
            existing = dirname(existing);
        const actual = relative(realpathSync(base), realpathSync(existing));
        if (actual === '..' || actual.startsWith(`..${sep}`) || isAbsolute(actual))
            throw permanent('DOWNLOAD_PATH_FORBIDDEN');
    }
    return target;
}
async function limitedBody(response: Response, max: number, signal?: AbortSignal,onChunk?:(size:number)=>void) {
    if (!response.ok || !response.body)
        throw retryable('MEDIA_FETCH_FAILED');
    const expected = response.headers.get('content-length');
    if (expected !== null && (!/^\d+$/.test(expected) || Number(expected) > max)) {
        await response.body.cancel();
        throw permanent('MEDIA_TOO_LARGE');
    }
    const parts: Uint8Array[] = [];
    let size = 0;
    const reader = response.body.getReader();
    const cancelRead = () => { void reader.cancel().catch(() => undefined); };
    signal?.addEventListener('abort', cancelRead, { once: true });
    try {
        while (true) {
            aborted(signal);
            const item = await reader.read();
            if (item.done)
                break;
            size += item.value.length;
            if (size > max)
                throw permanent('MEDIA_TOO_LARGE');
            onChunk?.(item.value.length);
            parts.push(item.value);
        }
    }
    finally {
        signal?.removeEventListener('abort', cancelRead);
        await reader.cancel().catch(() => undefined);
    }
    if (!size)
        throw permanent('MEDIA_EMPTY');
    if (expected !== null && Number(expected) !== size)
        throw retryable('MEDIA_TRUNCATED');
    return Buffer.concat(parts);
}
async function hlsEntries(host: SourceHostInvoker, url: string, context: DownloadContext, quality?: number,mediaContext?:string,inline?:{manifest:string;keys:Record<string,string>},live=false,offset=0): Promise<DownloadEntry[]> {
    if(inline&&(typeof inline.manifest!=='string'||Buffer.byteLength(inline.manifest)>2*1024*1024||!inline.keys||typeof inline.keys!=='object'||Object.keys(inline.keys).length>32||Object.values(inline.keys).some(value=>typeof value!=='string'||Buffer.from(value,'base64').length!==16)))throw permanent('SOURCE_PROTOCOL_ERROR');
    const options = { signal: context.signal,mediaContext };
    let response = inline?new Response(inline.manifest):await host.fetchResource!(url, options);
    if (response.url) url = response.url;
    let text = new TextDecoder().decode(unwrapHlsResource(await limitedBody(response, 2 * 1024 * 1024, context.signal),2*1024*1024));
    let codec:string|undefined;
    if (!text.startsWith('#EXTM3U'))
        throw permanent('SOURCE_PROTOCOL_ERROR');
    if (text.includes('#EXT-X-STREAM-INF:')) {
        if (/#EXT-X-MEDIA:[^\n]*URI=/.test(text))
            throw permanent('UNSUPPORTED_HLS_AUDIO_DOWNLOAD');
        const lines = text.split(/\r?\n/).map(line => line.trim());
        const choices: Array<{
            url: string;
            quality: number;
            bandwidth: number;
            codec?:string;
        }> = [];
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]!;
            if (!line.startsWith('#EXT-X-STREAM-INF:'))
                continue;
            const next = lines[i + 1];
            if (!next || next.startsWith('#'))
                throw permanent('SOURCE_PROTOCOL_ERROR');
            choices.push({ url: new URL(next, url).href, quality: Number(/RESOLUTION=\d+x(\d+)/.exec(line)?.[1] ?? 0), bandwidth: Number(/BANDWIDTH=(\d+)/.exec(line)?.[1] ?? 0),codec:/CODECS="([^"]+)"/.exec(line)?.[1] });
        }
        choices.sort((a, b) => b.quality - a.quality || b.bandwidth - a.bandwidth);
        const selected = quality ? choices.find(item => item.quality <= quality) ?? choices[0] : choices[0];
        if (!selected)
            throw permanent('SOURCE_PROTOCOL_ERROR');
        url = selected.url;
        codec=selected.codec===undefined?undefined:runtimeText(selected.codec,'codec',512);
        response = await host.fetchResource!(url, options);
        if (response.url) url = response.url;
        text = new TextDecoder().decode(unwrapHlsResource(await limitedBody(response, 2 * 1024 * 1024, context.signal),2*1024*1024));
    }
    if (!text.startsWith('#EXTM3U') || !live&&!text.includes('#EXT-X-ENDLIST') || /#EXT-X-(?:STREAM-INF|MEDIA:|BYTERANGE|GAP|PART|PRELOAD-HINT)/.test(text)||!live&&/#EXT-X-DISCONTINUITY/.test(text))
        throw permanent('UNSUPPORTED_HLS');
    const entries: DownloadEntry[] = [];
    const output: string[] = [];
    let key: Uint8Array | undefined;
    let iv: Uint8Array | undefined;
    let sequence = 0;
    let mapSeen = false;
    let duration=0,discontinuity=false,initialization:string|undefined;
    for (const raw of text.split(/\r?\n/)) {
        context.assertLease();
        aborted(context.signal);
        const line = raw.trim();
        if(line.startsWith('#EXTINF:')){duration=Number(line.slice(8).split(',')[0]);if(!Number.isFinite(duration)||duration<=0||duration>600)throw permanent('SOURCE_PROTOCOL_ERROR');}
        if(line==='#EXT-X-DISCONTINUITY')discontinuity=true;
        if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
            sequence = Number(line.slice(line.indexOf(':') + 1));
            if (!Number.isSafeInteger(sequence) || sequence < 0)
                throw permanent('SOURCE_PROTOCOL_ERROR');
        }
        if (line.startsWith('#EXT-X-KEY:')) {
            const method = /METHOD=([^,]+)/.exec(line)?.[1];
            if (method === 'NONE') {
                key = undefined;
                iv = undefined;
                continue;
            }
            if (method !== 'AES-128' || /KEYFORMAT=/.test(line) && !/KEYFORMAT="identity"/.test(line))
                throw permanent('UNSUPPORTED_HLS');
            const keyUrl = /URI="([^"]+)"/.exec(line)?.[1];
            if (!keyUrl)
                throw permanent('SOURCE_PROTOCOL_ERROR');
            const keyAddress=new URL(keyUrl,url).href;
            key = inline?.keys[keyAddress]?Buffer.from(inline.keys[keyAddress],'base64'):await limitedBody(await host.fetchResource!(keyAddress, options), 16, context.signal);
            if (key.length !== 16)
                throw permanent('HLS_KEY_INVALID');
            const encoded = /IV=0x([a-fA-F0-9]+)/.exec(line)?.[1];
            if (encoded && encoded.length !== 32)
                throw permanent('HLS_IV_INVALID');
            iv = encoded ? Buffer.from(encoded, 'hex') : undefined;
            continue;
        }
        const map = line.startsWith('#EXT-X-MAP:') ? /URI="([^"]+)"/.exec(line)?.[1] : undefined;
        if (line.startsWith('#EXT-X-MAP:') && (!map || !live&&(mapSeen || entries.length) || /BYTERANGE=/.test(line)))
            throw permanent('UNSUPPORTED_HLS');
        if (map || line && !line.startsWith('#')) {
            if (entries.length >= 20000)
                throw permanent('HLS_LIMIT');
            if (map)
                mapSeen = true;
            const sequenceIv = Buffer.alloc(16);
            sequenceIv.writeBigUInt64BE(BigInt(sequence), 8);
            if (map && key && !iv)
                throw permanent('HLS_IV_INVALID');
            const name = `${String(offset+entries.length).padStart(6, '0')}.bin`;
            if(live&&!map&&!duration)throw permanent('SOURCE_PROTOCOL_ERROR');
            if(map)initialization=createHash('sha256').update(JSON.stringify([new URL(map,url).href,key?Buffer.from(key).toString('hex'):null,iv?Buffer.from(iv).toString('hex'):null])).digest('hex');
            entries.push({ url: new URL(map ?? line, url).href, kind: 'segment',mediaContext,...(live?{recording:{sequence,duration:map?0:duration,discontinuity,map:!!map,initialization,codec}}:{}), ...(key ? { key, iv: iv ?? sequenceIv } : {}) });
            if(!map){duration=0;discontinuity=false;}
            output.push(map ? `#EXT-X-MAP:URI="${name}"` : name);
            if (!map)
                sequence++;
            continue;
        }
        if (line.startsWith('#EXT-X-') && /URI=/.test(line))
            throw permanent('UNSUPPORTED_HLS');
        if (!line.startsWith('#EXT-X-TOKEN'))
            output.push(line);
    }
    if (!entries.length)
        throw permanent('SOURCE_PROTOCOL_ERROR');
    entries.push({ url: '', kind: 'manifest', data: new TextEncoder().encode(output.join('\n')) });
    return entries;
}
function errorCode(error: unknown, fallback: string) {
    return error && typeof error === 'object' && 'code' in error && typeof (error as {
        code?: unknown;
    }).code === 'string' ? String((error as {
        code: string;
    }).code) : fallback;
}
function retryable(code: string) { return Object.assign(new Error(code), { retryable: true, code }); }
function permanent(code: string) { return Object.assign(new Error(code), { retryable: false, code }); }
export function classifySourceError(error: unknown) {
    const code = errorCode(error, 'SOURCE_NETWORK_ERROR');
    if (/AUTH|LOGIN|VERIFY|VERIFICATION|CHALLENGE|PERMISSION|UNAUTHORIZED|FORBIDDEN/i.test(code))
        return permanent(code);
    if (/PROTOCOL|INVALID|IDENTITY|SCHEMA|UNSUPPORTED|PARSE|BLOCKED|INCOMPATIBLE|CONFIG/i.test(code))
        return permanent(code);
    return retryable(code);
}
export class WorkerScheduler {
    private readonly db: DatabaseSync;
    private readonly options: WorkerSchedulerOptions;
    private timer: ReturnType<typeof setTimeout> | undefined;
    private stopping = false;
    private running = false;
    private readonly active = new Map<string, {
        controller: AbortController;
        promise: Promise<void>;
    }>();
    private tickPromise?: Promise<void>;
    private subscriptionController?: AbortController;
    private reconciled = false;
    private readonly owner: string;
    private readonly intervalMs: number;
    private readonly leaseTtlMs: number;
    private readonly outboxBatchSize: number;
    constructor(db: DatabaseSync, options: WorkerSchedulerOptions = {}) {
        this.db = db;
        this.options = options;
        this.owner = options.owner ?? `worker:${randomUUID()}`;
        this.intervalMs = Math.max(10, options.intervalMs ?? 1000);
        this.leaseTtlMs = Math.max(1000, options.leaseTtlMs ?? 30000);
        this.outboxBatchSize = Math.max(1, options.outboxBatchSize ?? 50);
    }
    get isRunning() { return this.running && !this.stopping; }
    get activeCount() { return this.active.size; }
    get subscriptionIntervalMs() { return this.options.subscriptionSettings?.().intervalMs??this.options.subscriptionIntervalMs ?? 300000; }
    async start() {
        if (this.running)
            return;
        this.running = true;
        this.stopping = false;
        try {
            await this.tick();
            this.schedule();
        }
        catch (error) {
            this.running = false;
            this.stopping = true;
            throw error;
        }
    }
    async stop() {
        this.stopping = true;
        if (this.timer)
            clearTimeout(this.timer);
        this.timer = undefined;
        this.subscriptionController?.abort(permanent('WORKER_STOPPED'));
        for (const entry of this.active.values())
            entry.controller.abort(permanent('WORKER_STOPPED'));
        await this.tickPromise;
        await Promise.all([...this.active.values()].map(entry => entry.promise));
        releaseLeases(this.db, this.owner);
        this.running = false;
    }
    notifyControl(taskId: string) { this.active.get(taskId)?.controller.abort(permanent('TASK_CONTROLLED')); }
    async tick() {
        if (this.stopping)
            return;
        if (this.tickPromise)
            return this.tickPromise;
        this.tickPromise = this.performTick();
        try {
            await this.tickPromise;
        }
        finally {
            this.tickPromise = undefined;
        }
    }
    private async performTick() {
        if (this.stopping)
            return;
        for (const [taskId, entry] of this.active) {
            const row = this.db.prepare('SELECT status FROM download_tasks WHERE task_id=?').get(taskId) as {
                status?: string;
            } | undefined;
            if (!row || row.status !== 'running' || this.db.prepare("SELECT 1 FROM deletion_intents WHERE task_id=? AND status='pending'").get(taskId))
                entry.controller.abort(permanent('TASK_CONTROLLED'));
        }
        await this.processOutbox();
        const removeFile = this.options.removeFile ?? (this.options!.downloadDir ? (path: string) => rmSync(safePath(this.options!.downloadDir!, path), { force: true }) : undefined);
        reconcileDeletionIntents(this.db, this.options!.downloadDir, removeFile, taskId => !this.active.has(taskId));
        reconcileDownloadFiles(this.db, this.options!.downloadDir, this.options.fileExists ?? existsSync, !this.reconciled);
        this.reconciled = true;
        await this.processTasks();
        await this.processSubscriptions();
    }
    private schedule() {
        if (!this.stopping)
            this.timer = setTimeout(async () => {
                try {
                    await this.tick();
                }
                catch (error) {
                    this.options.onError?.(error);
                }
                finally {
                    this.schedule();
                }
            }, this.intervalMs);
    }
    private async processTasks() {
        for (const task of recoverPendingTasks(this.db)) {
            if (this.stopping || this.active.has(task.task_id))
                continue;
            if(task.status==='running'){
                const now=new Date().toISOString();this.db.exec('BEGIN IMMEDIATE');let recovered=false;
                try{const result=this.db.prepare("UPDATE download_tasks SET status=CASE WHEN json_extract(recording_json,'$.stopRequested')=1 THEN 'queued' ELSE 'paused' END,speed=NULL,updated_at=?,version=version+1 WHERE task_id=? AND status='running' AND recording_json IS NOT NULL AND NOT EXISTS(SELECT 1 FROM task_leases WHERE task_id=? AND lease_expires_at>? AND cancellation_requested=0)").run(now,task.task_id,task.task_id,now);recovered=Number(result.changes)>0;if(recovered)recordEvent(this.db,'download.statusChanged','download',task.task_id,{taskId:task.task_id,recoveredRecording:true});this.db.exec('COMMIT');}catch(error){this.db.exec('ROLLBACK');throw error;}if(recovered)continue;
            }
            if (task.status === 'cancelling') {
                this.db.exec('BEGIN IMMEDIATE');
                try {
                    this.db.prepare("UPDATE download_tasks SET status='cancelled',speed=NULL,bytes=(SELECT COALESCE(SUM(bytes),0) FROM download_files WHERE task_id=download_tasks.task_id AND status='completed'),updated_at=?,version=version+1 WHERE task_id=? AND status='cancelling'").run(new Date().toISOString(), task.task_id);
                    recordEvent(this.db, 'download.statusChanged', 'download', task.task_id, { taskId: task.task_id, status: 'cancelled' });
                    this.db.exec('COMMIT');
                }
                catch (error) {
                    this.db.exec('ROLLBACK');
                    throw error;
                }
                continue;
            }
            if (!this.options.processTask && !this.options.downloadAdapter)
                continue;
            const limits=this.options.downloadSettings?.();if(limits){const activeSources=[...this.active.keys()].map(id=>String(this.db.prepare('SELECT source FROM download_tasks WHERE task_id=?').get(id)?.source));const source=String(this.db.prepare('SELECT source FROM download_tasks WHERE task_id=?').get(task.task_id)?.source);if(activeSources.filter(value=>value===source).length>=Math.max(1,limits.taskConcurrency)||!activeSources.includes(source)&&new Set(activeSources).size>=Math.max(1,limits.siteConcurrency))continue;}
            if (this.active.size >= (limits?Math.max(1,limits.siteConcurrency)*Math.max(1,limits.taskConcurrency):this.options.maxConcurrentTasks ?? 3))
                break;
            let lease: TaskLease;
            try {
                lease = acquireLease(this.db, task.task_id, this.owner, this.leaseTtlMs);
            }
            catch (error) {
                if ((error as {
                    code?: string;
                }).code !== 'LEASE_HELD')
                    this.options.onError?.(error);
                continue;
            }
            const controller = new AbortController();
            const promise = this.runTask(task, lease, controller).catch(error => this.options.onError?.(error)).finally(() => this.active.delete(task.task_id));
            this.active.set(task.task_id, { controller, promise });
        }
    }
    private async processOutbox() {
        if (!this.options.publishEvent)
            return;
        const rows = claimOutbox(this.db, this.outboxBatchSize);
        for (const row of rows) {
            if (this.stopping)
                return;
            try {
                await this.options.publishEvent(row);
                markOutboxPublished(this.db, String(row.event_id));
            }
            catch (error) {
                this.options.onError?.(error);
                recordOutboxAttempt(this.db, String(row.event_id));
            }
        }
    }
    private async processSubscriptions() {
        if(this.options.subscriptionSettings?.().enabled===false)return;
        const poll = this.options.subscriptionAdapter?.fetch.bind(this.options.subscriptionAdapter) ?? this.options.pollSubscription;
        if (!poll)
            return;
        const now = new Date().toISOString();
        const rows = this.db.prepare("SELECT * FROM subscriptions WHERE enabled=1 AND (next_due IS NULL OR next_due<=?) ORDER BY updated_at LIMIT 50").all(now) as unknown as Array<Record<string, unknown>>;
        for (const row of rows) {
            if (this.stopping)
                return;
            const subscriptionId = String(row.subscription_id);
            const controller = new AbortController();
            this.subscriptionController = controller;
            try {
                const saved=this.db.prepare('SELECT state_json FROM subscription_scan_state WHERE subscription_id=?').get(subscriptionId);
                const input={...row,known_ids:this.db.prepare('SELECT content_id FROM subscription_seen WHERE subscription_id=?').all(subscriptionId).map(item=>String(item.content_id)),scan_state:saved?JSON.parse(String(saved.state_json)):undefined};
                const observed = await abortable<readonly ObservedContent[]|SubscriptionBatch>(() => this.options.subscriptionAdapter ? this.options.subscriptionAdapter.fetch(input, { signal: controller.signal }) : poll(row), controller, this.options.subscriptionTimeoutMs ?? 60000);
                aborted(controller.signal);
                const current = this.db.prepare('SELECT version FROM subscriptions WHERE subscription_id=? AND enabled=1').get(subscriptionId) as {
                    version?: number;
                } | undefined;
                if (!current || current.version !== row.version)
                    continue;
                const batch=Array.isArray(observed)?undefined:observed as SubscriptionBatch;
                if(batch){
                    if(row.context_hash!==batch.context){this.db.prepare('UPDATE subscriptions SET baseline=NULL,context_hash=? WHERE subscription_id=?').run(batch.context??null,subscriptionId);this.db.prepare('DELETE FROM subscription_seen WHERE subscription_id=?').run(subscriptionId);}
                    if(!batch.complete){this.db.prepare('INSERT INTO subscription_scan_state VALUES(?,?) ON CONFLICT(subscription_id) DO UPDATE SET state_json=excluded.state_json').run(subscriptionId,JSON.stringify({items:batch.items,cursor:batch.cursor,context:batch.context,visited:batch.visited}));this.db.prepare('UPDATE subscriptions SET next_due=? WHERE subscription_id=?').run(new Date(Date.now()+1000).toISOString(),subscriptionId);continue;}
                    this.db.prepare('DELETE FROM subscription_scan_state WHERE subscription_id=?').run(subscriptionId);
                    this.db.prepare('UPDATE subscriptions SET context_hash=? WHERE subscription_id=?').run(batch.context??null,subscriptionId);
                }
                checkSubscription(this.db, subscriptionId, batch?batch.items:observed as readonly ObservedContent[]);
                this.db.prepare('UPDATE subscriptions SET next_due=? WHERE subscription_id=?').run(new Date(Date.now() + this.subscriptionIntervalMs).toISOString(), subscriptionId);
            }
            catch (error) {
                if (this.stopping || !this.db.prepare('SELECT 1 FROM subscriptions WHERE subscription_id=?').get(subscriptionId))
                    continue;
                this.options.onError?.(error);
                const failures = Number(row.failures ?? 0) + 1;
                const delay = Math.min(3600000, this.subscriptionIntervalMs * 2 ** Math.min(failures, 8));
                const next = new Date(Date.now() + delay).toISOString();
                this.db.exec('BEGIN IMMEDIATE');
                try {
                    const checkedAt = new Date().toISOString();
                    const code = errorCode(error, 'WORKER_ERROR');
                    this.db.prepare('INSERT INTO subscription_checks(subscription_id,checked_at,success,error_code) VALUES(?,?,0,?)').run(subscriptionId, checkedAt, code);
                    this.db.prepare('UPDATE subscriptions SET failures=?,next_due=?,updated_at=?,version=version+1 WHERE subscription_id=?').run(failures, next, checkedAt, subscriptionId);
                    recordEvent(this.db, 'subscription.updated', 'subscription', subscriptionId, { subscriptionId, kind: 'check', success: false, checkedAt, errorCode: code });
                    this.db.exec('COMMIT');
                }
                catch (failure) {
                    this.db.exec('ROLLBACK');
                    throw failure;
                }
            }
            finally {
                this.subscriptionController = undefined;
            }
        }
    }
    private async runTask(task: PendingTask, lease: TaskLease, controller: AbortController) {
        const heartbeat = setInterval(() => {
            try {
                assertLease(this.db, lease.taskId, lease.leaseOwner, lease.leaseGeneration);
                const now = new Date();
                this.db.prepare('UPDATE task_leases SET heartbeat_at=?,lease_expires_at=? WHERE task_id=? AND lease_owner=? AND lease_generation=?').run(now.toISOString(), new Date(now.getTime() + this.leaseTtlMs).toISOString(), lease.taskId, lease.leaseOwner, lease.leaseGeneration);
            }
            catch (error) {
                controller.abort(error);
            }
        }, Math.max(50, Math.floor(this.leaseTtlMs / 3)));
        try {
            await abortable(async () => {
                if (this.options.processTask)
                    return this.options.processTask(task, lease, controller.signal);
                const row = this.db.prepare('SELECT * FROM download_tasks WHERE task_id=?').get(task.task_id) as Record<string, unknown> | undefined;
                if (!row)
                    throw permanent('LEASE_FENCED');
                const result = await this.options.downloadAdapter!.execute(row, { lease, signal: controller.signal, assertLease: () => { aborted(controller.signal); assertLease(this.db, lease.taskId, lease.leaseOwner, lease.leaseGeneration); } });
                aborted(controller.signal);
                persistDownloadResult(this.db, lease, result);
            }, controller, this.options.taskTimeoutMs ?? (this.db.prepare('SELECT recording_json FROM download_tasks WHERE task_id=?').get(task.task_id)?.recording_json?61*60000:30*60000));
        }
        catch (error) {
            const code = errorCode(error, 'DOWNLOAD_ADAPTER_ERROR');
            if (!this.stopping && !['TASK_CONTROLLED', 'LEASE_FENCED', 'WORKER_STOPPED'].includes(code)) {
                try {
                    persistDownloadResult(this.db, lease, { status: (error as {
                            retryable?: boolean;
                        }).retryable === false ? 'permanent_failure' : 'retryable_failure', failureCode: code });
                }
                catch (failure) {
                    if (errorCode(failure, '') !== 'LEASE_FENCED')
                        throw failure;
                }
                this.options.onError?.(error);
            }
        }
        finally {
            clearInterval(heartbeat);
            resetTransferProgress(this.db,lease);
            this.db.prepare('UPDATE task_leases SET lease_expires_at=? WHERE task_id=? AND lease_owner=? AND lease_generation=?').run(new Date().toISOString(), lease.taskId, lease.leaseOwner, lease.leaseGeneration);
        }
    }
}
function resetTransferProgress(db:DatabaseSync,lease:TaskLease){
    db.exec('BEGIN IMMEDIATE');try{const prior=db.prepare('SELECT t.bytes,t.speed,t.status FROM download_tasks t JOIN task_leases l ON l.task_id=t.task_id WHERE t.task_id=? AND l.lease_owner=? AND l.lease_generation=?').get(lease.taskId,lease.leaseOwner,lease.leaseGeneration) as {bytes:number;speed:number|null;status:string}|undefined;
        if(prior){const bytes=Number((db.prepare("SELECT COALESCE(SUM(bytes),0) AS bytes FROM download_files WHERE task_id=? AND status='completed'").get(lease.taskId) as {bytes:number}).bytes);if(prior.bytes!==bytes||prior.speed!==null){db.prepare('UPDATE download_tasks SET bytes=?,speed=NULL,updated_at=?,version=version+1 WHERE task_id=?').run(bytes,new Date().toISOString(),lease.taskId);recordEvent(db,'download.statusChanged','download',lease.taskId,{taskId:lease.taskId,status:prior.status,bytes,speed:null});}}
        db.exec('COMMIT');
    }catch(error){db.exec('ROLLBACK');throw error;}
}
function recordOutboxAttempt(db: DatabaseSync, eventId: string) { db.prepare('UPDATE event_outbox SET attempts=attempts+1 WHERE event_id=? AND published_at IS NULL').run(eventId); }
async function abortable<T>(action: () => Promise<T> | T, controller: AbortController, timeoutMs: number): Promise<T> {
    aborted(controller.signal);
    let listener: (() => void) | undefined;
    const timer = setTimeout(() => controller.abort(retryable('TIMEOUT')), timeoutMs);
    try {
        return await Promise.race([Promise.resolve().then(action), new Promise<never>((_resolve, reject) => { listener = () => reject(controller.signal.reason ?? permanent('CANCELLED')); controller.signal.addEventListener('abort', listener, { once: true }); })]);
    }
    finally {
        clearTimeout(timer);
        if (listener)
            controller.signal.removeEventListener('abort', listener);
    }
}
export function persistDownloadResult(db: DatabaseSync, lease: TaskLease, result: DownloadResult) {
    if (!['completed', 'retryable_failure', 'permanent_failure'].includes(result.status))
        throw permanent('SOURCE_PROTOCOL_ERROR');
    for (const value of [result.completedCount, result.totalCount, result.bytes])
        if (value !== undefined && (!Number.isSafeInteger(value) || value < 0))
            throw permanent('SOURCE_PROTOCOL_ERROR');
    const now = new Date().toISOString();
    db.exec('BEGIN IMMEDIATE');
    try {
        assertLease(db, lease.taskId, lease.leaseOwner, lease.leaseGeneration);
        const status = result.status === 'completed' ? 'completed' : 'failed';
        db.prepare("UPDATE download_tasks SET status=?,speed=NULL,completed_count=COALESCE(?,completed_count),total_count=COALESCE(?,total_count),bytes=COALESCE(?,(SELECT COALESCE(SUM(bytes),0) FROM download_files WHERE task_id=download_tasks.task_id AND status='completed')),failure_code=?,recoverable=?,updated_at=?,version=version+1 WHERE task_id=?").run(status, result.completedCount ?? null, result.totalCount ?? null, result.bytes ?? null, result.failureCode ?? null, result.status === 'retryable_failure' ? 1 : 0, now, lease.taskId);
        const sequence = Number((db.prepare('SELECT COALESCE(MAX(sequence),0)+1 AS next FROM domain_events').get() as {
            next: number;
        }).next);
        const eventVersion = Number((db.prepare('SELECT COALESCE(MAX(event_version),0)+1 AS next FROM domain_events WHERE aggregate_type=? AND aggregate_id=?').get('download', lease.taskId) as {
            next: number;
        }).next);
        appendOutboxEventInTransaction(db, { eventId: randomUUID(), sequence, eventType: 'download.statusChanged', aggregateType: 'download', aggregateId: lease.taskId, aggregateVersion: Number((db.prepare('SELECT version FROM download_tasks WHERE task_id=?').get(lease.taskId) as {
                version: number;
            }).version), eventVersion, payload: { taskId: lease.taskId, status, failureCode: result.failureCode ?? null } });
        db.exec('COMMIT');
    }
    catch (error) {
        try {
            db.exec('ROLLBACK');
        }
        catch { }
        throw error;
    }
}
