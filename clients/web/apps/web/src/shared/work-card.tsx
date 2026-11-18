import { useContext, useState } from 'react';
import { AdaptiveSheet, showToast } from '@hentai-park/design-system';
import { workIdentityKey } from '@hentai-park/domain-model';
import { api, type ApiWork } from '../api.js';
import { CategoryNames, SourceNames, hrefFor, navigateClick } from '../app/app-context.js';
import { mediaLabels } from '../browse-ui.js';
import { CategoryEditor } from '../collection-controls.js';
import { CoverImage } from '../cover-image.js';
import { t } from '../i18n.js';
import { TranslatedTag } from '../language-tools.js';
import { useBackDismissable, useSharedState } from '../native.js';
import { PreferenceSettingsContext } from '../preferences.js';

function formatCompactMeta(work: ApiWork): string {
  const parts: string[] = [];
  if (typeof work.pages === 'number' && work.pages > 0) parts.push(`${work.pages}P`);
  if (work.duration !== undefined && String(work.duration).trim()) parts.push(String(work.duration));
  if (work.rating !== undefined && work.rating !== null) parts.push(`★ ${work.rating}`);
  if (work.badge) parts.push(work.badge);
  return parts.slice(0, 2).join(' · ');
}

export function WorkCard({
  work,
  navigate,
  manageCollections = false,
  cacheScope = 'transient',
  selection,
  openHref,
  compact = false,
  progressLabel,
  onRemove,
}: {
  work: ApiWork;
  navigate: (to: string) => void;
  manageCollections?: boolean;
  cacheScope?: 'cards' | 'transient';
  selection?: { selected: boolean; toggle: () => void };
  openHref?: string;
  compact?: boolean;
  progressLabel?: string;
  onRemove?: () => void;
}) {
  const prefs = useContext(PreferenceSettingsContext);
  const href = hrefFor(work);
  const shared = useSharedState();
  const categoryNames = useContext(CategoryNames);
  const sourceNames = useContext(SourceNames);
  const identity = workIdentityKey({ source: work.source, id: work.workId });
  const collection = shared.collections[identity];
  const categories = collection?.categoryIds ?? [];
  const favorite = collection?.favorite === true;
  const [favoriteBusy, setFavoriteBusy] = useState(false);
  const [sheetOpen, setSheetOpen] = useState(false);
  useBackDismissable(sheetOpen, () => setSheetOpen(false));

  const toggleFavorite = async () => {
    if (favoriteBusy) return;
    setFavoriteBusy(true);
    try {
      await api.setLibrary({ source: work.source, workId: work.workId, favorite: !favorite });
      showToast(!favorite ? t('已加入收藏') : t('已取消收藏'), 'success');
    } finally {
      setFavoriteBusy(false);
    }
  };

  const isLive = work.category === 'live';
  const coverAspect =
    isLive || work.mediaKind === 'video' || work.mediaKind === 'article'
      ? '16 / 9'
      : work.mediaKind === 'voice' || work.mediaKind === 'game'
        ? '1 / 1'
        : '3 / 4';
  const actionHref = openHref ?? href;
  const authorText = Array.isArray(work.authors)
    ? work.authors
        .map((a) => (typeof a === 'string' ? a : a?.name ?? a?.label ?? ''))
        .filter(Boolean)
        .join(' · ')
    : '';
  const subtitleLine = [
    prefs.badgeSource !== false ? sourceNames[work.source] ?? work.source : '',
    authorText || work.subtitle || work.workCode || '',
  ]
    .filter(Boolean)
    .join(' · ');
  const scrimMeta = progressLabel ?? formatCompactMeta(work);

  return (
    <article
      className={
        'work-card browse-cover-card media-' +
        work.mediaKind +
        (compact ? ' compact-work-card' : '') +
        (!work.coverAuthorization ? ' without-cover' : '')
      }
      onContextMenu={(e) => {
        if (!compact && !e.shiftKey) {
          e.preventDefault();
          setSheetOpen(true);
        }
      }}
    >
      {selection ? (
        <label className="work-select">
          <input type="checkbox" checked={selection.selected} onChange={selection.toggle} />
          <span className="sr-only">
            {t('选择作品')} {work.title}
          </span>
        </label>
      ) : null}

      <div
        style={{ aspectRatio: coverAspect }}
        className={
          'browse-cover-frame cover ' +
          (!work.coverAuthorization ? 'cover-empty' : '') +
          (work.coverBlurred ? ' source-blurred' : '')
        }
      >
        {work.coverAuthorization ? (
          <CoverImage
            authorization={work.coverAuthorization}
            alt={work.title + t('封面')}
            className="cover-image"
            retryLabel={t('重试封面')}
            scope={cacheScope}
            allowUnblur
          />
        ) : null}
        <a
          href={actionHref}
          className="browse-cover-link"
          aria-label={t('打开作品 ') + work.title}
          onClick={(event) => navigateClick(event, navigate, actionHref)}
        >
          <div className="browse-cover-top-badges">
            {isLive ? (
              <span className="browse-badge browse-badge-live">LIVE</span>
            ) : prefs.badgeUnread !== false && Number(work.unreadCount) > 0 ? (
              <span className="browse-badge browse-badge-accent">
                {work.unreadCount} {t('未读')}
              </span>
            ) : prefs.badgeDownloaded !== false && work.downloaded === true ? (
              <span className="browse-badge">{t('已下载')}</span>
            ) : (
              <span />
            )}
          </div>
          <div className="browse-cover-bottom-scrim">
            <span>{t(work.capabilities.metadataOnly ? '资料' : mediaLabels[work.mediaKind] ?? work.mediaKind)}</span>
            {scrimMeta ? <span>{scrimMeta}</span> : null}
          </div>
        </a>
        {!compact ? (
          <button
            type="button"
            className="browse-card-menu-btn"
            aria-label={t('更多操作') + ' · ' + work.title}
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              setSheetOpen(true);
            }}
          >
            ⋯
          </button>
        ) : null}
      </div>

      <div className="browse-card-body work-meta">
        <h3 className="browse-card-title">
          <a title={work.title} href={actionHref} onClick={(event) => navigateClick(event, navigate, actionHref)}>
            {work.title}
          </a>
        </h3>
        {subtitleLine ? <p className="browse-card-subtitle">{subtitleLine}</p> : null}
        {work.summary?.trim() ? <p className="work-excerpt">{work.summary}</p> : null}
        {categories.length ? (
          <div className="collection-tags" role="group" aria-label={t('分类')}>
            {categories.map((category) => (
              <span className="collection-tag" key={category}>
                {categoryNames[category] ?? t('已归类')}
              </span>
            ))}
          </div>
        ) : null}
        {compact && onRemove ? (
          <button className="work-card-remove chip" type="button" onClick={onRemove}>
            {t('移除')}
          </button>
        ) : null}
        {manageCollections ? <CategoryEditor source={work.source} workId={work.workId} title={work.title} /> : null}
      </div>

      {sheetOpen ? (
        <AdaptiveSheet
          open={sheetOpen}
          title={work.title}
          closeLabel={t('关闭')}
          onClose={() => setSheetOpen(false)}
        >
          <p className="muted" style={{ marginTop: 0 }}>
            {sourceNames[work.source] ?? work.source}
            {work.workCode ? ' · ' + work.workCode : ''}
          </p>
          {work.tags?.length ? (
            <div className="tag-row" style={{ marginBottom: 16 }}>
              {work.tags.slice(0, 12).map((tag, index) => (
                <span className="chip" key={index}>
                  <TranslatedTag source={tag.source} label={tag.label} namespace={tag.namespace} />
                </span>
              ))}
            </div>
          ) : null}
          <div className="action-row">
            <a
              className="primary-link"
              href={href}
              onClick={(event) => {
                setSheetOpen(false);
                navigateClick(event, navigate, href);
              }}
            >
              {t('打开作品')}
            </a>
            {!work.capabilities.metadataOnly ? (
              <button
                type="button"
                className="secondary-link"
                aria-pressed={favorite}
                disabled={favoriteBusy || !shared.collectionsReady}
                onClick={() => void toggleFavorite()}
              >
                {favorite ? t('已收藏') : t('收藏作品')}
              </button>
            ) : null}
            {!work.capabilities.metadataOnly ? (
              <a
                className="chip"
                href={href + '#chapter-downloads'}
                onClick={(event) => {
                  setSheetOpen(false);
                  navigateClick(event, navigate, href + '#chapter-downloads');
                }}
              >
                {t('选择章节下载')}
              </a>
            ) : null}
            {work.sourceUrl ? (
              <a className="chip" href={work.sourceUrl} target="_blank" rel="noopener noreferrer">
                {t('打开原站')}
              </a>
            ) : null}
          </div>
          {!work.capabilities.metadataOnly ? (
            <CategoryEditor source={work.source} workId={work.workId} title={work.title} />
          ) : null}
        </AdaptiveSheet>
      ) : null}
    </article>
  );
}

export function WorkGrid({
  items,
  view,
  navigate,
  manageCollections = false,
  cacheScope = 'transient',
  selection,
}: {
  items: ApiWork[];
  view: 'grid' | 'list';
  navigate: (to: string) => void;
  manageCollections?: boolean;
  cacheScope?: 'cards' | 'transient';
  selection?: { keys: string[]; toggle: (key: string) => void };
}) {
  const settings = useContext(PreferenceSettingsContext);
  const [showBlocked, setShowBlocked] = useState(false);
  const visible = showBlocked ? items : items.filter((work) => !work.blocked);
  return (
    <>
      {items.some((work) => work.blocked) ? (
        <button className="chip" aria-pressed={showBlocked} onClick={() => setShowBlocked((value) => !value)}>
          {showBlocked ? t('应用屏蔽规则') : t('临时显示原始结果')}
        </button>
      ) : null}
      <div
        className={'work-grid ' + (view === 'list' ? 'list-view' : '')}
        style={
          view !== 'list' && Number(settings.gridColumns) > 0
            ? { gridTemplateColumns: 'repeat(' + settings.gridColumns + ',minmax(0,1fr))' }
            : undefined
        }
      >
        {visible.length === 0 && items.length > 0 ? <p role="status">{t('结果已被屏蔽规则过滤。')}</p> : null}
        {visible.map((work) => (
          <WorkCard
            key={workIdentityKey({ source: work.source, id: work.workId })}
            work={work}
            navigate={navigate}
            manageCollections={manageCollections}
            cacheScope={cacheScope}
            selection={
              selection
                ? {
                    selected: selection.keys.includes(workIdentityKey({ source: work.source, id: work.workId })),
                    toggle: () => selection.toggle(workIdentityKey({ source: work.source, id: work.workId })),
                  }
                : undefined
            }
          />
        ))}
      </div>
    </>
  );
}
