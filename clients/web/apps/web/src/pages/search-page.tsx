import { useContext, useEffect, useRef, useState } from 'react';
import { Button, StatusMessage } from '@hentai-park/design-system';
import type { WorkTag } from '@hentai-park/domain-model';
import { allPages, api, type ApiWork, type ReverseMatch } from '../api.js';
import { SourceCatalog, SourceNames, navigateClick, searchSelectionQuery } from '../app/app-context.js';
import { ContentShelf, categoryLabels } from '../browse-ui.js';
import { CoverImage } from '../cover-image.js';
import { FilePicker } from '../file-picker.js';
import { t } from '../i18n.js';
import { useSharedState } from '../native.js';
import { PageHeader, StateView, errorMessage, useAsync } from '../page-ui.js';
import { SourceSearchForm, withinWorkDates } from './source-page.js';
import { usePreferences } from '../preferences.js';
import { ReverseHistory } from '../reverse-history.js';
import { SearchScope } from '../search-scope.js';
import { ImageCropModal } from '../shared/image-crop-modal.js';
import { MediaLightboxModal, type LightboxMediaItem } from '../shared/media-lightbox.js';
import { SearchBox } from '../shared/search-combobox.js';
import { WorkCard, WorkGrid } from '../shared/work-card.js';

async function normalizeSearchImage(file: File, signal: AbortSignal) {
  if (!['image/png', 'image/jpeg', 'image/webp', 'image/gif'].includes(file.type) || file.size > 32_000_000) {
    throw new Error(t('请选择不超过32MB的PNG、JPEG、WebP或GIF图片'));
  }
  const bitmap = await createImageBitmap(file);
  try {
    let scale = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height));
    for (let attempt = 0; attempt < 12; attempt++) {
      if (signal.aborted) throw new DOMException(t('已取消'), 'AbortError');
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.round(bitmap.width * scale));
      canvas.height = Math.max(1, Math.round(bitmap.height * scale));
      const context = canvas.getContext('2d');
      if (!context) throw new Error(t('浏览器无法处理图片'));
      context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise<Blob>((resolve, reject) =>
        canvas.toBlob((value) => (value ? resolve(value) : reject(new Error(t('图片编码失败')))), 'image/png'),
      );
      if (blob.size <= 1_800_000) {
        const bytes = new Uint8Array(await blob.arrayBuffer());
        let encoded = '';
        for (let index = 0; index < bytes.length; index += 8192) {
          encoded += String.fromCharCode(...bytes.subarray(index, index + 8192));
        }
        return btoa(encoded);
      }
      scale *= 0.75;
    }
    throw new Error(t('图片无法缩减到上传大小限制，请换一张图片'));
  } finally {
    bitmap.close();
  }
}

function classifyReverseGroup(sourceKey: string, manifest?: Record<string, unknown>): 'anime' | 'manga' | 'illust' | 'general' {
  const id = (sourceKey + ' ' + String(manifest?.name ?? '')).toLowerCase();
  if (/trace|anime|whatanime/.test(id)) return 'anime';
  if (/eh|e-hentai|nhentai|hitomi|manga|comic|ascii2d/.test(id)) return 'manga';
  if (/saucenao|iqdb|danbooru|pixiv|illust/.test(id)) return 'illust';
  return 'general';
}

export function ReverseSearch({ navigate }: { navigate: (to: string) => void }) {
  const sourceNames = useContext(SourceNames);
  const services = useAsync(() => allPages(api.sources), []);
  const [source, setSource] = useState(
    new URLSearchParams(window.location.search).get('mode') === 'reverse'
      ? new URLSearchParams(window.location.search).get('source') ?? ''
      : '',
  );
  const [rawCropFile, setRawCropFile] = useState<File>();
  const [file, setFile] = useState<File>();
  const [preview, setPreview] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [items, setItems] = useState<ReverseMatch[]>([]);
  const [cursor, setCursor] = useState<string | null>();
  const [error, setError] = useState('');
  const [lightbox, setLightbox] = useState<{ items: LightboxMediaItem[]; index: number; title: string }>();
  const controller = useRef<AbortController | undefined>(undefined);
  const generation = useRef(0);
  const [chosenSources, setChosenSources] = useState<string[]>([]);
  const cursors = useRef(new Map<string, string | null>());

  const available = (services.data ?? []).filter(
    (item) => item.installed !== false && item.enabled && (item.manifest?.capabilities as Record<string, boolean> | undefined)?.reverseSearch === true,
  );

  const cancel = () => {
    generation.current++;
    controller.current?.abort();
    setBusy(false);
  };

  useEffect(
    () => () => {
      controller.current?.abort();
      generation.current++;
    },
    [],
  );

  useEffect(() => {
    if (!file) {
      setPreview(undefined);
      return;
    }
    const url = URL.createObjectURL(file);
    setPreview(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);

  const acceptPreparedFile = async (next: File) => {
    cancel();
    const id = generation.current;
    setItems([]);
    setCursor(undefined);
    setError('');
    setMessage('');
    setFile(undefined);
    if (!['image/png', 'image/jpeg', 'image/webp', 'image/gif'].includes(next.type)) {
      setError(t('请选择PNG、JPEG、WebP或GIF图片'));
      return;
    }
    try {
      const bitmap = await createImageBitmap(next);
      bitmap.close();
      if (id !== generation.current) return;
      setFile(next);
      setMessage(t('图片已准备，选择服务后点击搜索才会上传。'));
    } catch {
      if (id === generation.current) setError(t('浏览器无法处理图片'));
    }
  };

  const openCropFor = (next: File) => {
    if (!['image/png', 'image/jpeg', 'image/webp', 'image/gif'].includes(next.type)) {
      setError(t('请选择PNG、JPEG、WebP或GIF图片'));
      return;
    }
    setRawCropFile(next);
  };

  const selectGroup = (group: 'all' | 'illust' | 'manga' | 'anime' | 'general') => {
    cancel();
    const matched =
      group === 'all'
        ? available.map((item) => item.source)
        : available.filter((item) => classifyReverseGroup(item.source, item.manifest) === group).map((item) => item.source);
    setSource('');
    setChosenSources(matched);
  };

  const submit = async (more = false) => {
    if (!more && (!file || (!source && !chosenSources.length))) return;
    cancel();
    const id = ++generation.current;
    const abort = new AbortController();
    controller.current = abort;
    setBusy(true);
    setError('');
    setMessage(t('正在处理本次反搜…'));
    if (!more) {
      setItems([]);
      setCursor(undefined);
    }
    try {
      const selected = chosenSources.length ? chosenSources : source ? [source] : [];
      const contentBase64 = await normalizeSearchImage(file!, abort.signal);
      if (!more) cursors.current.clear();
      const pending = more ? selected.filter((key) => cursors.current.get(key)) : selected;
      const settled = await Promise.allSettled(
        pending.map(async (src) => ({
          source: src,
          result: await api.reverseSearch(
            more ? { cursor: cursors.current.get(src)! } : { source: src, contentBase64, mimeType: 'image/png' },
            abort.signal,
          ),
        })),
      );
      if (id !== generation.current || abort.signal.aborted) return;
      const fresh: ReverseMatch[] = [];
      const failures: string[] = [];
      for (const [index, result] of settled.entries()) {
        if (result.status === 'fulfilled') {
          fresh.push(...result.value.result.items);
          cursors.current.set(result.value.source, result.value.result.page.nextCursor);
        } else {
          failures.push(pending[index] + ': ' + errorMessage(result.reason));
        }
      }
      setItems((value) => (more ? [...value, ...fresh] : fresh));
      setCursor([...cursors.current.values()].some(Boolean) ? 'multiple' : null);
      setError(failures.join(' · '));
      setMessage(fresh.length ? t('已返回出处候选，请核对原站信息。') : t('该服务没有找到匹配候选。'));
    } catch (reason) {
      if (id === generation.current && !abort.signal.aborted) {
        setError(errorMessage(reason));
        setMessage('');
      }
    } finally {
      if (id === generation.current) setBusy(false);
    }
  };

  const safeUrl = (value?: string) => {
    try {
      const url = new URL(value ?? '');
      return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password ? url.toString() : undefined;
    } catch {
      return undefined;
    }
  };

  return (
    <section
      className="reverse-search"
      tabIndex={0}
      aria-label={t('图片反搜')}
      onDragOver={(event) => event.preventDefault()}
      onDrop={(event) => {
        event.preventDefault();
        const next = event.dataTransfer.files[0];
        if (next) openCropFor(next);
      }}
      onPaste={(event) => {
        const next = Array.from(event.clipboardData.files).find((item) => item.type.startsWith('image/'));
        if (next) {
          event.preventDefault();
          openCropFor(next);
        }
      }}
    >
      <p>{t('候选只用于核对出处，可拖拽或粘贴图片，裁剪主体后再上传检索。')}</p>

      {available.length > 1 ? (
        <div className="action-row" style={{ flexBasis: '100%', margin: 0 }}>
          {(
            [
              ['all', '全部引擎'],
              ['illust', '二次元插画'],
              ['manga', '漫画本子'],
              ['anime', '番剧动画'],
              ['general', '通用引擎'],
            ] as const
          ).map(([group, label]) => (
            <button key={group} type="button" className="chip" disabled={busy} onClick={() => selectGroup(group)}>
              {t(label)}
            </button>
          ))}
        </div>
      ) : null}

      <div className="multi-pill-group" style={{ flexBasis: '100%' }}>
        {available.map((item) => {
          const checked = chosenSources.includes(item.source) || (!chosenSources.length && source === item.source);
          return (
            <button
              key={item.source}
              type="button"
              className={`chip ${checked ? 'active' : ''}`}
              aria-pressed={checked}
              disabled={busy}
              onClick={() => {
                cancel();
                setSource('');
                setChosenSources((prev) => {
                  const seed = prev.length ? prev : source ? [source] : [];
                  return seed.includes(item.source) ? seed.filter((x) => x !== item.source) : [...seed, item.source];
                });
              }}
            >
              {String(item.manifest?.name ?? item.source)}
            </button>
          );
        })}
      </div>

      <div className="action-row" style={{ flexBasis: '100%', margin: 0 }}>
        <FilePicker
          label={t('选择图片')}
          id="reverse-search-file"
          accept="image/png,image/jpeg,image/webp,image/gif"
          onChange={(event) => {
            const next = event.target.files?.[0];
            if (next) openCropFor(next);
            event.target.value = '';
          }}
        />
        {file ? (
          <button type="button" className="chip" onClick={() => setRawCropFile(file)}>
            {t('重新裁剪')}
          </button>
        ) : null}
        <button
          className="primary-link"
          disabled={busy || !file || (!source && !chosenSources.length)}
          onClick={() => void submit()}
        >
          {t('搜索图片')}
        </button>
        {busy ? (
          <button
            className="chip"
            onClick={() => {
              cancel();
              setMessage(t('本次反搜已取消，可重新提交。'));
            }}
          >
            {t('取消反搜')}
          </button>
        ) : null}
      </div>

      {preview ? <img className="reverse-preview" src={preview} alt={t('本次反搜图片预览')} /> : null}
      <ReverseHistory file={file} source={source || chosenSources[0]} onLoadFile={(f) => void acceptPreparedFile(f)} />

      <ImageCropModal
        file={rawCropFile}
        open={Boolean(rawCropFile)}
        onCancel={() => setRawCropFile(undefined)}
        onConfirm={(cropped) => {
          setRawCropFile(undefined);
          void acceptPreparedFile(cropped);
        }}
      />

      {services.error ? (
        <StatusMessage tone="danger" title={t('反搜服务读取失败')}>
          {errorMessage(services.error)}
        </StatusMessage>
      ) : !services.loading && !available.length ? (
        <StatusMessage title={t('暂无可用反搜服务')}>
          {t('请先在站点管理中安装并启用支持图片反搜的服务。')}
        </StatusMessage>
      ) : null}
      {message ? <p role="status">{message}</p> : null}
      {error ? (
        <StatusMessage tone="danger" title={t('反搜失败')}>
          {error}
        </StatusMessage>
      ) : null}

      {items.length ? (
        <div className="reverse-results">
          {items.map((item, index) => {
            const href = item.keyword ? '/search?q=' + encodeURIComponent(item.keyword) + '&scope=all' : undefined;
            const original = safeUrl(item.url);
            return (
              <article className="feed-item" key={item.source + ':' + index}>
                <h3>{item.title}</h3>
                <p>
                  {sourceNames[item.source] ?? item.source}
                  {item.similarity === undefined ? '' : t(' · 相似度 ') + item.similarity + '%'}
                  {item.uncertain ? t(' · 匹配结果不确定') : ''}
                </p>
                {item.description ? <p>{item.description}</p> : null}
                {item.episode !== undefined ? (
                  <p>
                    {t('集数：')}
                    {item.episode}
                  </p>
                ) : null}
                {item.from !== undefined || item.to !== undefined ? (
                  <p>
                    {t('时间片段：')}
                    {item.from ?? t('未知')}–{item.to ?? t('未知')}
                    {t('秒')}
                  </p>
                ) : null}
                <div className="action-row">
                  {href ? (
                    <a className="chip" href={href} onClick={(event) => navigateClick(event, navigate, href)}>
                      {t('继续搜索：')}
                      {item.keyword}
                    </a>
                  ) : null}
                  {original ? (
                    <a className="chip" href={original} target="_blank" rel="noreferrer">
                      {t('打开原站信息')}
                    </a>
                  ) : null}
                </div>
                {item.images?.length ? (
                  <div className="reverse-candidate-images">
                    {item.images.map((image, imageIndex) => (
                      <figure key={imageIndex} className="reverse-candidate-image">
                        <button
                          type="button"
                          className="work-preview-button"
                          onClick={() =>
                            setLightbox({
                              title: item.title,
                              index: imageIndex,
                              items: item.images!.map((img, i) => ({
                                id: String(i),
                                type: 'image',
                                authorization: img.mediaAuthorization,
                                caption: img.label,
                              })),
                            })
                          }
                        >
                          <CoverImage authorization={image.mediaAuthorization} alt={image.label ?? t('候选相关图片')} />
                        </button>
                        <figcaption>
                          {image.label ?? t('相关图片')}
                          {image.similarity === undefined ? '' : ' · ' + image.similarity + '%'}
                        </figcaption>
                      </figure>
                    ))}
                  </div>
                ) : null}
                {item.details ? (
                  <details>
                    <summary>{t('原站信息')}</summary>
                    <pre className="diagnostics" tabIndex={0} role="region" aria-label={t('详细信息')}>
                      {JSON.stringify(item.details, null, 2)}
                    </pre>
                  </details>
                ) : null}
              </article>
            );
          })}
        </div>
      ) : null}
      {cursor ? (
        <button className="chip" disabled={busy} onClick={() => void submit(true)}>
          {t('查看全部结果')}
        </button>
      ) : null}

      {lightbox ? (
        <MediaLightboxModal
          open={Boolean(lightbox)}
          title={lightbox.title}
          items={lightbox.items}
          index={lightbox.index}
          onIndexChange={(next) => setLightbox((prev) => (prev ? { ...prev, index: next } : prev))}
          onClose={() => setLightbox(undefined)}
        />
      ) : null}
    </section>
  );
}

const searchCacheStore = new Map<
  string,
  { items: ApiWork[]; sources: Array<{ source: string; status: string; code?: string }>; nextCursor?: string | null }
>();

export function SearchPage({
  selection,
  initialKeywords,
  initialQuery,
  initialScope,
  initialSource,
  initialCursor,
  initialLimit,
  initialView,
  initialFilters: routeFilters,
  navigate,
}: {
  selection: string;
  initialKeywords: string;
  initialQuery: string;
  initialScope: string;
  initialSource: string;
  initialCursor: string;
  initialLimit: number;
  initialView: 'grid' | 'list' | 'grouped';
  initialFilters: string;
  navigate: (to: string) => void;
}) {
  const shared = useSharedState();
  const sourceCatalog = useContext(SourceCatalog);
  const sourceNames = useContext(SourceNames);
  const dateParams = new URLSearchParams(window.location.search);
  const prefs = usePreferences();
  const presets = (prefs.settings.rememberedFilters ?? {}) as Record<string,string>;
  const applied = initialSource && !['from','to','filters'].some(key => dateParams.has(key)) ?
    new URLSearchParams(presets[JSON.stringify([initialSource,null])]) : dateParams;
  const initialFilters = routeFilters || applied.get('filters') || '';
  const from = applied.get('from') ?? '';
  const to = applied.get('to') ?? '';
  const manifest = sourceCatalog.data?.find(item => item.source === initialSource)?.manifest;
  const sourceLabel = (id: string) => sourceNames[id] ?? id;
  const searchKey = JSON.stringify([
    selection,
    initialKeywords,
    initialQuery,
    initialScope,
    initialSource,
    initialCursor,
    initialLimit,
    initialFilters,
  ]);
  const previous = searchCacheStore.get(searchKey);
  const [execution, setExecution] = useState(0);
  const [nextCursor, setNextCursor] = useState<string | null | undefined>(previous?.nextCursor);
  const [view, setView] = useState(initialView);
  const [loadedResults, setResults] = useState<ApiWork[]>(previous?.items ?? []);
  const results = from || to ? loadedResults.filter(work => withinWorkDates(work, from, to)) : loadedResults;
  const [sourceResults, setSourceResults] = useState<Array<{ source: string; status: string; code?: string }>>(
    previous?.sources ?? [],
  );
  const [loading, setLoading] = useState(false);
  const [streamingProgress, setStreamingProgress] = useState<{ done: number; total: number }>();
  const [error, setError] = useState<unknown>();
  const [cancelled, setCancelled] = useState(false);
  const generation = useRef(0);
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    setView(initialView);
  }, [initialView]);

  useEffect(() => {
    abortRef.current?.abort();
    setCancelled(false);
    setNextCursor(previous?.nextCursor);
    setError(undefined);
    setStreamingProgress(undefined);
    if (!previous) {
      setResults([]);
      setSourceResults([]);
    }
    let filters: WorkTag['filters'];
    try {
      if (initialFilters) {
        const parsed = JSON.parse(initialFilters);
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error(t('筛选条件必须是对象'));
        filters = parsed;
      }
    } catch {
      setError(new Error(t('URL筛选条件无效，请清除筛选后重试')));
      setLoading(false);
      return;
    }
    if (!initialQuery.trim() && (!filters || !Object.keys(filters).length)) {
      setLoading(false);
      return;
    }
    let keywords: string[] | undefined;
    try {
      if (initialKeywords) {
        const values = JSON.parse(initialKeywords);
        if (
          !Array.isArray(values) ||
          values.length > 8 ||
          values.some((value) => typeof value !== 'string' || !value || value.length > 512)
        ) {
          throw Error();
        }
        keywords = values;
      }
    } catch {
      setError(new Error(t('多语言关键词无效')));
      setLoading(false);
      return;
    }

    const controller = new AbortController();
    abortRef.current = controller;
    const current = ++generation.current;
    const parsedSelection = JSON.parse(selection) as { sources?: string[]; mediaKind?: string; category?: string };

    /* Concurrent per-source streaming fan-out when aggregating across multiple sites in grouped mode! */
    const eligibleMultiSources =
      !initialSource && !initialCursor && view === 'grouped' && sourceCatalog.data?.length
        ? sourceCatalog.data
            .filter((item) => {
              if (!item.enabled || item.installed === false) return false;
              const caps = (item.manifest?.capabilities ?? {}) as Record<string, unknown>;
              if (initialScope === 'metadata' ? caps.metadataSearch !== true : caps.search !== true || item.manifest?.metadataOnly) {
                return false;
              }
              if (parsedSelection.sources?.length && !parsedSelection.sources.includes(item.source)) return false;
              if (parsedSelection.category && item.manifest?.category !== parsedSelection.category) return false;
              return true;
            })
            .map((item) => item.source)
        : [];

    if (eligibleMultiSources.length > 1) {
      setLoading(true);
      setStreamingProgress({ done: 0, total: eligibleMultiSources.length });
      const accumulatedItems: ApiWork[] = [];
      const accumulatedSources: Array<{ source: string; status: string; code?: string }> = [];
      let idx = 0;
      let done = 0;
      const runWorker = async () => {
        while (idx < eligibleMultiSources.length && !controller.signal.aborted) {
          const src = eligibleMultiSources[idx++]!;
          try {
            const res = await api.search(
              {
                query: initialQuery,
                keywords,
                filters,
                scope: initialScope,
                source: src,
                mediaKind: parsedSelection.mediaKind,
                limit: 12,
                requestGeneration: current,
              },
              controller.signal,
            );
            if (controller.signal.aborted || current !== generation.current) return;
            if (res.items?.length) accumulatedItems.push(...res.items);
            const statuses = Array.isArray(res.sources) ? (res.sources as Array<{ source: string; status: string; code?: string }>) : [];
            accumulatedSources.push(...statuses);
          } catch (err) {
            if (controller.signal.aborted || current !== generation.current) return;
            accumulatedSources.push({
              source: src,
              status: 'error',
              code: (err as { code?: string })?.code ?? 'NETWORK',
            });
          } finally {
            done++;
            if (!controller.signal.aborted && current === generation.current) {
              setStreamingProgress({ done, total: eligibleMultiSources.length });
              setResults([...accumulatedItems]);
              setSourceResults([...accumulatedSources]);
            }
          }
        }
      };
      void Promise.all(Array.from({ length: Math.min(4, eligibleMultiSources.length) }, () => runWorker())).finally(() => {
        if (!controller.signal.aborted && current === generation.current) {
          searchCacheStore.set(searchKey, { items: accumulatedItems, sources: accumulatedSources, nextCursor: null });
          setLoading(false);
          setStreamingProgress(undefined);
        }
      });
      return () => controller.abort();
    }

    setLoading(true);
    void api
      .search(
        {
          ...parsedSelection,
          query: initialQuery,
          keywords,
          filters,
          scope: initialScope,
          source: initialSource || undefined,
          cursor: initialCursor || undefined,
          limit: initialLimit,
          requestGeneration: current,
        },
        controller.signal,
      )
      .then((value) => {
        if (!controller.signal.aborted && current === generation.current) {
          const items = value.items ?? [];
          const sources = Array.isArray(value.sources)
            ? (value.sources as Array<{ source: string; status: string; code?: string }>)
            : [];
          searchCacheStore.set(searchKey, { items, sources, nextCursor: value.page?.nextCursor });
          setResults(items);
          setNextCursor(value.page?.nextCursor);
          setSourceResults(sources);
        }
      })
      .catch((reason) => {
        if (!controller.signal.aborted && current === generation.current) setError(reason);
      })
      .finally(() => {
        if (!controller.signal.aborted && current === generation.current) setLoading(false);
      });
    return () => controller.abort();
  }, [selection, initialQuery, initialKeywords, initialScope, initialSource, initialCursor, initialLimit, initialFilters, execution]);

  const submitUrl = (
    queryValue: string,
    scope = initialScope,
    source = initialSource,
    cursor = '',
    limit = initialLimit,
    nextView = view,
    filters = initialFilters,
  ) =>
    '/search?q=' +
    encodeURIComponent(queryValue) +
    '&scope=' +
    encodeURIComponent(scope) +
    '&source=' +
    encodeURIComponent(source) +
    (from ? '&from=' + encodeURIComponent(from) : '') + (to ? '&to=' + encodeURIComponent(to) : '') +
    (cursor ? '&cursor=' + encodeURIComponent(cursor) : '') +
    '&limit=' +
    String(limit) +
    '&view=' +
    encodeURIComponent(nextView) +
    (filters ? '&filters=' + encodeURIComponent(filters) : '') +
    (queryValue === initialQuery && initialKeywords ? '&keywords=' + encodeURIComponent(initialKeywords) : '') +
    searchSelectionQuery();

  const executeOrNavigate = (to: string) => {
    const params = new URL(to, window.location.origin).searchParams;
    if (
      params.get('q') === initialQuery &&
      params.get('scope') === initialScope &&
      (params.get('source') ?? '') === initialSource &&
      (params.get('cursor') ?? '') === initialCursor &&
      Number(params.get('limit')) === initialLimit &&
      params.get('view') === initialView &&
      (params.get('filters') ?? '') === initialFilters
    ) {
      setExecution((value) => value + 1);
    } else navigate(to);
  };

  const clear = () => {
    abortRef.current?.abort();
    setResults([]);
    setSourceResults([]);
    setNextCursor(undefined);
    setError(undefined);
    setLoading(false);
    setCancelled(false);
    if (shared.incognito === false) {
      try {
        sessionStorage.removeItem('hp-last-search');
      } catch {
        /* ignore */
      }
    }
    navigate(submitUrl(''));
  };

  const restore = () => {
    if (shared.incognito !== false) return;
    try {
      const value = JSON.parse(sessionStorage.getItem('hp-last-search') ?? 'null') as {
        q?: string;
        scope?: string;
        source?: string;
        view?: string;
        filters?: string;
      } | null;
      if (value?.q) {
        executeOrNavigate(
          submitUrl(
            value.q,
            value.scope ?? 'all',
            value.source ?? '',
            '',
            initialLimit,
            value.view === 'grouped' ? 'grouped' : value.view === 'grid' ? 'grid' : value.view === 'list' ? 'list' : 'grouped',
            value.filters ?? '',
          ),
        );
      }
    } catch {
      /* ignore */
    }
  };

  const setViewInUrl = (next: 'grid' | 'list' | 'grouped') => {
    setView(next);
    navigate(submitUrl(initialQuery, initialScope, initialSource, initialCursor, initialLimit, next));
  };

  const scopeHref = (scope: string) => submitUrl(initialQuery, scope);
  const nextHref = nextCursor ? submitUrl(initialQuery, initialScope, initialSource, nextCursor) : undefined;
  const firstHref = submitUrl(initialQuery);

  if (new URLSearchParams(window.location.search).get('mode') === 'reverse') {
    return (
      <>
        <PageHeader title={t('图片反搜')}>
          <a className="navigation-link" href="/search" onClick={(event) => navigateClick(event, navigate, '/search')}>
            {t('搜索')}
          </a>
        </PageHeader>
        <section id="reverse-search">
          <ReverseSearch navigate={navigate} />
        </section>
      </>
    );
  }

  return (
    <div className="search-page">
      <PageHeader title={t('搜索')} description={t('提交关键词后并发查询各站点，命中结果实时流式呈现。')}>
        <SearchBox
          navigate={navigate}
          initial={initialQuery}
          scope={initialScope}
          source={initialSource}
          view={view}
          filters={initialFilters}
          onSearch={(queryValue) => executeOrNavigate(submitUrl(queryValue))}
        />
      </PageHeader>

      {initialSource && manifest ? <details className="browse-tools"><summary>{t('筛选')}</summary>
        <SourceSearchForm source={initialSource} manifest={manifest} navigate={navigate} results />
      </details> : null}
      <p className="search-scope-label">
        {t('搜索范围：')}
        {(initialSource ? sourceLabel(initialSource) : '') ||
          JSON.parse(selection).sources?.map(sourceLabel).join('、') ||
          (JSON.parse(selection).category
            ? t(categoryLabels[JSON.parse(selection).category] ?? JSON.parse(selection).category)
            : t('全部已启用站点'))}
        {streamingProgress ? ` · ${streamingProgress.done} / ${streamingProgress.total}` : ''}
      </p>

      <details
        className="browse-tools search-options"
        open={Boolean(initialFilters) || new URLSearchParams(window.location.search).get('mode') === 'reverse'}
      >
        <summary>{t('更多')}</summary>
        <SearchScope navigate={navigate} />
        <details className="browse-tools" id="reverse-search" open={new URLSearchParams(window.location.search).get('mode') === 'reverse'}>
          <summary>{t('以图搜图')}</summary>
          <ReverseSearch navigate={navigate} />
        </details>
        <div className="filter-row">
          <button className="chip" type="button" disabled={shared.incognito !== false} onClick={restore}>
            {t('恢复上次搜索')}
          </button>
          {shared.incognito === true ? <span className="filter-label">{t('无痕模式不保存或恢复最近搜索')}</span> : null}
          <button className="chip" type="button" onClick={clear}>
            {t('清空结果')}
          </button>
          {loading ? (
            <button
              className="chip"
              type="button"
              onClick={() => {
                abortRef.current?.abort();
                setLoading(false);
                setStreamingProgress(undefined);
                setCancelled(true);
              }}
            >
              {t('取消搜索')}
            </button>
          ) : null}
        </div>
        <div className="filter-row" role="group" aria-label={t('范围')}>
          {initialFilters ? (
            <a
              className="chip"
              href={submitUrl(initialQuery, initialScope, initialSource, '', initialLimit, view, '')}
              onClick={(event) =>
                navigateClick(event, navigate, submitUrl(initialQuery, initialScope, initialSource, '', initialLimit, view, ''))
              }
            >
              {t('清除来源筛选')}
            </a>
          ) : null}
          <a
            href={scopeHref('all')}
            className={'chip ' + (initialScope === 'all' ? 'active' : '')}
            onClick={(event) => navigateClick(event, navigate, scopeHref('all'))}
          >
            {t('全部内容')}
          </a>
          <a
            href={scopeHref('title')}
            className={'chip ' + (initialScope === 'title' ? 'active' : '')}
            onClick={(event) => navigateClick(event, navigate, scopeHref('title'))}
          >
            {t('标题')}
          </a>
          {(
            [
              ['summary', t('简介')],
              ['id', t('编号')],
              ['link', t('链接')],
              ['metadata', t('资料')],
            ] as const
          ).map(([scope, label]) => (
            <a
              key={scope}
              className={'chip ' + (initialScope === scope ? 'active' : '')}
              href={scopeHref(scope)}
              onClick={(event) => navigateClick(event, navigate, scopeHref(scope))}
            >
              {label}
            </a>
          ))}
        </div>
      </details>

      <div className="filter-row">
        <Button aria-pressed={view === 'grouped'} onClick={() => setViewInUrl('grouped')}>
          {t('站点分组')}
        </Button>
        <Button aria-pressed={view === 'grid'} onClick={() => setViewInUrl('grid')}>
          {t('网格')}
        </Button>
        <Button aria-pressed={view === 'list'} onClick={() => setViewInUrl('list')}>
          {t('列表')}
        </Button>
      </div>

      {cancelled ? <StatusMessage title={t('搜索已取消')}>{t('可以重新提交当前关键词。')}</StatusMessage> : null}
      {sourceResults
        .filter((source) => source.status === 'error')
        .map((source) => (
          <StatusMessage
            key={source.source}
            tone="warning"
            title={
              sourceLabel(source.source) +
              ' · ' +
              (/AUTH|LOGIN/.test(source.code ?? '')
                ? t('需要站点登录')
                : /VERIF|CHALLENGE|CONFIRM|CLOUDFLARE/.test(source.code ?? '')
                  ? t('需要站点验证')
                  : t('站点查询失败'))
            }
          >
            <span>{source.code ?? t('未知错误')}</span>
            <a
              href={'/source/' + encodeURIComponent(source.source)}
              onClick={(event) => navigateClick(event, navigate, '/source/' + encodeURIComponent(source.source))}
            >
              {t('查看站点')}
            </a>
            <button className="chip" onClick={() => setExecution((value) => value + 1)}>
              {t('重新查询')}
            </button>
          </StatusMessage>
        ))}

      {error ? (
        <button className="chip" onClick={() => setExecution((value) => value + 1)}>
          {t('重试当前搜索')}
        </button>
      ) : null}

      <StateView
        loading={loading && !results.length}
        error={error}
        empty={!loading && !error && !cancelled && Boolean(initialQuery || initialFilters) && !results.length}
        emptyDetail={t('没有匹配结果，可修改关键词或筛选条件后重试。')}
      >
        {view === 'grouped'
          ? [...new Set(results.map((work) => work.source))].map((src) => {
              const groupItems = results.filter((work) => work.source === src);
              const fullSourceHref = submitUrl(initialQuery, initialScope, src, '', initialLimit, 'grid', initialFilters);
              return (
                <section className="section-block" key={src} aria-label={sourceLabel(src)}>
                  <div className="section-header" style={{ marginBottom: 12 }}>
                    <h2 style={{ margin: 0 }}>{sourceLabel(src)}</h2>
                    <a href={fullSourceHref} onClick={(e) => navigateClick(e, navigate, fullSourceHref)}>
                      {t('查看此站全部')} ({groupItems.length}+)
                    </a>
                  </div>
                  <ContentShelf
                    local
                    heading={false}
                    shelf={{ key: src, source: src, title: sourceLabel(src), items: groupItems }}
                    navigate={navigate}
                    renderItem={(work) => <WorkCard work={work} navigate={navigate} />}
                  />
                </section>
              );
            })
          : <WorkGrid items={results} view={view} navigate={navigate} />}
      </StateView>

      <nav className="action-row" aria-label={t('搜索分页')}>
        {initialCursor ? (
          <a className="chip" href={firstHref} onClick={(event) => navigateClick(event, navigate, firstHref)}>
            {t('返回首页')}
          </a>
        ) : null}
        {!loading && !cancelled && !error && nextHref ? (
          <a className="chip" href={nextHref} onClick={(event) => navigateClick(event, navigate, nextHref)}>
            {t('下一页')}
          </a>
        ) : null}
      </nav>
    </div>
  );
}
