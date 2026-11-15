import type { DatabaseSync } from 'node:sqlite';

type Progress = {page:number|null;pageCount:number|null;position:number|null;duration:number|null;textOffset?:number|null};
const invalid=(code:string,statusCode:number)=>Object.assign(new Error(code),{code,statusCode,publicError:true,causeCategory:statusCode===409?'conflict':'validation',retryable:false});

/** Runs inside the caller's idempotent write transaction. */
export function mergeChapterProgress(db:DatabaseSync,source:string,workId:string,chapterId:string,version:number|undefined,input:Progress) {
  const row=db.prepare('SELECT c.version,c.page_progress,c.read_state,c.node_type,c.node_metadata_json,w.media_kind FROM chapters c JOIN works w ON w.source=c.source AND w.work_id=c.work_id WHERE c.source=? AND c.work_id=? AND c.chapter_id=?').get(source,workId,chapterId);
  if(!row)throw invalid('NOT_FOUND',404);
  if(version===undefined)throw invalid('PROGRESS_VERSION_REQUIRED',400);
  if(Number(row.version)!==version)throw Object.assign(invalid('CONFLICT',409),{details:{version:Number(row.version)}});
  if(input.page!==null&&input.pageCount!==null&&input.page>=input.pageCount)throw invalid('BAD_REQUEST',400);
  const textLength=Number(JSON.parse(String(row.node_metadata_json??'{}')).textLength);
  if(input.textOffset!=null&&(row.media_kind!=='novel'||!Number.isSafeInteger(input.textOffset)||input.textOffset<0||!Number.isSafeInteger(textLength)||input.textOffset>textLength))throw invalid('BAD_REQUEST',400);
  const comic=row.media_kind==='comic'||row.node_type==='image';
  const page=comic&&input.page!==null&&typeof row.page_progress==='number'?Math.max(input.page,row.page_progress):input.page;
  const complete=page!==null&&input.pageCount!==null&&page>=input.pageCount-1||input.position!==null&&input.duration!==null&&input.duration>0&&input.position>=input.duration*.99||input.textOffset!=null&&input.textOffset>=textLength;
  const untouched=input.page===null&&input.position===null&&input.textOffset==null;
  return {page,readState:complete||comic&&row.read_state==='read'?'read':untouched?String(row.read_state):'reading'};
}
