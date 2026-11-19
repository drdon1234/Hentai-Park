import { useEffect, useRef, useState, type ReactNode } from 'react';
import { confirmAction, showToast } from '@hentai-park/design-system';
import { api, request } from './api.js';
import { t, useLanguage } from './i18n.js';
import { TavernConnectionEditor, type TavernConnection } from './tavern-connections.js';
import { TavernLoreTranslations } from './worldbook-controls.js';

type ReplyVariant = {role:'assistant'; content:string; name?:string; status?:string};
const maxReplyVariants=8;
type Message = {
  role: string;
  content: string;
  name?: string;
  status?: string;
  alternatives?: ReplyVariant[];
};
type Settings = {
  userName: string;
  persona: string;
  memory?: string;
  notes?:string;
  tags?:string;
  speakerId?:string;
  castIds?:string[];
  title?:string;
  parentId?:string;
  worldbookIds: string[];
  contextTokens: number;
  maxTokens: number;
  temperature: number;
};
type Conversation = { conversationId?: string; version?: number; messages?: Message[]; settings?: Settings };
type Result = {
  role: string;
  content: string;
  inspection?: Array<{role:string;content:string}>;
  matchedEntries: number;
  unsupportedEntries: number;
  trimmedHistory: boolean;
  finishReason?: string;
};

const field = { flexDirection: 'column' as const, alignItems: 'stretch', gap: 8, width: '100%', maxWidth: '36rem', minWidth: 0 };
const textAreaStyle = {
  width: '100%',
  minWidth: 0,
  minHeight: 100,
  padding: 12,
  font: 'inherit',
  color: 'inherit',
  background: 'transparent',
  border: '1px solid var(--control-input-border, #737b88)',
  borderRadius: 12,
};
const defaults: Settings = { userName: 'User', persona: '', worldbookIds: [], contextTokens: 32768, maxTokens: 1024, temperature: 0.8 };
const API_BASE = (((import.meta as ImportMeta & { env?: Record<string, string> }).env?.VITE_API_BASE_URL) ?? '').replace(/\/$/, '');

/** Safe lightweight Markdown/RP formatter (no dangerouslySetInnerHTML, zero XSS risk). */
function renderSafeRpMessage(raw: string): ReactNode {
  const blocks = raw.split(/(```[\s\S]*?```)/g);
  return blocks.map((block, bIdx) => {
    if (block.startsWith('```') && block.endsWith('```')) {
      const inner = block.slice(3, -3).replace(/^[a-zA-Z0-9_-]+\n/, '');
      return (
        <pre key={bIdx} className="diagnostics" style={{ padding: 10, borderRadius: 10, background: 'var(--control-surface)' }}>
          <code>{inner}</code>
        </pre>
      );
    }
    const tokens = block.split(/(`[^`\n]+`|\*\*[^*\n]+\*\*|\*[^*\n]+\*|"[^"\n]+"|「[^」\n]+」|“[^”\n]+”)/g);
    return (
      <span key={bIdx} style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>
        {tokens.map((tok, tIdx) => {
          if (tok.startsWith('`') && tok.endsWith('`')) return <code key={tIdx}>{tok.slice(1, -1)}</code>;
          if (tok.startsWith('**') && tok.endsWith('**')) return <strong key={tIdx}>{tok.slice(2, -2)}</strong>;
          if (tok.startsWith('*') && tok.endsWith('*')) {
            return (
              <em key={tIdx} style={{ opacity: 0.82 }}>
                {tok.slice(1, -1)}
              </em>
            );
          }
          if (
            (tok.startsWith('"') && tok.endsWith('"')) ||
            (tok.startsWith('「') && tok.endsWith('」')) ||
            (tok.startsWith('“') && tok.endsWith('”'))
          ) {
            return (
              <span key={tIdx} style={{ color: 'var(--control-accent)', fontWeight: 500 }}>
                {tok}
              </span>
            );
          }
          return tok;
        })}
      </span>
    );
  });
}

async function generate(path: string, body: unknown, signal: AbortSignal, onDelta: (text: string) => void): Promise<Result> {
  const csrf = document.cookie
    .split(';')
    .map((value) => value.trim())
    .find((value) => value.startsWith('hp_csrf='))
    ?.slice(8);
  const headers: Record<string, string> = {
    'content-type': 'application/json',
    accept: 'text/event-stream',
    'x-request-id': crypto.randomUUID(),
  };
  if (csrf) headers['x-csrf-token'] = csrf;
  const response = await fetch(API_BASE + path, {
    method: 'POST',
    credentials: 'include',
    headers,
    body: JSON.stringify(body),
    signal,
  });
  if (!response.ok) {
    if (response.status === 423) window.dispatchEvent(new Event('hp:app-locked'));
    else if (response.status === 401) window.dispatchEvent(new Event('hp:unauthorized'));
    throw Error(t('生成请求失败（') + response.status + '）');
  }
  if (!response.body || !/text\/event-stream/.test(response.headers.get('content-type') ?? '')) {
    throw Error(t('模型返回格式无效。'));
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let pending = '';
  let result: Result | undefined;
  try {
    for (;;) {
      const next = await reader.read();
      if (next.done) break;
      pending += decoder.decode(next.value, { stream: true });
      if (pending.length > 1024 * 1024) throw Error(t('模型返回超过单次事件限制。'));
      let end: number;
      while ((end = pending.indexOf('\n\n')) >= 0) {
        const block = pending.slice(0, end);
        pending = pending.slice(end + 2);
        const data = block
          .split('\n')
          .filter((line) => line.startsWith('data:'))
          .map((line) => line.slice(5).trimStart())
          .join('\n');
        if (!data) continue;
        const event = JSON.parse(data);
        if (event.type === 'delta' && typeof event.content === 'string') onDelta(event.content);
        else if (event.type === 'done') result = event as Result;
        else if (event.type === 'error') {
          throw Error(
            event.code === 'CONTEXT_TOO_LARGE'
              ? t('上下文预算不足，请缩短资料、减少历史或调整预算。')
              : event.code === 'CANCELLED'
                ? t('生成已取消。')
                : t('模型回复未完成：') + String(event.code),
          );
        }
      }
    }
    if (!result) throw Error(t('回复流提前中断。'));
    return result;
  } finally {
    await reader.cancel().catch(() => {});
  }
}

export function TavernChat({
  assetId,
  initialGreeting,
  name = '',
  greetings = [],
  avatar,
}: {
  assetId: string;
  initialGreeting: string;
  name?: string;
  greetings?: string[];
  avatar?: string;
}) {
  const draftStorageKey = `hp-tavern-draft:${assetId}`;
  const [rows, setRows] = useState<Message[]>(initialGreeting ? [{ role: 'assistant', content: initialGreeting }] : []);
  const [draft, setDraft] = useState(() => {
    try {
      return localStorage.getItem(draftStorageKey) ?? '';
    } catch {
      return '';
    }
  });
  const [suggestedMemory,setSuggestedMemory]=useState('');
  const [inspection,setInspection]=useState<Result['inspection']>();
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [connection, setConnection] = useState<TavernConnection>();
  const [useTranslated, setUseTranslated] = useState(false);
  const [settings, setSettings] = useState<Settings>(defaults);
  const [conversation, setConversation] = useState<Conversation>({});
  const [history, setHistory] = useState<Conversation[]>([]);
  const [characters,setCharacters]=useState<Array<{assetId:string;name:string}>>([]);
  const [sessionQuery,setSessionQuery]=useState('');
  const branches=new Map<string,Conversation[]>();
  for(const item of history){
    const parent=item.settings?.parentId;
    if(parent){const list=branches.get(parent)??[];list.push(item);branches.set(parent,list);}
  }
  const ordered:{item:Conversation;depth:number}[]=[],seen=new Set<string>();
  const ids=new Set(history.map(item=>item.conversationId));
  for(const root of [...history.filter(item=>!ids.has(item.settings?.parentId??'')),...history]){
    const pending=[{item:root,depth:0}];
    while(pending.length){
      const row=pending.pop()!,id=row.item.conversationId;
      if(!id||seen.has(id))continue;
      seen.add(id);
      if(id===conversation.conversationId || [row.item.settings?.title,row.item.settings?.notes,row.item.settings?.tags].join(' ').toLowerCase().includes(sessionQuery.trim().toLowerCase()))ordered.push(row);
      for(const item of (branches.get(id)??[]).slice().reverse())pending.push({item,depth:row.depth+1});
    }
  }
  const [books, setBooks] = useState<Array<{ assetId: string; name: string }>>([]);
  const [greeting, setGreeting] = useState(0);

  const locale = useLanguage();
  const abort = useRef<AbortController | undefined>(undefined);
  const active = useRef(true);
  const path = '/api/v1/tavern/assets/' + encodeURIComponent(assetId);

  useEffect(() => {
    try {
      if (draft) localStorage.setItem(draftStorageKey, draft);
      else localStorage.removeItem(draftStorageKey);
    } catch {
      /* Optional localStorage */
    }
  }, [draft, draftStorageKey]);

  const refresh = async () => {
    const value = await request<{ items: Conversation[] }>(path + '/conversations');
    if (active.current) setHistory(value.items);
  };

  useEffect(() => {
    active.current = true;
    const controller = new AbortController();
    void Promise.all([
      refresh(),
      request<{ items: Array<{ assetId: string; name: string; kind: string }> }>('/api/v1/tavern/assets', {
        signal: controller.signal,
      }).then((value) => {
        if (!controller.signal.aborted) {setBooks(value.items.filter(row=>row.kind==='lorebook'));setCharacters(value.items.filter(row=>row.kind==='character'&&row.assetId!==assetId));}
      }),
    ]).catch((error) => {
      if (!controller.signal.aborted) setNote(String(error.message));
    });
    return () => {
      active.current = false;
      controller.abort();
      abort.current?.abort();
    };
  }, [path]);

  const save = async (messages = rows) => {
    const value = await request<Conversation>(path + '/conversations', {
      method: 'POST',
      body: JSON.stringify({ ...conversation, messages, settings }),
    });
    if (active.current) {
      setConversation(value);
      await refresh();
    }
  };

  const start = async (continuation = false, regenerate = false) => {
    if (!continuation && !regenerate && !draft.trim()) return;
    if (regenerate && (rows.at(-1)?.alternatives?.length??0)>=maxReplyVariants) return;
    const lastName=rows.at(-1)?.name;
    const replyId=(continuation||regenerate)&&lastName?characters.find(row=>row.name===lastName)?.assetId??'':settings.speakerId;
    const replyName=characters.find(row=>row.assetId===replyId)?.name??name;
    const original = rows;
    const sent = draft;
    const next = regenerate ? rows.slice(0, -1) : continuation ? rows : [...rows, { role: 'user', content: draft }];
    const controller = new AbortController();
    abort.current = controller;
    setRows(next);
    if (!continuation && !regenerate) setDraft('');
    setBusy(true);
    setNote('');
    let partial = '';
    let generated = false;
    const updated = (text: string) =>
      continuation && next.at(-1)?.role === 'assistant'
        ? [...next.slice(0, -1), { ...next.at(-1)!, content: next.at(-1)!.content + text }]
        : [...next, { role: 'assistant', name:replyName, content: text, status: 'complete' }];
    try {
      const result = await generate(
        path + '/reply',
        {
          connectionId: connection?.connectionId,
          messages: next,
          ...settings,
          speakerId:replyId,
          continuation,
          stream: true,
          locale,
          useTranslatedLore: useTranslated,
        },
        controller.signal,
        (text) => {
          partial += text;
          if (active.current) setRows(updated(partial));
        },
      );
      generated = true;
      const prior = regenerate ? rows.at(-1) : undefined;
      const complete = updated(result.content);
      if (complete.at(-1)?.role === 'assistant' && result.finishReason === 'length') {
        complete[complete.length - 1] = { ...complete.at(-1)!, status: 'length' };
      }
      if (regenerate && prior && complete.at(-1)?.role === 'assistant') {
        complete[complete.length - 1] = {
          ...complete.at(-1)!,
          alternatives: [...(prior.alternatives ?? []), { role: 'assistant', content: prior.content, name:prior.name, status:prior.status }],
        };
      }
      if (active.current) {
        setInspection(result.inspection);
        setRows(complete);
        setNote(
          (result.matchedEntries ? t('匹配世界书条目：') + result.matchedEntries : '') +
            (result.trimmedHistory ? t('；已按上下文预算裁剪较早历史。') : '') +
            (result.unsupportedEntries ? t('；部分扩展世界书规则未执行：') + result.unsupportedEntries : '') +
            (result.finishReason === 'length' ? t('；达到输出上限，可选择续写。') : ''),
        );
        await save(complete);
      }
    } catch (error) {
      if (active.current) {
        if (generated) {
          setNote(t('保存失败：') + String((error as Error).message));
        } else {
          if (!partial) {
            setRows(original);
            if (!continuation && !regenerate) setDraft(sent);
          }
          setNote(
            controller.signal.aborted
              ? t('生成已取消，输入与已接收内容已保留。')
              : t('发送失败，输入和会话已保留：') + String((error as Error).message),
          );
        }
      }
    } finally {
      if (active.current) setBusy(false);
    }
  };

  const replace = (text: string) => text.replaceAll('{{char}}', name).replaceAll('{{user}}', settings.userName);
  const options = [initialGreeting, ...greetings].filter(Boolean);
  const change = <K extends keyof Settings>(key: K, value: Settings[K]) => setSettings((prior) => ({ ...prior, [key]: value }));

  const [editing, setEditing] = useState<number>();
  const [editText, setEditText] = useState('');

  const hasUnsaved = () =>
    (editing !== undefined && editText !== rows[editing]?.content) ||
    JSON.stringify(rows) !==
      JSON.stringify(conversation.messages ?? (initialGreeting ? [{ role: 'assistant', content: initialGreeting }] : [])) ||
    JSON.stringify(settings) !== JSON.stringify(conversation.settings ?? defaults);

  const confirmSwitch = async () => !hasUnsaved() || (await confirmAction(t('切换会话将丢弃未保存的内容，继续？')));

  const updateMessages = async (next: Message[]) => {
    setRows(next);
    setBusy(true);
    try {
      await save(next);
      setNote(t('会话已保存。'));
    } catch (error) {
      setNote(t('保存失败：') + String((error as Error).message));
    } finally {
      setBusy(false);
    }
  };

  const switchAlternative = async (index: number) => {
    const message = rows[index];
    const alts = message?.alternatives ?? [];
    if (busy || !message || !alts.length) return;
    const next = [...rows];
    const current:ReplyVariant = {role:'assistant',content:message.content,name:message.name,status:message.status};
    next[index] = { ...alts[0]!, name:alts[0]!.name??message.name, alternatives: [...alts.slice(1), current] };
    await updateMessages(next);
  };

  const branch = async (index: number) => {
    if (!(await confirmSwitch())) return;
    setBusy(true);
    try {
      const next = rows.slice(0, index + 1);
      const value = await request<Conversation>(path + '/conversations', {
        method: 'POST',
        body: JSON.stringify({ messages: next, settings:{...settings,parentId:conversation.conversationId} }),
      });
      setConversation(value);
      setSuggestedMemory('');
      setInspection(undefined);
      setSettings({...defaults,...value.settings});
      setRows(next);
      setDraft('');
      await refresh();
      setNote(t('会话已保存。'));
    } catch (error) {
      setNote(t('保存失败：') + String((error as Error).message));
    } finally {
      setBusy(false);
    }
  };

  const removeCurrentConversation = async () => {
    if (!conversation.conversationId) return;
    const ok = await confirmAction({
      title: t('删除当前已保存的会话？'),
      confirmLabel: t('删除'),
      danger: true,
    });
    if (!ok) return;
    setBusy(true);
    try {
      await api.tavernDeleteConversation(assetId, conversation.conversationId);
      setSuggestedMemory('');
      setInspection(undefined);
      setConversation({});
      setRows(options[greeting] ? [{ role: 'assistant', content: options[greeting]! }] : []);
      await refresh();
      showToast(t('会话已删除'), 'success');
    } catch (err) {
      setNote(String((err as Error).message));
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    const handler = (event: BeforeUnloadEvent) => {
      if (hasUnsaved() || busy) event.preventDefault();
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  });

  const connectionPanel = useRef<HTMLDetailsElement>(null);
  const messages = useRef<HTMLOListElement>(null);
  const followTail = useRef(true);
  const [toolsOpen, setToolsOpen] = useState(false);
  useEffect(() => {
    if (followTail.current && messages.current) messages.current.scrollTop = messages.current.scrollHeight;
  }, [rows]);

  return (
    <section className="section-block tavern-conversation">
      <header className="tavern-chat-header">
        <div>
          <h3>{name || t('会话')}</h3>
          <span role="status">{busy ? t('正在生成') : connection?.usable ? t('可以开始对话') : t('尚未配置服务')}</span>
        </div>
        <button className="chip" aria-expanded={toolsOpen} onClick={() => setToolsOpen((value) => !value)}>
          {t(toolsOpen ? '关闭会话设置' : '会话设置')}
        </button>
      </header>

      <ol
        ref={messages}
        className="tavern-messages"
        aria-live="polite"
        onScroll={() => {
          const node = messages.current;
          if (node) followTail.current = node.scrollHeight - node.clientHeight - node.scrollTop < 64;
        }}
      >
        {rows.map((message, index) => (
          <li key={index} data-role={message.role}>
            <div className="tavern-identity">
              {message.role === 'assistant' && avatar ? (
                <img src={avatar} alt="" />
              ) : (
                <span aria-hidden="true">{(message.name || (message.role === 'user' ? settings.userName : name || t('角色'))).slice(0, 1)}</span>
              )}
              <strong>{message.name || (message.role === 'user' ? settings.userName : name || t('角色'))}</strong>
              {message.alternatives?.length ? (
                <small className="chapter-state">({message.alternatives.length + 1})</small>
              ) : null}
            </div>
            {editing === index ? (
              <form
                onSubmit={(event) => {
                  event.preventDefault();
                  if (editText.trim()) {
                    setEditing(undefined);
                    void updateMessages(rows.map((row, i) => (i === index ? { ...row, content: editText } : row)));
                  }
                }}
              >
                <textarea
                  style={textAreaStyle}
                  value={editText}
                  onChange={(event) => setEditText(event.target.value)}
                  aria-label={t('编辑消息')}
                  maxLength={100000}
                />
                <div className="action-row">
                  <button type="submit" disabled={busy || !editText.trim()}>
                    {t('保存')}
                  </button>
                  <button type="button" onClick={() => setEditing(undefined)}>
                    {t('取消')}
                  </button>
                </div>
              </form>
            ) : (
              <>
                <div style={{ marginTop: 6 }}>{renderSafeRpMessage(replace(message.content))}</div>
                {message.status === 'length' ? (
                  <small className="chapter-state">{t('回复达到输出上限，可继续生成。')}</small>
                ) : null}
              </>
            )}
            <details>
              <summary>{t('消息操作')}</summary>
              <div className="action-row">
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => {
                    setEditing(index);
                    setEditText(message.content);
                  }}
                >
                  {t('编辑消息')}
                </button>
                <button type="button" disabled={busy} onClick={() => void branch(index)}>
                  {t('从此处分支')}
                </button>
                <button type="button" disabled={busy || !message.alternatives?.length} onClick={() => void switchAlternative(index)}>
                  {t('切换候选回复')}
                </button>
                <button
                  type="button"
                  className="chip danger-action"
                  disabled={busy}
                  onClick={async () => {
                    if (await confirmAction({ title: t('将删除此条及后续消息，继续？'), danger: true })) {
                      void updateMessages(rows.slice(0, index));
                    }
                  }}
                >
                  {t('删除')}
                </button>
              </div>
            </details>
          </li>
        ))}
      </ol>

      <div className="tavern-composer">
        <label className="tavern-message-field">
          <span className="sr-only">{t('消息')}</span>
          <textarea
            rows={2}
            placeholder={t('输入消息…')}
            aria-label={t('消息')}
            onKeyDown={(event) => {
              if (
                (event.ctrlKey || event.metaKey) &&
                event.key === 'Enter' &&
                !event.nativeEvent.isComposing &&
                !busy &&
                connection?.usable &&
                draft.trim()
              ) {
                event.preventDefault();
                followTail.current = true;
                void start();
              }
            }}
            style={textAreaStyle}
            disabled={busy}
            value={draft}
            maxLength={100000}
            onChange={(e) => setDraft(e.target.value)}
          />
        </label>
        <div className="action-row">
          <button
            className="primary-link"
            disabled={busy || !draft.trim() || !connection?.usable}
            onClick={() => {
              followTail.current = true;
              void start();
            }}
          >
            {t('发送')}
          </button>
          <button
            className="chip"
            disabled={busy || rows.at(-1)?.role !== 'assistant' || !connection?.usable}
            onClick={() => void start(true)}
          >
            {t('续写')}
          </button>
          <button
            className="chip"
            disabled={busy || rows.at(-1)?.role !== 'assistant' || rows.length < 2 || (rows.at(-1)?.alternatives?.length??0)>=maxReplyVariants || !connection?.usable}
            onClick={() => void start(false, true)}
          >
            {t('重新生成')}{(rows.at(-1)?.alternatives?.length??0)>=maxReplyVariants?' (8/8)':''}
          </button>
          {busy ? (
            <button className="chip" onClick={() => abort.current?.abort()}>
              {t('取消生成')}
            </button>
          ) : null}
        </div>
        {note ? <p role="status">{note}</p> : null}
      </div>

      {!connection?.usable ? (
        <div className="action-row tavern-connection-hint">
          <p>{t('开始对话需要自行配置 AI 服务。')}</p>
          <button
            className="chip"
            onClick={() => {
              setToolsOpen(true);
              if (connectionPanel.current) {
                connectionPanel.current.open = true;
                connectionPanel.current.querySelector<HTMLElement>('input,select,button')?.focus();
              }
            }}
          >
            {t('AI连接设置')}
          </button>
        </div>
      ) : null}

      <div className="tavern-tools" hidden={!toolsOpen}>
        <div className="action-row">
          <button
            className="chip"
            disabled={busy}
            onClick={() =>
              void save()
                .then(() => setNote(t('会话已保存。')))
                .catch((error) => setNote(String(error.message)))
            }
          >
            {t('保存会话')}
          </button>
          {conversation.conversationId ? (
            <button type="button" className="chip danger-action" disabled={busy} onClick={() => void removeCurrentConversation()}>
              {t('删除会话')}
            </button>
          ) : null}
        </div>

        <details ref={connectionPanel} className="detail-secondary">
          <summary>{t('AI连接设置')}</summary>
          <p>
            {t(
              '支持 OpenAI 兼容接口与 Anthropic Messages 接口。本机模式支持无密钥的 HTTP 回环服务；密钥加密保存在当前实例。',
            )}
          </p>
          <TavernConnectionEditor
            settings={settings}
            disabled={busy}
            onSelect={(value) => {
              setConnection(value);
              if (value) {
                setSettings((prior) => ({
                  ...prior,
                  temperature: value.temperature,
                  maxTokens: value.maxTokens,
                  contextTokens: value.contextTokens,
                }));
              }
            }}
          />
          <label className="form-row" style={field}>
            {t('上下文长度（Token） ')}
            <input
              type="number"
              min="1024"
              max="2000000"
              disabled={busy}
              value={settings.contextTokens}
              onChange={(e) => change('contextTokens', Number(e.target.value))}
            />
          </label>
          <label className="form-row" style={field}>
            {t('单次回复上限（Token） ')}
            <input
              type="number"
              min="1"
              max="32768"
              disabled={busy}
              value={settings.maxTokens}
              onChange={(e) => change('maxTokens', Number(e.target.value))}
            />
          </label>
          <label className="form-row" style={field}>
            {t('随机程度（Temperature） ')}
            <input
              type="number"
              min="0"
              max="2"
              step=".1"
              disabled={busy}
              value={settings.temperature}
              onChange={(e) => change('temperature', Number(e.target.value))}
            />
          </label>
        </details>

        <details className="detail-secondary">
          <summary>{t('角色与世界书上下文')}</summary>
          <label className="form-row">{t('名称')}<input value={settings.title??''} onChange={e=>change('title',e.target.value)}/></label>
          <label className="form-row">{t('选择发言角色')}<select disabled={busy} value={settings.speakerId??''} onChange={e=>{const id=e.target.value;setSettings(old=>({...old,speakerId:id,castIds:[...new Set([...(old.castIds??[]),id].filter(Boolean))]}));}}><option value="">{name}</option>{characters.map(row=><option value={row.assetId} key={row.assetId}>{row.name}</option>)}</select></label>
          <label className="form-row">{t('标签')}<input maxLength={1024} value={settings.tags??''} onChange={e=>change('tags',e.target.value)}/></label>
          <label className="form-row">{t('会话笔记')}<textarea maxLength={16000} value={settings.notes??''} onChange={e=>change('notes',e.target.value)}/></label>
          <label className="form-row">{t('会话记忆')}<textarea value={settings.memory??''} onChange={e=>change('memory',e.target.value)}/></label>
          <button className="chip" disabled={busy||!connection?.usable||!rows.length} onClick={async()=>{
            setBusy(true);
            const controller=new AbortController();abort.current=controller;
            try {const result=await request<{text:string}>('/api/v1/tavern/revise',{method:'POST',signal:controller.signal,body:JSON.stringify({connectionId:connection?.connectionId,summary:true,text:[settings.memory,...rows.map(m=>(m.name??m.role)+': '+m.content)].filter(Boolean).join('\n')})});setSuggestedMemory(result.text);}
            catch(e){if(!controller.signal.aborted)setNote(String((e as Error).message));}finally{setBusy(false);}
          }}>{t('生成会话摘要')}</button>
          {suggestedMemory && <div><textarea aria-label={t('生成预览')} value={suggestedMemory} onChange={e=>setSuggestedMemory(e.target.value)}/><button className="chip" onClick={()=>{change('memory',suggestedMemory);setSuggestedMemory('');}}>{t('应用')}</button></div>}
          {inspection && <details><summary>{t('本轮提示词')}</summary>{inspection.map((m,i)=><section key={i}><strong>{m.role}</strong><p style={{whiteSpace:'pre-wrap'}}>{m.content}</p></section>)}</details>}
          <label className="form-row" style={field}>
            {t('你的名称 ')}
            <input
              disabled={busy}
              value={settings.userName}
              maxLength={256}
              onChange={(e) => change('userName', e.target.value)}
            />
          </label>
          <label className="form-row" style={field}>
            {t('你的角色设定 ')}
            <textarea
              style={textAreaStyle}
              disabled={busy}
              value={settings.persona}
              maxLength={16000}
              onChange={(e) => change('persona', e.target.value)}
            />
          </label>
          {books.map((book) => (
            <label key={book.assetId} style={{ display: 'flex', alignItems: 'center', gap: 8, minHeight: 44 }}>
              <input
                type="checkbox"
                disabled={busy}
                checked={settings.worldbookIds.includes(book.assetId)}
                onChange={(e) =>
                  change(
                    'worldbookIds',
                    e.target.checked
                      ? [...settings.worldbookIds, book.assetId]
                      : settings.worldbookIds.filter((id) => id !== book.assetId),
                  )
                }
              />
              {book.name}
            </label>
          ))}
        </details>

        <div className="action-row">
          <button
            className="chip"
            disabled={busy}
            onClick={async () => {
              if (!(await confirmSwitch())) return;
              setSuggestedMemory('');
      setInspection(undefined);
              setConversation({});
              setRows(options[greeting] ? [{ role: 'assistant', content: options[greeting]! }] : []);
              setDraft('');
              setNote('');
            }}
          >
            {t('新会话')}
          </button>
          {options.length > 1 ? (
            <label className="form-row" style={field}>
              {t('开场白 ')}
              <select
                disabled={busy || !!conversation.conversationId}
                value={greeting}
                onChange={(e) => {
                  const index = Number(e.target.value);
                  setGreeting(index);
                  setRows([{ role: 'assistant', content: options[index]! }]);
                }}
              >
                {options.map((_, index) => (
                  <option key={index} value={index}>
                    {t('开场白 ')}
                    {index + 1}
                  </option>
                ))}
              </select>
            </label>
          ) : null}
        </div>

        {history.length>1 && <label className="form-row">{t('搜索')}<input type="search" value={sessionQuery} onChange={e=>setSessionQuery(e.target.value)}/></label>}
        {history.length ? (
          <label className="form-row" style={field}>
            {t('已保存会话 ')}
            <select
              disabled={busy}
              value={conversation.conversationId ?? ''}
              onChange={async (e) => {
                const item = history.find((row) => row.conversationId === e.target.value);
                if (item && (await confirmSwitch())) {
                  setSuggestedMemory('');
      setInspection(undefined);
                  followTail.current = true;
                  setConversation(item);
                  setRows(item.messages ?? []);
                  setSettings({ ...defaults, ...item.settings });
                }
              }}
            >
              <option value="">{t('选择会话')}</option>
              {ordered.map(({item,depth}, index) => (
                <option key={item.conversationId} value={item.conversationId}>
                  {depth?'　'.repeat(Math.min(depth-1,4))+'↳ ':''}{item.settings?.title || (t('会话 ')+(index+1))}
                </option>
              ))}
            </select>
          </label>
        ) : null}

        <TavernLoreTranslations
          assetId={assetId}
          bookIds={settings.worldbookIds}
          useTranslated={useTranslated}
          onUseTranslated={setUseTranslated}
        />
      </div>
    </section>
  );
}
