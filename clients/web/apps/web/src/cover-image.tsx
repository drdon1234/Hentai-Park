import { useEffect, useState } from 'react';
import { api, directImageUrl, mediaUrl, type MediaTokenRequest } from './api.js';
import { useSharedState } from './native.js';
import { t } from './i18n.js';

export type CoverScope = 'cards' | 'transient';

let cacheVersion = 0;
const versionListeners = new Set<() => void>();

export function configureCoverCache(_mb: number) {
  /* Server-side partitioned LRU + native HTTP ETag/Cache-Control now manages cover storage without JS Blob duplication. */
}

export function clearCoverImages(_source?: string) {
  cacheVersion++;
  versionListeners.forEach((fn) => fn());
}

export async function clearBrowserCoverCache() {
  clearCoverImages();
  if (typeof caches !== 'undefined') {
    await caches.delete('hentai-park-cover-cache-cards-v1').catch(() => undefined);
    await caches.delete('hentai-park-cover-cache-v2').catch(() => undefined);
  }
}

if (typeof window !== 'undefined') {
  window.addEventListener('hp:browse-invalidated', () => clearCoverImages());
}

/**
 * 1-RTT Image Component: uses deterministic `/api/v1/media/direct/:authorizationId` directly in `<img>`
 * (zero `POST /api/v1/media/tokens` preflight storm, zero JS ReadableStream/Blob duplication, native HTTP cache).
 * Falls back to `api.mediaToken` only for legacy payloads lacking `directUrl`.
 */
export function CoverImage({
  authorization,
  alt,
  className = '',
  retryLabel = t('重试图片'),
  scope: _scope = 'transient',
  eager = false,
  allowUnblur = false,
}: {
  authorization: MediaTokenRequest;
  alt: string;
  className?: string;
  retryLabel?: string;
  scope?: CoverScope;
  eager?: boolean;
  allowUnblur?: boolean;
}) {
  const shared = useSharedState();
  const direct = directImageUrl(authorization);
  const [attempt, setAttempt] = useState(0);
  const [fallbackToken, setFallbackToken] = useState<string>();
  const [error, setError] = useState<string>();
  const [unblurred, setUnblurred] = useState(false);
  const [, setBuster] = useState(cacheVersion);

  useEffect(() => {
    const listener = () => setBuster(cacheVersion);
    versionListeners.add(listener);
    return () => {
      versionListeners.delete(listener);
    };
  }, []);

  useEffect(() => {
    setError(undefined);
    setFallbackToken(undefined);
    if (direct) return;
    const abort = new AbortController();
    void api
      .mediaToken(authorization, abort.signal)
      .then((grant) => {
        if (!abort.signal.aborted) setFallbackToken(grant.token);
      })
      .catch((reason) => {
        if (!abort.signal.aborted) {
          setError(reason instanceof Error ? reason.message : t('图片加载失败，请重试。'));
        }
      });
    return () => abort.abort();
  }, [direct, authorization.authorizationId, authorization.resourceKey, attempt]);

  const resolvedSrc = direct
    ? direct + (attempt > 0 ? `?retry=${attempt}` : '')
    : fallbackToken
      ? mediaUrl(fallbackToken)
      : undefined;

  return (
    <div
      className={'authorized-image ' + className}
      data-unblurred={unblurred ? 'true' : undefined}
    >
      {error ? (
        <div className="image-error" role="status">
          <span>{error}</span>
          <button
            type="button"
            className="chip"
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              setError(undefined);
              setAttempt((n) => n + 1);
            }}
          >
            {retryLabel}
          </button>
        </div>
      ) : resolvedSrc ? (
        <>
          <img
            src={resolvedSrc}
            alt={alt}
            loading={eager ? 'eager' : 'lazy'}
            decoding="async"
            onError={() => setError(t('图片加载失败，请重试。'))}
          />
          {allowUnblur && shared.coverBlur ? (
            <button
              type="button"
              className="cover-unblur-btn"
              onClick={(e) => {
                e.preventDefault();
                e.stopPropagation();
                setUnblurred((v) => !v);
              }}
            >
              {unblurred ? t('模糊') : t('清晰')}
            </button>
          ) : null}
        </>
      ) : (
        <div className="image-placeholder" aria-hidden="true" />
      )}
    </div>
  );
}
