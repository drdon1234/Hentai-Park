import { useState } from 'react';
import { blockPresets, knownAliasesForRule, validateBlockRule } from '@hentai-park/domain-model';
import { t } from './i18n.js';

const lines = (value: string) => value.split('\n').map((v) => v.trim()).filter(Boolean);

export function BlockPreferences({
  settings,
  onChange,
}: {
  settings: Record<string, unknown>;
  onChange: (patch: Record<string, unknown>) => void;
}) {
  const blockedWords = Array.isArray(settings.blockedWords) ? (settings.blockedWords as string[]) : [];
  const aliases = (settings.blockedTagAliases ?? {}) as Record<string, string[]>;
  const presets = (settings.blockPresets ?? {}) as Record<string, Record<string, unknown>>;
  const authorWorks = (settings.blockedAuthorWorks ?? {}) as Record<string, string[]>;

  const [ruleDraft, setRuleDraft] = useState('');
  const [ruleScope, setRuleScope] = useState<'tag' | 'title' | 'author' | 'regex'>('tag');
  const [ruleError, setRuleError] = useState('');

  const addStructuredRule = () => {
    const clean = ruleDraft.trim();
    if (!clean) return;
    const candidate = ruleScope === 'tag' ? clean : `${ruleScope}:${clean}`;
    const validation = validateBlockRule(candidate);
    if (validation !== null) {
      setRuleError(t(validation));
      return;
    }
    setRuleError('');
    if (!blockedWords.includes(candidate)) {
      const autoAliases = knownAliasesForRule(candidate);
      onChange({
        blockedWords: [...blockedWords, candidate],
        ...(autoAliases.length
          ? { blockedTagAliases: { ...aliases, [candidate]: [...new Set([...(aliases[candidate] ?? []), ...autoAliases])] } }
          : {}),
      });
    }
    setRuleDraft('');
  };

  return (
    <>
      <section style={{ display: 'grid', gap: 10, marginBlock: 12 }}>
        <div className="form-row" style={{ margin: 0 }}>
          <label>
            {t('规则类型')}
            <select value={ruleScope} onChange={(e) => setRuleScope(e.target.value as typeof ruleScope)}>
              <option value="tag">{t('标签（如 ntr 或 female:ntr）')}</option>
              <option value="title">{t('标题包含')}</option>
              <option value="author">{t('作者 / 社团')}</option>
              <option value="regex">{t('正则表达式')}</option>
            </select>
          </label>
          <label style={{ flex: 1 }}>
            {t('新增屏蔽规则')}
            <input
              value={ruleDraft}
              onChange={(e) => {
                setRuleDraft(e.target.value);
                setRuleError('');
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  addStructuredRule();
                }
              }}
              placeholder={ruleScope === 'regex' ? '^(NTR|牛头人)' : 'female:netorare'}
            />
          </label>
          <button type="button" className="chip" onClick={addStructuredRule}>
            {t('添加规则')}
          </button>
        </div>
        {ruleError ? <p role="alert">{ruleError}</p> : null}
        {blockedWords.length > 0 ? (
          <div className="multi-pill-group">
            {blockedWords.map((word) => (
              <button
                key={word}
                type="button"
                className="chip"
                title={t('点击移除此屏蔽规则')}
                onClick={() => onChange({ blockedWords: blockedWords.filter((w) => w !== word) })}
              >
                {word} ×
              </button>
            ))}
          </div>
        ) : null}
      </section>

      <details>
        <summary>{t('屏蔽词别名')}</summary>
        {blockedWords.map((entry) => (
          <label key={entry}>
            <span>
              {entry}
              {knownAliasesForRule(entry).length ? (
                <button
                  type="button"
                  className="chip"
                  style={{ marginInlineStart: 8 }}
                  onClick={() =>
                    onChange({
                      blockedTagAliases: {
                        ...aliases,
                        [entry]: [...new Set([...(aliases[entry] ?? []), ...knownAliasesForRule(entry)])],
                      },
                    })
                  }
                >
                  {t('填入常见同义词')}
                </button>
              ) : null}
            </span>
            <textarea
              aria-label={entry + ' ' + t('别名')}
              value={(aliases[entry] ?? []).join('\n')}
              onChange={(event) => onChange({ blockedTagAliases: { ...aliases, [entry]: lines(event.target.value) } })}
            />
          </label>
        ))}
      </details>

      <details>
        <summary>{t('作者关联作品')}</summary>
        {((settings.blockedAuthors ?? []) as string[]).map((author) => (
          <label key={author}>
            {author}
            <textarea
              aria-label={author + ' ' + t('关联作品')}
              placeholder="source:id"
              value={(authorWorks[author] ?? []).join('\n')}
              onChange={(event) =>
                onChange({ blockedAuthorWorks: { ...authorWorks, [author]: lines(event.target.value) } })
              }
            />
          </label>
        ))}
      </details>

      <h3>{t('10大常见雷点预设包')}</h3>
      {blockPresets.map((preset) => {
        const config = presets[preset.id] ?? {};
        const update = (patch: Record<string, unknown>) =>
          onChange({ blockPresets: { ...presets, [preset.id]: { ...config, ...patch } } });
        return (
          <details key={preset.id}>
            <summary>
              <span>{t(preset.name)}</span>
              <small className="muted" style={{ marginInlineStart: 8 }}>
                {config.on === true ? t('已启用') : ''}
              </small>
            </summary>
            {(['on', 'title', 'strong'] as const).map((key, index) => (
              <label key={key}>
                <input
                  type="checkbox"
                  checked={config[key] === true}
                  onChange={(event) => update({ [key]: event.target.checked })}
                />
                {t(['启用预设', '同时匹配标题', '启用强规则'][index]!)}
              </label>
            ))}
            {(['entries', 'strongEntries'] as const).map((key) => (
              <label key={key}>
                {t(key === 'entries' ? '屏蔽词' : '强规则')}
                <textarea
                  value={((config[key] ?? preset[key]) as readonly string[]).join('\n')}
                  onChange={(event) => update({ [key]: lines(event.target.value) })}
                />
              </label>
            ))}
            <details>
              <summary>{t('别名')}</summary>
              {((config.entries ?? preset.entries) as readonly string[]).map((entry) => (
                <label key={entry}>
                  {entry}
                  <textarea
                    value={((config.aliases as Record<string, string[]> | undefined)?.[entry] ?? []).join('\n')}
                    onChange={(event) =>
                      update({ aliases: { ...((config.aliases as object) ?? {}), [entry]: lines(event.target.value) } })
                    }
                  />
                </label>
              ))}
            </details>
            <button
              type="button"
              className="chip"
              onClick={() => update({ entries: [...preset.entries], strongEntries: [...preset.strongEntries], aliases: {} })}
            >
              {t('恢复默认规则')}
            </button>
          </details>
        );
      })}
    </>
  );
}
