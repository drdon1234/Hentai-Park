import { useEffect, useRef, useState } from 'react';
import { request } from './api.js';
import { t } from './i18n.js';

type Login = { loginId: string; frameUrl: string; expiresAt: number };
type LoginStatus = { url?: string; title?: string; popupCount?: number };

export function SourceLoginControls({
  source,
  onCompleted,
  verification = false,
}: {
  source: string;
  onCompleted: () => void;
  verification?: boolean;
}) {
  const [login, setLogin] = useState<Login>();
  const [status, setStatus] = useState<LoginStatus>();
  const [frame, setFrame] = useState('');
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const active = useRef<Login | undefined>(undefined);
  const objectUrl = useRef('');
  const generation = useRef(0);
  const opening = useRef<AbortController | undefined>(undefined);
  const dragStart = useRef<{ x: number; y: number } | null>(null);

  const path = (id: string) => '/api/v1/source-logins/' + encodeURIComponent(id);

  const cancel = async () => {
    opening.current?.abort();
    generation.current++;
    const current = active.current;
    active.current = undefined;
    setLogin(undefined);
    setStatus(undefined);
    setText('');
    setFrame('');
    if (objectUrl.current) {
      URL.revokeObjectURL(objectUrl.current);
      objectUrl.current = '';
    }
    if (current) {
      await request(path(current.loginId), { method: 'DELETE', body: JSON.stringify({ requestKey: crypto.randomUUID() }) });
    }
  };

  useEffect(
    () => () => {
      opening.current?.abort();
      const current = active.current;
      active.current = undefined;
      generation.current++;
      if (objectUrl.current) URL.revokeObjectURL(objectUrl.current);
      if (current) {
        void request(path(current.loginId), {
          method: 'DELETE',
          body: JSON.stringify({ requestKey: crypto.randomUUID() }),
        }).catch(() => {});
      }
    },
    [source],
  );

  useEffect(() => {
    if (!login) return;
    const abort = new AbortController();
    let reading = false;
    const update = async () => {
      if (reading || abort.signal.aborted) return;
      reading = true;
      try {
        const [response, stat] = await Promise.all([
          fetch(login.frameUrl, { credentials: 'include', cache: 'no-store', signal: abort.signal }),
          request<LoginStatus>(path(login.loginId) + '/status', { signal: abort.signal }).catch(() => undefined),
        ]);
        if (stat && !abort.signal.aborted) setStatus(stat);
        if (!response.ok || !response.headers.get('content-type')?.startsWith('image/jpeg')) {
          throw Error(t('登录页面已关闭或不可用，请重新打开。'));
        }
        const blob = await response.blob();
        if (blob.size > 2 * 1024 * 1024) throw Error(t('登录页面图像过大。'));
        if (abort.signal.aborted) return;
        const next = URL.createObjectURL(blob);
        const previous = objectUrl.current;
        objectUrl.current = next;
        setFrame(next);
        if (previous) URL.revokeObjectURL(previous);
      } catch (error) {
        if (!abort.signal.aborted) {
          setNotice(error instanceof Error ? error.message : t('无法读取登录页面。'));
          void cancel().catch(() => {});
        }
      } finally {
        reading = false;
      }
    };
    void update();
    const timer = setInterval(() => void update(), 400);
    return () => {
      clearInterval(timer);
      abort.abort();
    };
  }, [login]);

  const run = async (action: () => Promise<void>) => {
    if (busy) return;
    setBusy(true);
    setNotice('');
    try {
      await action();
    } catch (error) {
      setNotice(error instanceof Error ? error.message : t('网页登录操作未完成。'));
    } finally {
      setBusy(false);
    }
  };

  const start = () =>
    run(async () => {
      const current = ++generation.current;
      const controller = new AbortController();
      opening.current = controller;
      const result = await request<Login>(
        '/api/v1/sources/' + encodeURIComponent(source) + (verification ? '/verify-browser' : '/login-browser'),
        { method: 'POST', signal: controller.signal, body: JSON.stringify({ requestKey: crypto.randomUUID() }) },
      );
      if (!/^[A-Za-z0-9_-]{32}$/.test(result.loginId) || result.frameUrl !== path(result.loginId) + '/frame') {
        throw Error(t('登录页面地址无效。'));
      }
      if (current !== generation.current) {
        await request(path(result.loginId), { method: 'DELETE' });
        return;
      }
      active.current = result;
      setLogin(result);
    });

  const control = (body: Record<string, unknown>) =>
    run(async () => {
      if (!active.current) return;
      await request(path(active.current.loginId) + '/control', { method: 'POST', body: JSON.stringify(body) });
    });

  const complete = () =>
    run(async () => {
      if (!active.current) return;
      const result = await request<{ account: { loggedIn: boolean; configured?: boolean; verified?: boolean } }>(
        path(active.current.loginId) + '/complete',
        { method: 'POST', body: JSON.stringify({ requestKey: crypto.randomUUID() }) },
      );
      active.current = undefined;
      setLogin(undefined);
      setStatus(undefined);
      setText('');
      setFrame('');
      if (objectUrl.current) URL.revokeObjectURL(objectUrl.current);
      objectUrl.current = '';
      setNotice(
        verification
          ? t('站点验证已完成，请重新执行原来的读取操作。')
          : result.account.loggedIn
            ? t('原站账号已验证并登录。')
            : t('原站凭据已保存，站点未提供账号状态验证。'),
      );
      onCompleted();
    });

  const toCoords = (event: React.PointerEvent<HTMLImageElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    return {
      x: Math.max(0, Math.min(960, Math.round(((event.clientX - bounds.left) / bounds.width) * 960))),
      y: Math.max(0, Math.min(540, Math.round(((event.clientY - bounds.top) / bounds.height) * 540))),
    };
  };

  return (
    <div className="source-login-controls">
      {busy && !login ? (
        <button className="chip" onClick={() => void cancel().catch(() => {})}>
          {t('取消')}
        </button>
      ) : null}
      {!login ? (
        <button className="chip" disabled={busy} onClick={() => void start()}>
          {t(verification ? '打开站点人工验证' : '打开原站登录页面')}
        </button>
      ) : (
        <div>
          <h3>{t(verification ? '站点人工验证' : '原站网页登录')}</h3>
          {status?.url ? (
            <p className="muted" style={{ fontSize: 12, overflowWrap: 'anywhere' }}>
              {status.title ? `${status.title} · ` : ''}
              {status.url}
              {status.popupCount && status.popupCount > 0 ? ` · OAuth (${status.popupCount})` : ''}
            </p>
          ) : null}
          <p>
            {t(
              verification
                ? '在下方原站页面点击或拖拽完成滑块/人机验证后点击完成；取消不会导入状态。'
                : '在下方原站页面点击或拖拽操作，支持第三方 OAuth 弹窗。完成后点击保存导入声明的 Cookie 与本地存储。',
            )}
          </p>
          {frame ? (
            <div className="source-login-frame" style={{ overflow: 'auto', maxWidth: '100%', maxHeight: '34rem' }}>
              <img
                src={frame}
                alt={t('原站受控登录页面')}
                style={{ display: 'block', width: '100%', maxWidth: 960, aspectRatio: '16 / 9', touchAction: 'none' }}
                onPointerDown={(e) => {
                  e.currentTarget.setPointerCapture(e.pointerId);
                  dragStart.current = toCoords(e);
                }}
                onPointerUp={(e) => {
                  const startPt = dragStart.current;
                  dragStart.current = null;
                  const endPt = toCoords(e);
                  if (!startPt) return;
                  if (Math.hypot(endPt.x - startPt.x, endPt.y - startPt.y) > 12) {
                    void control({ action: 'drag', x: startPt.x, y: startPt.y, toX: endPt.x, toY: endPt.y });
                  } else {
                    void control({ action: 'click', x: endPt.x, y: endPt.y });
                  }
                }}
              />
            </div>
          ) : (
            <p role="status">{t('正在读取原站页面…')}</p>
          )}
          <form
            onSubmit={(event) => {
              event.preventDefault();
              const value = text;
              setText('');
              void control({ action: 'type', text: value });
            }}
          >
            <label>
              {t('输入到原站的文字')}
              <input
                type="password"
                value={text}
                maxLength={4096}
                autoComplete="off"
                disabled={busy}
                onChange={(event) => setText(event.target.value)}
              />
            </label>
            <button className="chip" disabled={busy || !text}>
              {t('发送输入')}
            </button>
          </form>
          <div className="action-row">
            {['Tab', 'Shift+Tab', 'Enter', 'Backspace', 'Escape'].map((key) => (
              <button key={key} className="chip" disabled={busy} onClick={() => void control({ action: 'key', key })}>
                {key}
              </button>
            ))}
            <button className="chip" disabled={busy} onClick={() => void control({ action: 'scroll', deltaY: -400 })}>
              {t('向上滚动')}
            </button>
            <button className="chip" disabled={busy} onClick={() => void control({ action: 'scroll', deltaY: 400 })}>
              {t('向下滚动')}
            </button>
          </div>
          <div className="action-row">
            <button className="primary-link" disabled={busy} onClick={() => void complete()}>
              {t(verification ? '完成验证' : '完成登录并验证账号')}
            </button>
            <button className="chip" onClick={() => void cancel().catch((error) => setNotice(String(error)))}>
              {t(verification ? '取消验证' : '取消网页登录')}
            </button>
          </div>
        </div>
      )}
      {notice ? <p role="status">{notice}</p> : null}
    </div>
  );
}
