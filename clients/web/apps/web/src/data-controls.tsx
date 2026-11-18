import { useEffect, useRef, useState } from 'react';
import { confirmAction } from '@hentai-park/design-system';
import { api, request, type DownloadTask, type HistoryEntry, type ImageTransform } from './api.js';
import { FilePicker } from './file-picker.js';
import { t } from './i18n.js';
import { ImageReaderLayout } from './image-reader-layout.js';
import { cropComicMargins, restoreImage } from './image-transform.js';
import { MediaSurface } from './media-surface.js';

type Row = Record<string, unknown>;
type LocalPage = { index: number; url: string; transform?: ImageTransform };
type OfflineContent = {
  source: string;
  workId: string;
  chapterId: string;
  mediaKind: string;
  incomplete?: boolean;
  previewOnly?: boolean;
  blocks?: Array<{ type: 'text' | 'image' | 'video'; text?: string; url?: string }>;
  pages: LocalPage[];
  mediaUrl?: string;
  volumes?: Array<{ volume: number; url: string }>;
  paragraphs?: string[];
  files: Array<{ id: number; url: string; kind: string }>;
};

const key = () => crypto.randomUUID();
const changed = () => window.dispatchEvent(new Event('hp:invalidate'));
const message = (reason: unknown) => (reason instanceof Error ? reason.message : t('操作未完成，请重试。'));

async function write<T>(path: string, method: string, body: Row = {}) {
  const result = await request<T>('/api/v1' + path, { method, body: JSON.stringify({ ...body, requestKey: key() }) });
  changed();
  return result;
}

function useResource<T>(path: string) {
  const [snapshot, setSnapshot] = useState<{ path: string; value: T }>();
  const [error, setError] = useState('');
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    const refresh = () => setAttempt((value) => value + 1);
    window.addEventListener('hp:server-update', refresh);
    window.addEventListener('hp:invalidate', refresh);
    return () => {
      window.removeEventListener('hp:server-update', refresh);
      window.removeEventListener('hp:invalidate', refresh);
    };
  }, []);
  useEffect(() => {
    const controller = new AbortController();
    setError('');
    void request<T>('/api/v1' + path, { signal: controller.signal })
      .then((value) => {
        if (!controller.signal.aborted) setSnapshot({ path, value });
      })
      .catch((reason) => {
        if (!controller.signal.aborted) setError(message(reason));
      });
    return () => controller.abort();
  }, [path, attempt]);
  return { data: snapshot?.path === path ? snapshot.value : undefined, error, reload: () => setAttempt((value) => value + 1) };
}

function Notice({ error, notice }: { error?: string; notice?: string }) {
  return error ? <p role="alert">{error}</p> : notice ? <p role="status">{notice}</p> : null;
}

function LocalImage({ page, cropMargins = false }: { page: LocalPage; cropMargins?: boolean }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const [canvasReady, setCanvasReady] = useState(false);
  const [error, setError] = useState('');
  const needsCanvas = Boolean(page.transform || cropMargins);

  return (
    <div className="authorized-image">
      {error ? (
        <p role="alert">
          {error}
          <button
            className="chip"
            onClick={() => {
              setError('');
              const image = canvas.current?.parentElement?.querySelector('img');
              if (image) image.src = page.url;
            }}
          >
            {t('重试图片')}
          </button>
        </p>
      ) : null}
      {needsCanvas ? (
        <canvas
          ref={canvas}
          role="img"
          aria-label={t('离线漫画第') + (page.index + 1) + t('页')}
          hidden={!canvasReady}
          style={{ maxWidth: '100%', height: 'auto' }}
        />
      ) : null}
      <img
        src={page.url}
        crossOrigin={needsCanvas ? 'use-credentials' : undefined}
        alt={needsCanvas && canvasReady ? '' : t('离线漫画第') + (page.index + 1) + t('页')}
        hidden={Boolean(page.transform || (cropMargins && canvasReady))}
        loading="lazy"
        style={{ maxWidth: '100%', height: 'auto' }}
        onLoad={(event) => {
          try {
            if (page.transform && canvas.current) {
              restoreImage(canvas.current, event.currentTarget, page.transform);
              setCanvasReady(true);
            } else if (cropMargins && canvas.current) {
              setCanvasReady(cropComicMargins(canvas.current, event.currentTarget));
            }
          } catch (reason) {
            setError(message(reason));
          }
        }}
        onError={() => setError(t('本地图片读取失败，请检查下载文件。'))}
      />
    </div>
  );
}

function OfflineMedia({ url, audio }: { url: string; audio: boolean }) {
  const element = useRef<HTMLMediaElement | null>(null);
  const [error, setError] = useState('');
  useEffect(() => {
    let live = true;
    let dispose: (() => void) | undefined;
    const controller = new AbortController();
    const media = element.current;
    if (media) {
      if (/\.m3u8(?:$|\?)/i.test(url)) {
        void import('./hls.js')
          .then(({ attachHls }) => {
            if (live) dispose = attachHls(media, url, setError);
          })
          .catch((reason) => {
            if (!controller.signal.aborted) setError(message(reason));
          });
      } else {
        void fetch(url, { method: 'HEAD', credentials: 'include', signal: controller.signal })
          .then(async (response) => {
            if (!response.ok) throw Error(t('本地媒体文件不可用'));
            if (/mpegurl/i.test(response.headers.get('content-type') ?? '')) {
              const { attachHls } = await import('./hls.js');
              if (live) dispose = attachHls(media, url, setError);
            } else if (live) media.src = url;
          })
          .catch((reason) => {
            if (!controller.signal.aborted) setError(message(reason));
          });
      }
    }
    return () => {
      live = false;
      controller.abort();
      dispose?.();
      if (media) {
        media.pause();
        media.removeAttribute('src');
        media.load();
      }
    };
  }, [url]);

  return (
    <>
      <MediaSurface key={url} audio={audio}>
        {audio ? (
          <audio
            ref={(node) => {
              element.current = node;
            }}
            controls
            preload="metadata"
            aria-label={t('离线音声')}
          />
        ) : (
          <video
            ref={(node) => {
              element.current = node;
            }}
            controls
            playsInline
            preload="metadata"
            style={{ maxWidth: '100%' }}
            aria-label={t('离线视频')}
          />
        )}
      </MediaSurface>
      <Notice error={error} />
    </>
  );
}

function OfflinePlayback({ content }: { content: OfflineContent }) {
  const [volume, setVolume] = useState(0);
  const volumes = content.volumes ?? [];
  const url = volumes[volume]?.url ?? content.mediaUrl;
  return (
    <>
      {volumes.length > 1 ? (
        <label>
          {t('录制分卷')}
          <select value={volume} onChange={(event) => setVolume(Number(event.target.value))}>
            {volumes.map((item, index) => (
              <option key={item.volume} value={index}>
                {t('第 {volume} 卷', { volume: item.volume + 1 })}
              </option>
            ))}
          </select>
        </label>
      ) : null}
      {url ? <OfflineMedia url={url} audio={content.mediaKind === 'voice'} /> : null}
    </>
  );
}

export function OfflinePage({ taskId }: { taskId: string }) {
  const allowIncomplete = new URLSearchParams(window.location.search).get('incomplete') === '1';
  const state = useResource<OfflineContent>(
    '/offline/' + encodeURIComponent(taskId) + (allowIncomplete ? '?allowIncomplete=true' : ''),
  );
  return (
    <section className="offline-content" aria-label={t('离线内容')}>
      <header className="page-header">
        <div>
          <h1>{t('离线阅读与播放')}</h1>
          <p>{state.data?.incomplete ? t('正在边下边读，新页面下载完成后可点击刷新加载。') : t('使用本机已完成的下载文件。')}</p>
        </div>
        <div className="action-row" style={{ margin: 0 }}>
          {state.data?.incomplete ? (
            <button type="button" className="chip" onClick={state.reload}>
              {t('刷新已下载页')}
            </button>
          ) : null}
          <a className="secondary-link navigation-link" href="/downloads">
            {t('下载')}
          </a>
        </div>
      </header>
      {state.error ? (
        <>
          <Notice error={state.error} />
          <button className="chip" onClick={state.reload}>
            {t('重试本地内容')}
          </button>
        </>
      ) : !state.data ? (
        <p role="status">{t('正在读取本地文件…')}</p>
      ) : (
        <>
          {state.data.previewOnly ? <p role="status">{t('仅原站公开预览')}</p> : null}
          {state.data.blocks ? (
            <article className="article-reader">
              {state.data.blocks.map((block, index) =>
                block.type === 'text' ? (
                  <p key={index} style={{ whiteSpace: 'pre-wrap' }}>
                    {block.text}
                  </p>
                ) : block.type === 'image' ? (
                  <LocalImage key={index} page={{ index, url: block.url! }} />
                ) : (
                  <div className="article-video-block" key={index}>
                    <OfflineMedia url={block.url!} audio={false} />
                  </div>
                ),
              )}
            </article>
          ) : null}
          {state.data.mediaUrl ? <OfflinePlayback content={state.data} /> : null}
          {state.data.paragraphs ? (
            <article className="chapter-text" style={{ maxWidth: '70ch', marginInline: 'auto' }}>
              {state.data.paragraphs.map((paragraph, index) => (
                <p key={index}>{paragraph}</p>
              ))}
            </article>
          ) : null}
          {state.data.pages.length ? (
            <div className="reader-canvas offline-image-reader">
              <ImageReaderLayout
                count={state.data.pages.length}
                renderPage={(index, _active, cropMargins) => (
                  <LocalImage page={state.data!.pages[index]!} cropMargins={cropMargins} />
                )}
              />
            </div>
          ) : null}
          {state.data.files
            .filter((file) => !state.data!.blocks && ['script', 'subtitle', 'attachment'].includes(file.kind))
            .map((file) => (
              <p key={file.id}>
                <a href={file.url} download>
                  {file.kind === 'subtitle' ? t('保存字幕') : file.kind === 'attachment' ? t('保存附件') : t('保存台本')}
                </a>
              </p>
            ))}
        </>
      )}
    </section>
  );
}

type Category = { id: string; name: string; version: number; sort: number };
export function LibraryManagement() {
  const state = useResource<{ items: Category[] }>('/categories');
  const history = useResource<{ items: HistoryEntry[] }>('/history?limit=200');
  const [name, setName] = useState('');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);
  const [selected, setSelected] = useState<string[]>([]);
  const [drafts, setDrafts] = useState<Record<string, string>>({});

  const run = async (action: () => Promise<unknown>) => {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      await action();
      state.reload();
      history.reload();
      setNotice(t('已保存。'));
    } catch (reason) {
      setError(message(reason));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section id="library-management" tabIndex={-1} className="section-block" aria-label={t('分类与历史管理')}>
      <h2>{t('分类管理')}</h2>
      <form
        className="form-row"
        onSubmit={(event) => {
          event.preventDefault();
          void run(async () => {
            await write('/categories', 'POST', { name: name.trim() });
            setName('');
          });
        }}
      >
        <label>
          {t('新分类名称')}
          <input value={name} onChange={(event) => setName(event.target.value)} maxLength={128} required disabled={busy} />
        </label>
        <button className="primary-link" disabled={busy || !name.trim()}>
          {t('创建分类')}
        </button>
      </form>
      <Notice error={error || state.error || history.error} notice={notice} />
      <ul className="chapter-list">
        {state.data?.items.map((category, index) => (
          <li key={category.id} style={{ padding: 16 }}>
            <form
              className="form-row"
              onSubmit={(event) => {
                event.preventDefault();
                void run(() =>
                  write('/categories/' + encodeURIComponent(category.id), 'PATCH', {
                    name: (drafts[category.id] ?? category.name).trim(),
                    version: category.version,
                  }),
                );
              }}
            >
              <label>
                {t('分类名称')}
                <input
                  aria-label={t('分类名称 ') + category.name}
                  value={drafts[category.id] ?? category.name}
                  maxLength={128}
                  disabled={busy}
                  onChange={(event) => setDrafts((value) => ({ ...value, [category.id]: event.target.value }))}
                />
              </label>
              <button
                className="chip"
                aria-label={t('保存分类') + ' ' + category.name}
                disabled={
                  busy ||
                  !(drafts[category.id] ?? category.name).trim() ||
                  (drafts[category.id] ?? category.name).trim() === category.name
                }
              >
                {t('保存分类')}
              </button>
            </form>
            <div className="action-row">
              <button
                className="chip"
                aria-label={t('上移') + ' ' + category.name}
                disabled={busy || index === 0}
                onClick={() =>
                  void run(() =>
                    write('/categories/' + encodeURIComponent(category.id), 'PATCH', {
                      sort: (state.data!.items[index - 1]?.sort ?? 0) - 0.5,
                      version: category.version,
                    }),
                  )
                }
              >
                {t('上移')}
              </button>
              <button
                className="chip danger-action"
                aria-label={t('删除') + ' ' + category.name}
                disabled={busy}
                onClick={async () => {
                  const ok = await confirmAction({
                    title: t('删除分类“') + category.name + t('”？作品、收藏和下载都会保留。'),
                    confirmLabel: t('删除'),
                    danger: true,
                  });
                  if (ok) void run(() => write('/categories/' + encodeURIComponent(category.id), 'DELETE', { version: category.version }));
                }}
              >
                {t('删除')}
              </button>
            </div>
          </li>
        ))}
      </ul>
      {state.data && !state.data.items.length ? <p>{t('还没有分类，创建后可在作品中归类。')}</p> : null}

      <h2>{t('历史管理')}</h2>
      <p>{t('删除访问记录不会删除收藏或下载文件。')}</p>
      <ul className="chapter-list">
        {history.data?.items.map((item) => {
          const id = JSON.stringify([item.source, item.workId, item.chapterId ?? null]);
          return (
            <li key={id} style={{ padding: 12 }}>
              <label>
                <input
                  type="checkbox"
                  checked={selected.includes(id)}
                  disabled={busy}
                  onChange={(event) =>
                    setSelected((value) => (event.target.checked ? [...value, id] : value.filter((k) => k !== id)))
                  }
                />
                {item.source} · {item.workTitle ?? item.chapterTitle ?? item.workId}
              </label>
            </li>
          );
        })}
      </ul>
      <div className="action-row">
        <button
          className="chip danger-action"
          disabled={busy || !selected.length}
          onClick={async () => {
            const ok = await confirmAction({
              title: t('删除所选访问记录？收藏、已读状态和下载文件都会保留。'),
              confirmLabel: t('删除'),
              danger: true,
            });
            if (ok) {
              void run(async () => {
                await write('/history', 'DELETE', { scopeKeys: selected });
                setSelected([]);
              });
            }
          }}
        >
          {t('删除所选历史（')}
          {selected.length}）
        </button>
        <button
          className="chip danger-action"
          disabled={busy}
          onClick={async () => {
            const ok = await confirmAction({
              title: t('清空全部访问历史？此操作不删除收藏或下载。'),
              confirmLabel: t('清空历史'),
              danger: true,
            });
            if (ok) void run(() => write('/history', 'DELETE', { all: true }));
          }}
        >
          {t('清空历史')}
        </button>
      </div>
    </section>
  );
}

type UpdateEvent = {
  event_id: string;
  source: string;
  kind?: string;
  title?: string;
  contentId?: string;
  content_id?: string;
  workId?: string;
  chapterId?: string;
  unread: number;
  targets: string[];
};

export function SubscriptionUpdates({ navigate }: { navigate: (url: string) => void }) {
  const state = useResource<{ items: UpdateEvent[] }>('/subscription-events');
  const [error, setError] = useState('');
  const [unreadOnly, setUnreadOnly] = useState(false);

  const read = async (ids: string[]) => {
    try {
      await api.readEvents(ids);
      state.reload();
    } catch (reason) {
      setError(message(reason));
    }
  };

  const visible = (state.data?.items ?? []).filter((item) => !unreadOnly || item.unread > 0);

  return (
    <section className="section-block" aria-label={t('更新内容')}>
      <div className="section-header">
        <h2>{t('更新内容')}</h2>
        <button
          type="button"
          className={`chip ${unreadOnly ? 'active' : ''}`}
          aria-pressed={unreadOnly}
          onClick={() => setUnreadOnly((v) => !v)}
        >
          {t('仅看未读')}
        </button>
      </div>
      <Notice error={error || state.error} />
      {!state.data && !state.error ? <p role="status">{t('正在读取更新…')}</p> : null}
      {state.data && !visible.length ? <p>{t('建立基线后，新发现的内容会显示在这里。')}</p> : null}
      <ul className="chapter-list">
        {visible.map((item) => {
          const id = item.contentId ?? item.content_id ?? '';
          const href =
            item.kind === 'chapter' && item.workId && item.chapterId
              ? '/work/' + [item.source, item.workId].map(encodeURIComponent).join('/') + '?chapter=' + encodeURIComponent(item.chapterId)
              : item.kind === 'post'
                ? '/post/' + [item.source, id].map(encodeURIComponent).join('/')
                : '/work/' + [item.source, item.workId ?? id].map(encodeURIComponent).join('/');
          return (
            <li key={item.event_id}>
              <a
                href={href}
                onClick={(event) => {
                  if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
                  event.preventDefault();
                  if (item.unread) setTimeout(() => void read([item.event_id]), 600);
                  navigate(href);
                }}
              >
                <span>
                  {item.unread ? <strong>{t('未读 · ')}</strong> : ''}
                  {item.title ?? id}
                  <small className="chapter-state">
                    {' '}
                    · {item.source}
                    {t(' · 关联')}
                    {item.targets.length}
                    {t('个订阅')}
                  </small>
                </span>
              </a>
              {item.unread ? (
                <button className="chip" onClick={() => void read([item.event_id])}>
                  {t('标为已读')}
                </button>
              ) : null}
            </li>
          );
        })}
      </ul>
    </section>
  );
}

/** Zero-Base64 Server-Side Lossless Streaming Export (CBZ with ComicInfo.xml, lossless PDF, or raw media). */
export function DownloadExtras({ task }: { task: DownloadTask }) {
  if (task.status !== 'completed') return null;
  return (
    <div className="action-row" style={{ marginTop: 8 }}>
      <a className="chip navigation-link" href={'/offline/' + encodeURIComponent(task.taskId)}>
        {t('离线打开')}
      </a>
      {task.mediaKind === 'comic' ? (
        <>
          <a className="chip" download href={api.downloadExportUrl(task.taskId, 'cbz')}>
            {t('导出CBZ')}
          </a>
          <a className="chip" download href={api.downloadExportUrl(task.taskId, 'pdf')}>
            {t('导出PDF')}
          </a>
        </>
      ) : (
        <a className="chip" download href={api.downloadExportUrl(task.taskId, 'raw')}>
          {t('保存文件')}
        </a>
      )}
    </div>
  );
}

export function ImportComic() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const importFile = async (file: File) => {
    setBusy(true);
    setError('');
    setNotice(t('正在检查漫画文件…'));
    try {
      if (file.size > 512 * 1024 * 1024) throw Error(t('CBZ文件不能超过512MiB。'));
      await api.importCbzFile(file);
      changed();
      setNotice(t('漫画已导入（已解析 ComicInfo.xml 元数据），可从下载列表离线打开。'));
    } catch (reason) {
      setError(message(reason));
      setNotice('');
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="settings-panel" aria-label={t('导入本地漫画')}>
      <h2>{t('导入CBZ漫画')}</h2>
      <FilePicker
        label={t('选择CBZ文件')}
        accept=".cbz,application/zip,application/vnd.comicbook+zip"
        disabled={busy}
        onChange={(event) => {
          const file = event.target.files?.[0];
          if (file) void importFile(file);
          event.target.value = '';
        }}
      />
      <Notice error={error} notice={notice} />
    </section>
  );
}
