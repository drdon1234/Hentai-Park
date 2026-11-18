import { useEffect, useState, type FormEvent, type ReactNode } from 'react';
import { StatusMessage } from '@hentai-park/design-system';
import { api, request } from './api.js';
import { tabId } from './native.js';
import { t } from './i18n.js';
import { errorMessage } from './page-ui.js';

/**
 * Non-destructive App Lock overlay: keeps <App /> mounted underneath so reading position,
 * video playback state, form drafts, and cached shelves are never destroyed when locked.
 */
export function AppLockGate({ initialLocked = false, children }: { initialLocked?: boolean; children: ReactNode }) {
  const [locked, setLocked] = useState(initialLocked);
  const [pin, setPin] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    const refresh = () => {
      void api.session
        .get()
        .then((s) => {
          if (!s.authenticated) window.dispatchEvent(new Event('hp:unauthorized'));
          else setLocked(s.locked === true);
        })
        .catch(() => {});
    };
    const activity = () => {
      void request('/api/v1/session/activity', {
        method: 'POST',
        body: JSON.stringify({ tabId, visible: !document.hidden }),
        keepalive: true,
      })
        .then(() => {
          if (!document.hidden) refresh();
        })
        .catch(() => {});
    };
    const onLocked = () => setLocked(true);
    window.addEventListener('hp:app-locked', onLocked);
    activity();
    const timer = setInterval(() => {
      if (!document.hidden) activity();
      else refresh();
    }, 15000);
    document.addEventListener('visibilitychange', activity);
    window.addEventListener('focus', activity);
    return () => {
      clearInterval(timer);
      window.removeEventListener('hp:app-locked', onLocked);
      document.removeEventListener('visibilitychange', activity);
      window.removeEventListener('focus', activity);
    };
  }, []);

  const unlock = async (event: FormEvent) => {
    event.preventDefault();
    if (!pin.trim() || busy) return;
    setBusy(true);
    setError('');
    try {
      const next = await api.session.unlock(pin.trim());
      setPin('');
      setLocked(next.locked === true);
      window.dispatchEvent(new Event('hp:resume-read'));
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <div aria-hidden={locked || undefined} inert={locked || undefined}>
        {children}
      </div>
      {locked ? (
        <div className="app-lock-overlay" role="dialog" aria-modal="true" aria-label={t('应用锁')}>
          <form className="app-lock-card" onSubmit={(e) => void unlock(e)}>
            <h2>{t('实例已锁定')}</h2>
            <p className="muted">{t('输入应用锁 PIN（或实例访问凭据）继续浏览，已打开的页面状态将完整保留。')}</p>
            <label>
              <span className="sr-only">{t('应用锁 PIN')}</span>
              <input
                type="password"
                autoFocus
                required
                autoComplete="current-password"
                placeholder={t('输入应用锁 PIN')}
                value={pin}
                onChange={(e) => setPin(e.target.value)}
              />
            </label>
            {error ? <StatusMessage tone="danger" title={t('解锁失败')}>{error}</StatusMessage> : null}
            <div className="action-row" style={{ justifyContent: 'flex-end', margin: 0 }}>
              <button type="submit" className="primary-link" disabled={busy || !pin.trim()}>
                {busy ? t('正在解锁…') : t('解锁')}
              </button>
            </div>
          </form>
        </div>
      ) : null}
    </>
  );
}
