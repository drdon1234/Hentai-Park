import { useContext, useEffect, useRef, useState } from 'react';
import { EmptyState, SegmentedTabs, StatusMessage, confirmAction } from '@hentai-park/design-system';
import { chapterIdentityKey, workIdentityKey } from '@hentai-park/domain-model';
import { allPages, api, request, type ApiWork, type LibraryEntry } from '../api.js';
import { CategoryNames, SourceNames, identityMatches, navigateClick } from '../app/app-context.js';
import { CategoryEditor } from '../collection-controls.js';
import { CoverImage } from '../cover-image.js';
import { LibraryManagement } from '../data-controls.js';
import { t } from '../i18n.js';
import { LibraryBatch } from '../library-batch.js';
import { LibraryMigration } from '../library-migration.js';
import { useSharedState } from '../native.js';
import { PageHeader, StateView, errorMessage, useAsync, useServerVersion } from '../page-ui.js';
import { PreferenceFields } from '../preference-fields.js';
import { usePreferences } from '../preferences.js';
import { WorkGrid } from '../shared/work-card.js';

export function LibraryPage({
  navigate,
  view,
  category,
}: {
  navigate: (to: string) => void;
  view: 'favorites' | 'history' | 'continue' | 'recent';
  category: string;
}) {
  const prefs = usePreferences();
  const p = prefs.settings;
  const shared = useSharedState();
  const categoryNames = useContext(CategoryNames);
  const sourceNames = useContext(SourceNames);
  const historyCategories = new URLSearchParams(window.location.search).get('categories') ?? undefined;
  const version = useServerVersion();
  const [checking, setChecking] = useState(false);
  const [checkMessage, setCheckMessage] = useState('');

  const state = useAsync(
    async (signal) => {
      const [library, history, works] = await Promise.all([
        allPages(api.library),
        allPages((params) => api.history({ ...params, categories: historyCategories })),
        request<{ items: ApiWork[] }>('/api/v1/library/works', { signal }),
      ]);
      return { library, history, works: works.items, failures: 0 };
    },
    [version, historyCategories],
  );
  const updatesFeed = useAsync(
    (signal) => (view === 'recent' ? api.libraryUpdates({ limit: 100 }, signal) : Promise.resolve(undefined)),
    [view, version],
  );
  const sourceState = useAsync(() => allPages(api.sources), [version]);

  const checkUpdates = async () => {
    setChecking(true);
    setCheckMessage('');
    try {
      const result = await request<{ checked: number; updated: number; failed?: number }>('/api/v1/library/check-updates', {
        method: 'POST',
        body: '{}',
      });
      setCheckMessage(`${t('检查完成')} · ${result.checked} / +${result.updated}`);
      window.dispatchEvent(new Event('hp:invalidate'));
    } catch (reason) {
      setCheckMessage(errorMessage(reason));
    } finally {
      setChecking(false);
    }
  };

  const previous = useRef<typeof state.data>(undefined);
  if (state.data) previous.current = state.data;
  const data = state.data ?? previous.current;

  const params = new URLSearchParams(window.location.search);
  const display = params.get('display') ?? String(p[view === 'history' || view === 'continue' ? 'historyDisplay' : 'libraryDisplay']);
  const sort = params.get('sort') ?? String(p.librarySort);
  const ascending = p.librarySortAsc === true;
  const filter = params.get('q') ?? '';
  const requestedPage = Number(params.get('page'));
  const page = Number.isSafeInteger(requestedPage) && requestedPage > 0 ? requestedPage : 1;
  const pageSize = 24;

  const url = (patch: Record<string, string>) => {
    const next = new URLSearchParams(window.location.search);
    for (const [key, value] of Object.entries(patch)) {
      if (value) next.set(key, value);
      else next.delete(key);
    }
    return (view === 'history' || view === 'continue' ? '/history' : '/library') + (next.size ? '?' + next.toString() : '');
  };

  const byKey = new Map((data?.works ?? []).map((work) => [workIdentityKey({ source: work.source, id: work.workId }), work]));
  const matches = (item: { source: string; workId: string; workTitle?: string | null }) =>
    !filter ||
    [item.source, item.workId, item.workTitle ?? byKey.get(workIdentityKey({ source: item.source, id: item.workId }))?.title ?? '']
      .join(' ')
      .toLocaleLowerCase()
      .includes(filter.toLocaleLowerCase());

  const sourceFilter = Array.isArray(p.libraryFilterSources) ? (p.libraryFilterSources as string[]) : [];
  const extraMatch = (item: { source: string; workId: string }) => {
    const work = byKey.get(workIdentityKey({ source: item.source, id: item.workId }));
    const hist = (data?.history ?? []).filter((row) => row.source === item.source && row.workId === item.workId);
    return (
      (!sourceFilter.length || sourceFilter.includes(item.source)) &&
      (p.libraryFilterKind === 'all' || work?.mediaKind === p.libraryFilterKind) &&
      (!p.libraryFilterDownloaded ||
        Object.values(shared.downloads).some((row) => identityMatches(row.key, item.source, item.workId) && row.status === 'completed')) &&
      (!p.libraryFilterUnread ||
        (work?.unreadCount != null ? work.unreadCount > 0 : !hist.length || hist.some((row) => row.readState !== 'read')))
    );
  };

  const sortValue = (item: LibraryEntry) => {
    const work = byKey.get(workIdentityKey({ source: item.source, id: item.workId }));
    return sort === 'title'
      ? work?.title ?? item.workId
      : sort === 'read'
        ? (data?.history ?? []).find((row) => row.source === item.source && row.workId === item.workId)?.updatedAt ?? ''
        : sort === 'updated'
          ? work?.contentUpdatedAt ?? item.updatedAt
          : item.favoritedAt ?? item.updatedAt;
  };

  const allRows = (data?.library ?? [])
    .filter((item) => (category ? item.categoryIds.includes(category) : item.favorite))
    .filter(matches)
    .filter(extraMatch)
    .filter((item) => view !== 'recent' || Boolean(byKey.get(workIdentityKey({ source: item.source, id: item.workId }))?.contentUpdatedAt))
    .sort((a, b) => (ascending ? 1 : -1) * sortValue(a).localeCompare(sortValue(b)));

  const rows = allRows.slice((page - 1) * pageSize, page * pageSize);
  const works = rows
    .map((item) => byKey.get(workIdentityKey({ source: item.source, id: item.workId })))
    .filter((item): item is ApiWork => Boolean(item));
  const unavailable = rows.filter((item) => !byKey.has(workIdentityKey({ source: item.source, id: item.workId })));
  const categories = [...new Set((data?.library ?? []).flatMap((item) => item.categoryIds))].sort();

  const history = (data?.history ?? [])
    .filter(matches)
    .filter((item) => view !== 'continue' || (item.readState !== 'read' && (item.pageCount == null || item.page == null || item.page + 1 < item.pageCount)))
    .sort((a, b) =>
      sort === 'title'
        ? (a.workTitle ?? byKey.get(workIdentityKey({ source: a.source, id: a.workId }))?.title ?? a.workId).localeCompare(
            b.workTitle ?? byKey.get(workIdentityKey({ source: b.source, id: b.workId }))?.title ?? b.workId,
            'zh-CN',
          )
        : (b.updatedAt ?? '').localeCompare(a.updatedAt ?? ''),
    );

  const historyMode = view === 'history' || view === 'continue';
  const total = historyMode ? history.length : view === 'recent' ? updatesFeed.data?.items.length ?? 0 : allRows.length;

  const [selected, setSelected] = useState<string[]>([]);
  const [selectionBusy, setSelectionBusy] = useState(false);
  const [selectionError, setSelectionError] = useState('');
  const toggleSelected = (key: string) =>
    setSelected((value) => (value.includes(key) ? value.filter((item) => item !== key) : [...value, key]));

  const removeSelected = async () => {
    if (!selected.length) return;
    const ok = await confirmAction({
      title: t(historyMode ? '删除选中的历史记录？' : '取消收藏选中的作品？'),
      confirmLabel: historyMode ? t('删除历史') : t('移除收藏'),
      danger: true,
    });
    if (!ok) return;
    setSelectionBusy(true);
    setSelectionError('');
    try {
      if (historyMode) {
        await request('/api/v1/history', { method: 'DELETE', body: JSON.stringify({ scopeKeys: selected }) });
        setSelected([]);
      } else {
        const results = await Promise.allSettled(
          selected.map((key) => {
            const item = (data?.library ?? []).find((row) => workIdentityKey({ source: row.source, id: row.workId }) === key);
            return item
              ? api.setLibrary({
                  source: item.source,
                  workId: item.workId,
                  favorite: false,
                  categoryIds: item.categoryIds,
                  version: item.version,
                })
              : Promise.reject(new Error(t('内容已发生变化，请刷新后重试。')));
          }),
        );
        const failed = selected.filter((_, index) => results[index]?.status === 'rejected');
        setSelected(failed);
        if (failed.length) setSelectionError(t('部分操作失败，失败项仍处于选中状态。'));
      }
      window.dispatchEvent(new Event('hp:invalidate'));
    } catch (error) {
      setSelectionError(errorMessage(error));
    } finally {
      setSelectionBusy(false);
    }
  };

  useEffect(() => {
    setSelected([]);
    setSelectionError('');
  }, [historyMode]);

  const distinctLibrarySources = [...new Set((data?.library ?? []).map((row) => row.source))];

  return (
    <>
      {selectionError ? (
        <StatusMessage tone="danger" title={t('操作未完成，请重试。')}>
          {selectionError}
        </StatusMessage>
      ) : null}
      {prefs.busy ? <p role="status">{t('正在保存…')}</p> : null}
      {prefs.error ? <p role="status">{prefs.error}</p> : null}

      <PageHeader title={t(historyMode ? '历史' : '收藏')}>
        <a
          className="chip"
          href={historyMode ? '/library' : '/history'}
          onClick={(event) => navigateClick(event, navigate, event.currentTarget.getAttribute('href')!)}
        >
          {t(historyMode ? '收藏' : '历史')}
        </a>
        <a
          className="chip"
          href="/tavern"
          onClick={(event) => navigateClick(event, navigate, '/tavern')}
        >
          {t('酒馆')}
        </a>
        {historyMode ? (
          <a className="chip" href="#library-management">
            {t('管理历史')}
          </a>
        ) : null}
      </PageHeader>

      {selected.length ? (
        <div className="selection-toolbar action-row" role="toolbar">
          <strong>{t('已选 {value0}', { value0: selected.length })}</strong>
          {!historyMode ? (
            <>
              <LibraryBatch
                items={(data?.library ?? []).filter((item) =>
                  selected.includes(workIdentityKey({ source: item.source, id: item.workId })),
                )}
                categories={categoryNames}
                onComplete={(failed) => setSelected(failed.map((item) => workIdentityKey({ source: item.source, id: item.workId })))}
              />
              <LibraryMigration
                items={(data?.library ?? []).filter((item) =>
                  selected.includes(workIdentityKey({ source: item.source, id: item.workId })),
                )}
                works={data?.works ?? []}
                sources={sourceState.data ?? []}
                categories={categoryNames}
                onComplete={(failed) => setSelected(failed.map((item) => workIdentityKey({ source: item.source, id: item.workId })))}
              />
            </>
          ) : null}
          <button className="chip danger-action" disabled={selectionBusy} onClick={() => void removeSelected()}>
            {historyMode ? t('删除历史') : t('移除收藏')}
          </button>
          <button className="chip" onClick={() => setSelected([])}>
            {t('取消选择')}
          </button>
        </div>
      ) : null}

      <details className="browse-tools" open={historyMode}>
        <summary>{t('分类与历史管理')}</summary>
        <LibraryManagement />
      </details>

      {!historyMode ? (
        <div className="action-row" style={{ alignItems: 'center', justifyContent: 'space-between' }}>
          <SegmentedTabs
            ariaLabel={t('书架视图')}
            value={view === 'recent' ? 'recent' : 'favorites'}
            onChange={(next) => navigate(next === 'recent' ? '/library?view=recent' : '/library')}
            items={[
              { value: 'favorites', label: t('收藏') },
              { value: 'recent', label: t('更新'), badge: updatesFeed.data?.items.length || undefined },
            ]}
          />
          <button className="chip" disabled={checking} onClick={() => void checkUpdates()}>
            {checking ? t('正在检查收藏更新') : t('检查收藏更新')}
          </button>
        </div>
      ) : (
        <label className="history-mode-switch">
          <input
            type="checkbox"
            checked={view === 'continue'}
            onChange={(event) => navigate(url({ mode: event.target.checked ? 'continue' : '', page: '' }))}
          />
          {t('继续阅读')}
        </label>
      )}
      {checkMessage ? <p role="status">{checkMessage}</p> : null}

      <div className="history-toolbar">
        <div className="history-primary-filters">
          <label>
            {t('查找收藏')}
            <input aria-label={t('查找收藏')} value={filter} onChange={(event) => navigate(url({ q: event.target.value, page: '' }))} />
          </label>
          <label>
            {t('排序')}
            <select
              aria-label={t('收藏排序')}
              value={sort}
              onChange={(event) => {
                const value = event.target.value;
                void prefs.save({ librarySort: value }).then(() => navigate(url({ sort: value, page: '' })));
              }}
            >
              <option value="added">{t('收藏时间')}</option>
              <option value="read">{t('阅读时间')}</option>
              <option value="updated">{t('最近更新')}</option>
              <option value="title">{t('标题')}</option>
            </select>
          </label>
          <label>
            {t('视图')}
            <select
              aria-label={t('收藏视图')}
              value={display}
              onChange={(event) => {
                const value = event.target.value;
                void prefs
                  .save({ [historyMode ? 'historyDisplay' : 'libraryDisplay']: value })
                  .then(() => navigate(url({ display: value })));
              }}
            >
              <option value="grid">{t('网格')}</option>
              <option value="list">{t('列表')}</option>
            </select>
          </label>
        </div>
        <details className="history-advanced">
          <summary>{t('筛选与显示')}</summary>
          <div className="history-advanced-fields">
            <PreferenceFields
              keys={['librarySortAsc', 'libraryFilterKind', 'libraryFilterDownloaded', 'libraryFilterUnread']}
              disabled={!prefs.ready}
              settings={p}
              onChange={(patch) => void prefs.save(patch)}
            />
            {distinctLibrarySources.length > 0 ? (
              <div style={{ gridColumn: '1 / -1' }}>
                <small className="muted">{t('站点筛选')}</small>
                <div className="multi-pill-group">
                  {distinctLibrarySources.map((src) => {
                    const active = sourceFilter.includes(src);
                    return (
                      <button
                        key={src}
                        type="button"
                        className={`chip ${active ? 'active' : ''}`}
                        aria-pressed={active}
                        onClick={() =>
                          void prefs.save({
                            libraryFilterSources: active ? sourceFilter.filter((s) => s !== src) : [...sourceFilter, src],
                          })
                        }
                      >
                        {sourceNames[src] ?? src}
                      </button>
                    );
                  })}
                </div>
              </div>
            ) : null}
          </div>
        </details>
      </div>

      {!historyMode && view !== 'recent' ? (
        <div className="filter-row">
          <button
            type="button"
            className={`chip ${!category ? 'active' : ''}`}
            onClick={() => navigate(url({ category: '', page: '' }))}
          >
            {t('全部收藏')}
          </button>
          {categories.map((id) => (
            <button
              key={id}
              type="button"
              className={`chip ${category === id ? 'active' : ''}`}
              onClick={() => navigate(url({ category: id, page: '' }))}
            >
              {categoryNames[id] ?? id}
            </button>
          ))}
        </div>
      ) : null}

      <StateView loading={state.loading && !data} error={data ? undefined : state.error} empty={false}>
        {historyMode ? (
          history.length ? (
            <ul className={'chapter-list ' + (display === 'grid' ? 'history-grid' : '')}>
              {history.slice((page - 1) * pageSize, page * pageSize).map((entry) => {
                const work = byKey.get(workIdentityKey({ source: entry.source, id: entry.workId }));
                const workHref = '/work/' + [entry.source, entry.workId].map(encodeURIComponent).join('/');
                const play = entry.nodeType
                  ? ['audio', 'video'].includes(entry.nodeType)
                  : (entry.mediaKind ?? work?.mediaKind) === 'video' || (entry.mediaKind ?? work?.mediaKind) === 'voice';
                const href = entry.chapterId
                  ? (play ? '/watch/' : '/read/') + [entry.source, entry.workId, entry.chapterId].map(encodeURIComponent).join('/')
                  : workHref;
                const rowKey = entry.chapterId
                  ? chapterIdentityKey({ source: entry.source, workId: entry.workId, chapterId: entry.chapterId })
                  : workIdentityKey({ source: entry.source, id: entry.workId });
                return (
                  <li key={rowKey}>
                    <label>
                      <input type="checkbox" checked={selected.includes(rowKey)} onChange={() => toggleSelected(rowKey)} />
                      <span>
                        <a href={workHref} onClick={(event) => navigateClick(event, navigate, workHref)}>
                          {entry.workTitle ?? work?.title ?? entry.workId}
                        </a>
                        <small className="chapter-state">
                          {entry.chapterTitle ?? entry.chapterId ?? t('作品')}
                          {entry.page !== null && entry.page !== undefined ? t(' · 第') + (entry.page + 1) + t('页') : ''}
                          {entry.position ? ' · ' + Math.floor(entry.position) + t('秒') : ''}
                        </small>
                      </span>
                    </label>
                    <a className="chip" href={href} onClick={(event) => navigateClick(event, navigate, href)}>
                      {play ? t('继续播放') : t('继续阅读')}
                    </a>
                  </li>
                );
              })}
            </ul>
          ) : (
            <EmptyState title={t('暂无历史')} detail={t('浏览过的作品会显示在这里。')} />
          )
        ) : view === 'recent' ? (
          updatesFeed.data?.items.length ? (
            <ul className="chapter-list">
              {updatesFeed.data.items.filter(matches).map((item) => {
                const play = item.mediaKind === 'video' || item.mediaKind === 'voice';
                const chapterHref =
                  (play ? '/watch/' : '/read/') +
                  [item.source, item.workId, item.chapterId].map(encodeURIComponent).join('/');
                const workHref = '/work/' + [item.source, item.workId].map(encodeURIComponent).join('/');
                return (
                  <li key={item.source + ':' + item.workId + ':' + item.chapterId} style={{ gap: 14 }}>
                    {item.coverAuthorization ? (
                      <div style={{ width: 52, aspectRatio: '3 / 4', borderRadius: 8, overflow: 'hidden', flexShrink: 0 }}>
                        <CoverImage authorization={item.coverAuthorization} alt={item.workTitle} allowUnblur />
                      </div>
                    ) : null}
                    <span style={{ flex: 1 }}>
                      <a href={workHref} onClick={(e) => navigateClick(e, navigate, workHref)}>
                        <strong>{item.workTitle}</strong>
                      </a>
                      <small className="chapter-state">
                        {item.chapterTitle} · {sourceNames[item.source] ?? item.source} ·{' '}
                        {new Date(item.updatedAt).toLocaleDateString()}
                      </small>
                    </span>
                    <a className="primary-link" href={chapterHref} onClick={(e) => navigateClick(e, navigate, chapterHref)}>
                      {play ? t('开始播放') : t('开始阅读')}
                    </a>
                  </li>
                );
              })}
            </ul>
          ) : (
            <EmptyState title={t('暂无更新')} detail={t('检查收藏更新后，未读新章节会按时间显示在这里。')} />
          )
        ) : (
          <>
            {works.length ? (
              <WorkGrid
                selection={{ keys: selected, toggle: toggleSelected }}
                items={works}
                view={display === 'list' ? 'list' : 'grid'}
                navigate={navigate}
                manageCollections
              />
            ) : null}
            {unavailable.length ? (
              <ul className="chapter-list">
                {unavailable.map((entry) => (
                  <li key={workIdentityKey({ source: entry.source, id: entry.workId })}>
                    <span>
                      {entry.source} · {entry.workId}
                      {t('（详情暂不可用）')}
                    </span>
                    <CategoryEditor source={entry.source} workId={entry.workId} title={entry.workId} />
                  </li>
                ))}
              </ul>
            ) : null}
            {!rows.length ? (
              <EmptyState
                title={category ? t('此分类暂无作品') : t('暂无收藏')}
                detail={t('可在作品详情中收藏或编辑分类。')}
              />
            ) : null}
          </>
        )}
      </StateView>

      {view !== 'recent' ? (
        <nav className="action-row" aria-label={t('收藏分页')}>
          <span>
            {total}
            {t(' 项 · 第 ')}
            {page}
            {t(' 页')}
          </span>
          {page > 1 ? (
            <a className="chip" href={url({ page: String(page - 1) })} onClick={(event) => navigateClick(event, navigate, url({ page: String(page - 1) }))}>
              {t('上一页')}
            </a>
          ) : null}
          {page * pageSize < total ? (
            <a className="chip" href={url({ page: String(page + 1) })} onClick={(event) => navigateClick(event, navigate, url({ page: String(page + 1) }))}>
              {t('下一页')}
            </a>
          ) : null}
        </nav>
      ) : null}
    </>
  );
}
