import { useEffect, useRef, useState } from 'react';
import { confirmAction } from '@hentai-park/design-system';
import { api, request } from './api.js';
import { t } from './i18n.js';

export type TavernConnection = {
  connectionId: string;
  endpoint: string;
  model: string;
  systemPrompt?: string;
  temperature: number;
  maxTokens: number;
  contextTokens: number;
  hasKey: boolean;
  usable: boolean;
  version: number;
};

const field = { flexDirection: 'column' as const, alignItems: 'stretch', gap: 8, width: '100%', maxWidth: '36rem', minWidth: 0 };

export function TavernConnectionEditor({
  settings,
  disabled = false,
  onSelect,
}: {
  settings: { temperature: number; maxTokens: number; contextTokens: number };
  disabled?: boolean;
  onSelect: (value: TavernConnection | undefined) => void;
}) {
  const [items, setItems] = useState<TavernConnection[]>([]);
  const [selected, setSelected] = useState<TavernConnection>();
  const [endpoint, setEndpoint] = useState('');
  const [model, setModel] = useState('');
  const [systemPrompt, setSystemPrompt] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [clearKey, setClearKey] = useState(false);
  const [availableModels, setAvailableModels] = useState<string[]>([]);
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const callback = useRef(onSelect);
  callback.current = onSelect;

  const choose = (value: TavernConnection | undefined) => {
    setSelected(value);
    setEndpoint(value?.endpoint ?? '');
    setModel(value?.model ?? '');
    setSystemPrompt(value?.systemPrompt ?? '');
    setApiKey('');
    setClearKey(false);
    setAvailableModels([]);
    setDirty(false);
    callback.current(value);
  };

  const load = async () => {
    const result = await request<{ items: TavernConnection[] }>('/api/v1/tavern/connections');
    setItems(result.items);
    return result.items;
  };

  useEffect(() => {
    const c = new AbortController();
    void request<{ items: TavernConnection[] }>('/api/v1/tavern/connections', { signal: c.signal })
      .then((value) => {
        if (!c.signal.aborted) {
          setItems(value.items);
          choose(value.items[0]);
        }
      })
      .catch((error) => {
        if (!c.signal.aborted) setMessage(String(error.message));
      });
    return () => c.abort();
  }, []);

  const changed = () => {
    setDirty(true);
    callback.current(undefined);
  };

  const fetchModels = async () => {
    if (!endpoint.trim()) return;
    setBusy(true);
    setMessage('');
    try {
      const res = await api.tavernListModels({
        connectionId: selected?.connectionId,
        endpoint: endpoint.trim(),
        ...(apiKey ? { apiKey } : {}),
      });
      setAvailableModels(res.items);
      if (res.items.length && !model) {
        setModel(res.items[0]!);
        changed();
      }
      setMessage(res.items.length ? `${t('已拉取模型数量：')}${res.items.length}` : t('服务端未返回模型列表，可手动输入模型名称。'));
    } catch (err) {
      setMessage(String((err as Error).message));
    } finally {
      setBusy(false);
    }
  };

  const save = async () => {
    setBusy(true);
    setMessage('');
    try {
      const value = await request<TavernConnection>('/api/v1/tavern/connections', {
        method: 'POST',
        body: JSON.stringify({
          connectionId: selected?.connectionId,
          version: selected?.version,
          endpoint,
          model,
          systemPrompt,
          apiKey,
          clearKey,
          ...settings,
        }),
      });
      await load();
      choose(value);
      setMessage(t('模型连接已安全保存。'));
    } catch (error) {
      setMessage(t('连接未保存，输入仍保留：') + String((error as Error).message));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section aria-label={t('已保存模型连接')}>
      <label className="form-row" style={field}>
        {t('模型连接 ')}
        <select
          disabled={disabled || busy}
          value={selected?.connectionId ?? ''}
          onChange={(e) => choose(items.find((value) => value.connectionId === e.target.value))}
        >
          <option value="">{t('新连接')}</option>
          {items.map((value) => (
            <option key={value.connectionId} value={value.connectionId}>
              {value.endpoint + ' · ' + value.model}
            </option>
          ))}
        </select>
      </label>
      <label className="form-row" style={field}>
        {t('服务地址 ')}
        <input
          type="url"
          disabled={disabled || busy}
          value={endpoint}
          onChange={(e) => {
            if (e.target.value !== endpoint) {
              setApiKey('');
              setClearKey(false);
            }
            setEndpoint(e.target.value);
            changed();
          }}
          placeholder="https://api.openai.com/v1 / https://api.anthropic.com/v1"
        />
      </label>
      <label className="form-row" style={field}>
        {t('API密钥 ')}
        <input
          type="password"
          autoComplete="off"
          disabled={disabled || busy}
          value={apiKey}
          placeholder={selected?.hasKey && !dirty ? t('已保存；留空保持现有密钥') : t('可选；HTTP本机服务必须留空')}
          onChange={(e) => {
            setApiKey(e.target.value);
            changed();
          }}
        />
      </label>
      {selected?.hasKey ? (
        <label style={{ display: 'flex', alignItems: 'center', gap: 8, minHeight: 44 }}>
          <input
            type="checkbox"
            disabled={disabled || busy}
            checked={clearKey}
            onChange={(e) => {
              setClearKey(e.target.checked);
              changed();
            }}
          />
          {t('清除此连接的密钥')}
        </label>
      ) : null}

      <div className="form-row" style={{ ...field, gap: 8 }}>
        <div className="action-row" style={{ margin: 0, justifyContent: 'space-between' }}>
          <span>{t('模型 ')}</span>
          <button
            type="button"
            className="chip"
            disabled={disabled || busy || !endpoint.trim()}
            onClick={() => void fetchModels()}
          >
            {t('拉取模型列表')}
          </button>
        </div>
        {availableModels.length > 0 ? (
          <select
            disabled={disabled || busy}
            value={model}
            onChange={(e) => {
              setModel(e.target.value);
              changed();
            }}
          >
            {availableModels.map((m) => (
              <option key={m} value={m}>
                {m}
              </option>
            ))}
          </select>
        ) : null}
        <input
          disabled={disabled || busy}
          value={model}
          onChange={(e) => {
            setModel(e.target.value);
            changed();
          }}
          placeholder="gpt-4o / claude-sonnet-4-5"
        />
      </div>

      <label className="form-row" style={field}>
        {t('系统提示词（可选）')}
        <textarea
          rows={3}
          disabled={disabled || busy}
          value={systemPrompt}
          maxLength={8000}
          onChange={(e) => {
            setSystemPrompt(e.target.value);
            changed();
          }}
          placeholder={t('附加在角色设定之前的全局指令…')}
        />
      </label>

      <div className="action-row">
        <button className="chip" disabled={disabled || busy || !endpoint || !model} onClick={() => void save()}>
          {t('保存模型连接')}
        </button>
        {selected ? (
          <button
            className="chip danger-action"
            disabled={disabled || busy}
            onClick={async () => {
              if (!(await confirmAction({ title: t('删除此模型连接和本地密钥？已保存会话会保留。'), danger: true }))) return;
              setBusy(true);
              void request('/api/v1/tavern/connections/' + encodeURIComponent(selected.connectionId), {
                method: 'DELETE',
                body: JSON.stringify({ version: selected.version }),
              })
                .then(async () => choose((await load())[0]))
                .catch((error) => setMessage(String(error.message)))
                .finally(() => setBusy(false));
            }}
          >
            {t('删除模型连接')}
          </button>
        ) : null}
      </div>
      <p>
        {dirty
          ? t('连接有未保存的更改，请保存后发送。')
          : selected?.usable === false
            ? t('此实例未允许本机HTTP模型连接。')
            : selected
              ? t('刷新后可继续使用此连接；密钥不会显示或进入普通备份。')
              : t('先保存一个模型连接，再开始会话。')}
      </p>
      {message ? <p role="status">{message}</p> : null}
    </section>
  );
}
