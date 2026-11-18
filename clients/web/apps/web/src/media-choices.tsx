import { useEffect, useRef, useState } from 'react';
import { request, type MediaChoiceItem, type MediaTokenRequest } from './api.js';
import { t } from './i18n.js';

export function MediaChoices({
  source,
  workId,
  chapterId,
  initialItems,
  onSelect,
  failed,
  audio = false,
}: {
  source: string;
  workId: string;
  chapterId: string;
  initialItems?: MediaChoiceItem[];
  onSelect: (authorization: MediaTokenRequest, format?: string) => void;
  failed?: string | boolean;
  audio?: boolean;
}) {
  const [loading, setLoading] = useState(!initialItems?.length);
  const [items, setItems] = useState<MediaChoiceItem[]>(initialItems ?? []);
  const [selected, setSelected] = useState('');
  const [error, setError] = useState('');
  const [attempt, setAttempt] = useState(0);
  const [notice, setNotice] = useState('');
  const select = useRef(onSelect);
  const position = useRef({ line: 0, mirror: 0 });
  const lastFailure = useRef<string | boolean | undefined>(undefined);
  select.current = onSelect;

  useEffect(() => {
    setError('');
    setNotice('');
    lastFailure.current = undefined;
    if (initialItems?.length && attempt === 0) {
      setItems(initialItems);
      setLoading(false);
      position.current = { line: Math.max(0, initialItems.findIndex((i) => i.preferred)), mirror: 0 };
      const item = initialItems[position.current.line];
      if (item) setSelected(item.id);
      return;
    }
    const abort = new AbortController();
    setLoading(true);
    setItems([]);
    setSelected('');
    void request<{ items: MediaChoiceItem[] }>(
      '/api/v1/works/' + [source, workId].map(encodeURIComponent).join('/') + '/media-choices/' + encodeURIComponent(chapterId),
      { signal: abort.signal },
    )
      .then((value) => {
        if (abort.signal.aborted) return;
        setItems(value.items);
        position.current = { line: Math.max(0, value.items.findIndex((i) => i.preferred)), mirror: 0 };
        const item = value.items[position.current.line];
        if (item) {
          setSelected(item.id);
          select.current(item.mediaAuthorization, item.format);
        }
      })
      .catch((err) => {
        if (!abort.signal.aborted) setError(err instanceof Error ? err.message : t('线路读取失败。'));
      })
      .finally(() => {
        if (!abort.signal.aborted) setLoading(false);
      });
    return () => abort.abort();
  }, [source, workId, chapterId, attempt, initialItems]);

  useEffect(() => {
    if (!failed) {
      lastFailure.current = undefined;
      return;
    }
    if (lastFailure.current === failed || !items.length) return;
    lastFailure.current = failed;
    let { line, mirror } = position.current;
    const current = items[line];
    if ((current?.mirrorAuthorizations?.length ?? 0) > mirror + 1) {
      mirror++;
      setNotice(t('当前播放地址不可用，正在尝试备用地址。'));
    } else if (line + 1 < items.length) {
      line++;
      mirror = 0;
      setNotice(t('当前线路不可用，正在尝试其他播放线路。'));
    } else {
      setNotice(t('已尝试所有播放线路，请重新加载或稍后重试。'));
      return;
    }
    position.current = { line, mirror };
    const next = items[line]!;
    setSelected(next.id);
    select.current(next.mirrorAuthorizations?.[mirror] ?? next.mediaAuthorization, next.format);
  }, [failed, items]);

  return (
    <div className="reader-controls" role="group" aria-label={audio ? t('播放线路') : t('媒体线路与清晰度')}>
      {loading ? <p role="status">{t('正在读取播放线路')}</p> : null}
      {items.length > 0 ? (
        <label>
          {audio ? t('播放线路') : t('线路与清晰度 ')}
          <select
            value={selected}
            onChange={(event) => {
              const line = items.findIndex((i) => i.id === event.target.value);
              if (line < 0) return;
              position.current = { line, mirror: 0 };
              const next = items[line]!;
              setSelected(next.id);
              setNotice('');
              lastFailure.current = undefined;
              select.current(next.mediaAuthorization, next.format);
            }}
          >
            {items.map((item) => (
              <option key={item.id} value={item.id}>
                {item.label}
                {item.mirrors > 1 ? ' · ' + item.mirrors + t('个播放地址') : ''}
              </option>
            ))}
          </select>
        </label>
      ) : null}
      {!loading && !error && !items.length ? <p role="status">{t('暂无可切换的播放线路')}</p> : null}
      {error ? (
        <div className="action-row" role="status">
          <span>{error}</span>
          <button className="chip" onClick={() => setAttempt((n) => n + 1)}>
            {t('重新加载线路')}
          </button>
        </div>
      ) : null}
      {notice ? <p role="status">{notice}</p> : null}
    </div>
  );
}
