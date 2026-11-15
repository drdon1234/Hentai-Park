import {t} from './i18n.js';
import { useEffect, useRef, useState, useId, type ReactNode } from 'react';
import { StatusMessage } from '@hentai-park/design-system';
import { workIdentityKey } from '@hentai-park/domain-model';
import { api,request, allPages, type ApiChapter, type DownloadTask } from './api.js';
import { dedupeDownload, useSharedState } from './native.js';

const message = (error: unknown) => error instanceof Error ? error.message : t("请求未能完成。");
function categoryIds(text: string) { const ids = [...new Set(text.split(/\r?\n/).map(value => value.trim()).filter(Boolean))]; if (ids.length > 128 || ids.some(value => value.length > 128 || !/^[A-Za-z0-9_][A-Za-z0-9._:-]*$/.test(value) || /^[A-Za-z][A-Za-z0-9+.-]*:/.test(value))) throw new Error(t("分类ID格式无效：每项最长128字符，以字母、数字或下划线开头，可含点、短横线和冒号，不接受网址；最多128项。")); return ids; }

export function CategoryEditor({ source, workId, title,openRequest=0,favoriteOnSave=false }: { source: string; workId: string; title: string;openRequest?:number;favoriteOnSave?:boolean }) {
  const dialog=useRef<HTMLDialogElement>(null),trigger=useRef<HTMLButtonElement>(null),titleId=useId();
  const [categories,setCategories]=useState<Array<{id:string;name:string}>>([]),[categoryError,setCategoryError]=useState(''),[categoryLoading,setCategoryLoading]=useState(true),[categoryAttempt,setCategoryAttempt]=useState(0);useEffect(()=>{let active=true;const reload=()=>{setCategoryLoading(true);void request<{items:Array<{id:string;name:string}>}>('/api/v1/categories').then(value=>{if(active){setCategories(value.items);setCategoryError('');}}).catch(reason=>{if(active)setCategoryError(message(reason));}).finally(()=>{if(active)setCategoryLoading(false);});};reload();window.addEventListener('hp:invalidate',reload);window.addEventListener('hp:server-update',reload);return()=>{active=false;window.removeEventListener('hp:invalidate',reload);window.removeEventListener('hp:server-update',reload);};},[categoryAttempt]);
  const shared = useSharedState(); const entry = shared.collections[workIdentityKey({ source, id: workId })]; const currentVersion = entry?.version ?? 0;
  const committed=useRef<{text:string;version:number;dirty:boolean}|undefined>(undefined);
  const [draft, setDraft] = useState<{ text: string; version: number; dirty: boolean }>(); const [busy, setBusy] = useState(false); const [notice, setNotice] = useState(''); const [error, setError] = useState('');
  const activeDraft = draft && (draft.dirty || draft.version > currentVersion) ? draft : undefined; const value = activeDraft?.text ?? (entry?.categoryIds ?? []).join('\n'); const baseVersion = activeDraft?.version ?? currentVersion; const dirty = activeDraft?.dirty === true;
  const reload = async () => { setBusy(true); setError(''); setNotice(t("正在读取分类…")); try { const entries = await allPages(api.library); const fresh = entries.find(value => value.source === source && value.workId === workId); setDraft({ text: (fresh?.categoryIds ?? []).join('\n'), version: fresh?.version ?? 0, dirty: false }); window.dispatchEvent(new Event('hp:invalidate')); setNotice(t("已读取当前服务端分类")); } catch (reason) { setError(message(reason)); setNotice(''); } finally { setBusy(false); } };
  useEffect(()=>{if(openRequest>0){setDraft({text:(entry?.categoryIds??[]).join('\n'),version:currentVersion,dirty:false});setError('');dialog.current?.showModal();}},[openRequest]);
  const save = async () => { let ids: string[]; try { ids = categoryIds(value); } catch (reason) { setError(message(reason)); return; } setBusy(true); setError(''); setNotice(t("正在保存分类…")); try { const saved = await api.setLibrary({ source, workId, categoryIds: ids, version: baseVersion,...(favoriteOnSave?{favorite:true}:{}) }); committed.current={ text: saved.categoryIds.join('\n'), version: saved.version, dirty: false }; setDraft(committed.current); setNotice(t("分类已保存")); dialog.current?.close(); } catch (reason) { setError(message(reason)); setNotice(''); } finally { setBusy(false); } };
  return <div className="collection-editor"><button ref={trigger} type="button" className="chip" onClick={()=>{committed.current={text:value,version:baseVersion,dirty:false};setNotice('');dialog.current?.showModal();}}>{t("编辑收藏分类")}</button><dialog ref={dialog} className="collection-dialog" aria-labelledby={titleId} onCancel={event=>{if(busy)event.preventDefault();}} onClose={()=>{setDraft(committed.current);setError('');trigger.current?.focus();}}><h2 id={titleId}>{t("编辑收藏分类")}</h2><p className="collection-work-title">{title}</p><p>{t("归类不会自动改变收藏状态。")}</p><form onSubmit={event => { event.preventDefault(); void save(); }}><fieldset><legend>{t('选择分类')}</legend>{categoryLoading?<p role="status">{t("正在读取分类…")}</p>:null}{categoryError?<p role="alert">{categoryError}<button type="button" className="chip" onClick={()=>setCategoryAttempt(value=>value+1)}>{t("重试")}</button></p>:null}{!categoryLoading&&!categoryError&&!categories.length?<p>{t("还没有分类，创建后可在作品中归类。")}</p>:null}{categories.map(category=><label key={category.id}><input type="checkbox" disabled={busy||!shared.collectionsReady} checked={value.split('\n').includes(category.id)} onChange={event=>{const ids=value.split('\n').filter(Boolean);setDraft({text:(event.target.checked?[...new Set([...ids,category.id])]:ids.filter(id=>id!==category.id)).join('\n'),version:baseVersion,dirty:true});setNotice('');}}/>{category.name}</label>)}</fieldset><a className="collection-manage-link" href="/library#library-management">{t('管理分类名称与排序')}</a><details className="advanced-options"><summary>{t("分类ID")}</summary><p>{t("每行输入一个稳定分类ID。")}</p><label>{t("分类ID")}<textarea aria-label={t("分类ID ") + title} rows={3} value={value} disabled={busy || !shared.collectionsReady} onChange={event => { setDraft({ text: event.target.value, version: baseVersion, dirty: true }); setNotice(''); }} /></label><button className="chip" disabled={busy || !shared.collectionsReady} type="button" onClick={() => {if(!dirty||window.confirm(t("重新读取会放弃未保存的分类选择，继续？")))void reload();}}>{t("重新读取分类")}</button></details><div className="action-row collection-dialog-actions"><button type="button" className="chip" disabled={busy} onClick={()=>dialog.current?.close()}>{t("取消")}</button><button className="primary-link" disabled={busy || !shared.collectionsReady || (!dirty&&!favoriteOnSave)} type="submit">{t("保存分类")}</button></div></form>{dirty && currentVersion > baseVersion ? <StatusMessage tone="warning" title={t("分类已在其他页面变更")}>{t("当前草稿已保留，保存前请重新读取服务端分类。")}</StatusMessage> : null}{error ? <StatusMessage tone="danger" title={t("分类保存失败")}>{error}</StatusMessage> : null}{busy&&notice?<p role="status">{notice}</p>:null}</dialog>{!busy&&notice ? <p role="status">{notice}</p> : null}</div>;
}

type Submission = { task?: DownloadTask; error?: string };
type ReadUpdate = Pick<ApiChapter, 'chapterId' | 'readState' | 'version'>;
export function ChapterDownloads({ source, workId, chapters, renderChapter, isVideo = false, allowDownload = true, hasMore = false }: { source: string; workId: string; chapters: ApiChapter[]; renderChapter: (chapter: ApiChapter) => ReactNode; isVideo?: boolean; allowDownload?: boolean; hasMore?: boolean }) {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [results, setResults] = useState<Record<string, Submission>>({});
  const [busy, setBusy] = useState(false), [total, setTotal] = useState(0), [submitted, setSubmitted] = useState(0);
  const [selecting, setSelecting] = useState(false), [reversed, setReversed] = useState(false);
  const [readUpdates, setReadUpdates] = useState<Record<string, ReadUpdate>>({});
  const [readMessage, setReadMessage] = useState(''), [readError, setReadError] = useState('');
  const alive = useRef(true), selectButton = useRef<HTMLButtonElement>(null), selectionTools = useRef<HTMLDivElement>(null);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
  useEffect(() => { const reveal = () => { if (window.location.hash === '#chapter-downloads') setSelecting(true); }; reveal(); window.addEventListener('hashchange', reveal); return () => window.removeEventListener('hashchange', reveal); }, []);
  useEffect(() => { if (selecting) selectionTools.current?.querySelector<HTMLButtonElement>('button')?.focus({preventScroll:true}); }, [selecting]);
  const rows = chapters.map(chapter => { const update = readUpdates[chapter.chapterId]; return update && update.version >= chapter.version ? {...chapter, ...update} : chapter; });
  const eligible = rows.filter(chapter => !chapter.nodeType || ['audio','video','image','script','subtitle'].includes(chapter.nodeType));
  const chosen = eligible.filter(chapter => selected.has(chapter.chapterId));
  const failed = eligible.filter(chapter => results[chapter.chapterId]?.error);
  const accepted = Object.values(results).filter(result => result.task).length;
  const unread = eligible.filter(chapter => chapter.readState !== 'read').length;
  const previous = chosen.length === 1 ? eligible.slice(0, eligible.findIndex(chapter => chapter.chapterId === chosen[0]!.chapterId)) : [];
  const ordered = reversed ? [...rows].reverse() : rows;
  const finishSelection = () => { setSelected(new Set()); setSelecting(false); requestAnimationFrame(() => selectButton.current?.focus()); };
  const submit = async (items: ApiChapter[]) => {
    if (busy || !allowDownload || !items.length) return;
    setBusy(true); setTotal(items.length); setSubmitted(0);
    for (let index = 0; index < items.length; index++) {
      const chapter = items[index]!; const input = { source, workId, chapterId: chapter.chapterId, variant: 'original' }; let result: Submission;
      try { result = { task: await dedupeDownload(input, () => api.createDownload(input)) }; } catch (reason) { result = { error: message(reason) }; }
      if (alive.current) { setResults(values => ({ ...values, [chapter.chapterId]: result })); setSubmitted(index + 1); }
    }
    if (alive.current) setBusy(false);
  };
  const mark = async (items: ApiChapter[], readState: 'read' | 'unread') => {
    if (busy || !items.length) return;
    setBusy(true); setReadError(''); setReadMessage(t('正在保存已读状态…'));
    try {
      for (let offset = 0; offset < items.length; offset += 200) {
        const batch = items.slice(offset, offset + 200);
        const result = await request<{items: ReadUpdate[]}>('/api/v1/works/' + encodeURIComponent(source) + '/' + encodeURIComponent(workId) + '/chapters/read-state', {method:'POST', body:JSON.stringify({chapters:batch.map(chapter=>({chapterId:chapter.chapterId,version:chapter.version})),readState,requestKey:crypto.randomUUID()})});
        if (alive.current) { setReadUpdates(values => ({...values,...Object.fromEntries(result.items.map(item=>[item.chapterId,item]))})); setSelected(values=>new Set([...values].filter(id=>!result.items.some(item=>item.chapterId===id)))); setReadMessage(t('已更新已读状态') + ' · ' + Math.min(offset + 200, items.length) + ' / ' + items.length); }
      }
      if (alive.current) finishSelection();
    } catch (reason) { if (alive.current) { setReadError(message(reason)); } }
    finally { if (alive.current) setBusy(false); }
  };
  return <section id="chapter-downloads" tabIndex={-1} className="chapter-downloads" aria-label={t(isVideo ? '选集' : '章节')}>
    {!selecting ? <div className="section-header"><h2>{t(isVideo ? '选集' : '章节')} · {hasMore ? t('已加载') + ' ' : ''}{rows.length}{!isVideo && unread ? '（' + t('未读') + ' ' + unread + '）' : ''}</h2><div className="action-row"><button className="chip" disabled={busy} onClick={()=>setReversed(value=>!value)} aria-label={t('切换章节排序')}>{t(reversed ? '倒序' : '正序')}</button><button ref={selectButton} className="chip" disabled={!eligible.length || busy} onClick={()=>setSelecting(true)}>{t('选择章节')}</button></div></div> :
      <div ref={selectionTools} className="chapter-download-tools" role="group" aria-label={t('章节选择操作')}><div className="action-row"><button className="chip" disabled={busy} onClick={finishSelection}>{t('取消选择')}</button><span>{t('已选 ')}{chosen.length}</span><button className="chip" disabled={busy || !eligible.length} onClick={()=>setSelected(new Set(eligible.map(chapter=>chapter.chapterId)))}>{t('全选已加载章节')}</button>{allowDownload ? <button className="chip" disabled={busy || !chosen.length} onClick={()=>void submit(chosen)}>{t('下载所选章节')}</button> : null}</div>{!isVideo ? <div className="action-row"><button className="chip" disabled={busy || !chosen.length} onClick={()=>void mark(chosen,'read')}>{t('标为已读')}</button><button className="chip" disabled={busy || !chosen.length} onClick={()=>void mark(chosen,'unread')}>{t('标为未读')}</button>{chosen.length === 1 ? <button className="chip" disabled={busy || !previous.length} onClick={()=>void mark(previous,'read')}>{t('此前已加载章节标为已读')}</button> : null}</div> : null}{allowDownload && busy && total > submitted ? <p>{t('已接收任务会在后台继续。请等待提交结束后再关闭页面。')}</p> : null}</div>}

    <ul className="chapter-list">{ordered.map(chapter=><li key={chapter.chapterId}>{selecting && eligible.includes(chapter) ? <label className="chapter-select"><input type="checkbox" aria-label={t('选择章节') + ' ' + chapter.title} checked={selected.has(chapter.chapterId)} disabled={busy} onChange={event=>setSelected(values=>{const next=new Set(values);if(event.target.checked)next.add(chapter.chapterId);else next.delete(chapter.chapterId);return next;})}/></label> : null}{renderChapter(chapter)}</li>)}</ul>
    {readMessage ? <p role="status">{readMessage}</p> : null}{readError ? <StatusMessage tone="danger" title={t('已读状态保存失败')}>{readError}<button className="chip" disabled={busy} onClick={()=>window.dispatchEvent(new Event('hp:retry-read'))}>{t('重新读取章节')}</button></StatusMessage> : null}
    {total > 0 ? <p role="status">{busy && total > submitted ? t('正在提交 ') + submitted + ' / ' + total : t('提交结束')} · {accepted}{t(' 项已接收，')}{failed.length}{t(' 项未提交')} <a href="/downloads">{t('查看下载任务')}</a></p> : null}
    {failed.length ? <><button className="chip" disabled={busy} onClick={()=>void submit(failed)}>{t('重试失败章节')}</button><ul className="download-failures">{failed.map(chapter=><li key={chapter.chapterId}>{chapter.title}：{results[chapter.chapterId]?.error}<button className="chip" disabled={busy} aria-label={t('重试下载 ') + chapter.title} onClick={()=>void submit([chapter])}>{t('重试此章')}</button></li>)}</ul></> : null}
  </section>;
}
