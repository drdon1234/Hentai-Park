import { useEffect, useState, type CSSProperties } from 'react';
import { StatusMessage, confirmAction } from '@hentai-park/design-system';
import { allPages, api, requestErrorMessage, type DownloadTask } from '../api.js';
import { navigateClick } from '../app/app-context.js';
import { mediaLabels } from '../browse-ui.js';
import { DownloadExtras, ImportComic } from '../data-controls.js';
import { t } from '../i18n.js';
import { useDownloadTelemetry } from '../native.js';
import { PageHeader, StateView, errorMessage, useAsync, useServerVersion } from '../page-ui.js';
import { RecordingControls, StopRecording } from '../recording-controls.js';

export function DownloadsPage({ navigate }: { navigate: (url: string) => void }) {
  const version = useServerVersion();
  const telemetry = useDownloadTelemetry();
  const state = useAsync(() => allPages(api.downloads), [version], undefined, { cacheKey: 'downloads' });
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [previous, setPrevious] = useState<DownloadTask[]>([]);
  const [selectedTasks, setSelectedTasks] = useState<string[]>([]);
  const [expandedWorks, setExpandedWorks] = useState<string[]>([]);
  const [batchBusy, setBatchBusy] = useState(false);

  useEffect(() => {
    if (state.data) setPrevious(state.data);
  }, [state.data]);
  const items = (state.data ?? previous).map((task) => {
    const live = telemetry[task.taskId];
    return live
      ? {
          ...task,
          bytes: live.bytes ?? task.bytes,
          completedCount: live.completedCount ?? task.completedCount,
          totalCount: live.totalCount ?? task.totalCount,
          speed: live.speed !== undefined ? live.speed : task.speed,
        }
      : task;
  });

  const sourceState = useAsync(() => allPages(api.sources), [version], undefined, { cacheKey: 'source-catalog' });
  const sourceLabel = (id: string) => String(sourceState.data?.find((item) => item.source === id)?.manifest?.name ?? id);

  const params = new URLSearchParams(window.location.search);
  const query = params.get('q') ?? '';
  const kind = params.get('kind') ?? '';
  const status = params.get('status') ?? '';
  const source = params.get('source') ?? '';

  const filter = (name: string, value: string) => {
    const next = new URLSearchParams(window.location.search);
    if (value) next.set(name, value);
    else next.delete(name);
    navigate('/downloads' + (next.size ? '?' + next : ''));
  };

  const visible = items.filter(
    (item) =>
      (!query || [item.workTitle, item.chapterTitle, item.workId].join(' ').toLocaleLowerCase().includes(query.toLocaleLowerCase())) &&
      (!kind || item.mediaKind === kind) &&
      (!status || item.status === status) &&
      (!source || item.source === source),
  );

  const grouped = new Map<string, DownloadTask[]>();
  for (const item of visible) {
    const key = JSON.stringify([item.source, item.workId]);
    grouped.set(key, [...(grouped.get(key) ?? []), item]);
  }

  const size = (bytes: number) => {
    const value = Math.max(0, Number.isFinite(bytes) ? bytes : 0);
    const unit = value >= 1073741824 ? 'GiB' : value >= 1048576 ? 'MiB' : value >= 1024 ? 'KiB' : 'B';
    const divisor = unit === 'GiB' ? 1073741824 : unit === 'MiB' ? 1048576 : unit === 'KiB' ? 1024 : 1;
    return new Intl.NumberFormat('zh-CN', { maximumFractionDigits: 1 }).format(value / divisor) + ' ' + unit;
  };

  const statusNames: Record<string, string> = {
    queued: t('等待下载'),
    running: t('下载中'),
    paused: t('已暂停'),
    completed: t('已完成'),
    failed: t('下载失败'),
    cancelling: t('正在取消'),
    cancelled: t('已取消'),
  };

  const run = async (item: DownloadTask, action: 'pause' | 'resume' | 'retry' | 'cancel' | 'delete') => {
    const id = item.taskId;
    if (!id) return;
    if (action === 'delete') {
      const ok = await confirmAction({
        title: t('删除任务及其本地文件？'),
        description: `${item.workTitle} · ${item.chapterTitle}`,
        confirmLabel: t('删除'),
        danger: true,
      });
      if (!ok) return;
    }
    setBusy(id);
    setError('');
    try {
      if (action === 'delete') await api.deleteDownload(id);
      else await api.downloadAction(id, action);
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setBusy('');
    }
  };

  const batch = async (action: 'pause' | 'resume' | 'delete') => {
    if (!selectedTasks.length) return;
    if (action === 'delete') {
      const ok = await confirmAction({
        title: t('删除所选任务及其本地文件？'),
        confirmLabel: t('删除'),
        danger: true,
      });
      if (!ok) return;
    }
    setBatchBusy(true);
    try {
      await Promise.all(selectedTasks.map((id) => (action === 'delete' ? api.deleteDownload(id) : api.downloadAction(id, action))));
      setSelectedTasks([]);
      window.dispatchEvent(new Event('hp:invalidate'));
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setBatchBusy(false);
    }
  };

  void RecordingControls;

  return (
    <>
      <PageHeader title={t('下载')} description={t('按作品聚合管理离线任务，支持边下边读与服务端无损导出。')}>
        {state.loading || state.error ? (
          <span className="muted" aria-label={t('下载列表同步状态')}>
            {state.error ? t('更新失败') : t('正在同步')}
          </span>
        ) : null}
      </PageHeader>

      {selectedTasks.length ? (
        <div className="selection-toolbar action-row" role="toolbar">
          <strong>{t('已选 {value0}', { value0: selectedTasks.length })}</strong>
          <button className="chip" disabled={batchBusy} onClick={() => void batch('pause')}>
            {t('暂停')}
          </button>
          <button className="chip" disabled={batchBusy} onClick={() => void batch('resume')}>
            {t('恢复')}
          </button>
          <button className="chip danger-action" disabled={batchBusy} onClick={() => void batch('delete')}>
            {t('删除')}
          </button>
          <button className="chip" onClick={() => setSelectedTasks([])}>
            {t('取消选择')}
          </button>
        </div>
      ) : null}

      <div className="filter-row">
        <label>
          {t('搜索')}
          <input aria-label={t('搜索')} value={query} onChange={(event) => filter('q', event.target.value)} />
        </label>
        <label>
          {t('媒体类型')}
          <select aria-label={t('媒体类型')} value={kind} onChange={(event) => filter('kind', event.target.value)}>
            <option value="">{t('全部')}</option>
            {[...new Set(items.map((item) => item.mediaKind).filter(Boolean))].map((value) => (
              <option key={value} value={value}>
                {t(mediaLabels[value!] ?? value!)}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t('状态')}
          <select aria-label={t('状态')} value={status} onChange={(event) => filter('status', event.target.value)}>
            <option value="">{t('全部')}</option>
            {Object.entries(statusNames).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t('站点')}
          <select aria-label={t('站点')} value={source} onChange={(event) => filter('source', event.target.value)}>
            <option value="">{t('全部')}</option>
            {[...new Set(items.map((item) => item.source))].map((value) => (
              <option key={value} value={value}>
                {sourceLabel(value)}
              </option>
            ))}
          </select>
        </label>
      </div>

      <details className="browse-tools">
        <summary>{t('导入本地漫画')}</summary>
        <ImportComic />
      </details>

      {error ? (
        <StatusMessage tone="danger" title={t('下载操作失败')}>
          {error}
        </StatusMessage>
      ) : null}
      {state.error && items.length ? (
        <StatusMessage tone="warning" title={t('下载列表刷新失败')}>
          {t('当前保留上次读取的进度。')}
          {errorMessage(state.error)}
        </StatusMessage>
      ) : null}

      <StateView
        loading={state.loading && !items.length}
        error={items.length ? undefined : state.error}
        empty={!state.loading && !state.error && !visible.length}
      >
        {[...grouped].map(([key, group]) => {
          const head = group[0]!;
          const totalFiles = group.reduce((acc, row) => acc + Math.max(1, row.totalCount || 1), 0);
          const doneFiles = group.reduce(
            (acc, row) => acc + (row.status === 'completed' ? Math.max(1, row.totalCount || 1) : row.completedCount || 0),
            0,
          );
          const progressPct = Math.min(100, Math.round((doneFiles / Math.max(1, totalFiles)) * 100));
          const totalBytes = group.reduce((acc, row) => acc + (row.bytes || 0), 0);
          const activeSpeed = group.reduce((acc, row) => acc + (row.status === 'running' && row.speed ? row.speed : 0), 0);
          const completedChapters = group.filter((row) => row.status === 'completed').length;
          const isOpen = group.length === 1 || expandedWorks.includes(key);
          const workHref = '/work/' + [head.source, head.workId].map(encodeURIComponent).join('/');

          return (
            <section className="download-work-card" key={key}>
              <div className="download-work-header">
                <div className="download-progress-ring" style={{ '--progress': progressPct } as CSSProperties}>
                  <div className="download-progress-ring-inner" style={{ display: 'grid', placeItems: 'center', padding: 6 }}>
                    <strong style={{ fontSize: 13 }}>{progressPct}%</strong>
                  </div>
                </div>

                <div style={{ minWidth: 0 }}>
                  <h2 style={{ margin: '0 0 4px', fontSize: 17, overflowWrap: 'anywhere' }}>
                    <a href={workHref} onClick={(e) => navigateClick(e, navigate, workHref)}>
                      {head.workTitle || head.workId}
                    </a>
                  </h2>
                  <p className="chapter-state" style={{ margin: 0 }}>
                    {sourceLabel(head.source)} · {completedChapters}/{group.length} {t('章节')} · {size(totalBytes)}
                    {activeSpeed > 0 ? ` · ${size(activeSpeed)}/s` : ''}
                  </p>
                </div>

                <div className="action-row" style={{ margin: 0 }}>
                  {completedChapters > 0 && head.mediaKind === 'comic' && group.length > 1 ? (
                    <>
                      <a className="chip" download href={api.workExportUrl(head.source, head.workId, 'cbz')}>
                        {t('整部CBZ')}
                      </a>
                      <a className="chip" download href={api.workExportUrl(head.source, head.workId, 'pdf')}>
                        {t('整部PDF')}
                      </a>
                    </>
                  ) : null}
                  {group.length > 1 ? (
                    <button
                      type="button"
                      className="chip"
                      aria-expanded={isOpen}
                      onClick={() =>
                        setExpandedWorks((prev) => (prev.includes(key) ? prev.filter((k) => k !== key) : [...prev, key]))
                      }
                    >
                      {isOpen ? t('收起') : t('展开')} ({group.length})
                    </button>
                  ) : null}
                </div>
              </div>

              {isOpen ? (
                <ul className="chapter-list" style={{ marginTop: 14 }} aria-busy={state.loading}>
                  {group.map((item) => {
                    const id = item.taskId;
                    const total = item.totalCount ?? 0;
                    const canOpenPartial = item.completedCount > 0 && item.status !== 'completed';
                    const offlineHref =
                      '/offline/' + encodeURIComponent(id) + (canOpenPartial ? '?incomplete=1' : '');
                    return (
                      <li key={id}>
                        <div className="download-select" style={{ display: 'flex', alignItems: 'center', gap: 10, flex: 1, minWidth: 0 }}>
                          <input
                            type="checkbox"
                            aria-label={t('选择下载任务') + ' ' + (item.chapterTitle ?? item.chapterId)}
                            checked={selectedTasks.includes(id)}
                            onChange={() =>
                              setSelectedTasks((value) => (value.includes(id) ? value.filter((x) => x !== id) : [...value, id]))
                            }
                          />
                          <span style={{ minWidth: 0 }}>
                            {item.status === 'completed' || canOpenPartial ? (
                              <a
                                className="download-content-link"
                                href={offlineHref}
                                onClick={(event) => navigateClick(event, navigate, offlineHref)}
                              >
                                <strong>{item.chapterTitle ?? item.chapterId}</strong>
                              </a>
                            ) : (
                              <strong>{item.chapterTitle ?? item.chapterId}</strong>
                            )}
                            <small className="chapter-state">
                              {size(item.bytes)}
                              {item.status === 'running' && item.speed !== null ? t(' · 速度：') + size(item.speed) + '/s' : null}
                              {' · '}
                              {item.completedCount ?? 0}
                              {total ? ' / ' + total : ''}
                            </small>
                            {item.failureCode ? (
                              <div className="chapter-state">
                                <p>{requestErrorMessage(item.failureCode)}</p>
                              </div>
                            ) : null}
                            {total ? <progress max={total} value={item.completedCount ?? 0} aria-label={t('下载进度')} /> : null}
                          </span>
                        </div>
                        <span className="action-row">
                          <b>{statusNames[item.status] ?? item.status}</b>
                          {canOpenPartial ? (
                            <a
                              className="chip"
                              href={offlineHref}
                              onClick={(e) => navigateClick(e, navigate, offlineHref)}
                            >
                              {t('边下边读')}
                            </a>
                          ) : null}
                          {item.status === 'running' ? (
                            <button className="chip" disabled={busy === id} onClick={() => void run(item, 'pause')}>
                              {t('暂停')}
                            </button>
                          ) : null}
                          {item.status === 'paused' ? (
                            <button className="chip" disabled={busy === id} onClick={() => void run(item, 'resume')}>
                              {t('恢复')}
                            </button>
                          ) : null}
                          {item.status === 'failed' && item.recoverable !== false ? (
                            <button className="chip" disabled={busy === id} onClick={() => void run(item, 'retry')}>
                              {t('重试')}
                            </button>
                          ) : null}
                          {['queued', 'running', 'paused', 'failed'].includes(item.status) ? (
                            <button className="chip" disabled={busy === id} onClick={() => void run(item, 'cancel')}>
                              {t('取消')}
                            </button>
                          ) : null}
                          <button className="chip danger-action" disabled={busy === id} onClick={() => void run(item, 'delete')}>
                            {t('删除')}
                          </button>
                        </span>
                        <div className="download-extra">
                          <StopRecording task={item} />
                          <DownloadExtras task={item} />
                        </div>
                      </li>
                    );
                  })}
                </ul>
              ) : null}
            </section>
          );
        })}
      </StateView>
    </>
  );
}
