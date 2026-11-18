import { useCallback, useEffect, useRef, useState } from 'react';
import { mediaUrl, type MediaTokenRequest } from '../api.js';
import { CoverImage } from '../cover-image.js';
import { t } from '../i18n.js';
import { loadHls } from '../load-hls.js';
import { useMediaGrant } from '../media-grant.js';
import { useBackDismissable } from '../native.js';

export type LightboxMediaItem = {
  id: string;
  type: 'image' | 'video';
  authorization: MediaTokenRequest;
  format?: string;
  caption?: string;
};

function LightboxVideo({ authorization, format }: { authorization: MediaTokenRequest; format?: string }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [error, setError] = useState('');
  const [attempt, setAttempt] = useState(0);
  const grant = useMediaGrant(authorization, attempt);

  useEffect(() => {
    const video = videoRef.current;
    if (!video || !grant.token) return;
    let dispose: (() => void) | undefined;
    let live = true;
    setError('');
    const url = mediaUrl(grant.token);
    if (format === 'hls' && video.canPlayType('application/vnd.apple.mpegurl') !== 'probably') {
      void loadHls()
        .then(({ attachHls }) => {
          if (live && videoRef.current) dispose = attachHls(videoRef.current, url, setError);
        })
        .catch((err) => {
          if (live) setError(err instanceof Error ? err.message : t('视频加载失败，请重取授权。'));
        });
    } else {
      video.src = url;
    }
    return () => {
      live = false;
      dispose?.();
      video.pause();
      video.removeAttribute('src');
      video.load();
    };
  }, [grant.token, format]);

  return (
    <div>
      {error || grant.error ? (
        <div className="action-row" role="alert">
          <span>{error || grant.error}</span>
          <button type="button" className="chip" onClick={() => setAttempt((n) => n + 1)}>
            {t('重试播放')}
          </button>
        </div>
      ) : null}
      <video ref={videoRef} controls autoPlay playsInline preload="metadata" aria-label={t('视频播放器')} />
    </div>
  );
}

/**
 * Fullscreen unified media lightbox supporting mixed images & videos in one continuous stream,
 * with pinch/Ctrl+wheel/double-tap zoom, pan, swipe prev/next, and mobile back-gesture dismissal.
 */
export function MediaLightboxModal({
  open,
  title,
  items,
  index,
  onIndexChange,
  onClose,
}: {
  open: boolean;
  title?: string;
  items: LightboxMediaItem[];
  index: number;
  onIndexChange: (next: number) => void;
  onClose: () => void;
}) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const dragRef = useRef<{ x: number; y: number; panX: number; panY: number } | null>(null);
  const pinchRef = useRef<{ dist: number; zoom: number } | null>(null);
  const swipeRef = useRef<{ x: number; y: number } | null>(null);
  const lastTapRef = useRef(0);

  useBackDismissable(open, onClose);

  const resetTransform = useCallback(() => {
    setZoom(1);
    setPan({ x: 0, y: 0 });
  }, []);

  useEffect(() => {
    resetTransform();
  }, [index, open, resetTransform]);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      try {
        dialog.showModal();
      } catch {
        dialog.setAttribute('open', '');
      }
    } else if (!open && dialog.open) {
      dialog.close();
    }
  }, [open]);

  const step = useCallback(
    (delta: number) => {
      const next = index + delta;
      if (next >= 0 && next < items.length) onIndexChange(next);
    },
    [index, items.length, onIndexChange],
  );

  if (!open || !items.length) return null;
  const current = items[Math.max(0, Math.min(items.length - 1, index))]!;

  return (
    <dialog
      ref={dialogRef}
      className="media-lightbox"
      aria-label={title || t('图片预览')}
      onClose={onClose}
      onKeyDown={(e) => {
        if (e.key === 'ArrowLeft') {
          e.preventDefault();
          step(-1);
        } else if (e.key === 'ArrowRight') {
          e.preventDefault();
          step(1);
        }
      }}
    >
      <header className="media-lightbox-bar">
        <strong style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {title ? `${title} · ` : ''}
          {index + 1} / {items.length}
        </strong>
        <div className="action-row" style={{ margin: 0 }}>
          {current.type === 'image' ? (
            <>
              <button
                type="button"
                className="chip"
                onClick={() => setZoom((z) => Math.max(1, Number((z - 0.5).toFixed(1))))}
              >
                −
              </button>
              <span>{Math.round(zoom * 100)}%</span>
              <button
                type="button"
                className="chip"
                onClick={() => setZoom((z) => Math.min(4, Number((z + 0.5).toFixed(1))))}
              >
                +
              </button>
            </>
          ) : null}
          <button type="button" className="chip" onClick={onClose}>
            {t('关闭')}
          </button>
        </div>
      </header>

      <div
        className="media-lightbox-stage"
        onWheel={(e) => {
          if (current.type !== 'image') return;
          if (e.ctrlKey || zoom > 1) {
            e.preventDefault();
            const next = Math.max(1, Math.min(4, zoom * (e.deltaY < 0 ? 1.15 : 0.87)));
            setZoom(next);
            if (next === 1) setPan({ x: 0, y: 0 });
          }
        }}
        onPointerDown={(e) => {
          if (current.type !== 'image') return;
          const now = Date.now();
          if (now - lastTapRef.current < 280) {
            setZoom((z) => {
              const next = z > 1 ? 1 : 2.5;
              if (next === 1) setPan({ x: 0, y: 0 });
              return next;
            });
            lastTapRef.current = 0;
            return;
          }
          lastTapRef.current = now;
          if (zoom > 1) {
            dragRef.current = { x: e.clientX, y: e.clientY, panX: pan.x, panY: pan.y };
          }
        }}
        onPointerMove={(e) => {
          if (dragRef.current && zoom > 1) {
            setPan({
              x: dragRef.current.panX + (e.clientX - dragRef.current.x),
              y: dragRef.current.panY + (e.clientY - dragRef.current.y),
            });
          }
        }}
        onPointerUp={() => {
          dragRef.current = null;
        }}
        onTouchStart={(e) => {
          if (e.touches.length === 2 && current.type === 'image') {
            const dx = e.touches[0]!.clientX - e.touches[1]!.clientX;
            const dy = e.touches[0]!.clientY - e.touches[1]!.clientY;
            pinchRef.current = { dist: Math.hypot(dx, dy), zoom };
            swipeRef.current = null;
          } else if (e.touches.length === 1 && zoom <= 1) {
            swipeRef.current = { x: e.touches[0]!.clientX, y: e.touches[0]!.clientY };
          }
        }}
        onTouchMove={(e) => {
          if (e.touches.length === 2 && pinchRef.current) {
            const dx = e.touches[0]!.clientX - e.touches[1]!.clientX;
            const dy = e.touches[0]!.clientY - e.touches[1]!.clientY;
            const ratio = Math.hypot(dx, dy) / Math.max(1, pinchRef.current.dist);
            setZoom(Math.max(1, Math.min(4, pinchRef.current.zoom * ratio)));
          }
        }}
        onTouchEnd={(e) => {
          pinchRef.current = null;
          if (swipeRef.current && zoom <= 1 && e.changedTouches[0]) {
            const dx = e.changedTouches[0].clientX - swipeRef.current.x;
            const dy = e.changedTouches[0].clientY - swipeRef.current.y;
            if (Math.abs(dx) > 64 && Math.abs(dx) > Math.abs(dy) * 1.8) {
              step(dx < 0 ? 1 : -1);
            }
          }
          swipeRef.current = null;
        }}
        onClick={(e) => {
          if (e.target === e.currentTarget && zoom <= 1) onClose();
        }}
      >
        <div
          style={
            current.type === 'image'
              ? {
                  transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
                  transition: dragRef.current || pinchRef.current ? 'none' : 'transform 120ms ease-out',
                }
              : undefined
          }
        >
          {current.type === 'image' ? (
            <CoverImage
              key={current.id}
              authorization={current.authorization}
              alt={current.caption ?? title ?? t('图片预览')}
              eager
            />
          ) : (
            <LightboxVideo key={current.id} authorization={current.authorization} format={current.format} />
          )}
        </div>
      </div>

      <footer className="media-lightbox-footer">
        <button type="button" className="chip" disabled={index <= 0} onClick={() => step(-1)}>
          {t('上一张')}
        </button>
        {current.caption ? <span className="muted">{current.caption}</span> : null}
        <button type="button" className="chip" disabled={index >= items.length - 1} onClick={() => step(1)}>
          {t('下一张')}
        </button>
      </footer>
    </dialog>
  );
}
