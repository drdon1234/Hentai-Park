import { useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react';
import { AdaptiveSheet, StatusMessage, confirmAction, showToast } from '@hentai-park/design-system';
import { workIdentityKey } from '@hentai-park/domain-model';
import { allPages, api, type ApiWork, type Source } from '../api.js';
import { navigateClick } from '../app/app-context.js';
import { ContentShelf, categoryLabels } from '../browse-ui.js';
import { pluginText, t } from '../i18n.js';
import { MaintenanceStatus } from '../maintenance-status.js';
import { useBackDismissable } from '../native.js';
import { PageHeader, StateView, errorMessage, useAsync, useServerVersion } from '../page-ui.js';
import { usePreferences } from '../preferences.js';
import { SearchTools } from '../search-tools.js';
import ShortVideoPage from '../short-video.js';
import { SourceManagement } from '../source-management.js';
import { SourcePackageControls } from '../source-packages-controls.js';
import { WorkCard, WorkGrid } from '../shared/work-card.js';

/** Parses pasted Cookie strings (`k=v; k2=v2`), `Cookie:` HTTP headers, Netscape cookies, or JSON into a clean Record. */
export function parsePastedCredentials(raw: string): Record<string, string> | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  try {
    const parsed = JSON.parse(trimmed);
    if (Array.isArray(parsed)) {
      const out: Record<string, string> = {};
      for (const item of parsed) {
        if (item && typeof item === 'object' && typeof item.name === 'string' && typeof item.value === 'string') {
          out[item.name] = item.value;
        }
      }
      if (Object.keys(out).length) return out;
    } else if (parsed && typeof parsed === 'object') {
      const out: Record<string, string> = {};
      for (const [k, v] of Object.entries(parsed)) {
        if (typeof v === 'string' || typeof v === 'number') out[k] = String(v);
      }
      if (Object.keys(out).length) return out;
    }
  } catch {
    /* Not JSON — try Netscape or header format */
  }
  const lines = trimmed.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  if (lines.some((l) => l.split('\t').length >= 7)) {
    const out: Record<string, string> = {};
    for (const line of lines) {
      if (line.startsWith('#')) continue;
      const cols = line.split('\t');
      if (cols.length >= 7 && cols[5]) out[cols[5]] = cols[6] ?? '';
    }
    if (Object.keys(out).length) return out;
  }
  const cleaned = trimmed.replace(/^cookie\s*:\s*/i, '');
  const out: Record<string, string> = {};
  for (const part of cleaned.split(';')) {
    const eq = part.indexOf('=');
    if (eq <= 0) continue;
    const k = part.slice(0, eq).trim();
    const v = part.slice(eq + 1).trim();
    if (k) out[k] = v;
  }
  return Object.keys(out).length ? out : null;
}

export type ReviewSource = Source & {
  version?: string;
  candidate?: {
    manifest: Record<string, unknown>;
    version: string;
    sha256: string;
    permissions: { added: string[]; removed: string[] };
  };
};

export function SourceStatus({ source, manifest }: { source: Source; manifest: Record<string, unknown> }) {
  if (!Object.keys(manifest).length) {
    return (
      <StatusMessage tone="danger" title={t('站点能力缺失')}>
        {t('服务端未返回 manifest，暂时无法安全渲染该站点。')}
      </StatusMessage>
    );
  }
  if (!source.enabled) {
    return (
      <StatusMessage tone="warning" title={t('站点已停用')}>
        {t('该站点已被停用，启用后才能浏览内容。')}
      </StatusMessage>
    );
  }
  const status = String(source.status ?? manifest.status ?? '');
  if (status === 'rate_limited' || status === 'limited') {
    return (
      <StatusMessage tone="warning" title={t('站点限流')}>
        {t('服务端正在限流，请稍后再试。')}
      </StatusMessage>
    );
  }
  if (status === 'login_required' || manifest.requiresLogin === true) {
    return (
      <StatusMessage tone="warning" title={t('需要登录')}>
        {t('请先完成站点登录。')}
      </StatusMessage>
    );
  }
  if (status === 'verification_required' || manifest.requiresVerification === true) {
    return (
      <StatusMessage tone="warning" title={t('需要验证')}>
        {t('请先完成站点验证。')}
      </StatusMessage>
    );
  }
  if (source.error) {
    return (
      <StatusMessage tone="danger" title={t('站点部分失败')}>
        {source.error}
      </StatusMessage>
    );
  }
  if (status === 'partial') {
    return (
      <StatusMessage tone="warning" title={t('部分内容不可用')}>
        {t('部分目录未能加载，其余内容仍可浏览。')}
      </StatusMessage>
    );
  }
  if (status === 'unavailable') {
    return (
      <StatusMessage tone="danger" title={t('站点不可用')}>
        {t('站点无法加载内容。')}
      </StatusMessage>
    );
  }
  return (
    <StatusMessage title={t('站点已启用')}>
      {t('manifest 已加载；实际网络可用性以目录请求结果为准。')}
    </StatusMessage>
  );
}

export function SourcePackageReview({
  item,
  action,
  busy,
  onConfirm,
  onCancel,
}: {
  item: ReviewSource;
  action: 'install' | 'update';
  busy: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  const candidate = item.candidate;
  if (!candidate) {
    return (
      <StatusMessage tone="danger" title={t('没有可信候选包')}>
        {t('服务端未提供可审阅的安装包，无法确认安装或更新。')}
      </StatusMessage>
    );
  }
  return (
    <section className="settings-panel" role="region" aria-label={t('插件权限审阅')}>
      <h2>{action === 'install' ? t('安装前审阅') : t('更新前审阅')}</h2>
      <p>
        {String(candidate.manifest.name ?? item.source)} · {item.source}
      </p>
      <p>
        {t('当前版本：')}
        {item.installed ? item.version ?? String(item.manifest?.version ?? '') : t('未安装')}
        {t(' → 目标版本：')}
        {candidate.version}
      </p>
      <p>
        {t('类型：')}
        {String(candidate.manifest.type ?? '')}
        {t(' · 分类：')}
        {String(candidate.manifest.category ?? '')}
        {t(' · 最低应用版本：')}
        {String(candidate.manifest.minAppVersion ?? '')}
      </p>
      <p>
        SHA-256：<code>{candidate.sha256}</code>
      </p>
      <h3>{t('新增权限')}</h3>
      {candidate.permissions.added.length ? (
        <ul>
          {candidate.permissions.added.map((value) => (
            <li key={value}>{value}</li>
          ))}
        </ul>
      ) : (
        <p>{t('无新增权限')}</p>
      )}
      <h3>{t('移除权限')}</h3>
      {candidate.permissions.removed.length ? (
        <ul>
          {candidate.permissions.removed.map((value) => (
            <li key={value}>{value}</li>
          ))}
        </ul>
      ) : (
        <p>{t('无移除权限')}</p>
      )}
      <p>
        {action === 'install'
          ? t('确认后执行插件代码，并允许访问上述声明的网络与能力。')
          : t('更新会替换当前插件；新增权限可能扩大可访问范围。校验或安装失败时保留上一可用版本，可在站点页回滚。')}
      </p>
      <div className="action-row">
        <button className="primary-link" disabled={busy} onClick={onConfirm}>
          {action === 'install' ? t('确认安装') : t('确认更新')}
        </button>
        <button className="secondary-link" disabled={busy} onClick={onCancel}>
          {t('取消审阅')}
        </button>
      </div>
    </section>
  );
}

type SourceFilterDeclaration = {
  key: string;
  label: string;
  type: string;
  dynamic?: boolean;
  dependsOn?: string[];
  keywordDependent?: boolean;
  default?: unknown;
  values?: Array<{ value: string | number | boolean; label: string }>;
  options?: Array<{ value: string | number | boolean; label: string }>;
};

function DynamicSourceFilter({
  source,
  scope,
  feed,
  item,
  values,
  keyword,
  value,
  onChange,
}: {
  source: string;
  scope: 'feed' | 'search';
  feed?: string;
  item: SourceFilterDeclaration;
  values: Record<string, unknown>;
  keyword?: string;
  value: unknown;
  onChange: (value: unknown) => void;
}) {
  const [options, setOptions] = useState<Array<{ value: string | number | boolean; label: string }>>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [attempt, setAttempt] = useState(0);
  const dependencies = Object.fromEntries((item.dependsOn ?? []).map((key) => [key, values[key]]));
  const ready =
    Object.values(dependencies).every(
      (val) =>
        typeof val === 'boolean' || (typeof val === 'number' && Number.isFinite(val)) || (typeof val === 'string' && Boolean(val)),
    ) &&
    (!item.keywordDependent || Boolean(keyword?.trim()));
  const identity = JSON.stringify([source, scope, feed, item.key, keyword, dependencies, ready]);

  useEffect(() => {
    const control = new AbortController();
    setOptions([]);
    setError('');
    if (!ready) {
      setLoading(false);
      return () => control.abort();
    }
    setLoading(true);
    void api
      .sourceFilterOptions(
        source,
        { scope, filter: item.key, values: dependencies, ...(scope === 'feed' ? { feed } : { keyword: keyword ?? '' }) },
        control.signal,
      )
      .then((result) => {
        if (!control.signal.aborted) setOptions(result.items);
      })
      .catch((err) => {
        if (!control.signal.aborted) setError(errorMessage(err));
      })
      .finally(() => {
        if (!control.signal.aborted) setLoading(false);
      });
    return () => control.abort();
  }, [identity, attempt]);

  return (
    <div>
      <label>
        {item.label}
        <select
          aria-label={(scope === 'feed' ? t('目录筛选：') : t('搜索筛选：')) + item.label}
          disabled={!ready || loading || Boolean(error)}
          value={value === undefined ? '' : JSON.stringify(value)}
          onChange={(event) =>
            onChange(options.find((option) => JSON.stringify(option.value) === event.target.value)?.value)
          }
        >
          <option value="">
            {loading ? t('正在加载选项') : !ready ? t('请先选择上级条件或输入关键词') : t('不限制')}
          </option>
          {options.map((option) => (
            <option key={JSON.stringify(option.value)} value={JSON.stringify(option.value)}>
              {option.label}
            </option>
          ))}
        </select>
      </label>
      {error ? (
        <StatusMessage tone="danger" title={item.label + t('选项加载失败')}>
          {error}
          <button className="chip" type="button" onClick={() => setAttempt((v) => v + 1)}>
            {t('重试')}
          </button>
        </StatusMessage>
      ) : null}
    </div>
  );
}

export function SourceSearchForm({
  source,
  manifest,
  navigate,
  browse = false,
  onApplied,
}: {
  source: string;
  manifest: Record<string, unknown>;
  navigate: (to: string) => void;
  browse?: boolean;
  onApplied?: () => void;
}) {
  const params = new URLSearchParams(window.location.search);
  const feeds = Array.isArray(manifest.feeds)
    ? (manifest.feeds as Array<{
        key: string;
        label: string;
        options?: SourceFilterDeclaration[];
        commonFilters?: Record<string, { range?: true | string[]; sort?: true | string[] }>;
      }>)
    : [];
  const [feedKey, setFeedKey] = useState(params.get('feed') ?? String(manifest.defaultFeed ?? feeds[0]?.key ?? ''));
  const selectedFeed = feeds.find((item) => item.key === feedKey);
  const [query, setQuery] = useState('');
  const [filters, setFilters] = useState<Record<string, unknown>>(() => {
    if (!browse) return {};
    try {
      const value = JSON.parse(params.get('filters') ?? '{}');
      if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
      const next = { ...value };
      delete next.common;
      return next;
    } catch {
      return {};
    }
  });
  const declarations = browse
    ? selectedFeed?.options ?? []
    : Array.isArray(manifest.searchFilters)
      ? (manifest.searchFilters as SourceFilterDeclaration[])
      : [];
  const common = browse
    ? selectedFeed?.commonFilters ?? {}
    : manifest.searchCommonFilters && typeof manifest.searchCommonFilters === 'object'
      ? (manifest.searchCommonFilters as Record<string, { range?: true | string[]; sort?: true | string[] }>)
      : {};
  const initialCommon = (() => {
    if (!browse) return {};
    try {
      return JSON.parse(params.get('filters') ?? '{}').common ?? {};
    } catch {
      return {};
    }
  })() as Record<string, { order?: string; min?: number; max?: number }>;
  const initialDimension = Object.keys(initialCommon)[0] ?? '';
  const [sort, setSort] = useState(initialCommon[initialDimension]?.order ?? '');
  const [minimum, setMinimum] = useState(
    initialCommon[initialDimension]?.min === undefined ? '' : String(initialCommon[initialDimension]!.min),
  );
  const [maximum, setMaximum] = useState(
    initialCommon[initialDimension]?.max === undefined ? '' : String(initialCommon[initialDimension]!.max),
  );
  const [dimension, setDimension] = useState(initialDimension);
  const effectiveValues = Object.fromEntries(declarations.map((item) => [item.key, filters[item.key] ?? item.default]));
  const updateValue = (key: string, value: unknown) =>
    setFilters((current) => {
      const next = { ...current };
      if (value === undefined) delete next[key];
      else next[key] = value;
      const pending = [key];
      while (pending.length) {
        const parent = pending.pop()!;
        for (const child of declarations) {
          if (child.dependsOn?.includes(parent)) {
            delete next[child.key];
            pending.push(child.key);
          }
        }
      }
      return next;
    });
  useEffect(() => {
    for (const item of declarations) if (item.keywordDependent) updateValue(item.key, undefined);
  }, [query]);
  const caps = (manifest.capabilities ?? {}) as Record<string, unknown>;
  if (browse ? !feeds.length || caps.feed !== true : caps.search !== true && caps.metadataSearch !== true) return null;
  const dimensions: Record<string, string> = {
    pages: t('页数'),
    likes: t('点赞数'),
    duration: t('时长'),
    score: t('评分'),
    favorites: t('收藏数'),
  };
  const selected = common[dimension];
  const ranges = selected?.range === true ? ['min', 'max'] : selected?.range ?? [];
  const orders = selected?.sort === true ? ['asc', 'desc'] : selected?.sort ?? [];
  const prefix = browse ? t('目录筛选：') : t('搜索筛选：');

  return (
    <form
      className="source-search-form"
      aria-label={browse ? t('目录筛选与排序') : t('站内搜索与筛选')}
      onSubmit={(event) => {
        event.preventDefault();
        const values = { ...filters };
        for (const item of declarations) {
          if (!item.dynamic && values[item.key] === undefined && item.default !== undefined) values[item.key] = item.default;
        }
        if (dimension && (sort || minimum || maximum)) {
          values.common = {
            [dimension]: {
              ...(sort ? { order: sort } : {}),
              ...(minimum ? { min: Number(minimum) } : {}),
              ...(maximum ? { max: Number(maximum) } : {}),
            },
          };
        }
        const filterQuery = Object.keys(values).length ? '&filters=' + encodeURIComponent(JSON.stringify(values)) : '';
        onApplied?.();
        if ((event.nativeEvent as SubmitEvent).submitter?.getAttribute('value') === 'album') {
          navigate(
            '/album/' +
              encodeURIComponent(source) +
              '?scope=' +
              encodeURIComponent(
                JSON.stringify(
                  browse
                    ? {
                        feed: feedKey,
                        options: Object.fromEntries(Object.entries(values).filter(([key]) => key !== 'common')),
                        ...(values.common ? { common: values.common } : {}),
                      }
                    : {
                        search: {
                          keyword: query.trim(),
                          filters: Object.fromEntries(Object.entries(values).filter(([key]) => key !== 'common')),
                          ...(values.common ? { common: values.common } : {}),
                        },
                      },
                ),
              ),
          );
          return;
        }
        navigate(
          browse
            ? '/source/' + encodeURIComponent(source) + '?feed=' + encodeURIComponent(feedKey) + filterQuery
            : '/search?q=' +
                encodeURIComponent(query.trim()) +
                '&scope=' +
                (caps.search === true ? 'all' : 'metadata') +
                '&source=' +
                encodeURIComponent(source) +
                '&view=grid' +
                filterQuery,
        );
      }}
    >
      {browse ? (
        <label>
          {t('站点目录')}
          <select
            aria-label={t('站点目录')}
            value={feedKey}
            onChange={(event) => {
              setFeedKey(event.target.value);
              setFilters({});
              setDimension('');
              setSort('');
              setMinimum('');
              setMaximum('');
            }}
          >
            {feeds.map((item) => (
              <option key={item.key} value={item.key}>
                {item.label}
              </option>
            ))}
          </select>
        </label>
      ) : (
        <label>
          {t('站内关键词')}
          <input aria-label={t('站内关键词')} required value={query} onChange={(event) => setQuery(event.target.value)} />
        </label>
      )}
      {declarations.map((item) => {
        const options = item.values ?? item.options ?? [];
        const value = filters[item.key] ?? item.default;
        if (item.dynamic) {
          return (
            <DynamicSourceFilter
              key={item.key}
              source={source}
              scope={browse ? 'feed' : 'search'}
              feed={browse ? feedKey : undefined}
              item={item}
              values={effectiveValues}
              keyword={browse ? undefined : query}
              value={value}
              onChange={(next) => updateValue(item.key, next)}
            />
          );
        }
        if (item.type === 'multi') {
          const currentArr = Array.isArray(value) ? value.map((v) => JSON.stringify(v)) : [];
          return (
            <fieldset key={item.key} style={{ flexBasis: '100%', margin: 0 }}>
              <legend>{item.label}</legend>
              <div className="multi-pill-group">
                {options.map((option) => {
                  const serialized = JSON.stringify(option.value);
                  const active = currentArr.includes(serialized);
                  return (
                    <button
                      key={serialized}
                      type="button"
                      className={`chip ${active ? 'active' : ''}`}
                      aria-pressed={active}
                      onClick={() => {
                        const nextArr = active
                          ? currentArr.filter((v) => v !== serialized)
                          : [...currentArr, serialized];
                        updateValue(
                          item.key,
                          nextArr
                            .map((s) => options.find((cand) => JSON.stringify(cand.value) === s)?.value)
                            .filter((v) => v !== undefined),
                        );
                      }}
                    >
                      {option.label}
                    </button>
                  );
                })}
              </div>
            </fieldset>
          );
        }
        return (
          <label key={item.key}>
            {item.label}
            {item.type === 'select' ? (
              <select
                aria-label={prefix + item.label}
                value={value === undefined ? '' : JSON.stringify(value)}
                onChange={(event) =>
                  updateValue(item.key, options.find((option) => JSON.stringify(option.value) === event.target.value)?.value)
                }
              >
                <option value="">{t('不限制')}</option>
                {options.map((option) => (
                  <option key={JSON.stringify(option.value)} value={JSON.stringify(option.value)}>
                    {option.label}
                  </option>
                ))}
              </select>
            ) : item.type === 'switch' ? (
              <input
                type="checkbox"
                role="switch"
                aria-label={prefix + item.label}
                checked={value === true}
                onChange={(event) => updateValue(item.key, event.target.checked)}
              />
            ) : (
              <input
                aria-label={prefix + item.label}
                type={item.type === 'number' ? 'number' : item.type === 'password' ? 'password' : 'text'}
                value={typeof value === 'string' || typeof value === 'number' ? value : ''}
                onChange={(event) =>
                  updateValue(
                    item.key,
                    event.target.value ? (item.type === 'number' ? Number(event.target.value) : event.target.value) : undefined,
                  )
                }
              />
            )}
          </label>
        );
      })}
      {Object.keys(common).length ? (
        <>
          <label>
            {t('筛选维度')}
            <select
              aria-label={prefix + t('维度')}
              value={dimension}
              onChange={(event) => {
                setDimension(event.target.value);
                setSort('');
                setMinimum('');
                setMaximum('');
              }}
            >
              <option value="">{t('来源默认')}</option>
              {Object.keys(common).map((key) => (
                <option key={key} value={key}>
                  {dimensions[key] ?? key}
                </option>
              ))}
            </select>
          </label>
          {orders.length ? (
            <label>
              {t('排序方向')}
              <select aria-label={prefix + t('排序方向')} value={sort} onChange={(event) => setSort(event.target.value)}>
                <option value="">{t('来源默认')}</option>
                {orders.map((order) => (
                  <option key={order} value={order}>
                    {order === 'asc' ? t('升序') : t('降序')}
                  </option>
                ))}
              </select>
            </label>
          ) : null}
          {ranges.includes('min') ? (
            <label>
              {t('最小值')}
              <input
                aria-label={prefix + t('最小值')}
                type="number"
                min={dimension === 'score' ? undefined : 0}
                step={dimension === 'duration' ? 'any' : 1}
                value={minimum}
                onChange={(event) => setMinimum(event.target.value)}
              />
            </label>
          ) : null}
          {ranges.includes('max') ? (
            <label>
              {t('最大值')}
              <input
                aria-label={prefix + t('最大值')}
                type="number"
                min={minimum || (dimension === 'score' ? undefined : 0)}
                step={dimension === 'duration' ? 'any' : 1}
                value={maximum}
                onChange={(event) => setMaximum(event.target.value)}
              />
            </label>
          ) : null}
        </>
      ) : null}
      <div className="action-row" style={{ flexBasis: '100%', margin: 0 }}>
        <button className="primary-link" disabled={browse ? !feedKey : !query.trim()}>
          {browse ? t('应用目录条件') : t('搜索此站')}
        </button>
        {browse ? (
          <button
            type="button"
            className="chip"
            onClick={() => {
              setFilters({});
              setDimension('');
              setSort('');
              setMinimum('');
              setMaximum('');
            }}
          >
            {t('重置筛选')}
          </button>
        ) : null}
        {caps.album === true ? (
          <button className="chip" value="album" disabled={browse ? !feedKey : !query.trim()}>
            {t('浏览相册')}
          </button>
        ) : null}
      </div>
      {!browse ? (
        <SearchTools
          keyword={query}
          source={source}
          navigate={navigate}
          search={(keyword, keywords) => {
            onApplied?.();
            navigate(
              '/search?' +
                new URLSearchParams({
                  q: keyword,
                  scope: caps.search === true ? 'all' : 'metadata',
                  source,
                  filters: JSON.stringify({
                    ...filters,
                    ...(dimension && (sort || minimum || maximum)
                      ? {
                          common: {
                            [dimension]: {
                              ...(sort ? { order: sort } : {}),
                              ...(minimum ? { min: Number(minimum) } : {}),
                              ...(maximum ? { max: Number(maximum) } : {}),
                            },
                          },
                        }
                      : {}),
                  }),
                  ...(keywords ? { keywords: JSON.stringify(keywords) } : {}),
                }),
            );
          }}
        />
      ) : null}
    </form>
  );
}

export function SourcesPage({ navigate }: { navigate: (to: string) => void }) {
  const version = useServerVersion();
  const state = useAsync(() => allPages(api.sources), [version], undefined, { cacheKey: 'source-catalog' });
  const [source, setSource] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [review, setReview] = useState<ReviewSource>();

  const prepare = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setMessage('');
    setReview(undefined);
    try {
      const value = (await api.source(source.trim())) as ReviewSource;
      if (!value.candidate) throw new Error(t('服务端未提供可信候选包'));
      setReview(value);
    } catch (error) {
      setMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const install = async () => {
    if (!review) return;
    setBusy(true);
    setMessage(t('正在安装…'));
    try {
      const latest = (await api.source(review.source)) as ReviewSource;
      if (JSON.stringify([latest.version, latest.candidate]) !== JSON.stringify([review.version, review.candidate])) {
        setReview(latest);
        throw new Error(t('候选包或当前版本已变化，请重新审阅后确认'));
      }
      const value = await api.sourceAction(review.source, 'update', {
        action: 'install',
        expectedSha256: review.candidate?.sha256,
        expectedVersion: review.candidate?.version,
        expectedCurrentVersion: review.version ?? null,
      });
      if (value.status !== 'completed') throw new Error(t('服务端未确认安装完成'));
      setMessage(t('服务端安装状态：') + String(value.status));
      setReview(undefined);
    } catch (error) {
      setMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const uninstall = async (key: string, name: string) => {
    const ok = await confirmAction({
      title: t('卸载插件'),
      description: `${name} (${key}) — ${t('卸载后已收藏和历史记录保留，插件脚本将被移除。')}`,
      confirmLabel: t('卸载'),
      danger: true,
    });
    if (!ok) return;
    setBusy(true);
    try {
      await api.uninstallSource(key);
      showToast(t('插件已卸载'), 'success');
      window.dispatchEvent(new Event('hp:invalidate'));
    } catch (err) {
      setMessage(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <PageHeader title={t('站点')} description={t('安装包、权限与版本由服务端索引校验。')} />
      <MaintenanceStatus />
      <SourcePackageControls onInstalled={() => window.dispatchEvent(new Event('hp:invalidate'))} />
      <details className="browse-tools">
        <summary>{t('安装站点标识')}</summary>
        <form className="form-row" onSubmit={(e) => void prepare(e)}>
          <input
            aria-label={t('安装站点标识')}
            disabled={busy}
            value={source}
            onChange={(event) => {
              setSource(event.target.value);
              setReview(undefined);
            }}
            required
            placeholder={t('官方索引中的站点标识')}
          />
          <button className="primary-link" disabled={busy || !source.trim()}>
            {t('安装站点')}
          </button>
        </form>
      </details>
      {review ? (
        <SourcePackageReview
          item={review}
          action="install"
          busy={busy}
          onConfirm={() => void install()}
          onCancel={() => {
            setReview(undefined);
            setMessage(t('已取消安装，未提交安装请求'));
          }}
        />
      ) : null}
      {message ? <p role="status">{message}</p> : null}
      <StateView loading={state.loading} error={state.error} empty={!state.loading && !state.error && !state.data?.length}>
        <ul className="chapter-list">
          {state.data?.map((item) => {
            const href = '/source/' + encodeURIComponent(item.source);
            const name = String(item.manifest?.name ?? item.source);
            return (
              <li key={item.source}>
                <a href={href} onClick={(event) => navigateClick(event, navigate, href)}>
                  {name}
                </a>
                <div className="action-row" style={{ margin: 0 }}>
                  <span className="chapter-state">
                    {item.installed === false ? t('未安装') : item.enabled ? t('已启用') : t('已停用')} ·{' '}
                    {String(item.manifest?.version ?? '')}
                  </span>
                  {item.installed !== false ? (
                    <button
                      type="button"
                      className="chip danger-action"
                      disabled={busy}
                      onClick={() => void uninstall(item.source, name)}
                    >
                      {t('卸载')}
                    </button>
                  ) : null}
                </div>
              </li>
            );
          })}
        </ul>
      </StateView>
    </>
  );
}

export function SourcePage({
  source,
  navigate,
  renderEmbeddedReader,
}: {
  source: string;
  navigate: (to: string) => void;
  renderEmbeddedReader: (parts: string[], active: boolean) => ReactNode;
}) {
  const prefs = usePreferences();
  const [loadRequested, setLoadRequested] = useState(false);
  const suppressFeed = !prefs.ready || (prefs.settings.dataSavingMode === 'super' && !loadRequested);
  useEffect(() => setLoadRequested(false), [source]);

  const version = useServerVersion();
  const browseParams = new URLSearchParams(window.location.search);
  const browseLink = browseParams.get('link') ?? undefined;
  const browseCursor = browseParams.get('cursor') ?? undefined;
  const initialBrowseView = browseParams.get('view');
  const browseFeed = browseParams.get('feed') ?? undefined;
  const browseFilters = browseParams.get('filters') ?? undefined;

  /* Instant client-side Grid/List toggle without network re-fetching! */
  const [layoutOverride, setLayoutOverride] = useState<'grid' | 'list' | undefined>(
    initialBrowseView === 'list' ? 'list' : initialBrowseView === 'grid' ? 'grid' : undefined,
  );
  const [filterDrawerOpen, setFilterDrawerOpen] = useState(false);
  useBackDismissable(filterDrawerOpen, () => setFilterDrawerOpen(false));

  const state = useAsync(() => api.source(source), [source, version], undefined, { cacheKey: 'source:' + source });
  const isShortVideoList = state.data?.manifest?.category === 'shortvideo' && (initialBrowseView === 'list' || layoutOverride === 'list');

  const feed = useAsync(
    async (signal) => {
      const sourceInfo = await api.source(source);
      if (
        suppressFeed ||
        !sourceInfo.enabled ||
        sourceInfo.installed === false ||
        (sourceInfo.manifest?.capabilities as Record<string, unknown> | undefined)?.feed !== true
      ) {
        return { items: [] as ApiWork[], sections: [] as Array<{ key: string; title: string; items: ApiWork[] }>, page: { limit: 24, nextCursor: null } };
      }
      if (sourceInfo.manifest?.category === 'shortvideo' && !isShortVideoList) {
        return { items: [] as ApiWork[], sections: [], page: { limit: 24, nextCursor: null } };
      }
      return api.works({ source, link: browseLink, feed: browseFeed, filters: browseFilters, cursor: browseCursor, limit: 24 }, signal);
    },
    [suppressFeed, source, version, browseFeed, browseFilters, browseLink, browseCursor, isShortVideoList],
    undefined,
    { cacheKey: 'source-feed:' + JSON.stringify([source, suppressFeed, browseFeed, browseFilters, browseLink, browseCursor]) },
  );

  const [extraItems, setExtraItems] = useState<ApiWork[]>([]);
  const [cursor, setCursor] = useState<string | null>();
  const [loadingMore, setLoadingMore] = useState(false);
  const sentinelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setExtraItems([]);
    setCursor(feed.data?.page?.nextCursor);
  }, [feed.data]);

  const loadMore = async () => {
    if (!cursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const nextPage = await api.works({
        source,
        link: browseLink,
        feed: browseFeed,
        filters: browseFilters,
        cursor,
        limit: 24,
      });
      setExtraItems((prev) => {
        const seen = new Set(prev.map((w) => w.workId));
        return [...prev, ...nextPage.items.filter((w) => !seen.has(w.workId))];
      });
      setCursor(nextPage.page?.nextCursor);
    } catch (err) {
      setMessage(errorMessage(err));
    } finally {
      setLoadingMore(false);
    }
  };

  useEffect(() => {
    const node = sentinelRef.current;
    if (!node || !cursor || loadingMore || prefs.settings.dataSavingMode === 'super') return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) void loadMore();
      },
      { rootMargin: '320px 0px' },
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, [cursor, loadingMore, prefs.settings.dataSavingMode]);

  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [credentials, setCredentials] = useState<Record<string, string>>({});
  const [cookieDraft, setCookieDraft] = useState('');
  const [review, setReview] = useState<ReviewSource>();

  const sourceSnapshot = useRef<Source | undefined>(undefined);
  if (state.data) sourceSnapshot.current = state.data;
  const details = state.data ?? sourceSnapshot.current;
  const result = details ? ([details, feed.data ?? { items: [] as ApiWork[] }] as const) : undefined;
  const manifest = details?.manifest ?? {};
  const capabilities = (manifest.capabilities ?? {}) as Record<string, unknown>;
  const account = manifest.account as
    | {
        type?: string;
        loginUrl?: string;
        fields?: Array<{ key: string; label: string; hint?: string; secret?: boolean; optional?: boolean }>;
      }
    | undefined;
  const network = manifest.network as { confirmation?: { selector?: string } } | undefined;

  const run = async (operation: 'enable' | 'update' | 'login' | 'verify', body: Record<string, unknown>) => {
    setBusy(true);
    setMessage(t('正在提交…'));
    try {
      const value = await api.sourceAction(source, operation, body);
      if (value.status !== 'completed') throw new Error(t('服务端未确认操作完成'));
      setMessage(t('服务端状态：') + String(value.status));
      if (operation === 'login') {
        setCredentials({});
        setCookieDraft('');
        showToast(t('登录凭据已保存'), 'success');
      }
    } catch (error) {
      setMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const prepareUpdate = async () => {
    setBusy(true);
    setMessage('');
    try {
      const value = (await api.source(source)) as ReviewSource;
      if (!value.candidate) throw new Error(t('服务端未提供可信候选包'));
      setReview(value);
    } catch (error) {
      setMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const confirmUpdate = async () => {
    if (!review) return;
    setBusy(true);
    try {
      const latest = (await api.source(source)) as ReviewSource;
      if (JSON.stringify([latest.version, latest.candidate]) !== JSON.stringify([review.version, review.candidate])) {
        setReview(latest);
        throw new Error(t('候选包或当前版本已变化，请重新审阅后确认'));
      }
      await run('update', {
        action: review.installed ? 'update' : 'install',
        expectedSha256: review.candidate?.sha256,
        expectedVersion: review.candidate?.version,
        expectedCurrentVersion: review.version ?? null,
      });
      setReview(undefined);
    } catch (error) {
      setMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const login = () => {
    if (account?.type !== 'cookies') {
      void run('login', { credentials });
      return;
    }
    try {
      const parsed = parsePastedCredentials(cookieDraft);
      if (
        !parsed ||
        Object.keys(parsed).length < 1 ||
        Object.keys(parsed).length > 100 ||
        Object.values(parsed).some((value) => typeof value !== 'string')
      ) {
        throw new Error(t('未识别到有效 Cookie，支持粘贴 JSON、Cookie 请求头或 Netscape 格式。'));
      }
      void run('login', { credentials: parsed });
    } catch (error) {
      setMessage(errorMessage(error));
    }
  };

  const pasteFromClipboard = async () => {
    try {
      const clip = await navigator.clipboard.readText();
      const parsed = parsePastedCredentials(clip);
      if (!parsed) {
        setMessage(t('剪贴板中未识别到 Cookie 或键值凭据。'));
        return;
      }
      if (account?.type === 'cookies') {
        setCookieDraft(JSON.stringify(parsed, null, 2));
      } else {
        setCredentials((prev) => ({ ...prev, ...parsed }));
      }
      showToast(t('已从剪贴板解析凭据'), 'success');
    } catch {
      setMessage(t('浏览器拒绝读取剪贴板，请直接在输入框内粘贴。'));
    }
  };

  const boards = Array.isArray(manifest.rankings) ? (manifest.rankings as Array<{ key: string; label: string }>) : [];
  const feeds = Array.isArray(manifest.feeds) ? (manifest.feeds as Array<{ key: string; label: string }>) : [];
  const activeFeed = browseFeed ?? String(manifest.defaultFeed ?? feeds[0]?.key ?? '');
  const selectedFeed = (Array.isArray(manifest.feeds) ? manifest.feeds : []).find(
    (item: { key?: string }) => item.key === activeFeed,
  ) as { options?: unknown[]; commonFilters?: Record<string, unknown> } | undefined;
  const hasBrowseFilters = Boolean(selectedFeed?.options?.length || Object.keys(selectedFeed?.commonFilters ?? {}).length);

  useEffect(() => {
    document
      .querySelector<HTMLElement>('.feed-tabs [aria-current="page"]')
      ?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }, [activeFeed]);

  const sections = feed.data?.sections ?? [];
  const grouped = new Set(
    sections.flatMap((section) => section.items.map((item) => workIdentityKey({ source: item.source, id: item.workId }))),
  );
  const allItems = [...(feed.data?.items ?? []), ...extraItems];
  const ungrouped = allItems.filter((item) => !grouped.has(workIdentityKey({ source: item.source, id: item.workId })));
  const effectiveLayout = layoutOverride ?? (manifest.browseLayout === 'list' ? 'list' : 'grid');

  if (!suppressFeed && details?.enabled && manifest.category === 'shortvideo' && !isShortVideoList) {
    return (
      <ShortVideoPage
        source={source}
        manifest={manifest}
        navigate={navigate}
        renderReader={renderEmbeddedReader}
      />
    );
  }

  return (
    <>
      {suppressFeed ? (
        <p>
          <button className="chip" disabled={!prefs.ready} onClick={() => setLoadRequested(true)}>
            {t('加载站点作品')}
          </button>
        </p>
      ) : null}

      <div className="source-quick-actions" role="toolbar" aria-label={t('站点工具')}>
        {hasBrowseFilters ? (
          <button type="button" className="chip" onClick={() => setFilterDrawerOpen(true)}>
            {t('目录筛选与排序')}
          </button>
        ) : null}
        {capabilities.search === true || capabilities.metadataSearch === true ? (
          <a
            className="chip"
            href={'/search?source=' + encodeURIComponent(source)}
            onClick={(event) => navigateClick(event, navigate, event.currentTarget.getAttribute('href')!)}
          >
            {t('站内搜索')}
          </a>
        ) : null}
        <button
          type="button"
          className={`chip ${effectiveLayout === 'grid' ? 'active' : ''}`}
          aria-pressed={effectiveLayout === 'grid'}
          onClick={() => setLayoutOverride('grid')}
        >
          {t('卡片视图')}
        </button>
        <button
          type="button"
          className={`chip ${effectiveLayout === 'list' ? 'active' : ''}`}
          aria-pressed={effectiveLayout === 'list'}
          onClick={() => setLayoutOverride('list')}
        >
          {t('列表视图')}
        </button>
      </div>

      <PageHeader
        title={pluginText(manifest, String(manifest.name ?? source))}
        description={t(categoryLabels[String(manifest.category ?? '')] ?? '内容站点') + ' · ' + t(manifest.metadataOnly ? '资料站点' : '站点主页')}
      >
        {manifest.category === 'shortvideo' && isShortVideoList ? (
          <button type="button" className="chip" onClick={() => setLayoutOverride(undefined)}>
            {t('短视频')}
          </button>
        ) : null}
        <button
          className="chip"
          onClick={() => {
            const panel = document.getElementById('source-management') as HTMLDetailsElement | null;
            if (panel) {
              panel.open = true;
              panel.querySelector('summary')?.focus();
              panel.scrollIntoView({ block: 'start' });
            }
          }}
        >
          {t('更多')}
        </button>
      </PageHeader>

      {result ? (
        <>
          {feeds.length ? (
            <nav className="feed-tabs" aria-label={t('站点分区')}>
              {feeds.map((item) => {
                const href = '/source/' + encodeURIComponent(source) + '?feed=' + encodeURIComponent(item.key);
                return (
                  <a
                    key={item.key}
                    className={activeFeed === item.key ? 'active' : ''}
                    aria-current={activeFeed === item.key ? 'page' : undefined}
                    href={href}
                    onClick={(event) => navigateClick(event, navigate, href)}
                  >
                    {pluginText(manifest, item.label)}
                  </a>
                );
              })}
            </nav>
          ) : null}
          {capabilities.search === true || capabilities.metadataSearch === true ? (
            <details id="source-search" className="browse-tools">
              <summary>{t('站内搜索与筛选')}</summary>
              <SourceSearchForm key={source} source={source} manifest={manifest} navigate={navigate} />
            </details>
          ) : null}
        </>
      ) : null}

      {filterDrawerOpen ? (
        <AdaptiveSheet
          open={filterDrawerOpen}
          side="right"
          title={t('目录筛选与排序')}
          closeLabel={t('关闭')}
          onClose={() => setFilterDrawerOpen(false)}
        >
          <SourceSearchForm
            key={'browse:' + source + (browseFeed ?? '') + (browseFilters ?? '')}
            source={source}
            manifest={manifest}
            navigate={navigate}
            browse
            onApplied={() => setFilterDrawerOpen(false)}
          />
        </AdaptiveSheet>
      ) : null}

      {message ? <p role="status">{message}</p> : null}

      <StateView loading={state.loading && !details} error={state.error} empty={false}>
        {result ? (
          <>
            <div className="action-row">
              {capabilities.reverseSearch === true ? (
                <a
                  className="primary-link"
                  href={'/search?mode=reverse&source=' + encodeURIComponent(source) + '#reverse-search'}
                  onClick={(event) => navigateClick(event, navigate, event.currentTarget.getAttribute('href')!)}
                >
                  {t('以图搜图')}
                </a>
              ) : null}
              {capabilities.subscription === true ? (
                <a
                  className="secondary-link"
                  href={'/channel/' + encodeURIComponent(source)}
                  onClick={(event) => navigateClick(event, navigate, '/channel/' + encodeURIComponent(source))}
                >
                  {t('打开频道')}
                </a>
              ) : null}
              {capabilities.album === true ? (
                <a
                  className="secondary-link"
                  href={'/album/' + encodeURIComponent(source)}
                  onClick={(event) => navigateClick(event, navigate, '/album/' + encodeURIComponent(source))}
                >
                  {t('打开相册')}
                </a>
              ) : null}
              {capabilities.metadataSearch === true ? (
                <a
                  className="primary-link"
                  href={'/search?q=&scope=metadata&source=' + encodeURIComponent(source)}
                  onClick={(event) =>
                    navigateClick(event, navigate, '/search?q=&scope=metadata&source=' + encodeURIComponent(source))
                  }
                >
                  {t('搜索此站资料')}
                </a>
              ) : null}
            </div>
            {boards.length ? (
              <nav className="source-directory" aria-label={t('站点榜单')}>
                {boards.map((board) => (
                  <a
                    key={board.key}
                    href={'/rankings?source=' + encodeURIComponent(source) + '&board=' + encodeURIComponent(board.key)}
                    onClick={(event) => navigateClick(event, navigate, event.currentTarget.getAttribute('href')!)}
                  >
                    {pluginText(manifest, board.label)}
                  </a>
                ))}
              </nav>
            ) : null}

            {capabilities.feed === true ? (
              <StateView
                loading={feed.loading}
                error={feed.error}
                empty={!feed.loading && !feed.error && !allItems.length && !sections.length}
              >
                {sections.map((section) => {
                  let sectionIndex: number | undefined;
                  try {
                    const [page, index] = JSON.parse(section.key);
                    if (page === 1) sectionIndex = index;
                  } catch {
                    /* ignore */
                  }
                  return effectiveLayout === 'list' ? (
                    <section
                      key={section.key}
                      id={sectionIndex === undefined ? undefined : 'section-' + source + '-' + sectionIndex}
                      tabIndex={-1}
                    >
                      <h2>{section.title}</h2>
                      <WorkGrid items={section.items} view="list" navigate={navigate} cacheScope="cards" />
                    </section>
                  ) : (
                    <ContentShelf
                      key={section.key}
                      local
                      shelf={{ ...section, source, sectionIndex }}
                      navigate={navigate}
                      renderItem={(work) => <WorkCard work={work} navigate={navigate} cacheScope="cards" />}
                    />
                  );
                })}
                {ungrouped.length ? (
                  <>
                    <h2>{pluginText(manifest, feeds.find((item) => item.key === activeFeed)?.label ?? t('内容列表'))}</h2>
                    <WorkGrid items={ungrouped} view={effectiveLayout} navigate={navigate} cacheScope="cards" />
                  </>
                ) : null}
                <div ref={sentinelRef} style={{ height: 1 }} aria-hidden="true" />
              </StateView>
            ) : (
              <p className="muted">
                {capabilities.subscription ||
                capabilities.album ||
                capabilities.reverseSearch ||
                capabilities.search ||
                capabilities.metadataSearch ||
                boards.length
                  ? t('此站点不提供公开推荐，使用上方的可用入口浏览。')
                  : t('此来源不提供公开目录，可从已收藏作品或单条播放链接进入。')}
              </p>
            )}

            {capabilities.feed === true && cursor ? (
              <nav className="pagination" aria-label={t('列表分页')}>
                <button className="chip" disabled={loadingMore} onClick={() => void loadMore()}>
                  {loadingMore ? t('正在加载') : t('加载更多')}
                </button>
              </nav>
            ) : null}
          </>
        ) : null}
      </StateView>

      {result ? (
        <details id="source-management" className="browse-tools source-management-tools">
          <summary>{t('账号与站点设置')}</summary>
          <SourceStatus source={result[0]} manifest={manifest} />
          <div className="action-row">
            <button
              className="secondary-link"
              disabled={busy}
              onClick={() => void run('enable', { enabled: !result[0].enabled })}
            >
              {result[0].enabled ? t('停用站点') : t('启用站点')}
            </button>
            <button className="secondary-link" disabled={busy} onClick={() => void prepareUpdate()}>
              {details?.installed === false ? t('安装') : t('更新')}
            </button>
            <button
              className="secondary-link"
              disabled={busy || details?.installed === false}
              onClick={async () => {
                if (await confirmAction(t('回滚到上一可用插件版本？'))) void run('update', { action: 'rollback' });
              }}
            >
              {t('回滚')}
            </button>
            {typeof manifest.homepage === 'string' ? (
              <a className="secondary-link" href={manifest.homepage} target="_blank" rel="noreferrer">
                {t('打开原站')}
              </a>
            ) : null}
            {network?.confirmation ? (
              <button
                className="secondary-link"
                disabled={busy}
                onClick={() => void run('verify', { url: manifest.homepage, selector: network.confirmation?.selector })}
              >
                {t('验证站点')}
              </button>
            ) : null}
          </div>

          {review ? (
            <SourcePackageReview
              item={review}
              action={review.installed ? 'update' : 'install'}
              busy={busy}
              onConfirm={() => void confirmUpdate()}
              onCancel={() => {
                setReview(undefined);
                setMessage(t('已取消审阅，未提交安装或更新请求'));
              }}
            />
          ) : null}

          {account ? (
            <form
              className="settings-panel"
              onSubmit={(event) => {
                event.preventDefault();
                login();
              }}
            >
              <div className="section-header" style={{ marginBottom: 12 }}>
                <h2 style={{ margin: 0 }}>{t('站点登录')}</h2>
                <button type="button" className="chip" onClick={() => void pasteFromClipboard()}>
                  {t('从剪贴板解析')}
                </button>
              </div>
              {account.type === 'cookies' ? (
                <>
                  <p>{t('支持直接粘贴浏览器 Cookie 字符串、JSON 或 Netscape 格式。登录成功后自动清空输入。')}</p>
                  <label>
                    {t('Cookie 凭据')}
                    <textarea
                      aria-label={t('站点Cookie JSON')}
                      value={cookieDraft}
                      onChange={(event) => setCookieDraft(event.target.value)}
                      autoComplete="off"
                      spellCheck={false}
                      rows={5}
                      required
                      placeholder={'session_id=...; cf_clearance=...'}
                    />
                  </label>
                </>
              ) : (
                account.fields?.map((field) => (
                  <label key={field.key}>
                    {pluginText(manifest, field.label)}
                    <input
                      type={field.secret ? 'password' : 'text'}
                      value={credentials[field.key] ?? ''}
                      onChange={(event) => setCredentials({ ...credentials, [field.key]: event.target.value })}
                      autoComplete="off"
                      required={!field.optional}
                      placeholder={field.hint ? pluginText(manifest, field.hint) : undefined}
                    />
                  </label>
                ))
              )}
              <button className="secondary-link" disabled={busy} type="submit">
                {t('登录站点')}
              </button>
            </form>
          ) : null}

          <SourceManagement source={source} manifest={manifest} enabled={details?.enabled === true} />
        </details>
      ) : null}
    </>
  );
}
