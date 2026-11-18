import { useEffect, useMemo, useState } from 'react';
import { AdaptiveSheet } from '@hentai-park/design-system';
import { api, type ApiWork, type LibraryEntry, type Source } from './api.js';
import { CoverImage } from './cover-image.js';
import { t } from './i18n.js';
import { errorMessage } from './page-ui.js';

export function LibraryMigration({
  items,
  works,
  sources,
  categories: _categories,
  onComplete,
}: {
  items: LibraryEntry[];
  works: ApiWork[];
  sources: Source[];
  categories: Record<string, string>;
  onComplete: (failed: LibraryEntry[]) => void;
}) {
  const [open, setOpen] = useState(false);
  const [index, setIndex] = useState(0);
  const [keyword, setKeyword] = useState('');
  const [source, setSource] = useState('__all__');
  const [results, setResults] = useState<ApiWork[]>([]);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [copyCategories, setCopyCategories] = useState(true);
  const [copyProgress, setCopyProgress] = useState(true);
  const [removeOld, setRemoveOld] = useState(true);
  const [failed, setFailed] = useState<LibraryEntry[]>([]);

  const current = items[index];
  const currentWork = works.find((work) => work.source === current?.source && work.workId === current?.workId);
  const targets = useMemo(
    () =>
      sources.filter(
        (item) =>
          item.enabled &&
          item.installed !== false &&
          item.source !== current?.source &&
          Boolean((item.manifest?.capabilities as Record<string, unknown> | undefined)?.search) &&
          Boolean((item.manifest?.capabilities as Record<string, unknown> | undefined)?.detail),
      ),
    [sources, current?.source],
  );

  useEffect(() => {
    if (open && current) {
      setKeyword(currentWork?.title ?? current.workId);
      setSource('__all__');
      setResults([]);
      setNotice('');
      setError('');
    }
  }, [open, index, current?.source, current?.workId]);

  const search = async () => {
    if (!keyword.trim() || !targets.length) return;
    setLoading(true);
    setError('');
    setResults([]);
    try {
      if (source === '__all__') {
        const queue = [...targets];
        const gathered: ApiWork[] = [];
        const runWorker = async () => {
          while (queue.length) {
            const targetSrc = queue.shift()!;
            try {
              const res = await api.search({
                query: keyword.trim(),
                scope: 'all',
                source: targetSrc.source,
                mediaKind: currentWork?.mediaKind,
                limit: 8,
              });
              if (res.items.length) {
                gathered.push(...res.items);
                setResults([...gathered]);
              }
            } catch {
              /* Ignore individual source errors during fan-out */
            }
          }
        };
        await Promise.all(Array.from({ length: Math.min(4, targets.length) }, () => runWorker()));
      } else {
        const value = await api.search({
          query: keyword.trim(),
          scope: 'all',
          source,
          mediaKind: currentWork?.mediaKind,
          limit: 20,
        });
        setResults(value.items);
      }
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setLoading(false);
    }
  };

  const migrate = async (target: ApiWork) => {
    if (!current || busy) return;
    setBusy(true);
    setError('');
    try {
      await api.work(target.source, target.workId);
      const result = await api.migrateLibrary({
        fromSource: current.source,
        fromWorkId: current.workId,
        toSource: target.source,
        toWorkId: target.workId,
        categories: copyCategories,
        progress: copyProgress,
        removeOld,
      });
      setFailed((value) => value.filter((item) => item !== current));
      setNotice(
        result.removed
          ? t('已迁移到新的站点')
          : result.unmatched
            ? t('已复制到新的站点；未匹配的进度保留在原收藏中')
            : t('已复制到新的站点'),
      );
      const nextIndex = index + 1;
      if (nextIndex >= items.length) {
        onComplete(failed.filter((item) => item !== current));
        setOpen(false);
      } else {
        setIndex(nextIndex);
        setResults([]);
      }
    } catch (reason) {
      setFailed((value) => [...value.filter((item) => item !== current), current]);
      setError(errorMessage(reason));
    } finally {
      setBusy(false);
    }
  };

  if (!items.length) return null;

  return (
    <>
      <button
        className="chip"
        disabled={busy}
        onClick={() => {
          setFailed([]);
          setIndex(0);
          setOpen(true);
        }}
      >
        {t('迁移到其他站点')}
      </button>

      <AdaptiveSheet
        open={open}
        title={t('迁移到其他站点')}
        closeLabel={t('取消')}
        onClose={() => {
          if (!busy) setOpen(false);
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 16 }}>
          {currentWork?.coverAuthorization ? (
            <div style={{ width: 64, aspectRatio: '3 / 4', borderRadius: 8, overflow: 'hidden', flexShrink: 0 }}>
              <CoverImage authorization={currentWork.coverAuthorization} alt={currentWork.title} />
            </div>
          ) : null}
          <div>
            <strong>
              {t('第 {value0}/{value1} 项', { value0: index + 1, value1: items.length })} · {currentWork?.title ?? current?.workId}
            </strong>
            <p className="muted" style={{ margin: '4px 0 0', fontSize: 12 }}>
              {current?.source}
            </p>
          </div>
        </div>

        <div className="form-row">
          <label>
            {t('目标站点')}
            <select value={source} disabled={busy} onChange={(event) => setSource(event.target.value)}>
              <option value="__all__">{t('全部可用站点（并发检索）')}</option>
              {targets.map((item) => (
                <option key={item.source} value={item.source}>
                  {String(item.manifest?.name ?? item.source)}
                </option>
              ))}
            </select>
          </label>
          <label style={{ flex: 1 }}>
            {t('搜索标题')}
            <input
              value={keyword}
              disabled={busy}
              onChange={(event) => setKeyword(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Enter') {
                  event.preventDefault();
                  void search();
                }
              }}
            />
          </label>
          <button
            className="primary-link"
            disabled={busy || loading || !targets.length || !keyword.trim()}
            onClick={() => void search()}
          >
            {loading ? t('正在搜索…') : t('搜索')}
          </button>
        </div>

        <fieldset disabled={busy}>
          <legend>{t('迁移选项')}</legend>
          <label>
            <input type="checkbox" checked={copyCategories} onChange={(event) => setCopyCategories(event.target.checked)} />
            {t('复制分类')}
          </label>
          <label>
            <input type="checkbox" checked={copyProgress} onChange={(event) => setCopyProgress(event.target.checked)} />
            {t('复制阅读与播放进度')}
          </label>
          <label>
            <input type="checkbox" checked={removeOld} onChange={(event) => setRemoveOld(event.target.checked)} />
            {t('迁移成功后取消原收藏')}
          </label>
        </fieldset>

        {error ? <p role="alert">{error}</p> : null}
        {notice ? <p role="status">{notice}</p> : null}

        <ul className="chapter-list">
          {results.map((result) => (
            <li key={result.source + ':' + result.workId} style={{ gap: 12 }}>
              {result.coverAuthorization ? (
                <div style={{ width: 52, aspectRatio: '3 / 4', borderRadius: 8, overflow: 'hidden', flexShrink: 0 }}>
                  <CoverImage authorization={result.coverAuthorization} alt={result.title} />
                </div>
              ) : null}
              <span style={{ flex: 1 }}>
                <strong>{result.title}</strong>
                <small className="chapter-state">
                  {String(sources.find((s) => s.source === result.source)?.manifest?.name ?? result.source)}
                  {result.pages ? ` · ${result.pages}P` : ''}
                </small>
              </span>
              <button className="primary-link" disabled={busy} onClick={() => void migrate(result)}>
                {t('选择并迁移')}
              </button>
            </li>
          ))}
        </ul>
        {!loading && !results.length ? <p>{t('搜索其他站点以选择匹配作品。')}</p> : null}
      </AdaptiveSheet>
    </>
  );
}
