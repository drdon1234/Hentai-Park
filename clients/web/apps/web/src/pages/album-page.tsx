import { useEffect, useRef, useState } from 'react';
import { EmptyState, StatusMessage } from '@hentai-park/design-system';
import { api, type AlbumItem } from '../api.js';
import { navigateClick } from '../app/app-context.js';
import { CoverImage } from '../cover-image.js';
import { PostDownloads } from '../extended-pages.js';
import { t } from '../i18n.js';
import { PageHeader, StateView, errorMessage, useAsync, useServerVersion } from '../page-ui.js';
import { usePreferences } from '../preferences.js';
import { MediaLightboxModal, type LightboxMediaItem } from '../shared/media-lightbox.js';

const albumCache = new Map<string, { items: AlbumItem[]; cursor: string | null | undefined }>();

export function AlbumPage({
  source,
  search,
  navigate,
}: {
  source: string;
  search: string;
  navigate: (to: string) => void;
}) {
  const [lightbox, setLightbox] = useState<{ items: LightboxMediaItem[]; index: number; title: string }>();
  const prefs = usePreferences();
  const params = new URLSearchParams(search);
  const scope = params.get('scope') ?? '';
  const cacheKey = JSON.stringify([source, scope]);
  const cachedAlbum = albumCache.get(cacheKey);
  const version = useServerVersion();
  const sourceState = useAsync(() => api.source(source), [source, version], undefined, { cacheKey: 'source:' + source });
  const [items, setItems] = useState<AlbumItem[]>(cachedAlbum?.items ?? []);
  const [cursor, setCursor] = useState<string | null | undefined>(cachedAlbum?.cursor);
  const autoPages = useRef(0);
  const cancelled = useRef(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [attempt, setAttempt] = useState(0);
  const controller = useRef<AbortController | undefined>(undefined);
  const [expanded, setExpanded] = useState<string[]>([]);
  const [target, setTarget] = useState('');
  const [kind, setKind] = useState('all');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');

  const merge = (next: AlbumItem[]) =>
    setItems((old) => {
      const map = new Map(old.map((row) => [row.id, row]));
      for (const row of next) map.set(row.id, row);
      const value = [...map.values()];
      albumCache.set(cacheKey, { items: value, cursor });
      return value;
    });

  const load = async (next?: string) => {
    cancelled.current = false;
    controller.current?.abort();
    const c = new AbortController();
    controller.current = c;
    setLoading(true);
    setError('');
    try {
      const result = await api.album(source, scope, next, c.signal);
      if (!c.signal.aborted) {
        merge(result.items);
        setCursor(result.page.nextCursor);
        const current = albumCache.get(cacheKey);
        if (current) albumCache.set(cacheKey, { ...current, cursor: result.page.nextCursor });
      }
    } catch (err) {
      if (!c.signal.aborted) setError(errorMessage(err));
    } finally {
      if (!c.signal.aborted) setLoading(false);
    }
  };

  useEffect(() => {
    if (!cachedAlbum) {
      setItems([]);
      setCursor(undefined);
    }
    autoPages.current = 0;
    cancelled.current = false;
    if (scope) void load(cachedAlbum?.cursor ?? undefined);
    return () => controller.current?.abort();
  }, [source, scope, attempt]);

  useEffect(() => {
    const stop = () => {
      controller.current?.abort();
      setLoading(false);
    };
    window.addEventListener('pagehide', stop);
    return () => window.removeEventListener('pagehide', stop);
  }, []);

  const manifest = sourceState.data?.manifest;
  const caps = manifest?.capabilities as Record<string, boolean> | undefined;
  const feeds = Array.isArray(manifest?.feeds) ? (manifest.feeds as Array<{ key: string; label: string }>) : [];

  useEffect(() => {
    autoPages.current = 0;
  }, [kind, from, to]);

  const [showBlocked, setShowBlocked] = useState(false);
  const filtered = items
    .filter((row) => showBlocked || !row.blocked)
    .filter((row) => {
      const date = row.date ? Date.parse(row.date) : NaN;
      return (!from || (Number.isFinite(date) && date >= Date.parse(from))) && (!to || (Number.isFinite(date) && date < Date.parse(to) + 86400000));
    });

  useEffect(() => {
    if (
      scope &&
      cursor &&
      !loading &&
      !error &&
      !cancelled.current &&
      autoPages.current < 3 &&
      !filtered.some((row) => row.media.some((m) => kind === 'all' || m.type === kind))
    ) {
      autoPages.current++;
      void load(cursor);
    }
  }, [scope, cursor, loading, error, items, kind, from, to]);

  return (
    <>
      <PageHeader title={t('相册')} description={t('按原站顺序浏览高密度媒体画廊，图片与视频支持同流全屏预览。')}>
        <a
          className="navigation-link"
          href={'/source/' + encodeURIComponent(source)}
          onClick={(event) => navigateClick(event, navigate, '/source/' + encodeURIComponent(source))}
        >
          {t('站点主页')}
        </a>
      </PageHeader>
      <StateView loading={sourceState.loading} error={sourceState.error} empty={false}>
        {caps?.album !== true ? (
          <StatusMessage title={t('此站点暂无可浏览的相册。')}>{t('此站点暂无可浏览的相册。')}</StatusMessage>
        ) : (
          <>
            <details className="album-options" open={!scope}>
              <summary>{t('相册范围与筛选')}</summary>
              <div className="action-row">
                {feeds.map((feed) => {
                  const href =
                    '/album/' +
                    encodeURIComponent(source) +
                    '?scope=' +
                    encodeURIComponent(JSON.stringify({ feed: feed.key, options: {} }));
                  return (
                    <a className="chip" key={feed.key} href={href} onClick={(event) => navigateClick(event, navigate, href)}>
                      {feed.label}
                      {t('相册')}
                    </a>
                  );
                })}
              </div>
              {caps.subscription ? (
                <form
                  onSubmit={(event) => {
                    event.preventDefault();
                    navigate(
                      '/album/' +
                        encodeURIComponent(source) +
                        '?scope=' +
                        encodeURIComponent(JSON.stringify({ target: target.trim() })),
                    );
                  }}
                >
                  <label>
                    {t('频道或用户目标')}
                    <input aria-label={t('相册目标')} required value={target} onChange={(event) => setTarget(event.target.value)} />
                  </label>
                  <button className="primary-link">{t('打开目标相册')}</button>
                </form>
              ) : null}
              {!scope ? <p role="status">{t('选择目录，或从站内搜索/筛选打开相册。')}</p> : null}
              <div className="reader-controls album-filters">
                <label>
                  {t('每行数量')}
                  <select
                    value={Number(prefs.settings.albumColumns)}
                    disabled={prefs.busy}
                    onChange={(event) => void prefs.save({ albumColumns: Number(event.target.value) })}
                  >
                    {[1, 2, 3, 4, 5, 6].map((value) => (
                      <option key={value} value={value}>
                        {value}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  <input
                    type="checkbox"
                    checked={Boolean(prefs.settings.albumCollapsed)}
                    onChange={(event) => {
                      setExpanded([]);
                      void prefs.save({ albumCollapsed: event.target.checked });
                    }}
                  />
                  {t('默认收起媒体')}
                </label>
                <label>
                  {t('媒体类型')}
                  <select value={kind} onChange={(event) => setKind(event.target.value)}>
                    <option value="all">{t('全部')}</option>
                    <option value="image">{t('图片')}</option>
                    <option value="video">{t('视频')}</option>
                  </select>
                </label>
                <label>
                  {t('起始日期')}
                  <input type="date" value={from} onChange={(event) => setFrom(event.target.value)} />
                </label>
                <label>
                  {t('结束日期')}
                  <input type="date" value={to} onChange={(event) => setTo(event.target.value)} />
                </label>
              </div>
            </details>

            {error ? (
              <StatusMessage tone="danger" title={t('相册加载失败')}>
                {error}
                <button className="chip" onClick={() => void load(cursor ?? undefined)}>
                  {t('重试相册')}
                </button>
                <button className="chip" onClick={() => setAttempt((v) => v + 1)}>
                  {t('重新加载相册')}
                </button>
              </StatusMessage>
            ) : null}

            {items.some((row) => row.blocked || row.media.some((item) => item.hiddenByPreferences)) ? (
              <button className="chip" aria-pressed={showBlocked} onClick={() => setShowBlocked((value) => !value)}>
                {showBlocked ? t('应用屏蔽规则') : t('临时显示原始结果')}
              </button>
            ) : null}

            {loading && !filtered.length ? (
              <div className="album-media-grid album-media-skeleton" aria-busy="true" aria-label={t('正在加载相册')}>
                {Array.from({ length: 6 }, (_, index) => (
                  <div className="work-preview-skeleton" key={index} aria-hidden="true" />
                ))}
              </div>
            ) : null}

            <div className="source-feed" role="region" aria-label={t('相册结果')}>
              {filtered.map((row) => {
                const open = prefs.settings.albumCollapsed ? expanded.includes(row.id) : !expanded.includes(row.id);
                const media = row.media.filter(
                  (m) => (showBlocked || !m.hiddenByPreferences) && (kind === 'all' || m.type === kind),
                );
                const streamItems: LightboxMediaItem[] = media.map((m) => ({
                  id: m.id,
                  type: m.type,
                  authorization: m.mediaAuthorization,
                  caption: m.previewOnly ? t('仅原站公开预览') : undefined,
                }));
                return (
                  <article className="feed-item" key={row.id} data-album-id={row.id}>
                    <div className="section-header" style={{ marginBottom: 8 }}>
                      <h2 style={{ margin: 0, fontSize: 16 }}>
                        {row.presentation === 'work' ? (
                          <a
                            href={'/work/' + [source, row.id].map(encodeURIComponent).join('/')}
                            onClick={(event) =>
                              navigateClick(event, navigate, '/work/' + [source, row.id].map(encodeURIComponent).join('/'))
                            }
                          >
                            {row.title}
                          </a>
                        ) : (
                          row.title
                        )}
                      </h2>
                      <button
                        className="chip"
                        aria-expanded={open}
                        onClick={() =>
                          setExpanded((value) => (value.includes(row.id) ? value.filter((id) => id !== row.id) : [...value, row.id]))
                        }
                      >
                        {open ? t('收起') : t('展开')} ({media.length})
                      </button>
                    </div>
                    <p style={{ fontSize: 12 }}>
                      {row.date ? new Date(row.date).toLocaleString() : t('日期未知')}
                      {row.locked ? t(' · 原站锁定，仅公开预览') : ''}
                    </p>
                    {open ? (
                      <>
                        {row.text ? <p className="article-text">{row.text}</p> : null}
                        <div
                          className="album-media-grid"
                          style={{
                            display: 'grid',
                            gridTemplateColumns:
                              'repeat(' + Math.min(Number(prefs.settings.albumColumns) || 4, Math.max(1, media.length)) + ',minmax(0,1fr))',
                            gap: 10,
                          }}
                        >
                          {media.map((m, idx) => (
                            <figure key={m.id} data-media-id={m.id} className={m.blurred ? 'album-blurred' : ''}>
                              <button
                                type="button"
                                className="work-preview-button"
                                style={{ aspectRatio: '1 / 1', position: 'relative' }}
                                aria-label={(m.type === 'video' ? t('播放视频') : t('查看大图')) + ' · ' + row.title}
                                onClick={() => setLightbox({ items: streamItems, index: idx, title: row.title })}
                              >
                                {m.type === 'image' ? (
                                  <CoverImage authorization={m.mediaAuthorization} alt={row.title + ' ' + (idx + 1)} allowUnblur />
                                ) : m.previewAuthorization ? (
                                  <CoverImage authorization={m.previewAuthorization} alt={t('视频预览')} allowUnblur />
                                ) : (
                                  <span className="muted">{t('视频')}</span>
                                )}
                                {m.type === 'video' ? (
                                  <span
                                    className="browse-badge"
                                    style={{ position: 'absolute', bottom: 8, right: 8 }}
                                  >
                                    ▶ {m.previewOnly ? t('公开预览') : t('视频')}
                                  </span>
                                ) : null}
                              </button>
                            </figure>
                          ))}
                        </div>
                        <details className="album-download-options">
                          <summary>{t('下载媒体')}</summary>
                          <PostDownloads post={row} />
                        </details>
                      </>
                    ) : null}
                  </article>
                );
              })}
            </div>

            {loading ? <p role="status">{t('正在加载相册')}</p> : null}
            {scope && !loading && !items.length && !error ? (
              <EmptyState title={t('暂无匹配媒体')} detail={t('可调整筛选，或继续加载更多内容。')} />
            ) : null}
            {cursor ? (
              <button className="chip" disabled={loading} onClick={() => void load(cursor)}>
                {t('加载更多相册')}
              </button>
            ) : null}
            {loading ? (
              <button
                className="chip"
                onClick={() => {
                  cancelled.current = true;
                  controller.current?.abort();
                  setLoading(false);
                }}
              >
                {t('取消相册加载')}
              </button>
            ) : null}
          </>
        )}
      </StateView>

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
    </>
  );
}
