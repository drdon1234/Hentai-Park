import { useEffect, useRef, useState, type MouseEvent } from 'react';
import { EmptyState, StatusMessage } from '@hentai-park/design-system';
import { api, allPages, type Source, type Subscription } from './api.js';
import { t } from './i18n.js';
import { PageHeader, StateView, useAsync, errorMessage, useServerVersion } from './page-ui.js';
import {SubscriptionUpdates} from './data-controls.js';
export function SubscriptionsPage({navigate}:{navigate:(href:string)=>void}) {
  const version = useServerVersion(); const state = useAsync(() => api.subscriptions({ limit: 200 }), [version]); const sourceState = useAsync(() => allPages(api.sources), [version]); const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const [message, setMessage] = useState(''); const [form, setForm] = useState({ source: '', dimension: '', target: '',notify:true }); const [extra, setExtra] = useState<Subscription[]>([]); const [cursor, setCursor] = useState<string | null>();
  const [previous, setPrevious] = useState<Awaited<ReturnType<typeof api.subscriptions>>>(); const [previousSources, setPreviousSources] = useState<Source[]>([]);
  useEffect(() => { if (state.data) setPrevious(state.data); }, [state.data]); useEffect(() => { if (sourceState.data) setPreviousSources(sourceState.data); }, [sourceState.data]);
  const snapshot = state.data ?? previous; const sourceSnapshot = sourceState.data ?? previousSources;
  const date = (value: string | null) => value ? <time dateTime={value}>{new Date(value).toLocaleString('zh-CN', { hour12: false })}</time> : t("尚无记录");
  const interval = (value: number | null) => value !== null && Number.isFinite(value) && value > 0 ? new Intl.NumberFormat('zh-CN', { maximumFractionDigits: 3 }).format(value / 1000) + t(" 秒") : t("后台尚未提供");
  const availableSources = (sourceSnapshot ?? []).filter((item) => item.enabled && item.installed !== false && (item.manifest?.capabilities as Record<string, boolean> | undefined)?.subscriptionUpdates === true);
  const dimensionsFor = (source: string) => { const declaration = availableSources.find((item) => item.source === source)?.manifest?.updateSubscriptions as { dimensions?: Array<{ key: string; label?: string }> } | undefined; return (declaration?.dimensions ?? []).filter((item) => typeof item.key === 'string' && item.key); };
  const dimensions = dimensionsFor(form.source);
  useEffect(() => { if (dimensions.length && !form.dimension) setForm((value) => ({ ...value, dimension: dimensions[0]!.key })); }, [form.source, form.dimension, sourceSnapshot]);
  useEffect(() => { setExtra([]); setCursor(snapshot?.page?.nextCursor); }, [snapshot]);
  const run = async (action: () => Promise<unknown>) => { setBusy(true); setError(''); setMessage(t("正在提交…")); try { await action(); setMessage(t("操作已完成")); } catch (reason) { setError(errorMessage(reason)); setMessage(''); } finally { setBusy(false); } };

  const readControl = useRef({ active: false, cancelled: false });
  const [reading, setReading] = useState(false);
  const [cancelling, setCancelling] = useState(false);
  useEffect(() => () => { readControl.current.cancelled = true; }, []);
  const read = async () => {
    if (busy || readControl.current.active) return;
    readControl.current = { active: true, cancelled: false };
    const control = readControl.current;
    setBusy(true); setReading(true); setCancelling(false); setError(''); setMessage(t('正在提交…'));
    try {
      let batch = await api.subscriptions({ limit: 1 });
      const maximum = Math.max(0, batch.unreadCount ?? 0);
      const processed = new Set<string>();
      while (!control.cancelled && processed.size < maximum) {
        const ids = (batch.unreadEventIds ?? []).slice(0, Math.min(500, maximum - processed.size));
        if (!ids.length) break;
        if (new Set(ids).size !== ids.length || ids.some(id => processed.has(id))) throw new Error(t('操作未完成，请重试。'));
        await api.readEvents(ids);
        ids.forEach(id => processed.add(id));
        setMessage(t('正在提交…') + ' ' + processed.size + ' / ' + maximum);
        if (!control.cancelled && processed.size < maximum) batch = await api.subscriptions({ limit: 1 });
      }
      setMessage(t(control.cancelled ? '已取消' : '操作已完成'));
    } catch (reason) { setError(errorMessage(reason)); setMessage(''); }
    finally {
      control.active = false; setBusy(false); setReading(false); setCancelling(false);
      window.dispatchEvent(new Event('hp:invalidate'));
    }
  };
  const dialog = useRef<HTMLDialogElement>(null);
  const [editing,setEditing]=useState<Subscription>();
  const [dialogError,setDialogError]=useState('');
  const trigger=useRef<HTMLElement|null>(null);
  const link=(event:MouseEvent<HTMLAnchorElement>)=>{if(event.button===0&&!event.ctrlKey&&!event.metaKey&&!event.shiftKey&&!event.altKey){event.preventDefault();navigate(event.currentTarget.getAttribute('href')!);}};
  const open=(item?:Subscription)=>{trigger.current=document.activeElement as HTMLElement;setEditing(item);setDialogError('');const source=item?.source??availableSources[0]?.source??'';setForm({source,dimension:item?.dimension??dimensionsFor(source)[0]?.key??'',target:item?.target??'',notify:item?.notify??true});dialog.current?.showModal();};
  const close=()=>{dialog.current?.close();trigger.current?.focus();};
  const submit=async(event:React.FormEvent)=>{event.preventDefault();setBusy(true);setDialogError('');try{if(editing)await api.updateSubscription(editing.subscriptionId,{target:form.target.trim(),notify:form.notify,version:editing.version});else await api.createSubscription({...form,target:form.target.trim(),enabled:true});close();setMessage(t('操作已完成'));}catch(reason){setDialogError(errorMessage(reason));}finally{setBusy(false);}};
  const items=[...(snapshot?.items??[]),...extra];
  const updates=new URLSearchParams(window.location.search).get('view')==='updates';
  const contentHref=(item:Subscription)=>{const caps=sourceSnapshot.find(source=>source.source===item.source)?.manifest?.capabilities as Record<string,boolean>|undefined;if(item.dimension==='posts'&&caps?.subscription)return '/channel/'+encodeURIComponent(item.source)+'?target='+encodeURIComponent(item.target);if(item.dimension==='work'&&caps?.detail)return '/work/'+[item.source,item.target].map(encodeURIComponent).join('/');return '/source/'+encodeURIComponent(item.source);};
  return <><PageHeader title={t(updates?'订阅更新':'订阅')}>
    {updates?<a className="chip" href="/subscriptions" onClick={link}>{t('订阅')}</a>:<button className="primary-link" disabled={busy||sourceState.loading} onClick={()=>availableSources.length?open():navigate('/sources')}>{t('添加订阅')}</button>}
  </PageHeader>
  {message?<p role="status">{message}</p>:null}{error?<StatusMessage tone="danger" title={t('订阅操作失败')}>{error}</StatusMessage>:null}
  {updates?<><div className="action-row"><span role="status">{snapshot?.unreadCount??0}{t(' 条未读')}</span><button className="chip" disabled={busy||!snapshot?.unreadEventIds?.length} onClick={()=>void read()}>{t('全部标为已读')}</button>{reading?<button className="chip" disabled={cancelling} onClick={()=>{readControl.current.cancelled=true;setCancelling(true);}}>{t(cancelling?'正在提交…':'取消')}</button>:null}</div><SubscriptionUpdates navigate={navigate}/></>:<>
    <div className="subscription-entry-links"><a href="/subscriptions?view=updates" onClick={link}>{t('订阅更新')}<span>{snapshot?.unreadCount??0}{t(' 条未读')} →</span></a><details><summary>{t('订阅设置')}</summary><a href="/settings?section=subscriptions" onClick={link}>{t('订阅与通知')}</a><p>{t('检查周期与通知由设置中的订阅分区管理。')}</p></details></div>
    <p className="muted">{t('无需登录即可保存订阅；媒体访问取决于原站权限。')}</p>
    {sourceState.error?<StatusMessage tone="danger" title={t('订阅站点读取失败')}>{errorMessage(sourceState.error)}</StatusMessage>:null}
    {!sourceState.loading&&!sourceState.error&&!availableSources.length?<StatusMessage title={t('暂无支持更新订阅的站点')}><a href="/sources" onClick={link}>{t('前往站点管理')}</a></StatusMessage>:null}
    {state.error&&snapshot?<StatusMessage tone="warning" title={t('订阅列表刷新失败')}>{t('当前保留上次读取的检查状态。')}{errorMessage(state.error)}</StatusMessage>:null}
    <StateView loading={state.loading&&!snapshot} error={snapshot?undefined:state.error} empty={false}>
      {!items.length?<EmptyState title={t('还没有订阅')} detail={t('添加订阅后，在这里查看与管理更新。')}/>:null}
      {[...new Set(items.map(item=>item.source))].map(source=><section className="subscription-group" key={source}><h2>{String(sourceSnapshot.find(item=>item.source===source)?.manifest?.name??source)}</h2><ul className="subscription-list">{items.filter(item=>item.source===source).map(item=><li key={item.subscriptionId}>
        <a className="subscription-target" href={contentHref(item)} onClick={link}><strong>{item.target}</strong><small>{dimensionsFor(source).find(dimension=>dimension.key===item.dimension)?.label??item.dimension} · {t(item.enabled?'检查已开启':'检查已暂停')}</small></a>
        <div className="action-row"><button className="chip" disabled={busy||!item.enabled} onClick={()=>void run(()=>api.checkSubscription(item.subscriptionId))}>{t('立即检查')}</button><button className="chip" disabled={busy} onClick={()=>void run(()=>api.updateSubscription(item.subscriptionId,{enabled:!item.enabled,version:item.version}))}>{t(item.enabled?'暂停':'启用')}</button></div><details className="subscription-options"><summary style={{display:'list-item',paddingBlock:12}}>{t('更多')}</summary><div className="action-row"><button className="chip" disabled={busy} onClick={()=>open(item)}>{t('编辑订阅')}</button><button className="chip" disabled={busy} aria-pressed={item.notify} onClick={()=>void run(()=>api.updateSubscription(item.subscriptionId,{notify:!item.notify,version:item.version}))}>{t(item.notify?'通知已启用':'通知已关闭')}</button><a href={'/source/'+encodeURIComponent(source)+'#source-management'} onClick={link}>{t('账号与站点设置')}</a><button className="chip danger-action" disabled={busy} onClick={()=>{if(window.confirm(t('删除订阅并保留更新历史？')))void run(()=>api.deleteSubscription(item.subscriptionId));}}>{t('删除')}</button></div><h3>{t('订阅状态')}</h3><p>{t(item.baseline?'已建立':'待首次检查')}</p><p>{t('最近成功：')}{date(item.lastSuccess)}{t(' · 下次检查：')}{item.enabled?item.nextDue?date(item.nextDue):t('等待调度'):t('已暂停')}</p><p>{t('检查周期：')}{interval(item.intervalMs)}{t(' · 最近检查：')}{date(item.lastCheckedAt)}</p>{item.lastError?<p role="status">{t('最近错误：')}{item.lastError}{t(' · 连续失败：')}{item.failures}</p>:null}</details>
      </li>)}</ul></section>)}
      {cursor?<button className="chip" disabled={busy} onClick={()=>void run(async()=>{const value=await api.subscriptions({cursor:cursor??undefined,limit:200});setExtra(items=>[...items,...value.items]);setCursor(value.page?.nextCursor);})}>{t('加载更多订阅')}</button>:null}
    </StateView>
  </>}
  <dialog ref={dialog} className="subscription-dialog" aria-labelledby="subscription-dialog-title" onCancel={event=>{if(busy)event.preventDefault();}} onClose={()=>trigger.current?.focus()}><form onSubmit={event=>void submit(event)}><h2 id="subscription-dialog-title">{t(editing?'编辑订阅':'添加订阅')}</h2>{editing?<p>{String(sourceSnapshot.find(source=>source.source===editing.source)?.manifest?.name??editing.source)} · {dimensionsFor(editing.source).find(item=>item.key===editing.dimension)?.label??editing.dimension}</p>:<><label>{t('订阅站点')}<select autoFocus value={form.source} required onChange={event=>{const source=event.target.value;setForm({...form,source,dimension:dimensionsFor(source)[0]?.key??''});}}>{availableSources.map(item=><option key={item.source} value={item.source}>{String(item.manifest?.name??item.source)}</option>)}</select></label><label>{t('订阅维度')}<select value={form.dimension} required onChange={event=>setForm({...form,dimension:event.target.value})}>{dimensions.map(item=><option key={item.key} value={item.key}>{item.label??item.key}</option>)}</select></label></>}
    <label>{t('订阅目标')}<input autoFocus={Boolean(editing)} value={form.target} required onChange={event=>setForm({...form,target:event.target.value})}/></label><label><input type="checkbox" checked={form.notify} onChange={event=>setForm({...form,notify:event.target.checked})}/>{t('新内容通知')}</label>
    {!editing&&form.dimension&&!dimensions.some(item=>item.key===form.dimension)?<StatusMessage tone="warning" title={t('站点订阅能力已变更')}>{t('当前输入已保留，请重新选择站点声明的订阅维度。')}</StatusMessage>:null}
    {dialogError?<StatusMessage tone="danger" title={t('订阅操作失败')}>{dialogError}</StatusMessage>:null}<div className="action-row"><button type="button" className="chip" disabled={busy} onClick={close}>{t('取消')}</button><button className="primary-link" disabled={busy||!form.target.trim()||(!editing&&(!form.source||!dimensions.some(item=>item.key===form.dimension)))}>{t(busy?'正在提交…':'保存')}</button></div>
  </form></dialog></>;
}
