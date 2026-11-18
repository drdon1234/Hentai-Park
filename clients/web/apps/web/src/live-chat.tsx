import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { request } from './api.js';
import { t } from './i18n.js';
import { PreferenceFields } from './preference-fields.js';
import { usePreferences } from './preferences.js';

type ChatMessage = { id: string; text: string; author: string; time: number };
type ScheduledDanmaku = ChatMessage & { received: number; lane: number };

const LANE_COUNT = 8;

export function LiveChat({ source, workId }: { source: string; workId: string }) {
  const prefs = usePreferences();
  const [overlay, setOverlay] = useState(true);
  const [recent, setRecent] = useState<ScheduledDanmaku[]>([]);
  const [fsElement, setFsElement] = useState<Element | null>(() =>
    typeof document !== 'undefined' ? document.fullscreenElement : null,
  );
  const laneFreeAt = useRef<number[]>(Array.from({ length: LANE_COUNT }, () => 0));

  useEffect(() => {
    const onFs = () => setFsElement(document.fullscreenElement);
    document.addEventListener('fullscreenchange', onFs);
    const timer = setInterval(() => setRecent((value) => value.filter((item) => Date.now() - item.received < 8200)), 1000);
    return () => {
      document.removeEventListener('fullscreenchange', onFs);
      clearInterval(timer);
    };
  }, []);

  const [active, setActive] = useState(false);
  const [status, setStatus] = useState('idle');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [error, setError] = useState('');
  const scroll = useRef<HTMLDivElement>(null);
  const follow = useRef(true);

  const allocateLane = (textLen: number): number => {
    const now = Date.now();
    let bestLane = 0;
    let earliest = Infinity;
    for (let i = 0; i < LANE_COUNT; i++) {
      const freeAt = laneFreeAt.current[i]!;
      if (freeAt <= now) {
        bestLane = i;
        break;
      }
      if (freeAt < earliest) {
        earliest = freeAt;
        bestLane = i;
      }
    }
    laneFreeAt.current[bestLane] = Math.max(now, laneFreeAt.current[bestLane]!) + Math.min(3500, 1200 + textLen * 45);
    return bestLane;
  };

  useEffect(() => {
    if (!active) return;
    let disposed = false;
    let chatId: string | undefined;
    let events: EventSource | undefined;
    const abort = new AbortController();
    setStatus('connecting');
    setError('');
    setMessages([]);
    const close = () => {
      events?.close();
      if (chatId) {
        const id = chatId;
        chatId = undefined;
        void request('/api/v1/live-chat/' + encodeURIComponent(id), {
          method: 'DELETE',
          body: JSON.stringify({ requestKey: crypto.randomUUID() }),
        }).catch(() => {});
      }
    };
    void request<{ chatId: string; eventsUrl: string }>(
      '/api/v1/live/' + encodeURIComponent(source) + '/' + encodeURIComponent(workId) + '/chat',
      { method: 'POST', body: JSON.stringify({ requestKey: crypto.randomUUID() }), signal: abort.signal },
    )
      .then((result) => {
        chatId = result.chatId;
        if (disposed) {
          close();
          return;
        }
        const url = new URL(result.eventsUrl, window.location.origin);
        if (
          url.origin !== window.location.origin ||
          !/^\/api\/v1\/live-chat\/[A-Za-z0-9_-]{32}\/events$/.test(url.pathname) ||
          url.search ||
          url.hash
        ) {
          throw Error(t('聊天连接地址无效。'));
        }
        events = new EventSource(url.pathname, { withCredentials: true });
        events.addEventListener('status', (event) => {
          try {
            const data = JSON.parse((event as MessageEvent).data);
            if (disposed) return;
            setStatus(data.connected === true ? 'connected' : data.state === 'closed' ? 'closed' : 'connecting');
            if (data.state === 'closed') close();
          } catch {
            setError(t('聊天状态无效，请重新连接。'));
            close();
            setStatus('closed');
          }
        });
        events.addEventListener('message', (event) => {
          try {
            const data = JSON.parse((event as MessageEvent).data) as ChatMessage;
            if (
              disposed ||
              typeof data.id !== 'string' ||
              typeof data.text !== 'string' ||
              typeof data.author !== 'string' ||
              data.text.length > 4000
            ) {
              return;
            }
            const lane = allocateLane(data.text.length);
            setMessages((current) => [...current, data].slice(-150));
            setRecent((current) => [...current, { ...data, received: Date.now(), lane }].slice(-28));
          } catch {
            /* ignore */
          }
        });
        events.addEventListener('error', () => {
          if (disposed) return;
          setStatus('closed');
          setError(t('聊天连接已断开，可以重新连接。'));
          close();
        });
      })
      .catch((reason) => {
        if (!disposed) {
          setError(reason instanceof Error && !reason.message.startsWith('error.') ? t(reason.message) : t('聊天连接未能建立。'));
          setStatus('closed');
          close();
        }
      });
    return () => {
      disposed = true;
      abort.abort();
      close();
    };
  }, [source, workId, active]);

  useEffect(() => {
    if (follow.current && scroll.current) scroll.current.scrollTop = scroll.current.scrollHeight;
  }, [messages]);

  const hostTarget =
    (fsElement && fsElement.tagName !== 'VIDEO' ? fsElement : null) ??
    document.querySelector('.media-picture') ??
    document.querySelector('.reader-canvas');
  const area = String(prefs.settings.danmakuArea);
  const height = area === 'topQuarter' ? '25%' : area === 'full' ? '100%' : '50%';

  return (
    <section className="settings-panel" aria-labelledby="live-chat-heading">
      {active && overlay && hostTarget
        ? createPortal(
            <div className="danmaku-overlay" aria-hidden="true" style={{ height, top: area === 'bottomHalf' ? '50%' : 0 }}>
              {recent.map((message) => (
                <span key={message.id + ':' + message.received} style={{ top: message.lane * 12 + '%' }}>
                  {message.text}
                </span>
              ))}
            </div>,
            hostTarget,
          )
        : null}
      <label>
        <input type="checkbox" checked={overlay} onChange={(event) => setOverlay(event.target.checked)} />
        {t('显示弹幕')}
      </label>
      <PreferenceFields keys={['danmakuArea']} settings={prefs.settings} onChange={(patch) => void prefs.save(patch)} />
      <h2 id="live-chat-heading">{t('直播聊天')}</h2>
      <p role="status">
        {status === 'connected'
          ? t('已连接直播间聊天')
          : status === 'connecting'
            ? t('正在连接，等待直播间确认')
            : status === 'closed'
              ? t('聊天连接已关闭')
              : t('连接后展示新的公开聊天消息。')}
      </p>
      <div className="action-row">
        <button
          className="chip"
          onClick={() => {
            if (active && status === 'closed') {
              setActive(false);
              setTimeout(() => setActive(true), 0);
            } else setActive((value) => !value);
          }}
        >
          {active && status !== 'closed' ? t('停止聊天连接') : status === 'closed' ? t('重新连接聊天') : t('连接直播聊天')}
        </button>
        <button className="chip" disabled={!messages.length} onClick={() => setMessages([])}>
          {t('清空显示')}
        </button>
        <label>
          <input
            type="checkbox"
            defaultChecked
            onChange={(event) => {
              follow.current = event.target.checked;
            }}
          />
          {t('自动滚动')}
        </label>
      </div>
      {error ? <p role="alert">{error}</p> : null}
      <div ref={scroll} role="log" aria-live="polite" aria-relevant="additions" style={{ maxHeight: '22rem', overflowY: 'auto', overflowWrap: 'anywhere' }}>
        {messages.length ? (
          <ol>
            {messages.map((message, index) => (
              <li key={message.id + ':' + index}>
                <strong>{message.author || t('匿名用户')}</strong>：{message.text}
              </li>
            ))}
          </ol>
        ) : (
          <p>{active ? t('尚无新的聊天消息。') : t('聊天连接尚未启动。')}</p>
        )}
      </div>
    </section>
  );
}
