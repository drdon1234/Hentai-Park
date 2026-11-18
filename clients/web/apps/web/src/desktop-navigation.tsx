import { t } from './i18n.js';
import { getInternalNavDepth } from './native.js';

/** POP through internal SPA history when available, falling back to semantic parent route. */
export function DesktopBack({ location, navigate }: { location: string; navigate: (url: string, replace?: boolean) => void }) {
  const [path, query = ''] = location.split('#')[0]!.split('?');
  const parts = path!.split('/');
  const kind = parts[1];
  const params = new URLSearchParams(query);
  const section = kind === 'settings' && params.has('section');
  if (
    !section &&
    !['domain', 'sites', 'source', 'work', 'read', 'watch', 'channel', 'post', 'album', 'rankings', 'reverse-search', 'history', 'offline', 'tavern', 'logs', 'licenses'].includes(
      kind ?? '',
    )
  ) {
    return null;
  }
  const source = '/source/' + (parts[2] ?? '');
  const fallback = section
    ? '/settings'
    : kind === 'logs' || kind === 'licenses'
      ? '/settings?section=about'
      : kind === 'work' || kind === 'channel' || kind === 'album' || kind === 'post'
        ? source
        : kind === 'read' || kind === 'watch'
          ? '/work/' + [parts[2], parts[3]].join('/')
          : kind === 'source'
            ? '/sites'
            : kind === 'history' || kind === 'tavern'
              ? '/library'
              : kind === 'offline'
                ? '/downloads'
                : '/discover';
  const previous =
    typeof window.history.state?.hpFrom === 'string' && /^\/(?!\/)/.test(window.history.state.hpFrom)
      ? window.history.state.hpFrom
      : undefined;
  const canGoBack = Boolean(previous) || getInternalNavDepth() > 0;
  const label = kind === 'read' || kind === 'watch' ? '退出阅读' : '返回';
  return (
    <div className="desktop-back">
      <a
        href={previous ?? fallback}
        aria-label={t(label)}
        title={t(label)}
        onClick={(event) => {
          if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
          event.preventDefault();
          if (canGoBack) window.history.back();
          else navigate(fallback, true);
        }}
      >
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
          <path d="M20 12H4m7-7-7 7 7 7" />
        </svg>
        {t(label)}
      </a>
    </div>
  );
}

export function DesktopScrollTop() {
  return (
    <button
      className="desktop-scroll-top"
      type="button"
      aria-label={t('回到顶部')}
      title={t('回到顶部')}
      onClick={() =>
        window.scrollTo({ top: 0, behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' })
      }
    >
      {t('回到顶部')}
    </button>
  );
}
