import { useCallback, useEffect, useRef, useState } from 'react';
import { confirmAction, showToast } from '@hentai-park/design-system';
import { api, request, type MediaTokenRequest } from './api.js';
import { ContentImage } from './content-controls.js';
import { FilePicker } from './file-picker.js';
import { t } from './i18n.js';
import { TavernAssetEditor } from './tavern-editor.js';
import { useMediaGrant } from './media-grant.js';
import { TavernChat } from './tavern-chat.js';
import { WorldbookTermPacks } from './worldbook-controls.js';

type Row = Record<string, unknown>;
const enc = encodeURIComponent;
const errorText = (e: unknown) => (e instanceof Error ? e.message : t('请求未能完成。'));

function usePage<T>(path: string) {
  const [data, setData] = useState<T>();
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    const abort = new AbortController();
    setLoading(true);
    setError('');
    void request<T>(path, { signal: abort.signal })
      .then((value) => {
        if (!abort.signal.aborted) setData(value);
      })
      .catch((err) => {
        if (!abort.signal.aborted) setError(errorText(err));
      })
      .finally(() => {
        if (!abort.signal.aborted) setLoading(false);
      });
    return () => abort.abort();
  }, [path, attempt]);
  return { data, error, loading, retry: () => setAttempt((n) => n + 1) };
}

function ContentVideo({
  authorization,
  format,
  source,
  workId,
  mediaId,
}: {
  authorization: MediaTokenRequest;
  format?: string;
  source: string;
  workId: string;
  mediaId: string;
}) {
  const video = useRef<HTMLVideoElement | null>(null);
  const position = useRef(0);
  const resume = useRef(false);
  const [error, setError] = useState('');
  const [attempt, setAttempt] = useState(0);
  const [currentAuthorization, setCurrentAuthorization] = useState(authorization);
  useEffect(() => setCurrentAuthorization(authorization), [authorization]);
  const changed = useCallback(() => {
    if (video.current) {
      position.current = video.current.currentTime;
      resume.current = !video.current.paused;
    }
  }, []);
  const grant = useMediaGrant(currentAuthorization, attempt, changed);

  useEffect(() => {
    if (!grant.token) return;
    const abort = new AbortController();
    let cleanup: (() => void) | undefined;
    setError('');
    void (async () => {
      const url = '/api/v1/media/' + enc(grant.token!);
      let type = format;
      if (!type) {
        const head = await fetch(url, { method: 'HEAD', credentials: 'include', signal: abort.signal });
        if (!head.ok) throw Error(t('媒体授权无法读取，请重试。'));
        type = head.headers.get('content-type') ?? '';
      }
      if (abort.signal.aborted || !video.current) return;
      if (type === 'hls' || /mpegurl/i.test(type)) {
        const { attachHls } = await import('./hls.js');
        if (!abort.signal.aborted && video.current) cleanup = attachHls(video.current, url, setError);
      } else video.current.src = url;
    })().catch((err) => {
      if (!abort.signal.aborted) setError(errorText(err));
    });
    return () => {
      abort.abort();
      cleanup?.();
      if (video.current) {
        video.current.pause();
        video.current.removeAttribute('src');
        video.current.load();
      }
    };
  }, [grant.token, format, attempt]);

  return (
    <div className="post-video-frame">
      {error || grant.error ? (
        <p role="alert" className="action-row">
          {error || grant.error}
          <button
            className="chip"
            onClick={() => {
              changed();
              void request<{ mediaAuthorization: MediaTokenRequest }>(
                '/api/v1/posts/' + [source, workId].map(enc).join('/') + '/media/' + enc(mediaId),
              )
                .then((value) => {
                  setCurrentAuthorization(value.mediaAuthorization);
                  setAttempt((n) => n + 1);
                })
                .catch((err) => setError(errorText(err)));
            }}
          >
            {t('重试视频授权')}
          </button>
        </p>
      ) : null}
      <video
        ref={video}
        controls
        playsInline
        preload="metadata"
        style={{ maxWidth: '100%', maxHeight: '75vh' }}
        aria-label={t('帖子视频播放器')}
        onLoadedMetadata={() => {
          if (video.current) {
            if (position.current > 0) video.current.currentTime = position.current;
            if (resume.current) void video.current.play().catch(() => {});
          }
        }}
        onError={() => setError(t('视频加载失败，请重取授权。'))}
      />
    </div>
  );
}

export function PostDownloads({
  post,
}: {
  post: { source: unknown; id: unknown; workId?: unknown; locked?: unknown; text?: unknown; textDownloadNodeId?: unknown; media?: unknown };
}) {
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState('');
  const add = async (id: string, preview = false) => {
    setBusy(id);
    try {
      await api.createDownload({
        source: String(post.source),
        workId: String(post.workId ?? post.id),
        chapterId: id,
        variant: preview ? 'preview' : 'original',
      });
      setMessage(t('已加入后台下载队列。'));
    } catch (err) {
      setMessage(errorText(err));
    } finally {
      setBusy('');
    }
  };
  return (
    <div className="action-row" role="group" aria-label={t('帖子离线下载')}>
      {!post.locked && String(post.text ?? '').length ? (
        <button className="chip" disabled={!!busy} onClick={() => void add(String(post.textDownloadNodeId))}>
          {t('下载帖子正文')}
        </button>
      ) : null}
      {((post.media as Row[]) ?? [])
        .filter((item) => !post.locked || item.previewOnly)
        .map((item, index) => (
          <button
            className="chip"
            key={String(item.id)}
            disabled={!!busy}
            onClick={() => void add(String(item.downloadNodeId ?? item.id), item.previewOnly === true)}
          >
            {t('下载媒体 ')}
            {index + 1}
            {item.previewOnly ? ' · ' + t('仅原站公开预览') : null}
          </button>
        ))}
      {message ? (
        <p role="status">
          {message} <a href="/downloads">{t('查看下载')}</a>
        </p>
      ) : null}
    </div>
  );
}

function PostCard({ post, standalone = false }: { post: Row; standalone?: boolean }) {
  const Heading = standalone ? 'h1' : 'h2';
  const [active, setActive] = useState('');
  const [reveal, setReveal] = useState(false);
  useEffect(() => {
    setReveal(false);
    setActive('');
  }, [post.source, post.id, post.blocked, post.media]);
  if (post.blocked && !reveal) {
    return (
      <article className="feed-item">
        <p>{t('已按屏蔽规则隐藏此帖子。')}</p>
        <button className="chip" onClick={() => setReveal(true)}>
          {t('临时显示此帖子')}
        </button>
      </article>
    );
  }
  const media = Array.isArray(post.media) ? (post.media as Row[]) : [];
  return (
    <article className="feed-item" aria-label={String(post.title ?? t('帖子'))}>
      <Heading title={String(post.title ?? post.id)}>{String(post.title ?? post.id)}</Heading>
      {reveal && (post.blocked || media.some((item) => item.hiddenByPreferences)) ? (
        <button
          className="chip"
          onClick={() => {
            setActive('');
            setReveal(false);
          }}
        >
          {post.blocked ? t('恢复屏蔽') : t('恢复隐藏预览')}
        </button>
      ) : null}
      {post.date ? <time>{String(post.date)}</time> : null}
      {post.locked ? <p>{t('原站锁定，仅显示明确公开的内容。')}</p> : null}
      <p style={{ whiteSpace: 'pre-wrap' }}>{String(post.text ?? '')}</p>
      {media.map((item) =>
        item.hiddenByPreferences && !reveal ? (
          <div key={String(item.id)}>
            <p>{t('公开预览已按偏好隐藏。')}</p>
            <button className="chip" onClick={() => setReveal(true)}>
              {t('临时显示公开预览')}
            </button>
          </div>
        ) : (
          <figure className="post-media" key={String(item.id)}>
            {item.type === 'image' ? (
              <div style={item.blurred ? { filter: 'blur(12px)' } : undefined}>
                <ContentImage authorization={item.mediaAuthorization as MediaTokenRequest} alt={t('帖子图片')} />
              </div>
            ) : active === String(item.id) ? (
              <>
                <ContentVideo
                  source={String(post.source)}
                  workId={String(post.workId ?? post.id)}
                  mediaId={String(item.id)}
                  authorization={item.mediaAuthorization as MediaTokenRequest}
                  format={typeof item.format === 'string' ? item.format : undefined}
                />
                <button className="chip" onClick={() => setActive('')}>
                  {t('关闭视频')}
                </button>
              </>
            ) : (
              <>
                {item.previewAuthorization ? (
                  <div className="post-video-preview">
                    <ContentImage authorization={item.previewAuthorization as MediaTokenRequest} alt={t('视频预览图')} />
                  </div>
                ) : null}
                <button className="chip" onClick={() => setActive(String(item.id))}>
                  {item.previewOnly ? t('播放公开预览') : t('播放此视频')}
                </button>
              </>
            )}
            {item.previewOnly ? <figcaption>{t('仅原站公开预览')}</figcaption> : null}
          </figure>
        ),
      )}
      {(!post.locked && String(post.text ?? '').length > 0) || media.some((item) => !post.locked || item.previewOnly) ? (
        <details className="detail-secondary post-downloads">
          <summary>{t('下载')}</summary>
          <PostDownloads post={{ ...post, source: post.source, id: post.id }} />
        </details>
      ) : null}
    </article>
  );
}

export function ChannelPage({
  source,
  target: initialTarget = '',
  kind: initialKind = 'creator',
  navigate,
}: {
  source: string;
  target?: string;
  kind?: string;
  navigate?: (href: string) => void;
}) {
  const [target, setTarget] = useState(initialTarget);
  const [draft, setDraft] = useState(initialTarget);
  const [kind, setKind] = useState(initialKind);
  const [query, setQuery] = useState('');
  const [appliedQuery, setAppliedQuery] = useState('');
  const [targets, setTargets] = useState<Row[]>([]);
  const [targetCursor, setTargetCursor] = useState<string>();
  const [moreTargets, setMoreTargets] = useState(false);
  const [posts, setPosts] = useState<Row[]>([]);
  const [cursor, setCursor] = useState<string>();
  const [morePosts, setMorePosts] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const saved = usePage<{ version: number; items: Row[] }>('/api/v1/channels/' + enc(source) + '/saved');
  const manifest = usePage<{ manifest: Row }>('/api/v1/sources/' + enc(source));
  const controls = useRef<Set<AbortController>>(new Set());
  const base = '/api/v1/channels/' + enc(source);

  const remoteTargets = useCallback(
    async (next?: string) => {
      const c = new AbortController();
      controls.current.add(c);
      setLoading(true);
      try {
        const q = new URLSearchParams({ kind, query: appliedQuery });
        if (next) q.set('cursor', next);
        const value = await request<{ items: Row[]; cursor?: string; hasNext?: boolean; queryApplied?: boolean }>(
          base + '/targets?' + q,
          { signal: c.signal },
        );
        if (!c.signal.aborted) {
          const items = value.queryApplied
            ? value.items
            : value.items.filter(
                (row) => !appliedQuery || [row.id, row.label].join(' ').toLocaleLowerCase().includes(appliedQuery.toLocaleLowerCase()),
              );
          setTargets((prior) => (next ? [...new Map([...prior, ...items].map((row) => [row.id, row])).values()] : items));
          setTargetCursor(value.cursor);
          setMoreTargets(value.hasNext === true);
        }
      } catch (err) {
        if (!c.signal.aborted) setError(t('关注列表加载失败：') + errorText(err));
      } finally {
        controls.current.delete(c);
        if (!c.signal.aborted) setLoading(false);
      }
    },
    [source, kind, appliedQuery, base],
  );

  const loadPosts = useCallback(
    async (next?: string) => {
      if (!target) return;
      const c = new AbortController();
      controls.current.add(c);
      setLoading(true);
      setError('');
      try {
        const q = new URLSearchParams({ target });
        if (next) q.set('cursor', next);
        const value = await request<{ items: Row[]; hasNext: boolean; cursor?: string }>(base + '/posts?' + q, {
          signal: c.signal,
        });
        if (!c.signal.aborted) {
          setPosts((prior) => (next ? [...new Map([...prior, ...value.items].map((p) => [p.id, p])).values()] : value.items));
          setCursor(value.cursor);
          setMorePosts(value.hasNext);
        }
      } catch (err) {
        if (!c.signal.aborted) setError(errorText(err));
      } finally {
        controls.current.delete(c);
        if (!c.signal.aborted) setLoading(false);
      }
    },
    [base, target],
  );

  useEffect(() => {
    setPosts([]);
    setCursor(undefined);
    void loadPosts();
    return () => {
      for (const c of controls.current) c.abort();
      controls.current.clear();
    };
  }, [loadPosts]);

  const declaration = (manifest.data?.manifest.subscription ?? {}) as Row;
  useEffect(() => {
    if (declaration.joinedTargets === true) void remoteTargets();
  }, [remoteTargets, declaration.joinedTargets]);

  const open = (id: string) => {
    setTarget(id);
    const href = '/channel/' + enc(source) + '?target=' + enc(id);
    if (navigate) navigate(href);
    else window.history.replaceState(null, '', href);
  };
  const save = async () => {
    setError('');
    try {
      await request(base + '/saved', { method: 'POST', body: JSON.stringify({ input: draft, version: saved.data?.version ?? 0 }) });
      saved.retry();
    } catch (err) {
      setError(errorText(err));
    }
  };

  const managementBody = (
    <>
      <p>{t('保存到订阅不会在原站关注、加入或付费。访问内容仍由原站权限决定。')}</p>
      <form
        className="form-row"
        onSubmit={(e) => {
          e.preventDefault();
          void request<{ id: string }>(base + '/normalize', { method: 'POST', body: JSON.stringify({ input: draft }) })
            .then((row) => open(row.id))
            .catch((err) => setError(errorText(err)));
        }}
      >
        <label>
          {t('频道或用户链接/ID ')}
          <input
            required
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder={typeof declaration.communityExample === 'string' ? declaration.communityExample : undefined}
          />
        </label>
        <button className="primary-link">{t('打开频道')}</button>
        <button className="chip" type="button" disabled={!draft.trim()} onClick={() => void save()}>
          {t('保存到本地订阅')}
        </button>
      </form>
      <section>
        <h2>{t('已保存频道')}</h2>
        {saved.error ? (
          <p role="status">
            {saved.error}
            <button className="chip" onClick={saved.retry}>
              {t('重新加载频道')}
            </button>
          </p>
        ) : saved.loading ? (
          <p role="status">{t('正在加载已保存频道')}</p>
        ) : !saved.data?.items.length ? (
          <p>{t('尚未保存频道')}</p>
        ) : (
          <div className="tag-row">
            {saved.data?.items.map((row) => (
              <span key={String(row.id)} className="action-row" style={{ margin: 0 }}>
                <button className="chip" onClick={() => open(String(row.id))}>
                  {String(row.label)}
                </button>
                <button
                  className="chip danger-action"
                  aria-label={t('移除已保存频道 ') + String(row.label)}
                  onClick={() =>
                    void request(base + '/saved', {
                      method: 'DELETE',
                      body: JSON.stringify({ id: row.id, version: saved.data?.version }),
                    })
                      .then(saved.retry)
                      .catch((err) => setError(errorText(err)))
                  }
                >
                  ×
                </button>
              </span>
            ))}
          </div>
        )}
      </section>
      {declaration.joinedTargets === true ? (
        <section>
          <h2>{t('原站关注列表')}</h2>
          {declaration.communities === true ? (
            <label>
              {t('频道类型 ')}
              <select value={kind} onChange={(e) => setKind(e.target.value)}>
                <option value="creator">{t('创作者')}</option>
                <option value="community">{t('社群')}</option>
              </select>
            </label>
          ) : null}
          <form
            className="form-row"
            onSubmit={(e) => {
              e.preventDefault();
              setAppliedQuery(query);
            }}
          >
            <label>
              {t('查找已关注频道 ')}
              <input value={query} onChange={(e) => setQuery(e.target.value)} />
            </label>
            <button className="chip">{t('查找')}</button>
          </form>
          <div className="tag-row">
            {targets.map((row) => (
              <button key={String(row.id)} className="chip" onClick={() => open(String(row.id))}>
                {String(row.label)}
              </button>
            ))}
          </div>
          {moreTargets ? (
            <button className="chip" disabled={loading} onClick={() => void remoteTargets(targetCursor)}>
              {t('加载更多已关注频道')}
            </button>
          ) : null}
        </section>
      ) : null}
    </>
  );

  return (
    <>
      <header className="page-header">
        <div>
          <h1>
            {target
              ? String([...(saved.data?.items ?? []), ...targets].find((item) => String(item.id) === target)?.label ?? target)
              : t('频道与创作者')}
          </h1>
        </div>
        <a className="chip navigation-link" href={'/source/' + enc(source)}>
          {t('站点主页')}
        </a>
      </header>
      {target ? (
        <details className="detail-secondary channel-management" key={target}>
          <summary>{t('切换与管理频道')}</summary>
          {managementBody}
        </details>
      ) : (
        managementBody
      )}
      <section aria-label={t('完整帖子列表')}>
        {!target ? <h2>{t('选择频道后浏览帖子')}</h2> : null}
        {posts.map((post) => (
          <PostCard key={String(post.id)} post={post} />
        ))}
        {loading ? (
          <p role="status">{t('正在读取内容')}</p>
        ) : target && !posts.length && !error ? (
          <p>{morePosts ? t('本页暂无帖子，可继续浏览后续内容。') : t('暂无帖子')}</p>
        ) : null}
        {error ? (
          <p role="alert" className="action-row">
            {error}
            <button className="chip" onClick={() => void (target ? loadPosts(cursor) : remoteTargets())}>
              {t('重试内容')}
            </button>
          </p>
        ) : null}
        {morePosts ? (
          <button className="chip" disabled={loading} onClick={() => void loadPosts(cursor)}>
            {t('加载更多帖子')}
          </button>
        ) : null}
      </section>
    </>
  );
}

export function PostPage({ source, workId }: { source: string; workId: string }) {
  const value = usePage<Row>('/api/v1/posts/' + [source, workId].map(enc).join('/'));
  return (
    <>
      {value.loading ? (
        <p role="status">{t('正在读取帖子')}</p>
      ) : value.error ? (
        <p role="alert" className="action-row">
          {value.error}
          <button className="chip" onClick={value.retry}>
            {t('重试内容')}
          </button>
          <a className="chip navigation-link" href={'/channel/' + enc(source)}>
            {t('频道')}
          </a>
        </p>
      ) : value.data ? (
        <PostCard post={value.data} standalone />
      ) : null}
    </>
  );
}

interface GameView {
  gameId: string;
  frameUrl: string;
  audioUrl: string;
  inputUrl: string;
  closeUrl: string;
  width: number;
  height: number;
}

export function GameResources({ source, workId, online = false }: { source: string; workId: string; online?: boolean }) {
  const [items, setItems] = useState<Row[]>([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [resolved, setResolved] = useState<Row>();
  const [game, setGame] = useState<GameView>();
  const [attempt, setAttempt] = useState(0);
  const base = '/api/v1/games/' + [source, workId].map(enc).join('/');

  useEffect(() => {
    if (online) return;
    const abort = new AbortController();
    setLoading(true);
    setError('');
    void request<{ items: Row[] }>(base + '/resources', { signal: abort.signal })
      .then((value) => setItems(value.items))
      .catch((err) => {
        if (!abort.signal.aborted) setError(errorText(err));
      })
      .finally(() => {
        if (!abort.signal.aborted) setLoading(false);
      });
    return () => abort.abort();
  }, [base, online, attempt]);

  const resolve = async (resource: Row, channel: Row) => {
    const desc = channel.requiresReply
      ? t('将向原站发送以下回复后获取链接：\n') + String(channel.replyText ?? '')
      : undefined;
    const ok = await confirmAction({
      title: channel.requiresReply ? t('提交回复并获取资源链接？') : t('获取此资源渠道的当次链接？'),
      description: desc,
    });
    if (!ok) return;
    setLoading(true);
    setResolved(undefined);
    try {
      setResolved(
        await request(base + '/resolve', {
          method: 'POST',
          body: JSON.stringify({ resourceId: resource.id, channelId: channel.id, confirmed: true }),
        }),
      );
      setError('');
    } catch (err) {
      setError(errorText(err));
    } finally {
      setLoading(false);
    }
  };

  return (
    <section className="section-block">
      <h2>{online ? t('在线游玩') : t('游戏资源')}</h2>
      <p>
        {online
          ? t('开始后可使用键盘、鼠标或虚拟手柄游玩，支持导出和导入本地存档。')
          : t('先确认资源支持的平台与版本，再选择下载渠道。')}
      </p>
      {online ? (
        game ? (
          <GameSurface game={game} onClose={() => setGame(undefined)} />
        ) : (
          <button
            className="primary-link"
            disabled={loading}
            onClick={() => {
              setLoading(true);
              void request<GameView>(base + '/play', { method: 'POST', body: '{}' })
                .then(setGame)
                .catch((err) => setError(errorText(err)))
                .finally(() => setLoading(false));
            }}
          >
            {t('开始游玩')}
          </button>
        )
      ) : (
        items.map((resource) => (
          <article key={String(resource.id)} className="feed-item">
            <h3>{String(resource.title || resource.id)}</h3>
            <p>
              {[
                resource.version ? t('版本 ') + String(resource.version) : '',
                resource.size ? String(resource.size) : '',
                ...((resource.platforms as string[]) ?? []),
                ...((resource.languages as string[]) ?? []),
                resource.testStatus === 'tested'
                  ? t('原站标记已测试')
                  : resource.testStatus === 'untested'
                    ? t('原站标记未测试')
                    : t('测试状态未知'),
              ]
                .filter(Boolean)
                .join(' · ')}
            </p>
            {resource.notes ? (
              <details>
                <summary>{t('准备步骤与资源说明')}</summary>
                <p style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{String(resource.notes)}</p>
              </details>
            ) : null}
            <div className="action-row">
              {((resource.channels as Row[]) ?? []).map((channel) => (
                <button
                  className="chip"
                  key={String(channel.id)}
                  disabled={loading || resource.status === 'expired'}
                  onClick={() => void resolve(resource, channel)}
                >
                  {resource.status === 'expired' ? t('已失效：') : ''}
                  {String(channel.label || channel.id)}
                </button>
              ))}
            </div>
          </article>
        ))
      )}

      {resolved ? (
        <section className="settings-panel" aria-label={t('当次资源链接')} style={{ marginTop: 16 }}>
          <h3>{t('当次资源链接')}</h3>
          <div className="action-row">
            {resolved.downloadUrl ? (
              <a className="primary-link" href={String(resolved.downloadUrl)} target="_blank" rel="noreferrer">
                {t('下载资源文件')}
              </a>
            ) : (
              ((resolved.urls as string[]) ?? []).map((url, index) => (
                <a key={url} className="primary-link" href={url} target="_blank" rel="noreferrer">
                  {t('打开渠道 ')}
                  {index + 1}
                </a>
              ))
            )}
            {resolved.extractionCode ? (
              <button
                type="button"
                className="chip"
                onClick={() =>
                  void navigator.clipboard
                    .writeText(String(resolved.extractionCode))
                    .then(() => showToast(t('已复制提取码'), 'success'))
                }
              >
                {t('提取码：')}
                {String(resolved.extractionCode)} ({t('复制')})
              </button>
            ) : null}
            {resolved.archivePassword ? (
              <button
                type="button"
                className="chip"
                onClick={() =>
                  void navigator.clipboard
                    .writeText(String(resolved.archivePassword))
                    .then(() => showToast(t('已复制解压密码'), 'success'))
                }
              >
                {t('解压密码：')}
                {String(resolved.archivePassword)} ({t('复制')})
              </button>
            ) : null}
          </div>
        </section>
      ) : null}

      {loading ? <p role="status">{t('正在处理游戏资源')}</p> : null}
      {error ? (
        <p role="alert" className="action-row">
          {error}
          {!online ? (
            <button className="chip" onClick={() => setAttempt((value) => value + 1)}>
              {t('重试内容')}
            </button>
          ) : null}
        </p>
      ) : null}
    </section>
  );
}

function GameSurface({ game, onClose }: { game: GameView; onClose: () => void }) {
  const lastPointer = useRef(0);
  const exit = useRef<HTMLButtonElement | null>(null);
  const held = useRef(new Set<string>());
  const image = useRef<HTMLImageElement | null>(null);
  const [frame, setFrame] = useState('');
  const [error, setError] = useState('');
  const [showPad, setShowPad] = useState(() => typeof matchMedia === 'function' && matchMedia('(any-pointer: coarse)').matches);

  useEffect(() => {
    const abort = new AbortController();
    let url = '';
    let timer: ReturnType<typeof setTimeout> | undefined;
    const load = async () => {
      try {
        const response = await fetch(game.frameUrl, { signal: abort.signal, credentials: 'include' });
        if (!response.ok) throw Error(t('游戏会话已结束，请重新开始。'));
        const next = URL.createObjectURL(await response.blob());
        if (abort.signal.aborted) {
          URL.revokeObjectURL(next);
          return;
        }
        if (url) URL.revokeObjectURL(url);
        url = next;
        setFrame(next);
        timer = setTimeout(load, 100);
      } catch (err) {
        if (!abort.signal.aborted) setError(errorText(err));
      }
    };
    void load();
    const close = () => void request(game.closeUrl, { method: 'POST', body: '{}', keepalive: true }).catch(() => {});
    window.addEventListener('pagehide', close);
    return () => {
      abort.abort();
      if (timer) clearTimeout(timer);
      if (url) URL.revokeObjectURL(url);
      window.removeEventListener('pagehide', close);
      close();
    };
  }, [game]);

  const input = (body: Row) =>
    void request(game.inputUrl, { method: 'POST', body: JSON.stringify({ ...body, requestKey: crypto.randomUUID() }) }).catch((err) =>
      setError(errorText(err)),
    );

  const pointer = (event: React.PointerEvent<HTMLImageElement>) => {
    const box = event.currentTarget.getBoundingClientRect();
    return {
      x: ((event.clientX - box.left) * game.width) / box.width,
      y: ((event.clientY - box.top) * game.height) / box.height,
      button: event.button === 2 ? 'right' : event.button === 1 ? 'middle' : 'left',
    };
  };

  const release = () => {
    for (const k of held.current) input({ action: 'keyUp', key: k });
    held.current.clear();
  };

  const key = (event: React.KeyboardEvent) => {
    event.preventDefault();
    if (event.key === 'Escape' && event.shiftKey) {
      release();
      exit.current?.focus();
      return;
    }
    const k = event.key === ' ' ? 'Space' : event.key;
    if (event.type === 'keydown') held.current.add(k);
    else held.current.delete(k);
    input({ action: event.type === 'keydown' ? 'keyDown' : 'keyUp', key: k });
  };

  const tapVirtualKey = (k: string, down: boolean) => {
    if (down) held.current.add(k);
    else held.current.delete(k);
    input({ action: down ? 'keyDown' : 'keyUp', key: k });
  };

  const exportSaves = async () => {
    try {
      const data = await api.gameSavesExport(game.gameId);
      const blob = new Blob([JSON.stringify(data.saves, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `game-save-${game.gameId.slice(0, 8)}.json`;
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      showToast(t('游戏存档已导出'), 'success');
    } catch (err) {
      setError(errorText(err));
    }
  };

  const importSaves = async (file: File) => {
    try {
      const parsed = JSON.parse(await file.text()) as Record<string, string>;
      const res = await api.gameSavesImport(game.gameId, parsed);
      showToast(`${t('已导入存档条目：')}${res.imported}`, 'success');
    } catch (err) {
      setError(errorText(err));
    }
  };

  return (
    <section className="game-surface" aria-label={t('在线游戏画面')}>
      {frame ? (
        <img
          ref={image}
          src={frame}
          alt={t('在线游戏实时画面')}
          tabIndex={0}
          style={{ width: '100%', maxWidth: 960, touchAction: 'none', borderRadius: 12 }}
          onContextMenu={(e) => e.preventDefault()}
          onPointerDown={(e) => {
            e.currentTarget.focus();
            e.currentTarget.setPointerCapture(e.pointerId);
            input({ action: 'pointerDown', ...pointer(e) });
          }}
          onPointerUp={(e) => input({ action: 'pointerUp', ...pointer(e) })}
          onPointerMove={(e) => {
            if (performance.now() - lastPointer.current < 33) return;
            lastPointer.current = performance.now();
            input({ action: 'pointerMove', ...pointer(e) });
          }}
          onKeyDown={key}
          onKeyUp={key}
          onBlur={release}
        />
      ) : (
        <p role="status">{t('正在读取游戏画面')}</p>
      )}

      {showPad ? (
        <div className="game-virtual-pad" aria-label={t('虚拟手柄')}>
          <div className="game-dpad">
            <span />
            <button
              type="button"
              onPointerDown={() => tapVirtualKey('ArrowUp', true)}
              onPointerUp={() => tapVirtualKey('ArrowUp', false)}
            >
              ↑
            </button>
            <span />
            <button
              type="button"
              onPointerDown={() => tapVirtualKey('ArrowLeft', true)}
              onPointerUp={() => tapVirtualKey('ArrowLeft', false)}
            >
              ←
            </button>
            <span />
            <button
              type="button"
              onPointerDown={() => tapVirtualKey('ArrowRight', true)}
              onPointerUp={() => tapVirtualKey('ArrowRight', false)}
            >
              →
            </button>
            <span />
            <button
              type="button"
              onPointerDown={() => tapVirtualKey('ArrowDown', true)}
              onPointerUp={() => tapVirtualKey('ArrowDown', false)}
            >
              ↓
            </button>
            <span />
          </div>
          <div className="game-ab-buttons">
            {(
              [
                ['Enter', 'OK'],
                ['Escape', 'ESC'],
                ['z', 'Z'],
                ['x', 'X'],
                ['Shift', 'RUN'],
                ['Control', 'SKIP'],
              ] as const
            ).map(([k, label]) => (
              <button
                key={k}
                type="button"
                className="chip"
                onPointerDown={() => tapVirtualKey(k, true)}
                onPointerUp={() => tapVirtualKey(k, false)}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      ) : null}

      <div className="action-row" style={{ marginTop: 12 }}>
        <button type="button" className="chip" aria-pressed={showPad} onClick={() => setShowPad((v) => !v)}>
          {t('虚拟手柄')}
        </button>
        <button type="button" className="chip" onClick={() => void exportSaves()}>
          {t('导出存档')}
        </button>
        <FilePicker
          label={t('导入存档')}
          accept="application/json,.json"
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (f) void importSaves(f);
            e.target.value = '';
          }}
        />
        <button ref={exit} className="chip danger-action" onClick={onClose}>
          {t('关闭游戏并保存本地状态')}
        </button>
      </div>

      <details className="detail-secondary">
        <summary>{t('游戏音频')}</summary>
        <audio controls preload="none" src={game.audioUrl} aria-label={t('游戏音频')} />
      </details>
      {error ? (
        <p role="alert" className="action-row">
          {error}
        </p>
      ) : null}
    </section>
  );
}

export function TavernSourcePanel({ source, workId }: { source: string; workId: string }) {
  const [asset, setAsset] = useState<Row>();
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const load = async (save = false) => {
    setLoading(true);
    try {
      setAsset(await request('/api/v1/tavern/source/' + [source, workId].map(enc).join('/'), save ? { method: 'POST', body: '{}' } : {}));
      setError('');
    } catch (err) {
      setError(errorText(err));
    } finally {
      setLoading(false);
    }
  };
  return (
    <section className="section-block">
      <h2>{t('角色卡与世界书')}</h2>
      <div className="action-row">
        <button className="chip" disabled={loading} onClick={() => void load()}>
          {t('查看角色卡或世界书')}
        </button>
        <button className="primary-link" disabled={loading} onClick={() => void load(true)}>
          {t('保存到酒馆资源库')}
        </button>
        <a className="chip navigation-link" href="/tavern">
          {t('打开资源库')}
        </a>
      </div>
      {loading ? <p role="status">{t('正在加载角色卡或世界书')}</p> : null}
      {error ? (
        <p role="alert" className="action-row">
          {error}
        </p>
      ) : null}
      {asset ? <TavernAsset asset={asset} onSaved={setAsset} /> : null}
    </section>
  );
}

function normalizeLoreEntries(entries: unknown): Array<{ id: string; keys: string[]; comment: string; content: string; enabled: boolean }> {
  const rawList = Array.isArray(entries)
    ? entries
    : entries && typeof entries === 'object'
      ? Object.values(entries as Record<string, unknown>)
      : [];
  return rawList.map((raw, idx) => {
    const row = (raw && typeof raw === 'object' ? raw : {}) as Row;
    const keys = Array.isArray(row.key)
      ? row.key.map(String)
      : Array.isArray(row.keys)
        ? row.keys.map(String)
        : [];
    return {
      id: String(row.uid ?? row.id ?? idx + 1),
      keys,
      comment: String(row.comment ?? row.name ?? ''),
      content: String(row.content ?? ''),
      enabled: row.disable !== true && row.enabled !== false,
    };
  });
}

function TavernAsset({ asset, onDeleted, onSaved }: { asset: Row; onDeleted?: () => void; onSaved?:(asset:Row)=>void }) {
  const [editing, setEditing] = useState(false);

  const data = (asset.data ?? {}) as Row;
  const card = (data.data ?? data) as Row;
  const loreEntries = asset.kind === 'lorebook' ? normalizeLoreEntries(data.entries ?? card.entries) : [];

  const exportAsset = () => {
    const png = typeof asset.originalPng === 'string';
    const bytes = png ? Uint8Array.from(atob(String(asset.originalPng)), (c) => c.charCodeAt(0)) : JSON.stringify(data, null, 2);
    const url = URL.createObjectURL(new Blob([bytes], { type: png ? 'image/png' : 'application/json' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = String(card.name ?? 'tavern-asset').replace(/[\\/:*?"<>|]/g, '_') + (png ? '.png' : '.json');
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  const removeAsset = async () => {
    if (!asset.assetId) return;
    const ok = await confirmAction({
      title: t('删除此酒馆资源及其已保存会话？'),
      description: String(card.name ?? asset.assetId),
      confirmLabel: t('删除'),
      danger: true,
    });
    if (!ok) return;
    await api.tavernDeleteAsset(String(asset.assetId), typeof asset.version === 'number' ? asset.version : undefined);
    showToast(t('资源已删除'), 'success');
    onDeleted?.();
  };

  return (
    <article className="feed-item tavern-asset">
      {!asset.assetId || asset.kind === 'lorebook' ? <h3>{String(card.name ?? asset.workId ?? t('世界书'))}</h3> : null}
      {asset.assetId && asset.kind !== 'lorebook' ? (
        <TavernChat
          avatar={typeof asset.originalPng === 'string' ? 'data:image/png;base64,' + asset.originalPng : undefined}
          name={String(card.name ?? '')}
          greetings={
            Array.isArray(card.alternate_greetings)
              ? card.alternate_greetings.filter((value): value is string => typeof value === 'string')
              : []
          }
          assetId={String(asset.assetId)}
          initialGreeting={typeof card.first_mes === 'string' ? card.first_mes : ''}
        />
      ) : null}
      <details className="detail-secondary tavern-asset-details" open={!asset.assetId || asset.kind === 'lorebook'}>
        <summary>{t('详细信息')}</summary>
        <div className="action-row">
          <button className="chip" onClick={exportAsset}>
            {t('导出原格式文件')}
          </button>
          {asset.assetId ? <button className="chip" onClick={() => setEditing((value) => !value)}>{editing ? t('关闭编辑') : t('编辑')}</button> : null}
          {asset.assetId ? (
            <button type="button" className="chip danger-action" onClick={() => void removeAsset()}>
              {t('删除资源')}
            </button>
          ) : null}
        </div>
        {editing && asset.assetId ? <TavernAssetEditor asset={asset} onSaved={(value) => { onSaved?.(value); setEditing(false); }} /> : null}
        {(['description', 'personality', 'scenario', 'first_mes'] as const)
          .filter((key) => typeof card[key] === 'string' && card[key])
          .map((key) => (
            <section key={key}>
              <h4>{{ description: t('描述'), personality: t('性格'), scenario: t('场景'), first_mes: t('开场白') }[key]}</h4>
              <p style={{ whiteSpace: 'pre-wrap' }}>{String(card[key])}</p>
            </section>
          ))}
        {asset.kind === 'lorebook' ? (
          <section>
            <h4>
              {t('世界书条目')} ({loreEntries.length})
            </h4>
            <ul className="chapter-list">
              {loreEntries.map((entry) => (
                <li key={entry.id} style={{ flexDirection: 'column', alignItems: 'flex-start', padding: 14 }}>
                  <div className="action-row" style={{ margin: 0 }}>
                    <strong>{entry.comment || `#${entry.id}`}</strong>
                    {entry.keys.map((kw) => (
                      <span key={kw} className="collection-tag">
                        {kw}
                      </span>
                    ))}
                    {!entry.enabled ? <span className="chapter-state">{t('已停用')}</span> : null}
                  </div>
                  <p style={{ whiteSpace: 'pre-wrap', margin: '8px 0 0', fontSize: 13 }}>{entry.content}</p>
                </li>
              ))}
            </ul>
          </section>
        ) : null}
      </details>
    </article>
  );
}

export function TavernLibraryPage() {
  const result = usePage<{ items: Row[] }>('/api/v1/tavern/assets');
  const [selected, setSelected] = useState<Row>();
  const [error, setError] = useState('');
  const [creating,setCreating]=useState<Row>();
  const [query,setQuery]=useState('');
  const [pins,setPins]=useState<string[]>(()=>{try{const value=JSON.parse(localStorage.getItem('hp:tavern-pins')??'[]');return Array.isArray(value)?value.filter(id=>typeof id==='string'):[];}catch{return [];}});
  function togglePin(id:string){
    const next=pins.includes(id)?pins.filter(key=>key!==id):[...pins,id];
    setPins(next);
    try{localStorage.setItem('hp:tavern-pins',JSON.stringify(next));}catch{/* 浏览器禁用存储时保留本次排序。 */}
  }
  const [sort,setSort]=useState('updated');
  const assets=(result.data?.items??[]).filter(item=>[item.name,...(Array.isArray(item.tags)?item.tags:[])].join(' ').toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()));
  if(sort==='name') assets.sort((a,b)=>String(a.name).localeCompare(String(b.name)));
  assets.sort((a,b)=>Number(pins.includes(String(b.assetId)))-Number(pins.includes(String(a.assetId))));
  function create(kind:string) {
    const data=kind==='character'?{spec:'chara_card_v2',spec_version:'2.0',data:{name:'',description:'',personality:'',scenario:'',first_mes:'',mes_example:'',creator_notes:'',system_prompt:'',post_history_instructions:'',alternate_greetings:[],tags:[],creator:'',character_version:'',extensions:{}}}:{name:'',entries:[],extensions:{}};
    setSelected(undefined);
    setCreating({kind,data});
  }
  const open = (id: string) =>
    void request<Row>('/api/v1/tavern/assets/' + enc(id))
      .then(setSelected)
      .catch((err) => setError(errorText(err)));

  const importFile = async (file: File) => {
    try {
      if (file.size > 12 * 1024 * 1024) throw Error(t('文件不能超过12MiB。'));
      let payload: Row;
      if (file.type === 'image/png' || /\.png$/i.test(file.name)) {
        const bytes = new Uint8Array(await file.arrayBuffer());
        let binary = '';
        for (let i = 0; i < bytes.length; i += 32768) binary += String.fromCharCode(...bytes.subarray(i, i + 32768));
        payload = { kind: 'character', format: 'png', pngBase64: btoa(binary) };
      } else {
        let data: Row;
        try {
          const parsed = JSON.parse(await file.text());
          if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw Error();
          data = parsed as Row;
        } catch {
          throw Error(t('无法识别此JSON文件，请选择角色卡或世界书文件。'));
        }
        payload = { kind: data.entries || (data.data as Row | undefined)?.entries ? 'lorebook' : 'character', format: 'json', data };
      }
      const asset = await request<Row>('/api/v1/tavern/import', { method: 'POST', body: JSON.stringify(payload) });
      setSelected(asset);
      result.retry();
      setError('');
    } catch (err) {
      setError(errorText(err));
    }
  };

  if(creating) return <>
    <header className="page-header"><h1>{creating.kind==='character'?t('角色卡'):t('世界书')}</h1>
    <button className="chip" onClick={()=>setCreating(undefined)}>{t('返回资源列表')}</button></header>
    <TavernAssetEditor asset={creating} onSaved={value=>{setCreating(undefined);setSelected(value);result.retry();}}/>
  </>;
  return (
    <>
      <header className="page-header">
        <div>
          <h1>{t(selected ? '会话' : '酒馆资源库')}</h1>
          {!selected ? <p>{t('管理角色卡、世界书与多模型对话工作台。')}</p> : null}
        </div>
        <div className="action-row" style={{ margin: 0 }}>
          {selected ? (
            <button type="button" className="chip" onClick={() => setSelected(undefined)}>
              {t('返回资源列表')}
            </button>
          ) : null}
          {!selected && !creating && <><button className="chip" onClick={()=>create('character')}>{t('新建')} · {t('角色卡')}</button><button className="chip" onClick={()=>create('lorebook')}>{t('新建')} · {t('世界书')}</button></>}
          <FilePicker
            label={t('导入JSON或PNG')}
            accept="application/json,image/png,.json,.png"
            onChange={(e) => {
              const file = e.target.files?.[0];
              if (file) void importFile(file);
              e.target.value = '';
            }}
          />
        </div>
      </header>
      {result.loading ? <p role="status">{t('正在读取资源库')}</p> : null}
      {result.error ? (
        <p role="alert" className="action-row">
          {result.error}
          <button className="chip" onClick={result.retry}>
            {t('重新加载资源库')}
          </button>
        </p>
      ) : null}
      {error ? <p role="alert">{error}</p> : null}
      {selected ? (
        <TavernAsset
          key={String(selected.assetId)}
          asset={selected}
          onSaved={value=>{setSelected(value);result.retry();}}
          onDeleted={() => {
            setSelected(undefined);
            result.retry();
          }}
        />
      ) : null}
      <details className="detail-secondary tavern-library-list" open={!selected}>
        <summary>{t('酒馆资源库')}</summary>
        <label className="form-row">{t('搜索')}<input type="search" value={query} onChange={e=>setQuery(e.target.value)}/></label>
        <label className="form-row">{t('排序')}<select value={sort} onChange={e=>setSort(e.target.value)}><option value="updated">{t('最近更新')}</option><option value="name">{t('名称')}</option></select></label>
        {query && !assets.length && <p role="status">{t('没有匹配结果，可修改关键词或筛选条件后重试。')}</p>}
        <ul className="chapter-list tavern-asset-list">
          {assets.map((item) => (
            <li key={String(item.assetId)} style={{display:'flex',alignItems:'center'}}>
              <button className="chapter-row-button" onClick={() => open(String(item.assetId))}>
                <strong>{String(item.name)}</strong>
                <span className="chapter-state">{item.kind === 'lorebook' ? t('世界书') : t('角色卡')}</span>
              </button>
              <button className="chip" aria-pressed={pins.includes(String(item.assetId))} onClick={()=>togglePin(String(item.assetId))}>{pins.includes(String(item.assetId))?t('取消置顶'):t('置顶')}</button>
            </li>
          ))}
        </ul>
      </details>
      {result.data && !result.data.items.length ? <p>{t('还没有保存的资源')}</p> : null}
      <details className="detail-secondary">
        <summary>{t('世界书词包')}</summary>
        <WorldbookTermPacks />
      </details>
    </>
  );
}
