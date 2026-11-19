import { useState, useRef, useEffect, useMemo } from 'react';
import { confirmAction } from '@hentai-park/design-system';
import { api, request } from './api.js';
import { t, useLanguage } from './i18n.js';
import { TavernConnectionEditor, type TavernConnection } from './tavern-connections.js';
import { sharedStateStore, useSharedState } from './native.js';
import { reviewProposal } from './tavern-proposal.js';
import { readDraft, writeDraft } from './tavern-drafts.js';
type Row = Record<string, unknown>;
const errorText = (error: unknown) => (error instanceof Error ? error.message : t('请求未能完成。'));
function ListField({
  value,
  onChange,
  paragraphs = false,
}: {
  value: unknown;
  onChange: (items: string[]) => void;
  paragraphs?: boolean;
}) {
  const normalized = JSON.stringify(Array.isArray(value) ? value : []);
  const format = () =>
    ((Array.isArray(value) ? value : []) as string[]).join(paragraphs ? '\n\n' : ', ');
  const [typed, setTyped] = useState(format);
  const last = useRef(normalized);
  useEffect(() => {
    if (last.current !== normalized) {
      last.current = normalized;
      setTyped(format());
    }
  }, [normalized]);
  function edit(text: string) {
    const items = text
      .split(paragraphs ? /\n\s*\n/ : /[,，]/)
      .map((item) => item.trim())
      .filter(Boolean);
    last.current = JSON.stringify(items);
    setTyped(text);
    onChange(items);
  }
  return paragraphs ? (
    <textarea value={typed} onChange={(e) => edit(e.target.value)} />
  ) : (
    <input value={typed} onChange={(e) => edit(e.target.value)} />
  );
}
export function TavernAssetEditor({ asset, onSaved }: { asset: Row; onSaved: (asset: Row) => void }) {
  const source = (asset.data ?? {}) as Row;
  const [draft, setDraft] = useState<Row>(() => JSON.parse(JSON.stringify(source)) as Row);
  const [history, setHistory] = useState<{ revision: string; date: string; data: Row }[]>();
  async function loadHistory() {
    try {
      const result = await request<{ items: { revision: string; date: string; data: Row }[] }>(
        '/api/v1/tavern/assets/' + encodeURIComponent(String(asset.assetId)) + '/revisions',
      );
      setHistory(result.items);
    } catch (error) {
      setMessage(errorText(error));
    }
  }
  const [saving, setSaving] = useState(false);
  const [recovered, setRecovered] = useState(false);
  const [message, setMessage] = useState('');
  const [portrait, setPortrait] = useState<string>();
  const draftKey = JSON.stringify([asset.assetId ?? asset.kind, asset.version ?? 0]);
  const initial = useRef(draft);
  const latest = useRef({ draft, portrait });
  latest.current = { draft, portrait };
  const { incognito } = useSharedState();
  const privateSession = useRef(incognito);
  if (incognito) privateSession.current = true;
  const committed = useRef(false);
  useEffect(() => {
    if (privateSession.current) return;
    let live = true;
    void readDraft(draftKey)
      .then((saved) => {
        if (
          live &&
          !sharedStateStore.getSnapshot().incognito &&
          saved &&
          latest.current.draft === initial.current &&
          !latest.current.portrait
        ) {
          setDraft(saved.data);
          setPortrait(saved.portrait);
          setRecovered(true);
        }
      })
      .catch(() => {
        if (live) setMessage(t('草稿保存不可用'));
      });
    return () => {
      live = false;
    };
  }, [draftKey, incognito]);
  useEffect(() => {
    if (privateSession.current || committed.current || (draft === initial.current && !portrait)) return;
    void writeDraft(draftKey, { data: draft, portrait }).catch(() => setMessage(t('草稿保存不可用')));
  }, [draftKey, draft, portrait, incognito]);
  async function pickPortrait(file: File) {
    if (file.size > 12 * 1024 * 1024) {
      setMessage(t('文件不能超过12MiB。'));
      return;
    }
    setSaving(true);
    const reader = new FileReader();
    reader.onloadend = () => setSaving(false);
    reader.onload = () => {
      setPortrait(String(reader.result).split(',')[1]);
      setMessage('');
    };
    reader.onerror = () => setMessage(t('请求未能完成。'));
    reader.readAsDataURL(file);
  }
  const card = (draft.data ?? draft) as Row;
  const entriesValue =
    asset.kind === 'lorebook'
      ? ((draft.entries ?? card.entries) as unknown)
      : card.character_book && typeof card.character_book === 'object'
        ? (card.character_book as Row).entries
        : undefined;
  const entries = Array.isArray(entriesValue)
    ? (entriesValue as Row[])
    : entriesValue && typeof entriesValue === 'object'
      ? (Object.values(entriesValue as Row) as Row[])
      : [];
  const [sample, setSample] = useState('');
  type Preview = { items: string[]; trace: { name: string; reason: string; key?: string }[] };
  const [hits, setHits] = useState<Preview>();
  const previewEpoch = useRef(0);
  useEffect(() => {
    previewEpoch.current++;
    setHits(undefined);
  }, [draft, sample]);
  const reasons: Record<string, string> = {
    keyword: t('关键词'),
    constant: t('常驻'),
    miss: t('关键词未命中'),
    disabled: t('已停用'),
    empty: t('正文为空'),
    secondary: t('次关键词条件未满足'),
    unsupported: t('规则未支持'),
    budget: t('超出词条预算'),
    probability: t('概率未通过'),
  };
  const [brief, setBrief] = useState('');
  const [connection, setConnection] = useState<TavernConnection>();
  const fields: Record<string, string> = {
    name: t('名称'),
    description: t('描述'),
    personality: t('性格'),
    scenario: t('场景'),
    system_prompt: t('系统提示词'),
    first_mes: t('开场白'),
    mes_example: t('示例对话'),
  };
  const [field, setAiField] = useState('');
  const [revision, setRevision] = useState<string>();
  const [proposal, setProposal] = useState<Row>();
  const [omitted, setOmitted] = useState(new Set<string>());
  const review = useMemo(
    () => (proposal ? reviewProposal(draft, proposal, asset.kind === 'character', omitted) : undefined),
    [draft, proposal, asset.kind, omitted],
  );
  const active = useRef<AbortController | undefined>(undefined);
  const locale = useLanguage();
  useEffect(() => () => active.current?.abort(), []);
  const generate = async (outline = false) => {
    if (!connection || !brief.trim() || active.current) return;
    const controller = new AbortController();
    active.current = controller;
    setSaving(true);
    try {
      if (field || outline) {
        const value = await request<{ text: string }>('/api/v1/tavern/revise', {
          method: 'POST',
          signal: controller.signal,
          body: JSON.stringify({
            connectionId: connection.connectionId,
            text: outline ? brief : (revision ?? String(card[field] ?? '')),
            outline,
            brief: outline ? '' : brief,
            locale,
          }),
        });
        if (outline) setBrief(value.text);
        else setRevision(value.text);
      } else {
        const value = await request<{ data: Row }>('/api/v1/tavern/generate', {
          method: 'POST',
          signal: controller.signal,
          body: JSON.stringify({
            connectionId: connection.connectionId,
            kind: asset.kind,
            locale,
            prompt: brief + '\n' + JSON.stringify(review?.result ?? draft),
          }),
        });
        setOmitted(new Set());
        setProposal(value.data);
      }
      setMessage('');
    } catch (error) {
      if (!controller.signal.aborted) setMessage(errorText(error));
    } finally {
      active.current = undefined;
      setSaving(false);
    }
  };
  async function importEntries(file: File) {
    try {
      if (file.size > 12 * 1024 * 1024) throw Error(t('文件不能超过12MiB。'));
      const imported = JSON.parse(await file.text()) as Row;
      const source = (imported.entries ?? (imported.data as Row)?.entries) as unknown;
      if (!source || typeof source !== 'object')
        throw Error(t('无法识别此JSON文件，请选择角色卡或世界书文件。'));
      const additions = Object.values(source) as Row[];
      if (!additions.length || additions.some((row) => !row || typeof row.content !== 'string'))
        throw Error(t('无法识别此JSON文件，请选择角色卡或世界书文件。'));
      setDraft((prior) => {
        const next = structuredClone(prior),
          card = (next.data ?? next) as Row;
        const book =
          asset.kind === 'lorebook'
            ? card
            : ((card.character_book ??= { entries: [], extensions: {} }) as Row);
        const target = book.entries as Record<string, Row> | Row[];
        const used = new Set(
          Object.values(target)
            .flatMap((row) => [row.id, row.uid])
            .filter((id) => id !== undefined)
            .map(String),
        );
        let id = 0;
        for (const addition of additions) {
          const row = { ...addition };
          for (const key of ['id', 'uid']) {
            if (row[key] === undefined) continue;
            if (used.has(String(row[key]))) {
              while (used.has(String(id))) id++;
              row[key] = id;
            }
            used.add(String(row[key]));
          }
          if (Array.isArray(target)) target.push(row);
          else {
            while (String(id) in target) id++;
            target[String(id++)] = row;
          }
        }
        return next;
      });
      setHits(undefined);
      setMessage('');
    } catch (error) {
      setMessage(errorText(error));
    }
  }
  const setField = (key: string, value: unknown) =>
    setDraft((prior) => {
      const next = structuredClone(prior);
      const target = (next.data ?? next) as Row;
      target[key] = value;
      return next;
    });
  const save = async (copy = false) => {
    setSaving(true);
    try {
      const payload = {
        kind: asset.kind,
        format: 'json',
        data: draft,
        version: asset.version,
        portrait,
      };
      const value = asset.assetId
        ? await api.tavernUpdateAsset(String(asset.assetId), { ...payload, copy })
        : await request<Row>('/api/v1/tavern/import', { method: 'POST', body: JSON.stringify(payload) });
      committed.current = true;
      if (!privateSession.current) await writeDraft(draftKey).catch(() => {});
      onSaved(value);
      setMessage(t('已保存'));
    } catch (error) {
      setMessage(errorText(error));
    } finally {
      setSaving(false);
    }
  };
  const updateEntry = (index: number, key: string, value: unknown) =>
    setDraft((prior) => {
      const next = structuredClone(prior);
      const target = (next.data ?? next) as Row;
      const book = asset.kind === 'lorebook' ? target : (target.character_book as Row);
      const container = book.entries as Row[] | Record<string, Row>;
      const id = Object.keys(container)[index]!;
      const rows = container as Record<string, Row>;
      const row = rows[id]!;
      if (key === 'delete') {
        if (Array.isArray(container)) container.splice(index, 1);
        else delete rows[id];
      } else if (key === 'copy') {
        const copy = structuredClone(row);
        const ids = new Set(
          Object.values(rows)
            .flatMap((item) => [item.uid, item.id])
            .map(String)
            .concat(Object.keys(rows)),
        );
        let newId = 0;
        while (ids.has(String(newId))) newId++;
        if ('uid' in copy) copy.uid = newId;
        if ('id' in copy) copy.id = newId;
        if (Array.isArray(container)) container.splice(index + 1, 0, copy);
        else rows[String(newId)] = copy;
      } else if (key === 'enabled') {
        row.enabled = value;
        if ('disable' in row) row.disable = !value;
      } else {
        row[key] = value;
        const aliases: Record<string, string[]> = {
          keys: ['key'],
          secondary_keys: ['keysecondary', 'secondaryKeys'],
          insertion_order: ['order'],
        };
        for (const alias of aliases[key] ?? []) if (alias in row) row[alias] = value;
      }
      return next;
    });
  return (
    <section className="detail-secondary tavern-editor">
      <h4>{asset.kind === 'lorebook' ? t('编辑世界书') : t('编辑角色卡')}</h4>
      {recovered && (
        <div className="action-row" role="status">
          {t('已恢复编辑草稿')}
          <button
            className="chip"
            disabled={saving}
            onClick={async () => {
              if (!(await confirmAction({ title: t('丢弃编辑草稿？'), danger: true }))) return;
              try {
                await writeDraft(draftKey);
                setDraft(initial.current);
                setPortrait(undefined);
                setProposal(undefined);
                setRevision(undefined);
                setRecovered(false);
                setMessage('');
              } catch (error) {
                setMessage(errorText(error));
              }
            }}
          >
            {t('删除')}
          </button>
        </div>
      )}
      {!!asset.assetId && (
        <details
          onToggle={(e) => {
            if (e.currentTarget.open && !history) void loadHistory();
          }}
        >
          <summary>{t('文本版本历史')}</summary>
          {history?.length === 0 && <p>{t('尚无记录')}</p>}
          {history?.map((item) => {
            const before = (item.data.data ?? item.data) as Row;
            const changes = Object.fromEntries(
              [...new Set([...Object.keys(card), ...Object.keys(before)])]
                .filter((key) => JSON.stringify(card[key]) !== JSON.stringify(before[key]))
                .map((key) => [key, before[key] ?? null]),
            );
            return (
              <details key={item.revision}>
                <summary>{new Date(item.date).toLocaleString(locale)}</summary>
                <pre style={{ whiteSpace: 'pre-wrap' }}>{JSON.stringify(changes, null, 2)}</pre>
                <button
                  className="chip"
                  onClick={() => {
                    setDraft(structuredClone(item.data));
                    setProposal(undefined);
                    setRevision(undefined);
                  }}
                >
                  {t('应用')}
                </button>
              </details>
            );
          })}
        </details>
      )}
      <details>
        <summary>{t('AI 创作')}</summary>
        <TavernConnectionEditor
          settings={{ maxTokens: 4096, contextTokens: 32768, temperature: 0.7 }}
          onSelect={setConnection}
          disabled={saving}
        />
        {asset.kind === 'lorebook' && (
          <button
            type="button"
            className="chip"
            disabled={saving || !brief.trim() || !connection?.usable}
            onClick={() => void generate(true)}
          >
            {t('生成世界书大纲')}
          </button>
        )}
        {asset.kind === 'character' && (
          <label className="form-row">
            {t('内容')}
            <select
              disabled={saving}
              value={field}
              onChange={(e) => {
                setAiField(e.target.value);
                setRevision(undefined);
                setProposal(undefined);
              }}
            >
              <option value="">{t('角色卡')}</option>
              {Object.entries(fields).map(([key, label]) => (
                <option value={key} key={key}>
                  {label}
                </option>
              ))}
            </select>
          </label>
        )}
        <label className="form-row">
          {t('描述你想创作的内容')}
          <textarea value={brief} onChange={(e) => setBrief(e.target.value)} rows={3} />
        </label>
        <button
          className="chip"
          disabled={saving || !brief.trim() || !connection?.usable}
          onClick={() => void generate()}
        >
          {t('生成草稿')}
        </button>
        {active.current && (
          <button className="chip" onClick={() => active.current?.abort()}>
            {t('取消')}
          </button>
        )}
        {revision !== undefined && (
          <div>
            <label className="form-row">
              {t('生成预览')}
              <textarea rows={5} value={revision} onChange={(e) => setRevision(e.target.value)} />
            </label>
            <button
              className="chip"
              disabled={saving}
              onClick={() => {
                setField(field, revision);
                setRevision(undefined);
                setBrief('');
              }}
            >
              {t('应用')}
            </button>
          </div>
        )}
        {proposal && (
          <details open>
            <summary>{t('生成预览')}</summary>
            {review?.changes.map((change) => (
              <div key={change.key}>
                <label>
                  <input
                    type="checkbox"
                    checked={!omitted.has(change.key)}
                    onChange={(e) => {
                      const next = new Set(omitted);
                      if (e.target.checked) next.delete(change.key);
                      else next.add(change.key);
                      setOmitted(next);
                    }}
                  />
                  {fields[change.label] ?? change.label}
                </label>
                {!!change.sharedKeys?.length && (
                  <small>
                    {t('共享关键词')} · {change.sharedKeys.join(', ')}
                  </small>
                )}
                <details>
                  <summary>{t('生成预览')}</summary>
                  <pre style={{ whiteSpace: 'pre-wrap' }}>{JSON.stringify(change.value, null, 2)}</pre>
                </details>
              </div>
            ))}
            <button
              className="chip"
              disabled={saving}
              onClick={() => {
                setDraft(review!.result);
                setProposal(undefined);
                setBrief('');
              }}
            >
              {t('应用')}
            </button>
          </details>
        )}
      </details>
      {asset.kind === 'lorebook' && (
        <label className="form-row">
          {t('名称')}
          <input value={String(card.name ?? '')} onChange={(e) => setField('name', e.target.value)} />
        </label>
      )}
      {asset.kind !== 'lorebook' ? (
        <>
          <label className="form-row">
            {t('头像')} · PNG
            <input
              type="file"
              accept="image/png,.png"
              disabled={saving}
              onChange={(e) => {
                const file = e.currentTarget.files?.[0];
                if (file) void pickPortrait(file);
              }}
            />
          </label>
          {(portrait || typeof asset.originalPng === 'string') && (
            <img
              width={80}
              height={80}
              style={{ objectFit: 'cover' }}
              alt={t('头像')}
              src={'data:image/png;base64,' + (portrait ?? asset.originalPng)}
            />
          )}
          {(
            [
              'name',
              'description',
              'personality',
              'scenario',
              'system_prompt',
              'first_mes',
              'mes_example',
            ] as const
          ).map((key) => (
            <label className="form-row" key={key}>
              {
                {
                  name: t('名称'),
                  description: t('描述'),
                  personality: t('性格'),
                  scenario: t('场景'),
                  system_prompt: t('系统提示词'),
                  first_mes: t('开场白'),
                  mes_example: t('示例对话'),
                }[key]
              }
              <textarea
                value={String(card[key] ?? '')}
                onChange={(event) => setField(key, event.target.value)}
                rows={key === 'name' ? 1 : 4}
              />
            </label>
          ))}
          <label className="form-row">
            {t('作者')}
            <input
              value={String(card.creator ?? '')}
              onChange={(e) => setField('creator', e.target.value)}
            />
          </label>
          <label className="form-row">
            {t('标签')}
            <ListField value={card.tags} onChange={(items) => setField('tags', items)} />
          </label>
          <label className="form-row">
            {t('其他开场白')}
            <ListField
              paragraphs
              value={card.alternate_greetings}
              onChange={(items) => setField('alternate_greetings', items)}
            />
          </label>
        </>
      ) : null}
      <h5>
        {t('世界书条目')} ({entries.length})
      </h5>
      <button
        className="chip"
        onClick={() =>
          setDraft((prior) => {
            const next = structuredClone(prior),
              target = (next.data ?? next) as Row;
            const book =
              asset.kind === 'lorebook'
                ? target
                : ((target.character_book ??= { extensions: {}, entries: [] }) as Row);
            const entry = {
              keys: [],
              comment: '',
              content: '',
              enabled: true,
              extensions: {},
              insertion_order: 100,
            };
            if (Array.isArray(book.entries)) book.entries.push(entry);
            else (book.entries as Row)[crypto.randomUUID()] = entry;
            return next;
          })
        }
      >
        {t('新增')}
      </button>
      <label className="form-row">
        {t('导入世界书词条')}
        <input
          type="file"
          accept=".json,application/json"
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) void importEntries(file);
            e.target.value = '';
          }}
        />
      </label>
      {!!entries.length && (
        <details>
          <summary>{t('测试触发')}</summary>
          <label className="form-row">
            {t('消息')}
            <input
              value={sample}
              onChange={(e) => {
                setSample(e.target.value);
                setHits(undefined);
              }}
            />
          </label>
          <button
            className="chip"
            onClick={() => {
              const epoch = ++previewEpoch.current;
              void request<Preview>('/api/v1/tavern/preview-lore', {
                method: 'POST',
                body: JSON.stringify({
                  book: asset.kind === 'lorebook' ? card : card.character_book,
                  text: sample,
                  locale,
                }),
              })
                .then((value) => {
                  if (epoch === previewEpoch.current) setHits(value);
                })
                .catch((e) => setMessage(errorText(e)));
            }}
          >
            {t('测试触发')}
          </button>
          {hits && (
            <p role="status">
              {t('匹配世界书条目：')}
              {hits.items.length}
              {hits.trace.map((entry, i) => (
                <span style={{ display: 'block' }} key={i}>
                  {[entry.name, reasons[entry.reason], entry.key].filter(Boolean).join(' · ')}
                </span>
              ))}
            </p>
          )}
        </details>
      )}
      {entries.map((entry, index) => (
        <div className="tavern-entry-editor" key={String(entry.uid ?? entry.id ?? index)}>
          <label className="form-row">
            {t('名称')}
            <input
              value={String(entry.comment ?? entry.name ?? '')}
              onChange={(event) => updateEntry(index, 'comment', event.target.value)}
            />
          </label>
          <label className="form-row">
            {t('关键词')}
            <ListField
              value={entry.keys ?? entry.key}
              onChange={(items) => updateEntry(index, 'keys', items)}
            />
          </label>
          <label className="form-row">
            {t('内容')}
            <textarea
              value={String(entry.content ?? '')}
              onChange={(event) => updateEntry(index, 'content', event.target.value)}
              rows={5}
            />
          </label>
          <details>
            <summary>{t('触发规则')}</summary>
            <label>
              <input
                type="checkbox"
                checked={entry.enabled !== false && entry.disable !== true}
                onChange={(e) => updateEntry(index, 'enabled', e.target.checked)}
              />
              {t('启用')}
            </label>
            <label>
              <input
                type="checkbox"
                checked={entry.selective === true}
                onChange={(e) => updateEntry(index, 'selective', e.target.checked)}
              />
              {t('次关键词')}
            </label>
            {entry.selective === true && (
              <label className="form-row">
                {t('次关键词')}
                <ListField
                  value={entry.secondary_keys ?? entry.keysecondary ?? entry.secondaryKeys}
                  onChange={(items) => updateEntry(index, 'secondary_keys', items)}
                />
              </label>
            )}
            <label>
              <input
                type="checkbox"
                checked={entry.constant === true}
                onChange={(e) => updateEntry(index, 'constant', e.target.checked)}
              />
              {t('常驻')}
            </label>
            {Object.entries({
              priority: t('优先级'),
              insertion_order: t('插入顺序'),
              probability: t('概率'),
              scanDepth: t('扫描深度'),
            }).map(([key, label]) => (
              <label className="form-row" key={key}>
                {label}
                <input
                  type="number"
                  value={String(entry[key] ?? '')}
                  onChange={(e) =>
                    updateEntry(index, key, e.target.value === '' ? undefined : e.target.valueAsNumber)
                  }
                />
              </label>
            ))}
            <label>
              <input
                type="checkbox"
                checked={entry.useProbability === true}
                onChange={(e) => updateEntry(index, 'useProbability', e.target.checked)}
              />
              {t('概率')}
            </label>
          </details>
          <div className="action-row">
            <button className="chip" onClick={() => updateEntry(index, 'copy', true)}>
              {t('复制')}
            </button>
            <button className="chip" onClick={() => updateEntry(index, 'delete', true)}>
              {t('删除')}
            </button>
          </div>
        </div>
      ))}
      <div className="action-row">
        <button className="primary-link" disabled={saving} onClick={() => void save()}>
          {saving ? t('正在保存') : t('保存')}
        </button>
        {Boolean(asset.assetId) && (
          <button className="chip" disabled={saving} onClick={() => void save(true)}>
            {t('另存为副本')}
          </button>
        )}
        {message ? <span role="status">{message}</span> : null}
      </div>
    </section>
  );
}
