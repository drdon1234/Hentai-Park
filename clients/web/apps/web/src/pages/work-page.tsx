import { useContext, useEffect, useState, type ReactNode } from 'react';
import { AdaptiveSheet, EmptyState, StatusMessage, showToast } from '@hentai-park/design-system';
import { workIdentityKey, type WorkTag } from '@hentai-park/domain-model';
import { api, type ApiChapter } from '../api.js';
import { SourceNames, canSearchTag, navigateClick, tagHref } from '../app/app-context.js';
import { mediaLabels } from '../browse-ui.js';
import { CategoryEditor, ChapterDownloads } from '../collection-controls.js';
import { WorkDetails, WorkFacts } from '../content-controls.js';
import { CoverImage } from '../cover-image.js';
import { GameResources, TavernSourcePanel } from '../extended-pages.js';
import { t } from '../i18n.js';
import { TranslateText, TranslatedTag } from '../language-tools.js';
import { useBackDismissable, useSharedState } from '../native.js';
import { StateView, errorMessage, useAsync, useServerVersion } from '../page-ui.js';
import { PreferenceSettingsContext, usePreferences } from '../preferences.js';
import { TagPackReminder } from '../tag-pack-reminder.js';

const NAMESPACE_LABELS: Record<string, string> = {
  female: '女性标签',
  male: '男性标签',
  artist: '画师 / 作者',
  group: '社团',
  parody: '原作',
  character: '角色',
  language: '语言',
  cosplayer: '出演',
  mixed: '混合',
  other: '其他标签',
};

export function WorkPage({
  parts,
  directory,
  navigate,
  renderArticleReader,
}: {
  parts: string[];
  directory?: string;
  navigate: (to: string) => void;
  renderArticleReader: (parts: string[]) => ReactNode;
}) {
  const sourceNames = useContext(SourceNames);
  const prefs = usePreferences();
  const source = decodeURIComponent(parts[0] ?? '');
  const id = decodeURIComponent(parts[1] ?? '');
  const state = useAsync(
    async (signal) => {
      const work = await api.work(source, id, signal);
      const chapters =
        work.capabilities.metadataOnly || ['game', 'tavern'].includes(work.mediaKind)
          ? undefined
          : await api.chapters(source, id, { directoryId: directory }, signal);
      return [work, chapters] as const;
    },
    [source, id, directory],
    undefined,
    { cacheKey: 'work:' + JSON.stringify([source, id, directory]) },
  );
  const historyVersion = useServerVersion();
  const resume = useAsync(() => api.history({ source, workId: id, resume: true, limit: 1 }), [source, id, historyVersion]);
  const shared = useSharedState();
  const collection = shared.collections[workIdentityKey({ source, id })];
  const favorite = collection?.favorite === true;
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [extra, setExtra] = useState<ApiChapter[]>([]);
  const [cursor, setCursor] = useState<string | null>();
  const [activeTag, setActiveTag] = useState<WorkTag>();
  useBackDismissable(Boolean(activeTag), () => setActiveTag(undefined));

  useEffect(() => {
    setExtra([]);
    setCursor(state.data?.[1]?.page?.nextCursor);
  }, [state.data]);

  const work = state.data?.[0];
  const chapters = [...(state.data?.[1]?.items ?? []), ...extra];
  const kind = work?.mediaKind;
  const playback = kind === 'video' || kind === 'voice';
  const webVideoOnly = playback && work?.capabilities.webVideo === true && work.capabilities.videos !== true;
  const canRead = Boolean(
    chapters.length &&
      work?.capabilities.metadataOnly !== true &&
      (playback
        ? work?.capabilities.videos || work?.capabilities.webVideo
        : kind === 'article' || work?.capabilities.chapter || work?.capabilities.textChapter),
  );
  const canDownload = Boolean(
    !webVideoOnly &&
      work?.category !== 'live' &&
      chapters.length &&
      work?.capabilities.metadataOnly !== true &&
      (work?.capabilities.chapter ||
        work?.capabilities.textChapter ||
        work?.capabilities.videos ||
        work?.capabilities.voiceResource ||
        kind === 'article'),
  );
  const readable = (chapter: ApiChapter) =>
    chapter.nodeType ? ['audio', 'video', 'subtitle', 'image', 'script'].includes(chapter.nodeType) : canRead;
  const firstReadable = chapters.find(readable);
  const lastRead = resume.data?.items[0];
  const resumeChapter =
    lastRead?.chapterId &&
    work &&
    work.category !== 'live' &&
    !work.capabilities.metadataOnly &&
    !['game', 'tavern'].includes(work.mediaKind)
      ? { chapterId: lastRead.chapterId, nodeType: lastRead.nodeType ?? undefined }
      : undefined;
  const primaryChapter = resumeChapter ?? firstReadable;
  const [temporarilyVisible, setTemporarilyVisible] = useState(false);
  useEffect(() => setTemporarilyVisible(false), [source, id]);

  const chapterHref = (chapter: Pick<ApiChapter, 'chapterId' | 'nodeType'>) =>
    chapter.nodeType === 'directory'
      ? '/work/' + [source, id].map(encodeURIComponent).join('/') + '?directory=' + encodeURIComponent(chapter.chapterId)
      : (chapter.nodeType ? (['audio', 'video'].includes(chapter.nodeType) ? '/watch/' : '/read/') : playback ? '/watch/' : '/read/') +
        [source, id, chapter.chapterId].map(encodeURIComponent).join('/');

  const operate = async (action: () => Promise<unknown>) => {
    setBusy(true);
    setMessage(t('正在提交…'));
    try {
      await action();
      setMessage(t('操作已完成'));
    } catch (error) {
      setMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const favoritePreferences = useContext(PreferenceSettingsContext);
  const [categoryRequest, setCategoryRequest] = useState(0);
  const toggleFavorite = () => {
    if (!favorite && favoritePreferences.askCategoryOnFavorite) {
      setCategoryRequest((value) => value + 1);
      return;
    }
    void operate(async () => {
      await api.setLibrary({ source, workId: id, favorite: !favorite });
    });
  };

  const blockSelectedTag = async (tag: WorkTag) => {
    const rule = tag.namespace ? `${tag.namespace}:${tag.label}` : tag.label;
    const current = Array.isArray(prefs.settings.blockedWords) ? (prefs.settings.blockedWords as string[]) : [];
    if (!current.includes(rule)) {
      await prefs.save({ blockedWords: [...current, rule] });
    }
    setActiveTag(undefined);
    showToast(t('已加入屏蔽词：') + rule, 'success');
  };

  const more = () =>
    operate(async () => {
      const value = await api.chapters(source, id, { directoryId: directory, cursor: cursor ?? undefined });
      setExtra((rows) => [...rows, ...value.items]);
      setCursor(value.page?.nextCursor);
    });

  if (work && !temporarilyVisible && work.blocked) {
    return (
      <StatusMessage tone="warning" title={t('内容已被屏蔽')}>
        {t('该作品命中实例屏蔽词。')}
        <button className="chip" onClick={() => setTemporarilyVisible(true)}>
          {t('临时显示此作品')}
        </button>
      </StatusMessage>
    );
  }

  if (work?.mediaKind === 'article' && !work.capabilities.metadataOnly && firstReadable) {
    return (
      <>
        <div className="action-row">
          <a
            className="secondary-link navigation-link"
            href={'/source/' + encodeURIComponent(source)}
            onClick={(event) => navigateClick(event, navigate, '/source/' + encodeURIComponent(source))}
          >
            {t('站点主页')}
          </a>
          <button
            className="chip"
            aria-pressed={favorite}
            disabled={busy || !shared.collectionsReady}
            onClick={toggleFavorite}
          >
            {favorite ? t('已收藏') : t('收藏作品')}
          </button>
          {canDownload ? (
            <button
              className="chip"
              disabled={busy}
              onClick={() =>
                void operate(() =>
                  api.createDownload({ source, workId: id, chapterId: firstReadable.chapterId, variant: 'original' }),
                )
              }
            >
              {t('下载')}
            </button>
          ) : null}
        </div>
        {message ? <p role="status">{message}</p> : null}
        {renderArticleReader([source, id, firstReadable.chapterId].map(encodeURIComponent))}
        <details className="detail-secondary">
          <summary>{t('更多')}</summary>
          <CategoryEditor source={source} workId={id} title={work.title} />
          <div className="tag-row">
            {(work.tags ?? []).map((tag, index) =>
              canSearchTag(tag) ? (
                <a
                  className="chip"
                  key={index}
                  href={tagHref(tag)}
                  onClick={(event) => navigateClick(event, navigate, tagHref(tag))}
                >
                  <TranslatedTag source={tag.source} label={tag.label} namespace={tag.namespace} />
                </a>
              ) : (
                <span key={index}>{tag.label}</span>
              ),
            )}
          </div>
          <a className="secondary-link" href={work.sourceUrl} target="_blank" rel="noopener noreferrer">
            {t('打开原站')}
          </a>
          {chapters.length > 1 ? (
            <ul className="chapter-list">
              {chapters.map((chapter) => (
                <li key={chapter.chapterId}>
                  <a href={chapterHref(chapter)} onClick={(event) => navigateClick(event, navigate, chapterHref(chapter))}>
                    {chapter.title}
                  </a>
                </li>
              ))}
            </ul>
          ) : null}
          {cursor ? (
            <button className="chip" disabled={busy} onClick={more}>
              {t('加载更多章节')}
            </button>
          ) : null}
        </details>
        <WorkDetails
          work={work}
          source={source}
          workId={id}
          navigate={navigate}
          readHref={kind === 'comic' && firstReadable ? chapterHref(firstReadable) : undefined}
        />
      </>
    );
  }

  if (state.loading && !work) {
    return (
      <>
        <a
          className="back-link"
          href={'/source/' + encodeURIComponent(source)}
          onClick={(event) => navigateClick(event, navigate, '/source/' + encodeURIComponent(source))}
        >
          {t('返回站点')}
        </a>
        <section className="detail-layout work-overview detail-skeleton" aria-busy="true" aria-label={t('正在加载')}>
          <div className="detail-cover skeleton-block" />
          <div className="work-overview-content">
            <div className="skeleton-line skeleton-line-title" />
            <div className="skeleton-line skeleton-line-meta" />
            <div className="skeleton-actions">
              <span className="skeleton-button" />
              <span className="skeleton-button" />
              <span className="skeleton-button" />
            </div>
            <div className="skeleton-facts">
              <span />
              <span />
              <span />
            </div>
          </div>
        </section>
      </>
    );
  }

  const groupedTags = new Map<string, WorkTag[]>();
  for (const tag of work?.tags ?? []) {
    const ns = tag.namespace || 'other';
    groupedTags.set(ns, [...(groupedTags.get(ns) ?? []), tag]);
  }
  const hasMultipleNamespaces = groupedTags.size > 1 || (groupedTags.size === 1 && !groupedTags.has('other'));

  return (
    <>
      <a
        className="back-link"
        href={'/source/' + encodeURIComponent(source)}
        onClick={(event) => navigateClick(event, navigate, '/source/' + encodeURIComponent(source))}
      >
        {t('返回站点')}
      </a>
      <StateView loading={false} error={state.error} empty={false}>
        {work ? (
          <>
            <section
              className={
                'detail-layout work-overview detail-' +
                work.mediaKind +
                (work.capabilities.metadataOnly ? ' detail-metadata detail-category-' + work.category : '') +
                (!work.coverAuthorization ? ' without-cover' : '')
              }
            >
              <div className={'detail-cover ' + (!work.coverAuthorization ? 'cover-empty' : '')}>
                {work.coverAuthorization ? (
                  <CoverImage
                    authorization={work.coverAuthorization}
                    alt={work.title + t('封面')}
                    className="cover-image"
                    retryLabel={t('重试封面')}
                    eager
                    allowUnblur
                  />
                ) : null}
                <span className="cover-kind">
                  {t(work.capabilities.metadataOnly ? '资料' : mediaLabels[kind ?? ''] ?? kind ?? '')}
                </span>
              </div>

              <div className="work-overview-content">
                <h1>{work.title}</h1>
                <p className="chapter-state" style={{ overflowWrap: 'anywhere' }}>
                  {t('来源：')}
                  {sourceNames[work.source] ?? work.source}
                  {t(' · 编号：')}
                  {typeof work.workCode === 'string' && work.workCode ? work.workCode : work.workId}
                </p>
                {Array.isArray(work.authors) && work.authors.length ? (
                  <p>
                    {t('作者：')}
                    {work.authors
                      .map((author) =>
                        typeof author === 'string'
                          ? author
                          : typeof author?.name === 'string'
                            ? author.name
                            : typeof author?.label === 'string'
                              ? author.label
                              : t('作者资料暂不可用'),
                      )
                      .join(' · ')}
                  </p>
                ) : null}
                {Array.isArray(work.actors) && work.actors.length ? (
                  <p>
                    {t('出演：')}
                    {work.actors.join(' · ')}
                  </p>
                ) : null}

                <div className="action-row">
                  {work.capabilities.metadataOnly && typeof work.workCode === 'string' && work.workCode ? (
                    <a
                      className="primary-link"
                      href={'/search?q=' + encodeURIComponent(work.workCode) + '&scope=all'}
                      onClick={(event) =>
                        navigateClick(event, navigate, '/search?q=' + encodeURIComponent(work.workCode!) + '&scope=all')
                      }
                    >
                      {t('用编号搜索')}
                    </a>
                  ) : null}
                  {primaryChapter ? (
                    <a
                      className="primary-link"
                      href={chapterHref(primaryChapter)}
                      onClick={(event) => navigateClick(event, navigate, chapterHref(primaryChapter))}
                    >
                      {primaryChapter.nodeType && !['audio', 'video'].includes(primaryChapter.nodeType)
                        ? t('查看附件')
                        : resumeChapter
                          ? playback
                            ? t('继续播放')
                            : t('继续阅读')
                          : webVideoOnly
                            ? t('打开网页播放器')
                            : playback
                              ? t('开始播放')
                              : t('开始阅读')}
                    </a>
                  ) : null}
                  {canDownload ? (
                    <a className="secondary-link" href="#chapter-downloads">
                      {t('选择章节下载')}
                    </a>
                  ) : null}
                  {!work.capabilities.metadataOnly ? (
                    <button
                      className="secondary-link"
                      aria-pressed={favorite}
                      onClick={toggleFavorite}
                      disabled={busy || !shared.collectionsReady}
                    >
                      {favorite ? t('已收藏') : t('收藏作品')}
                    </button>
                  ) : (
                    <span>{t('资料条目 · 仅供查询原站信息')}</span>
                  )}
                </div>

                {resumeChapter ? (
                  <p className="chapter-state">
                    {lastRead?.chapterTitle ?? resumeChapter.chapterId}
                    {lastRead?.page != null
                      ? t(' · 第') + (lastRead.page + 1) + t('页')
                      : lastRead?.position
                        ? ' · ' + Math.floor(lastRead.position) + t('秒')
                        : ''}
                  </p>
                ) : null}
                {message ? <p role="status">{message}</p> : null}

                {work.capabilities.onlineGame || work.capabilities.gameResources ? (
                  <GameResources source={source} workId={id} online={work.capabilities.onlineGame === true} />
                ) : null}
                {work.capabilities.tavernAsset ? <TavernSourcePanel source={source} workId={id} /> : null}

                <WorkFacts work={work} />
                {!work.capabilities.metadataOnly ? (
                  <CategoryEditor
                    key={workIdentityKey({ source, id })}
                    source={source}
                    workId={id}
                    title={work.title}
                    openRequest={categoryRequest}
                    favoriteOnSave={categoryRequest > 0 && !favorite}
                  />
                ) : null}
              </div>
            </section>

            <section className="detail-body">
              {work.summary?.trim() ? (
                <details className="detail-summary" open>
                  <summary>{t('简介')}</summary>
                  <p className="lead">{work.summary}</p>
                  <TranslateText text={work.summary} />
                </details>
              ) : null}

              {hasMultipleNamespaces ? (
                <div style={{ display: 'grid', gap: 12, marginBlock: 16 }}>
                  {[...groupedTags.entries()].map(([ns, tags]) => (
                    <div key={ns} style={{ display: 'flex', alignItems: 'baseline', gap: 10, flexWrap: 'wrap' }}>
                      <small className="muted" style={{ minWidth: 72, fontWeight: 600 }}>
                        {t(NAMESPACE_LABELS[ns] ?? ns)}
                      </small>
                      <div className="tag-row" style={{ margin: 0, flex: 1 }}>
                        {tags.map((tag, index) =>
                          canSearchTag(tag) ? (
                            <a
                              className="chip"
                              key={index}
                              href={tagHref(tag)}
                              onClick={(event) => navigateClick(event, navigate, tagHref(tag))}
                              onContextMenu={(e) => {
                                e.preventDefault();
                                setActiveTag(tag);
                              }}
                            >
                              <TranslatedTag source={tag.source} label={tag.label} namespace={tag.namespace} />
                            </a>
                          ) : (
                            <button type="button" className="chip" key={index} onClick={() => setActiveTag(tag)}>
                              {tag.label}
                            </button>
                          ),
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="tag-row">
                  {(work.tags ?? []).map((tag, index) =>
                    canSearchTag(tag) ? (
                      <a
                        className="chip"
                        key={index}
                        href={tagHref(tag)}
                        onClick={(event) => navigateClick(event, navigate, tagHref(tag))}
                        onContextMenu={(e) => {
                          e.preventDefault();
                          setActiveTag(tag);
                        }}
                      >
                        <TranslatedTag source={tag.source} label={tag.label} namespace={tag.namespace} />
                      </a>
                    ) : (
                      <button type="button" className="chip" key={index} onClick={() => setActiveTag(tag)}>
                        {tag.label}
                      </button>
                    ),
                  )}
                </div>
              )}

              <details className="detail-secondary">
                <summary>{t('更多')}</summary>
                {work.tags?.length ? <TagPackReminder source={source} /> : null}
                <a className="secondary-link" href={work.sourceUrl} target="_blank" rel="noopener noreferrer">
                  {t('打开原站')}
                </a>
              </details>
            </section>

            {activeTag ? (
              <AdaptiveSheet
                open={Boolean(activeTag)}
                title={activeTag.namespace ? `${activeTag.namespace}:${activeTag.label}` : activeTag.label}
                closeLabel={t('关闭')}
                onClose={() => setActiveTag(undefined)}
              >
                <div className="action-row">
                  {canSearchTag(activeTag) ? (
                    <a
                      className="primary-link"
                      href={tagHref(activeTag)}
                      onClick={(e) => {
                        setActiveTag(undefined);
                        navigateClick(e, navigate, tagHref(activeTag));
                      }}
                    >
                      {t('搜索此标签')}
                    </a>
                  ) : null}
                  <button type="button" className="button danger-action" onClick={() => void blockSelectedTag(activeTag)}>
                    {t('屏蔽此标签')}
                  </button>
                </div>
              </AdaptiveSheet>
            ) : null}

            {!work.capabilities.metadataOnly &&
            !webVideoOnly &&
            work.category !== 'live' &&
            !['game', 'tavern'].includes(work.mediaKind) ? (
              <section className="section-block">
                {work.voiceRoot ? (
                  <nav className="action-row" aria-label={t('音声目录导航')}>
                    <a
                      href={'/work/' + [source, id].map(encodeURIComponent).join('/')}
                      onClick={(event) =>
                        navigateClick(event, navigate, '/work/' + [source, id].map(encodeURIComponent).join('/'))
                      }
                    >
                      {work.voiceRoot.name}
                    </a>
                    {directory ? <span>{t(' / 当前目录')}</span> : null}
                  </nav>
                ) : null}
                {chapters.length ? (
                  <ChapterDownloads
                    key={workIdentityKey({ source, id }) + ':' + (directory ?? '')}
                    source={source}
                    workId={id}
                    chapters={chapters}
                    isVideo={kind === 'video'}
                    allowDownload={canDownload}
                    hasMore={Boolean(cursor)}
                    renderChapter={(chapter) =>
                      readable(chapter) || chapter.nodeType === 'directory' ? (
                        <a
                          href={chapterHref(chapter)}
                          onClick={(event) => navigateClick(event, navigate, chapterHref(chapter))}
                        >
                          <span>{chapter.title}</span>
                          <span className="chapter-state">
                            {t(
                              (
                                {
                                  directory: '目录',
                                  audio: '音频',
                                  video: '视频',
                                  subtitle: '字幕',
                                  image: '图片',
                                  script: '文本',
                                  other: '文件',
                                  unread: '未读',
                                  reading: '阅读中',
                                  read: '已读',
                                  completed: '已读',
                                } as Record<string, string>
                              )[chapter.nodeType ?? chapter.readState] ?? '',
                            )}
                          </span>
                        </a>
                      ) : (
                        <span>
                          {chapter.title}
                          <small className="chapter-state">{t('当前来源能力不支持站内阅读或播放')}</small>
                        </span>
                      )
                    }
                  />
                ) : (
                  <EmptyState title={t('暂无章节')} detail={t('服务端没有返回可阅读章节。')} />
                )}
                {cursor ? (
                  <button className="chip" onClick={more} disabled={busy}>
                    {t('加载更多章节')}
                  </button>
                ) : null}
              </section>
            ) : null}

            <WorkDetails
              work={work}
              source={source}
              workId={id}
              navigate={navigate}
              readHref={kind === 'comic' && firstReadable ? chapterHref(firstReadable) : undefined}
            />
          </>
        ) : null}
      </StateView>
    </>
  );
}
