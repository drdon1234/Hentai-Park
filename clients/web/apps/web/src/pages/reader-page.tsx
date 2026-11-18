import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { StatusMessage } from '@hentai-park/design-system';
import { chapterIdentityKey } from '@hentai-park/domain-model';
import { ApiError, api, directImageUrl, mediaUrl, type MediaTokenRequest, type ReaderPayload } from '../api.js';
import { navigateClick } from '../app/app-context.js';
import { MediaChoices, ReaderNavigation } from '../content-controls.js';
import { CoverImage } from '../cover-image.js';
import { t } from '../i18n.js';
import { ImageReaderLayout } from '../image-reader-layout.js';
import { cropComicMargins, restoreImage } from '../image-transform.js';
import { SelectedTextTranslation, TranslateText } from '../language-tools.js';
import { LiveChat } from '../live-chat.js';
import { loadHls, playerModuleError } from '../load-hls.js';
import { useMediaGrant } from '../media-grant.js';
import { MediaSurface } from '../media-surface.js';
import { useMediaLifecycle, useSharedState, type ProgressState } from '../native.js';
import { NovelReader } from '../novel-reader.js';
import { StateView, errorMessage, useAsync } from '../page-ui.js';
import { usePreferences } from '../preferences.js';
import { ReadingChrome } from '../reading-chrome.js';
import { RecordingControls } from '../recording-controls.js';
import { MediaLightboxModal, type LightboxMediaItem } from '../shared/media-lightbox.js';
import { ControlledWebPlayer } from '../web-player.js';

export function AuthorizedImage({
  authorization,
  alt,
  transform,
  cropMargins = false,
  width,
  height,
  retryGeneration = 0,
  active = true,
  controlled = false,
  className = '',
  retryLabel = t('重试此页'),
}: {
  authorization: NonNullable<ReaderPayload['pages']>[number]['mediaAuthorization'];
  alt: string;
  transform?: NonNullable<ReaderPayload['pages']>[number]['transform'];
  cropMargins?: boolean;
  width?: number;
  height?: number;
  retryGeneration?: number;
  active?: boolean;
  controlled?: boolean;
  className?: string;
  retryLabel?: string;
}) {
  const canvas = useRef<HTMLCanvasElement | null>(null);
  const root = useRef<HTMLDivElement | null>(null);
  const [near, setNear] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [fallbackToken, setFallbackToken] = useState<string>();
  const [canvasReady, setCanvasReady] = useState(false);
  const [error, setError] = useState<string>();
  const scrollAtRetry = useRef<number | undefined>(undefined);
  const direct = directImageUrl(authorization);
  const needsCanvas = Boolean(transform || cropMargins);

  useEffect(() => {
    const node = root.current;
    if (!node || !active) {
      setNear(false);
      return;
    }
    let visible = false;
    const update = () => setNear(visible && !document.hidden);
    const check = () => {
      const box = node.getBoundingClientRect();
      visible = node.getClientRects().length > 0 && box.bottom > -400 && box.top < window.innerHeight + 400;
      update();
    };
    let observer: IntersectionObserver | undefined;
    if (typeof IntersectionObserver !== 'undefined') {
      observer = new IntersectionObserver(
        (entries) => {
          visible = entries.some((entry) => entry.isIntersecting);
          update();
        },
        { rootMargin: '400px 0px' },
      );
      observer.observe(node);
    } else {
      check();
      window.addEventListener('scroll', check, { passive: true });
      window.addEventListener('resize', check);
    }
    document.addEventListener('visibilitychange', update);
    return () => {
      observer?.disconnect();
      window.removeEventListener('scroll', check);
      window.removeEventListener('resize', check);
      document.removeEventListener('visibilitychange', update);
    };
  }, [active]);

  useEffect(() => {
    setCanvasReady(false);
    setError(undefined);
    if ((!near && !controlled) || !active || !authorization || direct) return;
    setFallbackToken(undefined);
    const abort = new AbortController();
    let live = true;
    void api
      .mediaToken(authorization, abort.signal)
      .then((value) => {
        if (live) setFallbackToken(value.token);
      })
      .catch((reason) => {
        if (live && !abort.signal.aborted) setError(errorMessage(reason));
      });
    return () => {
      live = false;
      abort.abort();
    };
  }, [authorization, direct, retryGeneration, attempt, near, controlled, active, cropMargins]);

  const shouldRender = (near || controlled) && active;
  const resolvedSrc = !shouldRender
    ? undefined
    : direct
      ? direct + (attempt > 0 || retryGeneration > 0 ? `?retry=${retryGeneration}_${attempt}` : '')
      : fallbackToken
        ? mediaUrl(fallbackToken)
        : undefined;

  return (
    <div
      ref={root}
      className={'authorized-image ' + className}
      style={width && height && width > 0 && height > 0 && !canvasReady ? { aspectRatio: width + ' / ' + height } : undefined}
    >
      {error ? (
        <div className="image-error" role="status">
          <span>{error}</span>
          <button
            className="chip"
            onClick={() => {
              scrollAtRetry.current = window.scrollY;
              setAttempt((value) => value + 1);
            }}
          >
            {retryLabel}
          </button>
        </div>
      ) : resolvedSrc ? (
        <>
          {needsCanvas ? <canvas ref={canvas} role="img" aria-label={alt} hidden={!canvasReady} /> : null}
          <img
            src={resolvedSrc}
            crossOrigin={needsCanvas ? 'use-credentials' : undefined}
            alt={needsCanvas && canvasReady ? '' : alt}
            hidden={Boolean(transform || (cropMargins && canvasReady))}
            aria-hidden={needsCanvas && canvasReady ? true : undefined}
            loading={needsCanvas || controlled ? 'eager' : 'lazy'}
            decoding="async"
            onError={() => setError(t('图片加载失败，请重试。'))}
            onLoad={(event) => {
              try {
                if (transform && canvas.current) {
                  restoreImage(canvas.current, event.currentTarget, transform);
                  if (cropMargins) {
                    const tmp = document.createElement('canvas');
                    if (cropComicMargins(tmp, canvas.current)) {
                      canvas.current.width = tmp.width;
                      canvas.current.height = tmp.height;
                      canvas.current.getContext('2d')?.drawImage(tmp, 0, 0);
                    }
                  }
                  setCanvasReady(true);
                } else if (cropMargins && canvas.current) {
                  setCanvasReady(cropComicMargins(canvas.current, event.currentTarget));
                }
                if (scrollAtRetry.current !== undefined) {
                  window.scrollTo({ top: scrollAtRetry.current, behavior: 'auto' });
                  scrollAtRetry.current = undefined;
                }
              } catch (reason) {
                setError(errorMessage(reason));
              }
            }}
          />
        </>
      ) : (
        <div className="image-placeholder" aria-hidden="true">
          {t('图片待加载')}
        </div>
      )}
    </div>
  );
}

function AuthorizedTrack({
  track,
  selected,
  generation,
  onFailure,
}: {
  track: NonNullable<ReaderPayload['subtitles']>[number];
  selected: boolean;
  generation: number;
  onFailure: (message: string) => void;
}) {
  const [token, setToken] = useState<string>();
  const failure = useRef(onFailure);
  failure.current = onFailure;
  useEffect(() => {
    if (!selected) return;
    setToken(undefined);
    const abort = new AbortController();
    void api
      .mediaToken(track.mediaAuthorization, abort.signal)
      .then((value) => setToken(value.token))
      .catch((error) => {
        if (!abort.signal.aborted) failure.current(track.label + '：' + errorMessage(error));
      });
    return () => abort.abort();
  }, [track.mediaAuthorization, generation, selected]);
  return (
    <track
      src={token ? mediaUrl(token) : undefined}
      label={track.label}
      srcLang={track.language}
      kind="subtitles"
      default={selected}
      onError={() => {
        if (selected) failure.current(track.label + t('字幕加载失败，可重新加载字幕。'));
      }}
    />
  );
}

export function InlineMedia({
  load,
  reload,
  autoplay = false,
}: {
  autoplay?: boolean;
  load: (signal: AbortSignal) => Promise<ReaderPayload>;
  reload?: (signal: AbortSignal) => Promise<ReaderPayload>;
}) {
  const [attempt, setAttempt] = useState(0);
  const state = useAsync((signal) => (attempt > 0 && reload ? reload(signal) : load(signal)), [load, reload, attempt]);
  const [token, setToken] = useState<string>();
  const [error, setError] = useState<string>();
  const [media, setMedia] = useState<HTMLMediaElement | null>(null);
  const position = useRef(0);
  const paused = useRef(true);
  const changing = useCallback(() => {
    if (media) {
      position.current = media.currentTime;
      paused.current = media.paused;
    }
  }, [media]);
  const grant = useMediaGrant(state.data?.mediaAuthorization, attempt, changing);
  useEffect(() => {
    setToken(grant.token);
    setError(grant.error);
  }, [grant.token, grant.error]);
  useEffect(() => {
    if (!media || !position.current) return;
    const restore = () => {
      media.currentTime = position.current;
      if (!paused.current) void media.play().catch(() => {});
    };
    media.addEventListener('loadedmetadata', restore, { once: true });
    return () => media.removeEventListener('loadedmetadata', restore);
  }, [media, token]);
  useEffect(() => {
    if (!media || !autoplay) return;
    const play = () => {
      void media.play().catch(() => {});
    };
    media.addEventListener('canplay', play, { once: true });
    if (media.readyState >= 2) play();
    return () => media.removeEventListener('canplay', play);
  }, [media, autoplay]);
  useEffect(
    () => () => {
      if (media) {
        media.pause();
        media.removeAttribute('src');
        media.load();
      }
    },
    [media],
  );
  return (
    <div className="inline-media-frame">
      <StateView loading={state.loading} error={state.error} empty={false}>
        {state.data ? (
          <ReaderContent
            reader={state.data}
            mediaKind={state.data.mediaKind}
            formatHint={state.data.format}
            token={token}
            mediaError={error}
            initialPage={0}
            retryGeneration={attempt}
            setMedia={setMedia}
            setMediaError={setError}
            onPageChange={() => {}}
            onRetry={() => {
              changing();
              setAttempt((v) => v + 1);
            }}
          />
        ) : null}
      </StateView>
    </div>
  );
}

function ArticleVideo({
  source,
  workId,
  id,
  showBlocked,
}: {
  source: string;
  workId: string;
  id: string;
  showBlocked?: boolean;
}) {
  const load = useCallback(
    (signal: AbortSignal) => api.articleMedia(source, workId, id, signal, showBlocked),
    [source, workId, id, showBlocked],
  );
  return <InlineMedia load={load} autoplay />;
}

function ArticleContent({
  reader,
  initialPage,
  onPageChange,
  navigate,
  showBlocked,
}: {
  showBlocked?: boolean;
  reader: ReaderPayload;
  initialPage: number;
  onPageChange: (page: number) => void;
  navigate: (to: string) => void;
}) {
  const [active, setActive] = useState<string>();
  const [lightboxIndex, setLightboxIndex] = useState<number>();
  const restoring = useRef(false);
  const elements = useRef<Array<HTMLDivElement | null>>([]);
  const save = useRef(onPageChange);
  save.current = onPageChange;

  useEffect(() => {
    const target = elements.current[initialPage];
    restoring.current = initialPage > 0;
    const stop = () => {
      restoring.current = false;
      resize.disconnect();
    };
    const restore = () => {
      if (restoring.current) target?.scrollIntoView({ block: 'start' });
    };
    const resize = new ResizeObserver(restore);
    if (restoring.current) {
      for (const element of elements.current.slice(0, initialPage + 1)) if (element) resize.observe(element);
      restore();
    }
    for (const name of ['wheel', 'pointerdown', 'keydown']) window.addEventListener(name, stop, { once: true });
    const observer = new IntersectionObserver(
      (entries) => {
        if (restoring.current) return;
        for (const entry of entries) {
          if (entry.isIntersecting) save.current(Number((entry.target as HTMLElement).dataset.block));
        }
      },
      { rootMargin: '-15% 0px -65% 0px' },
    );
    for (const element of elements.current) if (element) observer.observe(element);
    return () => {
      observer.disconnect();
      resize.disconnect();
      for (const name of ['wheel', 'pointerdown', 'keydown']) window.removeEventListener(name, stop);
    };
  }, [reader]);

  useEffect(() => {
    const stop = () => setActive(undefined);
    window.addEventListener('pagehide', stop);
    return () => window.removeEventListener('pagehide', stop);
  }, []);

  const imageBlocks: LightboxMediaItem[] = (reader.blocks ?? []).flatMap<LightboxMediaItem>(
    (block, idx) =>
      block.type === 'image'
        ? [{ id: String(idx), type: 'image', authorization: block.mediaAuthorization }]
        : [],
  );

  return (
    <article className="article-reader" aria-label={t('文章正文')}>
      <h1>{reader.workTitle}</h1>
      {reader.blocks?.map((block, index) => (
        <div
          key={index}
          data-block={index}
          data-block-type={block.type}
          ref={(element) => {
            elements.current[index] = element;
          }}
        >
          {block.type === 'text' ? (
            <p className="article-text">{block.text}</p>
          ) : block.type === 'image' ? (
            <button
              className="article-media-open"
              aria-label={t('查看正文图片 ') + (index + 1)}
              onClick={() => {
                const pos = imageBlocks.findIndex((b) => b.id === String(index));
                if (pos >= 0) setLightboxIndex(pos);
              }}
            >
              <AuthorizedImage authorization={block.mediaAuthorization} alt={t('正文图片 ') + (index + 1)} />
            </button>
          ) : (
            <section className="article-video" aria-label={t('帖内视频 ') + (index + 1)}>
              {active === block.id ? (
                <>
                  <ArticleVideo key={block.id} source={reader.source} workId={reader.workId} id={block.id} showBlocked={showBlocked} />
                  <button className="chip" onClick={() => setActive(undefined)}>
                    {t('关闭视频')}
                  </button>
                </>
              ) : (
                <div className="article-video-poster">
                  {block.previewAuthorization ? (
                    <AuthorizedImage authorization={block.previewAuthorization} alt={t('视频预览')} />
                  ) : null}
                  <button
                    className="article-video-play"
                    aria-label={t('播放视频 ') + (index + 1)}
                    onClick={() => {
                      save.current(index);
                      setActive(block.id);
                    }}
                  >
                    <svg viewBox="0 0 48 48" width="56" height="56" aria-hidden="true">
                      <circle cx="24" cy="24" r="22" fill="rgba(0,0,0,.6)" />
                      <path d="m19 13 17 11-17 11Z" fill="white" />
                    </svg>
                    <span>{t('播放视频')}</span>
                  </button>
                </div>
              )}
            </section>
          )}
        </div>
      ))}
      <nav className="tag-row" aria-label={t('文章标签')}>
        {reader.tagLinks?.map((tag) => {
          const href = '/source/' + encodeURIComponent(reader.source) + '?link=' + encodeURIComponent(tag.url);
          return (
            <a className="chip" key={tag.url} href={href} onClick={(event) => navigateClick(event, navigate, href)}>
              {tag.name}
            </a>
          );
        })}
      </nav>
      <SelectedTextTranslation />
      <MediaLightboxModal
        open={lightboxIndex !== undefined}
        title={reader.workTitle}
        items={imageBlocks}
        index={lightboxIndex ?? 0}
        onIndexChange={setLightboxIndex}
        onClose={() => setLightboxIndex(undefined)}
      />
    </article>
  );
}

export function ReaderContent({
  reader,
  mediaKind,
  formatHint,
  playbackOptions,
  token,
  mediaError,
  initialPage,
  retryGeneration,
  setMedia,
  setMediaError,
  onPageChange,
  onRetry,
  chapterFooter,
}: {
  reader: ReaderPayload;
  mediaKind: string;
  formatHint?: string;
  playbackOptions?: ReactNode;
  token?: string;
  mediaError?: string;
  initialPage: number;
  retryGeneration: number;
  setMedia: (media: HTMLMediaElement | null) => void;
  setMediaError: (message: string) => void;
  onPageChange: (page: number) => void;
  onRetry: () => void;
  chapterFooter?: ReactNode;
}) {
  const prefs = usePreferences();
  const pages = reader.pages ?? [];
  const [rate, setRate] = useState(1);
  const mediaRef = useRef<HTMLMediaElement | null>(null);

  useEffect(() => {
    setRate(Number(prefs.settings.playbackRate));
    if (mediaRef.current) mediaRef.current.playbackRate = Number(prefs.settings.playbackRate);
  }, [prefs.settings.playbackRate]);

  useEffect(() => {
    const hidden = () => {
      if (document.hidden && mediaKind === 'voice' && prefs.settings.voiceBackgroundPlayback !== true) {
        mediaRef.current?.pause();
      }
    };
    document.addEventListener('visibilitychange', hidden);
    return () => document.removeEventListener('visibilitychange', hidden);
  }, [mediaKind, prefs.settings.voiceBackgroundPlayback]);

  const audioWork = useAsync(
    (signal) =>
      mediaKind === 'voice' && reader.source && reader.workId
        ? api.work(reader.source, reader.workId, signal)
        : Promise.resolve(undefined),
    [mediaKind, reader.source, reader.workId],
  );
  const audio = mediaKind === 'voice';
  const playback = audio || mediaKind === 'video';
  const [controlError, setControlError] = useState('');
  const canFullscreen = document.fullscreenEnabled !== false && typeof document.documentElement.requestFullscreen === 'function';
  const displayControl = (name: string, action: () => Promise<unknown>) => {
    setControlError('');
    const failed = (error: unknown) =>
      setControlError(
        name +
          t('不可用：') +
          errorMessage(error) +
          (playback ? t('。普通播放器仍可继续使用。') : t('。当前阅读布局仍可继续使用。')),
      );
    try {
      void action().catch(failed);
    } catch (error) {
      failed(error);
    }
  };
  const controlNotice = controlError ? (
    <StatusMessage tone="warning" title={t('显示控制不可用')}>
      {controlError}
      <button className="chip" onClick={() => setControlError('')}>
        {t('关闭显示提示')}
      </button>
    </StatusMessage>
  ) : null;

  const [subtitleErrors, setSubtitleErrors] = useState<string[]>([]);
  const [subtitleAttempt, setSubtitleAttempt] = useState(0);
  const [subtitleIndex, setSubtitleIndex] = useState(
    Math.max(0, reader.subtitles?.findIndex((track) => track.language === 'zh') ?? 0),
  );
  const [cueText, setCueText] = useState('');
  const [cueList, setCueList] = useState<Array<{ startTime: number; endTime: number; text: string }>>([]);
  const [activeCueIdx, setActiveCueIdx] = useState(-1);

  const subtitleFailure = useCallback((message: string) => setSubtitleErrors((value) => [...new Set([...value, message])]), []);

  useEffect(() => {
    if (!audio) return;
    const media = mediaRef.current;
    if (!media) return;
    const observed = new Set<TextTrack>();
    const syncCues = () => {
      const selected = media.textTracks[subtitleIndex];
      const all = Array.from(selected?.cues ?? []).map((item) => ({
        startTime: item.startTime,
        endTime: item.endTime,
        text: 'text' in item ? String((item as VTTCue).text) : '',
      }));
      setCueList(all);
      const activeText = Array.from(selected?.activeCues ?? [])
        .map((item) => ('text' in item ? String((item as VTTCue).text) : ''))
        .join('\n');
      setCueText(activeText);
      const activeIdx = all.findIndex((c) => media.currentTime >= c.startTime && media.currentTime <= c.endTime);
      setActiveCueIdx(activeIdx);
    };
    const configure = () => {
      Array.from(media.textTracks).forEach((track, index) => {
        track.mode = index === subtitleIndex ? 'hidden' : 'disabled';
        if (!observed.has(track)) {
          observed.add(track);
          track.addEventListener('cuechange', syncCues);
        }
      });
      syncCues();
    };
    media.textTracks.addEventListener('addtrack', configure);
    media.addEventListener('loadedmetadata', configure);
    media.addEventListener('loadeddata', configure);
    configure();
    return () => {
      media.textTracks.removeEventListener('addtrack', configure);
      media.removeEventListener('loadedmetadata', configure);
      media.removeEventListener('loadeddata', configure);
      observed.forEach((track) => track.removeEventListener('cuechange', syncCues));
    };
  }, [audio, token, subtitleIndex, subtitleAttempt]);

  const subtitleTracks = (reader.subtitles ?? []).map((track, index) => (
    <AuthorizedTrack
      key={track.mediaAuthorization.authorizationId}
      track={track}
      selected={index === subtitleIndex}
      generation={subtitleAttempt}
      onFailure={subtitleFailure}
    />
  ));

  const currentRate = useRef(rate);
  currentRate.current = rate;
  const attachMedia = useCallback(
    (element: HTMLMediaElement | null) => {
      mediaRef.current = element;
      if (element) element.playbackRate = currentRate.current;
      setMedia(element);
    },
    [setMedia],
  );
  const mediaFailure = useRef(setMediaError);
  mediaFailure.current = setMediaError;

  /* MediaSession lock-screen controls & metadata */
  useEffect(() => {
    if (!playback || !('mediaSession' in navigator)) return;
    try {
      const coverUrl = audioWork.data?.coverAuthorization ? directImageUrl(audioWork.data.coverAuthorization) : undefined;
      navigator.mediaSession.metadata = new MediaMetadata({
        title: reader.title || reader.workTitle || 'HentaiPark',
        artist: reader.workTitle || reader.source || '',
        artwork: coverUrl ? [{ src: coverUrl }] : [],
      });
      navigator.mediaSession.setActionHandler('play', () => void mediaRef.current?.play().catch(() => {}));
      navigator.mediaSession.setActionHandler('pause', () => mediaRef.current?.pause());
      navigator.mediaSession.setActionHandler('seekbackward', () => {
        if (mediaRef.current) mediaRef.current.currentTime = Math.max(0, mediaRef.current.currentTime - 10);
      });
      navigator.mediaSession.setActionHandler('seekforward', () => {
        if (mediaRef.current) mediaRef.current.currentTime = mediaRef.current.currentTime + 10;
      });
    } catch {
      /* Optional MediaSession */
    }
  }, [playback, reader.title, reader.workTitle, reader.source, audioWork.data?.coverAuthorization]);

  /* Direct format-hinted attachment: eliminates blocking HEAD probe when `format` is already known! */
  useEffect(() => {
    if (!playback || !token) return;
    const media = mediaRef.current;
    if (!media) return;
    const abort = new AbortController();
    let live = true;
    let destroy: (() => void) | undefined;
    const source = mediaUrl(token);
    const effectiveFormat = formatHint ?? reader.format;

    void (async () => {
      let isHls = effectiveFormat === 'hls' || /m3u8|mpegurl/i.test(effectiveFormat ?? '');
      if (!effectiveFormat) {
        const response = await fetch(source, { method: 'HEAD', credentials: 'include', signal: abort.signal });
        if (!response.ok) {
          throw new Error(
            t(response.status === 401 || response.status === 403 ? '播放权限验证失败，请重新加载。' : '播放内容加载失败，请重试。'),
          );
        }
        isHls = /mpegurl/i.test(response.headers.get('content-type') ?? '');
      }
      if (!live) return;
      if (isHls && media.canPlayType('application/vnd.apple.mpegurl') !== 'probably') {
        const { attachHls } = await loadHls();
        if (!live) return;
        destroy = attachHls(media, source, (message) => mediaFailure.current(message));
      } else {
        media.src = source;
      }
    })().catch((error) => {
      if (live && !abort.signal.aborted) mediaFailure.current(errorMessage(error));
    });

    return () => {
      live = false;
      abort.abort();
      destroy?.();
      media.removeAttribute('src');
      media.load();
    };
  }, [playback, token, formatHint, reader.format]);

  const onMediaError = () => setMediaError(t('媒体加载失败，请重试播放。'));
  const fullscreen = () => {
    const target = mediaRef.current?.requestFullscreen ? mediaRef.current : document.documentElement;
    if (typeof target.requestFullscreen !== 'function') {
      setControlError(t('浏览器未提供全屏，当前内容仍可正常使用。'));
      return;
    }
    displayControl(t('全屏'), () => target.requestFullscreen());
  };

  if (playback) {
    return (
      <div className="media-stage">
        {prefs.error ? <p role="status">{prefs.error}</p> : null}
        {controlNotice}
        <MediaSurface
          audio={audio}
          title={reader.workTitle || reader.title}
          subtitle={reader.title}
          artwork={
            audioWork.data?.coverAuthorization ? (
              <CoverImage authorization={audioWork.data.coverAuthorization} alt={audioWork.data.title} />
            ) : undefined
          }
          settings={
            <>
              <div className="reader-controls">
                <label>
                  {t('播放速度')}
                  <select
                    aria-label={t('播放速度')}
                    value={rate}
                    onChange={(event) => {
                      const value = Number(event.target.value);
                      setRate(value);
                      void prefs.save({ playbackRate: value });
                      if (mediaRef.current) mediaRef.current.playbackRate = value;
                    }}
                  >
                    {[0.5, 1, 1.25, 1.5, 2].map((value) => (
                      <option key={value} value={value}>
                        {value}×
                      </option>
                    ))}
                  </select>
                </label>
                {!audio &&
                token &&
                !mediaError &&
                document.pictureInPictureEnabled &&
                typeof HTMLVideoElement.prototype.requestPictureInPicture === 'function' ? (
                  <button
                    className="chip"
                    onClick={() => {
                      const video = mediaRef.current as HTMLVideoElement | null;
                      if (video) displayControl(t('画中画'), () => video.requestPictureInPicture());
                    }}
                  >
                    {t('画中画')}
                  </button>
                ) : null}
              </div>
              {playbackOptions}
            </>
          }
        >
          {mediaError ? (
            <StatusMessage tone="danger" title={t('媒体加载失败')}>
              {mediaError}
              <button className="chip" onClick={mediaError === playerModuleError() ? () => window.location.reload() : onRetry}>
                {mediaError === playerModuleError() ? t('刷新页面') : t('重试播放')}
              </button>
            </StatusMessage>
          ) : token ? (
            audio ? (
              <audio ref={attachMedia} controls preload="metadata" aria-label={t('作品音频播放器')} onError={onMediaError}>
                {subtitleTracks}
              </audio>
            ) : (
              <video ref={attachMedia} controls preload="metadata" playsInline aria-label={t('作品视频播放器')} onError={onMediaError}>
                {subtitleTracks}
              </video>
            )
          ) : (
            <StatusMessage title={t('正在加载播放内容')}>{t('正在准备播放，请稍候。')}</StatusMessage>
          )}
        </MediaSurface>

        <div className="media-caption" hidden={audio}>
          <h1>{reader.workTitle || (audio ? t('音声播放器') : t('视频播放器'))}</h1>
          <p>{reader.title}</p>
        </div>

        {subtitleErrors.length ? (
          <StatusMessage tone="warning" title={t('部分字幕不可用')}>
            {subtitleErrors.join('；')}
            <button
              className="chip"
              onClick={() => {
                setSubtitleErrors([]);
                setSubtitleAttempt((value) => value + 1);
              }}
            >
              {t('重新加载字幕')}
            </button>
          </StatusMessage>
        ) : null}

        {audio && reader.subtitles?.length ? (
          <section className="audio-subtitles" aria-label={t('音声字幕')}>
            <div className="action-row" style={{ marginBottom: 8 }}>
              <label>
                {t('字幕轨道')}
                <select
                  aria-label={t('音声字幕轨道')}
                  value={subtitleIndex}
                  onChange={(event) => setSubtitleIndex(Number(event.target.value))}
                >
                  {reader.subtitles.map((track, index) => (
                    <option key={index} value={index}>
                      {track.label}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <p>{cueText || t('当前时间没有字幕')}</p>
            {cueText && prefs.settings.contentTranslationEnabled ? <TranslateText text={cueText} /> : null}
            {cueList.length > 0 ? (
              <details>
                <summary>
                  {t('字幕时间轴')} ({cueList.length})
                </summary>
                <div className="voice-cue-list">
                  {cueList.map((cue, i) => (
                    <button
                      key={i}
                      type="button"
                      className={`voice-cue-row ${i === activeCueIdx ? 'active' : ''}`}
                      onClick={() => {
                        if (mediaRef.current) {
                          mediaRef.current.currentTime = cue.startTime;
                          void mediaRef.current.play().catch(() => {});
                        }
                      }}
                    >
                      <small style={{ fontVariantNumeric: 'tabular-nums', opacity: 0.7 }}>
                        {Math.floor(cue.startTime / 60)}:{String(Math.floor(cue.startTime % 60)).padStart(2, '0')}
                      </small>
                      <span>{cue.text}</span>
                    </button>
                  ))}
                </div>
              </details>
            ) : null}
          </section>
        ) : null}
      </div>
    );
  }

  if (pages.length) {
    return (
      <ImageReaderLayout
        count={pages.length}
        title={reader.workTitle + ' · ' + reader.title}
        initialPage={initialPage}
        onPageChange={onPageChange}
        notice={controlNotice}
        controls={
          canFullscreen ? (
            <button className="chip" onClick={fullscreen}>
              {t('全屏')}
            </button>
          ) : null
        }
        chapterFooter={chapterFooter}
        renderPage={(index, active, cropMargins) => {
          const item = pages[index]!;
          return (
            <AuthorizedImage
              authorization={item.mediaAuthorization}
              transform={item.transform}
              cropMargins={cropMargins}
              width={item.width}
              height={item.height}
              alt={item.alt ?? t('漫画页面')}
              retryGeneration={retryGeneration}
              active={active}
              controlled
            />
          );
        }}
      />
    );
  }

  return (
    <article className="text-reader">
      <h1>{reader.title ?? t('阅读内容')}</h1>
      {reader.content ? (
        <p className="chapter-text">{reader.content}</p>
      ) : (
        <StatusMessage tone="warning" title={t('没有可用内容')}>
          {t('来源没有返回可阅读或播放的内容。')}
        </StatusMessage>
      )}
    </article>
  );
}

export function ReaderPage({
  mode,
  parts,
  navigate,
  embedded = false,
  active = true,
}: {
  mode: 'read' | 'watch';
  parts: string[];
  navigate: (to: string) => void;
  embedded?: boolean;
  active?: boolean;
}) {
  const source = decodeURIComponent(parts[0] ?? '');
  const workId = decodeURIComponent(parts[1] ?? '');
  const chapterId = decodeURIComponent(parts[2] ?? '');
  const [attempt, setAttempt] = useState(0);
  const [showBlocked, setShowBlocked] = useState(false);
  const state = useAsync(
    (signal) => api.reader(source, workId, chapterId, signal, showBlocked),
    [source, workId, chapterId, attempt, showBlocked],
    (value) => {
      if (value.webPlayer) void api.webPlayerControl(value.webPlayer.controlUrl, { action: 'close' }, true).catch(() => undefined);
    },
  );

  useEffect(() => {
    const refresh = () => setAttempt((value) => value + 1);
    window.addEventListener('hp:session-rotated', refresh);
    return () => window.removeEventListener('hp:session-rotated', refresh);
  }, []);

  const [media, setMedia] = useState<HTMLMediaElement | null>(null);
  const [token, setToken] = useState<string>();
  const [tokenAttempt, setTokenAttempt] = useState(0);
  const [mediaError, setMediaError] = useState<string>();
  const [saveError, setSaveError] = useState<string>();
  const [localPage, setLocalPage] = useState<{ key: string; page: number }>();
  const [selectedMedia, setSelectedMedia] = useState<{ auth: MediaTokenRequest; format?: string }>();

  const shared = useSharedState();
  const progressKey = chapterIdentityKey({ source, workId, chapterId });
  const initialPage =
    localPage?.key === progressKey
      ? localPage.page
      : Math.max(
          0,
          Math.min(
            (state.data?.pages?.length ?? 1) - 1,
            Number(new URLSearchParams(window.location.search).get('page')) > 0
              ? Math.floor(Number(new URLSearchParams(window.location.search).get('page'))) - 1
              : state.data?.pageProgress ?? 0,
          ),
        );

  const queue = useRef(Promise.resolve());
  const progressVersions = useRef(new Map<string, number>());
  useEffect(() => {
    if (state.data?.version) progressVersions.current.set(progressKey, state.data.version);
  }, [progressKey, state.data?.version]);

  const resumePosition = useRef<number | undefined>(undefined);
  const resumePaused = useRef<boolean | undefined>(undefined);
  const [playbackNotice, setPlaybackNotice] = useState('');
  useEffect(() => {
    resumePosition.current = undefined;
    setSelectedMedia(undefined);
  }, [source, workId, chapterId]);

  const persist = useCallback(
    (progress: ProgressState) => {
      if (progress.page === undefined) resumePosition.current = progress.position;
      if (!active || shared.incognito || state.data?.category === 'live') return;
      const identity = { source, workId, chapterId };
      const data =
        progress.page !== undefined
          ? { page: progress.page, pageCount: state.data?.blocks?.length ?? state.data?.pages?.length }
          : { position: progress.position, duration: progress.duration };
      queue.current = queue.current.catch(() => undefined).then(async () => {
        try {
          const saved = await api.saveHistory(identity.source, identity.workId, identity.chapterId, {
            ...data,
            version: progressVersions.current.get(progressKey),
          });
          if (saved.saved) progressVersions.current.set(progressKey, saved.version);
          setSaveError(undefined);
        } catch (error) {
          if (
            error instanceof ApiError &&
            error.status === 409 &&
            typeof (error.details as { version?: number } | undefined)?.version === 'number'
          ) {
            progressVersions.current.set(progressKey, (error.details as { version: number }).version);
          }
          setSaveError(t('进度保存失败：') + errorMessage(error));
        }
      });
    },
    [active, source, workId, chapterId, progressKey, mode, shared.incognito, state.data?.category, state.data?.pages?.length],
  );

  const pageSave = useRef<{ page: number; save: () => void } | undefined>(undefined);
  const pageTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const flushPage = useCallback(() => {
    if (pageTimer.current) clearTimeout(pageTimer.current);
    pageTimer.current = undefined;
    const pending = pageSave.current;
    pageSave.current = undefined;
    pending?.save();
  }, []);
  const savePage = useCallback(
    (page: number) => {
      setLocalPage({ key: progressKey, page });
      if (pageSave.current?.page === page) return;
      pageSave.current = { page, save: () => persist({ page, position: 0, updatedAt: Date.now() }) };
      if (pageTimer.current) clearTimeout(pageTimer.current);
      pageTimer.current = setTimeout(flushPage, 1000);
    },
    [persist, progressKey, flushPage],
  );

  useEffect(() => {
    const hidden = () => {
      if (document.hidden) flushPage();
    };
    document.addEventListener('visibilitychange', hidden);
    window.addEventListener('pagehide', flushPage);
    return () => {
      flushPage();
      document.removeEventListener('visibilitychange', hidden);
      window.removeEventListener('pagehide', flushPage);
    };
  }, [progressKey, flushPage]);

  useMediaLifecycle(active ? media : null, progressKey, persist);
  useEffect(() => {
    if (!active) media?.pause();
  }, [active, media]);

  useEffect(() => {
    if (!media) return;
    const position = state.data?.category === 'live' ? undefined : resumePosition.current ?? state.data?.videoPosition;
    const restore = () => {
      if (typeof position === 'number' && Number.isFinite(position) && position > 0 && media.currentTime === 0) {
        media.currentTime = Math.min(position, Number.isFinite(media.duration) ? media.duration : position);
      }
      if (resumePaused.current === false) {
        void media
          .play()
          .then(() => setPlaybackNotice(''))
          .catch(() => setPlaybackNotice(t('浏览器暂停了自动恢复，请点击播放器继续播放。')));
      }
    };
    if (media.readyState >= 1) restore();
    else media.addEventListener('loadedmetadata', restore, { once: true });
    return () => media.removeEventListener('loadedmetadata', restore);
  }, [media, state.data?.videoPosition, state.data?.category, token]);

  const preservePosition = useCallback(() => {
    if (media) {
      if (media.currentTime > 0) resumePosition.current = media.currentTime;
      resumePaused.current = media.paused;
    }
  }, [media]);

  const grant = useMediaGrant(selectedMedia?.auth ?? state.data?.mediaAuthorization, tokenAttempt, preservePosition);
  useEffect(() => {
    setToken(grant.token);
    setMediaError(grant.error);
  }, [grant.token, grant.error]);

  useEffect(() => {
    if (!mediaError || tokenAttempt >= 2) return;
    const timer = setTimeout(() => {
      if (media && media.currentTime > 0) resumePosition.current = media.currentTime;
      setTokenAttempt((value) => value + 1);
    }, 500 * 2 ** tokenAttempt);
    return () => clearTimeout(timer);
  }, [mediaError, tokenAttempt, media]);

  const reader = state.data;
  const novelOffset = useRef(0);
  const persistText = useCallback(
    (offset: number) => {
      novelOffset.current = offset;
      if (shared.incognito || !state.data) return;
      const key = progressKey;
      queue.current = queue.current.catch(() => undefined).then(async () => {
        try {
          const saved = await api.saveHistory(source, workId, chapterId, {
            textOffset: offset,
            textLength: state.data?.textLength,
            version: progressVersions.current.get(key),
          });
          if (saved.saved) progressVersions.current.set(key, saved.version);
          setSaveError(undefined);
        } catch (error) {
          if (error instanceof ApiError && typeof (error.details as { version?: number } | undefined)?.version === 'number') {
            progressVersions.current.set(key, (error.details as { version: number }).version);
          }
          setSaveError(t('进度保存失败：') + errorMessage(error));
        }
      });
    },
    [source, workId, chapterId, progressKey, shared.incognito, state.data],
  );

  const visited = useRef<string | undefined>(undefined);
  const recordVisit = useCallback(async () => {
    try {
      const saved = await api.saveHistory(source, workId, chapterId, { version: progressVersions.current.get(progressKey) });
      if (saved.saved) progressVersions.current.set(progressKey, saved.version);
      setSaveError(undefined);
    } catch (error) {
      setSaveError(t('网页访问记录保存失败：') + errorMessage(error));
    }
  }, [source, workId, chapterId, progressKey]);

  useEffect(() => {
    if (active && reader?.webPlayer && shared.incognito === false && reader.category !== 'live' && visited.current !== progressKey) {
      visited.current = progressKey;
      void recordVisit();
    }
  }, [reader?.webPlayer?.playerId, shared.incognito, reader?.category, progressKey, recordVisit, active]);

  const workHref = '/work/' + [source, workId].map(encodeURIComponent).join('/');
  const offlineTask = reader?.offlineTaskId ?? reader?.partialOfflineTaskId;

  return (
    <ReadingChrome active={!embedded && Boolean(reader && ['comic', 'novel'].includes(reader.mediaKind))}>
      {!embedded ? (
        <div className="reader-top">
          <a className="navigation-link" href={workHref} onClick={(event) => navigateClick(event, navigate, workHref)}>
            {t('作品详情')}
          </a>
          <div className="action-row" style={{ margin: 0 }}>
            {offlineTask ? (
              <a
                className="chip"
                href={'/offline/' + encodeURIComponent(offlineTask)}
                onClick={(e) => navigateClick(e, navigate, '/offline/' + encodeURIComponent(offlineTask))}
              >
                {reader?.offlineTaskId ? t('使用离线文件打开') : t('边下边读（离线缓存）')}
              </a>
            ) : null}
            <span>{shared.incognito ? t('无痕浏览，不保存进度') : ''}</span>
          </div>
        </div>
      ) : null}

      {saveError ? (
        <StatusMessage tone="danger" title={t('进度尚未保存')}>
          {saveError}
          <button
            className="chip"
            onClick={() =>
              reader?.webPlayer
                ? void recordVisit()
                : reader?.mediaKind === 'novel'
                  ? persistText(novelOffset.current)
                  : persist(
                      media
                        ? {
                            position: media.currentTime,
                            duration: Number.isFinite(media.duration) ? media.duration : undefined,
                            updatedAt: Date.now(),
                          }
                        : { page: initialPage, position: 0, updatedAt: Date.now() },
                    )
            }
          >
            {t('重试保存')}
          </button>
        </StatusMessage>
      ) : null}

      {state.error instanceof ApiError && state.error.code === 'BLOCKED' ? (
        <button className="chip" onClick={() => setShowBlocked(true)}>
          {t('临时显示此章节')}
        </button>
      ) : null}

      <StateView loading={state.loading} error={state.error} empty={false}>
        {reader && !reader.webPlayer && !['video', 'voice'].includes(reader.mediaKind) && !embedded ? (
          <ReaderNavigation source={source} workId={workId} chapterId={chapterId} />
        ) : null}
        <section className={'reader-canvas reader-kind-' + (reader?.mediaKind ?? 'loading')}>
          {playbackNotice ? <p role="status">{playbackNotice}</p> : null}
          {reader?.webPlayer ? (
            <ControlledWebPlayer key={reader.webPlayer.playerId} player={reader.webPlayer} onRetry={() => setAttempt((value) => value + 1)} />
          ) : reader?.mediaKind === 'novel' ? (
            <NovelReader reader={reader} initialOffset={reader.textOffset ?? 0} onOffsetChange={persistText} />
          ) : reader?.blocks ? (
            <ArticleContent
              reader={reader}
              initialPage={initialPage}
              onPageChange={savePage}
              navigate={navigate}
              showBlocked={showBlocked}
            />
          ) : reader ? (
            <ReaderContent
              key={chapterIdentityKey({ source, workId, chapterId })}
              reader={reader}
              mediaKind={reader.mediaKind}
              formatHint={selectedMedia?.format ?? reader.format}
              playbackOptions={
                reader.mediaAuthorization &&
                ['video', 'voice'].includes(reader.mediaKind) &&
                (!reader.nodeType || ['audio', 'video'].includes(reader.nodeType)) ? (
                  <MediaChoices
                    audio={reader.nodeType === 'audio' || (reader.mediaKind === 'voice' && !reader.nodeType)}
                    source={source}
                    workId={workId}
                    chapterId={chapterId}
                    initialItems={reader.mediaChoices}
                    failed={mediaError}
                    onSelect={(auth, fmt) => {
                      preservePosition();
                      setMediaError(undefined);
                      setSelectedMedia({ auth, format: fmt });
                      setTokenAttempt(0);
                    }}
                  />
                ) : null
              }
              token={token}
              mediaError={mediaError}
              initialPage={initialPage}
              retryGeneration={tokenAttempt}
              setMedia={setMedia}
              setMediaError={setMediaError}
              onPageChange={savePage}
              onRetry={() => {
                if (media && media.currentTime > 0) resumePosition.current = media.currentTime;
                setToken(undefined);
                setMediaError(undefined);
                setSelectedMedia(undefined);
                setTokenAttempt(0);
                setAttempt((value) => value + 1);
              }}
              chapterFooter={
                !embedded && reader.mediaKind === 'comic' ? (
                  <ReaderNavigation source={source} workId={workId} chapterId={chapterId} />
                ) : undefined
              }
            />
          ) : null}
        </section>
        {reader && !reader.webPlayer && ['video', 'voice'].includes(reader.mediaKind) && !embedded ? (
          <ReaderNavigation source={source} workId={workId} chapterId={chapterId} />
        ) : null}
        {reader?.category === 'live' ? (
          <div className="live-tools">
            {reader.mediaAuthorization ? <RecordingControls source={source} workId={workId} chapterId={chapterId} /> : null}
            {reader.liveChatAvailable ? <LiveChat source={source} workId={workId} /> : null}
          </div>
        ) : null}
      </StateView>
    </ReadingChrome>
  );
}
