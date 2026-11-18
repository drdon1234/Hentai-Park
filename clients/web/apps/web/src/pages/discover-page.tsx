import { useContext, useEffect, useRef, useState } from 'react';
import { EmptyState, StatusMessage, showToast } from '@hentai-park/design-system';
import { chapterIdentityKey, workIdentityKey } from '@hentai-park/domain-model';
import { api, request, type ApiWork, type Source } from '../api.js';
import { SourceCatalog, navigateClick } from '../app/app-context.js';
import { FeatureIcon, categoryInScope, categoryLabels, domainHref, domainOrder } from '../browse-ui.js';
import { clearBrowseSessions } from '../browse-session-cache.js';
import { clearCoverImages } from '../cover-image.js';
import { HomeSourcePicker, useHomePreferences } from '../home-preferences.js';
import { HomeSource } from '../home-source.js';
import { t } from '../i18n.js';
import { PageHeader, errorMessage, useAsync, useServerVersion } from '../page-ui.js';
import { usePreferences } from '../preferences.js';
import { SearchBox } from '../shared/search-combobox.js';
import { WorkCard } from '../shared/work-card.js';

export function DiscoverPage({
  navigate,
  category,
  sitesOnly = false,
}: {
  navigate: (to: string) => void;
  category?: string;
  sitesOnly?: boolean;
}) {
  const homePreferences = useHomePreferences();
  const prefs = usePreferences();
  const historyVersion = useServerVersion(['chapter.progressed', 'work.updated', 'account.updated']);
  const params = new URLSearchParams(window.location.search);
  const urlDim = params.get('dimension');
  const urlMedia = params.get('media');
  const savedDim = typeof prefs.settings.homeDimension === 'string' ? prefs.settings.homeDimension : 'all';
  const savedMedia = typeof prefs.settings.homeMedia === 'string' ? prefs.settings.homeMedia : 'all';
  const dimension = ['twoD', 'threeD'].includes(urlDim ?? '')
    ? urlDim!
    : ['twoD', 'threeD'].includes(savedDim)
      ? savedDim
      : 'all';
  const media = ['image', 'video', 'voice', 'other'].includes(urlMedia ?? '')
    ? urlMedia!
    : ['image', 'video', 'voice', 'other'].includes(savedMedia)
      ? savedMedia
      : 'all';

  const ordered = Array.isArray(prefs.settings.domainOrder) ? (prefs.settings.domainOrder as string[]) : [];
  const selected = Array.isArray(prefs.settings.homeCategories) ? (prefs.settings.homeCategories as string[]) : [];
  const categories = [
    ...ordered.filter((value) => domainOrder.includes(value)),
    ...domainOrder.filter((value) => !ordered.includes(value)),
  ].filter(
    (value) =>
      categoryInScope(value, dimension, media) &&
      (category || sitesOnly || !selected.length || selected.includes(String(value))),
  );
  const scopeCategories = !prefs.ready ? [] : category ? categories.filter((value) => value === category) : categories;
  const scope = scopeCategories.join(',');

  const destination = (value?: string, sites = false) => {
    const query = new URLSearchParams();
    if (dimension !== 'all') query.set('dimension', dimension);
    if (media !== 'all') query.set('media', media);
    return (sites ? '/sites' : value ? domainHref(value) : '/discover') + (query.size ? '?' + query : '');
  };

  const setScope = (name: 'dimension' | 'media', value: string) => {
    void prefs.save(name === 'dimension' ? { homeDimension: value } : { homeMedia: value });
    const query = new URLSearchParams(window.location.search);
    if (value === 'all') query.delete(name);
    else query.set(name, value);
    const nextDimension = name === 'dimension' ? value : dimension;
    const nextMedia = name === 'media' ? value : media;
    const nextCategory = category && categoryInScope(category, nextDimension, nextMedia) ? category : undefined;
    navigate((sitesOnly ? '/sites' : nextCategory ? domainHref(nextCategory) : '/discover') + (query.size ? '?' + query : ''));
  };

  const [retries, setRetries] = useState(0);
  const [expanded, setExpanded] = useState<string[]>([]);
  const [hiddenHistory, setHiddenHistory] = useState<string[]>([]);
  const [removingHistory, setRemovingHistory] = useState<string>();
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => {
    if (prefs.ready) {
      setExpanded(Array.isArray(prefs.settings.homeExpandedDomains) ? (prefs.settings.homeExpandedDomains as string[]) : []);
    }
  }, [prefs.ready, prefs.settings.homeExpandedDomains]);

  const continueTrack = useRef<HTMLDivElement>(null);
  const [historyEdges, setHistoryEdges] = useState({ start: true, end: true, scrollable: false });
  const moveHistory = (direction: number) => {
    const track = continueTrack.current;
    if (track) {
      track.scrollBy({
        left: direction * (getComputedStyle(track).direction === 'rtl' ? -1 : 1) * track.clientWidth * 0.85,
        behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth',
      });
    }
  };

  const sources = useContext(SourceCatalog);
  const [knownSources, setKnownSources] = useState<Source[]>([]);
  useEffect(() => {
    if (sources.data) setKnownSources(sources.data);
  }, [sources.data]);

  /* Zero-scrape Continue Reading strip: uses enriched SQLite fields from GET /api/v1/history directly! */
  const history = useAsync(
    async () => {
      if (sitesOnly) return [];
      const page = await api.history({ categories: scope, limit: 20, uniqueWorks: true });
      return page.items.map((entry) => {
        const work: ApiWork | undefined = entry.workTitle
          ? {
              source: entry.source,
              workId: entry.workId,
              title: entry.workTitle,
              sourceUrl: '',
              mediaKind: entry.mediaKind ?? 'comic',
              version: 1,
              updatedAt: entry.updatedAt ?? '',
              category: entry.category ?? 'comic',
              coverAuthorization: entry.coverAuthorization,
              capabilities: {} as ApiWork['capabilities'],
            }
          : undefined;
        return { entry, work };
      });
    },
    [scope, retries, sitesOnly],
    undefined,
    { refreshKey: historyVersion, cacheKey: 'home-history:' + JSON.stringify([scope, sitesOnly]) },
  );

  useEffect(() => setHiddenHistory([]), [scope, sitesOnly]);

  const removeHistory = async (key: string) => {
    if (removingHistory) return;
    setRemovingHistory(key);
    try {
      await request('/api/v1/history', { method: 'DELETE', body: JSON.stringify({ scopeKeys: [key] }) });
      setHiddenHistory((value) => [...value, key]);
      window.dispatchEvent(new Event('hp:invalidate'));
    } finally {
      setRemovingHistory(undefined);
    }
  };

  useEffect(() => {
    const track = continueTrack.current;
    if (!track) return;
    const card = track.querySelector<HTMLElement>('.work-card, .continue-card');
    const update = () => {
      setHistoryEdges({
        start: Math.abs(track.scrollLeft) < 2,
        end: Math.abs(track.scrollLeft) + track.clientWidth >= track.scrollWidth - 2,
        scrollable: track.scrollWidth > track.clientWidth + 2,
      });
      if (card && track.parentElement) {
        const bounds = card.getBoundingClientRect();
        track.parentElement.style.setProperty(
          '--shelf-control-center',
          `${bounds.top + bounds.height / 2 - track.parentElement.getBoundingClientRect().top}px`,
        );
      }
    };
    const observer = new ResizeObserver(update);
    observer.observe(track);
    if (card) observer.observe(card);
    track.addEventListener('scroll', update, { passive: true });
    update();
    return () => {
      observer.disconnect();
      track.removeEventListener('scroll', update);
    };
  }, [history.data?.length]);

  const sourcePositions = new Map(homePreferences.order.map((source, index) => [source, index]));
  const baselinePositions = new Map(
    (sources.data ?? knownSources).map((source, index) => [source.source, source.defaultOrder ?? index]),
  );
  const enabled = (sources.data ?? knownSources)
    .filter((item) => item.installed !== false && item.enabled)
    .sort(
      (a, b) =>
        (sourcePositions.get(a.source) ?? Number.MAX_SAFE_INTEGER) -
          (sourcePositions.get(b.source) ?? Number.MAX_SAFE_INTEGER) ||
        (baselinePositions.get(a.source) ?? Number.MAX_SAFE_INTEGER) -
          (baselinePositions.get(b.source) ?? Number.MAX_SAFE_INTEGER),
    );
  const selectedSources = enabled.filter((item) => scopeCategories.includes(String(item.manifest?.category ?? 'other')));
  const metadataSources = enabled.filter((item) => {
    const manifest = item.manifest ?? {};
    const cap = manifest.capabilities as Record<string, unknown> | undefined;
    return (
      (manifest.metadataOnly === true || (manifest.rankingOnly === true && cap?.metadataDetail === true)) &&
      (scopeCategories.includes(String(manifest.category)) ||
        (Array.isArray(manifest.rankings) &&
          manifest.rankings.some((board: { category?: string }) => scopeCategories.includes(board.category ?? ''))))
    );
  });
  const utilitySources = selectedSources.filter(
    (item) => item.manifest?.rankingOnly === true || item.manifest?.reverseSearchOnly === true,
  );
  const searchable = selectedSources.filter((item) => {
    const cap = item.manifest?.capabilities as Record<string, unknown> | undefined;
    return !item.manifest?.metadataOnly && cap?.search === true;
  });

  const search = (query: string) => {
    const next = new URLSearchParams({ q: query });
    if (category) next.set('category', category);
    if (dimension !== 'all' || media !== 'all') {
      for (const item of searchable) next.append('sources', item.source);
    }
    navigate('/search?' + next);
  };

  const refreshHome = async () => {
    if (refreshing) return;
    setRefreshing(true);
    try {
      await api.discovery({ categories: scope, refresh: true }).catch(() => undefined);
      clearBrowseSessions();
      clearCoverImages();
      window.dispatchEvent(new Event('hp:browse-invalidated'));
      setRetries((v) => v + 1);
      showToast(t('已刷新推荐内容'), 'success');
    } finally {
      setRefreshing(false);
    }
  };

  const rankSources = selectedSources.filter(
    (item) => Array.isArray(item.manifest?.rankings) && item.manifest.rankings.length,
  );
  const reverseAvailable = enabled.some(
    (item) => (item.manifest?.capabilities as Record<string, unknown> | undefined)?.reverseSearch === true,
  );

  const domainNav = (
    <nav className="domain-nav" aria-label={t('内容领域')}>
      {!category ? (
        <a href="/subscriptions" onClick={(event) => navigateClick(event, navigate, '/subscriptions')}>
          {t('订阅')}
        </a>
      ) : (
        <a href={destination()} onClick={(event) => navigateClick(event, navigate, destination())}>
          {t('全部')}
        </a>
      )}
      {categories.map((value) => (
        <a
          key={value}
          className={category === value ? 'active' : ''}
          aria-current={category === value ? 'page' : undefined}
          href={destination(value)}
          onClick={(event) => navigateClick(event, navigate, destination(value))}
        >
          {t(categoryLabels[value] ?? value)}
        </a>
      ))}
      {category ? (
        <a href="/subscriptions" onClick={(event) => navigateClick(event, navigate, '/subscriptions')}>
          {t('订阅')}
        </a>
      ) : null}
    </nav>
  );

  useEffect(() => {
    document
      .querySelector<HTMLElement>('.domain-nav [aria-current="page"]')
      ?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }, [category, dimension, media]);

  const status = (loading: boolean, error: unknown) =>
    loading ? (
      <p role="status">{t('正在加载')}</p>
    ) : error ? (
      <StatusMessage tone="danger" title={t('此分区暂不可用')}>
        {errorMessage(error)}
        <button
          className="chip"
          onClick={() => {
            setRetries((value) => value + 1);
            window.dispatchEvent(new Event('hp:retry-read'));
          }}
        >
          {t('重试')}
        </button>
      </StatusMessage>
    ) : null;

  return (
    <>
      <PageHeader
        title={sitesOnly ? t('全部站点') : category ? t(categoryLabels[category] ?? category) : t('发现')}
        description={category ? undefined : t('按内容领域发现，前往喜欢的站点继续浏览。')}
      >
        {!sitesOnly ? (
          <button type="button" className="chip" disabled={refreshing} onClick={() => void refreshHome()}>
            {refreshing ? t('正在刷新…') : t('刷新推荐')}
          </button>
        ) : null}
        {rankSources.length ? (
          <a
            className="feature-entry"
            href={'/rankings' + (category ? '?category=' + encodeURIComponent(category) : '')}
            onClick={(event) => navigateClick(event, navigate, event.currentTarget.getAttribute('href')!)}
          >
            <FeatureIcon name="rankings" />
            <span>{t('排行榜')}</span>
          </a>
        ) : null}
        {reverseAvailable ? (
          <a
            className="feature-entry"
            href="/search?mode=reverse#reverse-search"
            onClick={(event) => navigateClick(event, navigate, '/search?mode=reverse#reverse-search')}
          >
            <FeatureIcon name="reverse" />
            <span>{t('图片反搜')}</span>
          </a>
        ) : null}
      </PageHeader>

      <div className="filter-row" style={{ marginBottom: 14 }} role="toolbar" aria-label={t('内容范围与媒体筛选')}>
        <div className="segmented-tabs" style={{ marginBottom: 0 }}>
          {(
            [
              ['all', '全部'],
              ['twoD', '二次元'],
              ['threeD', '三次元'],
            ] as const
          ).map(([val, label]) => (
            <button
              key={val}
              type="button"
              className={`segmented-tab ${dimension === val ? 'active' : ''}`}
              aria-pressed={dimension === val}
              onClick={() => setScope('dimension', val)}
            >
              {t(label)}
            </button>
          ))}
        </div>
        <div className="segmented-tabs" style={{ marginBottom: 0 }}>
          {(
            [
              ['all', '全部'],
              ['image', '图片'],
              ['video', '视频'],
              ['voice', '音声'],
              ['other', '其他'],
            ] as const
          ).map(([val, label]) => (
            <button
              key={val}
              type="button"
              className={`segmented-tab ${media === val ? 'active' : ''}`}
              aria-pressed={media === val}
              onClick={() => setScope('media', val)}
            >
              {t(label)}
            </button>
          ))}
        </div>
      </div>

      {category ? domainNav : null}

      {!sitesOnly && searchable.length ? (
        <div className="discovery-search">
          <SearchBox navigate={navigate} onSearch={search} />
          <p className="muted">
            {category
              ? t(categoryLabels[category] ?? category)
              : t(dimension === 'all' ? '全部' : dimension === 'twoD' ? '二次元' : '三次元')}{' '}
            ·{' '}
            {t(
              media === 'all'
                ? '全部媒体'
                : media === 'image'
                  ? '图片'
                  : media === 'video'
                    ? '视频'
                    : media === 'voice'
                      ? '音声'
                      : '其他',
            )}{' '}
            · {searchable.length} {t('个站点')}
          </p>
        </div>
      ) : null}

      {status(sources.loading && !knownSources.length, sources.error)}
      {homePreferences.error ? (
        <StatusMessage tone="warning" title={t('更新失败')}>
          {homePreferences.error}
          <button className="chip" onClick={() => void homePreferences.reload().catch(() => undefined)}>
            {t('重试')}
          </button>
        </StatusMessage>
      ) : null}

      {!sitesOnly && (history.loading || history.error || Boolean(history.data?.length)) ? (
        <section className="section-block">
          <div className="section-header">
            <h2>{t('继续看')}</h2>
            {(history.data?.length ?? 0) > 1 ? (
              <div className="shelf-actions history-header-arrows">
                <button className="chip" onClick={() => moveHistory(-1)} aria-label={t('向前浏览')}>
                  {t('上一页')}
                </button>
                <button className="chip" onClick={() => moveHistory(1)} aria-label={t('向后浏览')}>
                  {t('下一页')}
                </button>
              </div>
            ) : null}
            <a
              href={'/history' + (scope !== domainOrder.join(',') ? '?categories=' + encodeURIComponent(scope) : '')}
              onClick={(event) => navigateClick(event, navigate, event.currentTarget.getAttribute('href')!)}
            >
              {t('全部')}
            </a>
          </div>
          {history.error ? status(false, history.error) : null}
          <div className={'shelf-carousel continue-carousel' + (historyEdges.scrollable ? ' is-scrollable' : '')}>
            <button
              className="shelf-side shelf-side-start"
              disabled={historyEdges.start}
              aria-label={t('向前浏览') + ' · ' + t('继续看')}
              onClick={() => moveHistory(-1)}
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
                <path d="M20 12H4m7-7-7 7 7 7" />
              </svg>
            </button>
            <div
              className="continue-track"
              ref={continueTrack}
              onKeyDown={(event) => {
                if (event.target === event.currentTarget && (event.key === 'ArrowLeft' || event.key === 'ArrowRight')) {
                  event.preventDefault();
                  moveHistory(
                    (event.key === 'ArrowRight' ? 1 : -1) *
                      (getComputedStyle(event.currentTarget).direction === 'rtl' ? -1 : 1),
                  );
                }
              }}
              tabIndex={0}
              role="region"
              aria-label={t('继续看')}
            >
              {history.loading && !history.data?.length ? (
                <div className="continue-loading-skeleton" role="status" aria-label={t('正在加载')} />
              ) : null}
              {history.data
                ?.filter(
                  ({ entry }) =>
                    !hiddenHistory.includes(
                      entry.chapterId
                        ? chapterIdentityKey({ source: entry.source, workId: entry.workId, chapterId: entry.chapterId })
                        : workIdentityKey({ source: entry.source, id: entry.workId }),
                    ),
                )
                .map(({ entry, work }) => {
                  const workHref = '/work/' + [entry.source, entry.workId].map(encodeURIComponent).join('/');
                  const play = entry.nodeType
                    ? ['audio', 'video'].includes(entry.nodeType)
                    : work?.mediaKind === 'video' || work?.mediaKind === 'voice';
                  const href = entry.chapterId
                    ? (play ? '/watch/' : '/read/') + [entry.source, entry.workId, entry.chapterId].map(encodeURIComponent).join('/')
                    : workHref;
                  const historyKey = entry.chapterId
                    ? chapterIdentityKey({ source: entry.source, workId: entry.workId, chapterId: entry.chapterId })
                    : workIdentityKey({ source: entry.source, id: entry.workId });
                  const progressLabel =
                    entry.page != null
                      ? `${entry.page + 1}${entry.pageCount ? '/' + entry.pageCount : ''}P`
                      : entry.position
                        ? `${Math.floor(entry.position)}s`
                        : entry.chapterTitle ?? undefined;
                  return work ? (
                    <WorkCard
                      key={historyKey}
                      work={work}
                      navigate={navigate}
                      cacheScope="cards"
                      openHref={href}
                      compact
                      progressLabel={progressLabel}
                      onRemove={() => void removeHistory(historyKey)}
                    />
                  ) : (
                    <article className="continue-card" key={historyKey}>
                      <div className="continue-card-heading">
                        <a href={href} onClick={(event) => navigateClick(event, navigate, href)}>
                          {entry.workId}
                        </a>
                        <button
                          className="chip continue-card-remove"
                          type="button"
                          onClick={() => void removeHistory(historyKey)}
                        >
                          {t('移除')}
                        </button>
                      </div>
                      <p>{entry.chapterTitle ?? entry.chapterId ?? t('作品')}</p>
                      <small>{progressLabel ?? entry.source}</small>
                    </article>
                  );
                })}
            </div>
            <button
              className="shelf-side shelf-side-end"
              disabled={historyEdges.end}
              aria-label={t('向后浏览') + ' · ' + t('继续看')}
              onClick={() => moveHistory(1)}
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
                <path d="M4 12h16m-7-7 7 7 7-7" />
              </svg>
            </button>
          </div>
        </section>
      ) : null}

      {!category ? (
        <>
          {!sitesOnly ? (
            <div className="section-header all-sites-entry">
              <h2>
                <a
                  href={destination(undefined, true)}
                  onClick={(event) => navigateClick(event, navigate, destination(undefined, true))}
                >
                  {t('全部站点')}
                </a>
              </h2>
              <a
                href={destination(undefined, true)}
                onClick={(event) => navigateClick(event, navigate, destination(undefined, true))}
              >
                {selectedSources.length} {t('个站点')}
              </a>
            </div>
          ) : null}
          {domainNav}
        </>
      ) : null}

      {(category || sitesOnly) && metadataSources.length ? (
        <section className="source-role-section" aria-label={t('作品资料')}>
          <div className="section-header">
            <h2>{t('作品资料')}</h2>
            {metadataSources.some(
              (item) => (item.manifest?.capabilities as Record<string, unknown> | undefined)?.metadataSearch === true,
            ) ? (
              <a
                className="navigation-link"
                href={'/search?scope=metadata' + (category ? '&category=' + encodeURIComponent(category) : '')}
                onClick={(event) => navigateClick(event, navigate, event.currentTarget.getAttribute('href')!)}
              >
                {t('搜索作品资料')}
              </a>
            ) : null}
          </div>
          <nav className="source-role-links" aria-label={t('资料站点')}>
            {metadataSources.map((item) => (
              <HomeSource
                key={item.source}
                source={item}
                visible
                directory
                navigate={navigate}
                renderItem={(work) => <WorkCard work={work} navigate={navigate} cacheScope="cards" />}
              />
            ))}
          </nav>
        </section>
      ) : null}

      {sitesOnly && utilitySources.length ? (
        <section className="source-role-section">
          <h2>{t('检索工具')}</h2>
          <nav className="source-role-links">
            {utilitySources.map((item) => (
              <HomeSource
                key={item.source}
                source={item}
                visible
                directory
                navigate={navigate}
                renderItem={(work) => <WorkCard work={work} navigate={navigate} cacheScope="cards" />}
              />
            ))}
          </nav>
        </section>
      ) : null}

      {scopeCategories.map((value) => {
        const domainSources = selectedSources.filter((item) => {
          if (String(item.manifest?.category ?? 'other') !== value) return false;
          if (sitesOnly) {
            return !item.manifest?.metadataOnly && !item.manifest?.rankingOnly && !item.manifest?.reverseSearchOnly;
          }
          const manifest = item.manifest ?? {};
          const capabilities = manifest.capabilities as Record<string, unknown> | undefined;
          return (
            !manifest.metadataOnly &&
            !manifest.rankingOnly &&
            !manifest.reverseSearchOnly &&
            (Boolean(category) || capabilities?.feed === true || capabilities?.subscription === true)
          );
        });
        if (!domainSources.length) return null;
        const open = Boolean(category || sitesOnly || expanded.includes(value));
        return (
          <section className="domain-section" key={value} aria-label={t(categoryLabels[value] ?? value)}>
            {!category ? (
              <div className="section-header domain-heading">
                <h2>{t(categoryLabels[value] ?? value)}</h2>
                <div className="domain-heading-actions">
                  {!sitesOnly && domainSources.length > 1 ? (
                    <>
                      <HomeSourcePicker sources={domainSources} preferences={homePreferences} />
                      <button
                        className="domain-expand"
                        aria-expanded={expanded.includes(value)}
                        aria-controls={'domain-sources-' + value}
                        disabled={!prefs.ready || prefs.busy}
                        onClick={() => {
                          const next = expanded.includes(value)
                            ? expanded.filter((item) => item !== value)
                            : [...expanded, value];
                          setExpanded(next);
                          void prefs.save({ homeExpandedDomains: next });
                        }}
                      >
                        {t(expanded.includes(value) ? '收起' : '展开')}
                      </button>
                    </>
                  ) : null}
                  <a href={destination(value)} onClick={(event) => navigateClick(event, navigate, destination(value))}>
                    {t('进入域')}
                  </a>
                </div>
              </div>
            ) : null}
            <div id={'domain-sources-' + value}>
              {domainSources.map((item, index) => (
                <HomeSource
                  key={JSON.stringify([item.source, item.updatedAt, item.manifest, retries, sitesOnly])}
                  source={item}
                  visible={!homePreferences.loading && (open || index === 0)}
                  directory={sitesOnly}
                  hiddenWorks={homePreferences.hidden.includes(item.source)}
                  saving={homePreferences.saving}
                  onToggleHidden={() => void homePreferences.toggleHidden(item.source).catch(() => undefined)}
                  navigate={navigate}
                  renderItem={(work) => <WorkCard work={work} navigate={navigate} cacheScope="cards" />}
                />
              ))}
            </div>
          </section>
        );
      })}

      {!sources.loading && !sources.error && !selectedSources.length ? (
        <>
          <EmptyState title={t('当前范围没有启用的站点')} detail={t('前往站点管理，安装或启用内容来源')} />
          <a className="primary-link" href="/sources" onClick={(event) => navigateClick(event, navigate, '/sources')}>
            {t('管理站点')}
          </a>
        </>
      ) : null}
    </>
  );
}
