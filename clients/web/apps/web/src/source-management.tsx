import { useEffect, useState } from 'react';
import { confirmAction } from '@hentai-park/design-system';
import { request } from './api.js';
import { pluginText, t } from './i18n.js';
import { SourceLoginControls } from './source-login-controls.js';

type Row = Record<string, unknown>;
type Setting = {
  key: string;
  label: string;
  description?: string;
  type: string;
  values?: Array<{ value: string | number | boolean; label: string }>;
  options?: Array<{ value: string | number | boolean; label: string }>;
};

const failure = (error: unknown) => (error instanceof Error ? error.message : t('操作未能完成。'));

export function SourceManagement({ source, manifest, enabled }: { source: string; manifest: Row; enabled: boolean }) {
  const path = '/api/v1/sources/' + encodeURIComponent(source);
  const declarations = (Array.isArray(manifest.settings) ? (manifest.settings as Setting[]) : []).filter(
    (item) => !((manifest.account as Row | undefined)?.managedAccount === true && item.key === 'managedAccount'),
  );
  const [settings, setSettings] = useState<Row>({});
  const [version, setVersion] = useState(0);
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const [account, setAccount] = useState<Row>();

  const reload = async (signal?: AbortSignal) => {
    if (declarations.length || (manifest.account as Row | undefined)?.managedAccount === true) {
      const result = await request<{ settings: Row; version: number }>(path + '/settings', { signal });
      if (!signal?.aborted) {
        setSettings(result.settings);
        setVersion(result.version);
        setDirty(false);
      }
    }
    if (manifest.account) {
      const result = await request<Row>(path + '/account', { signal });
      if (!signal?.aborted) {
        setAccount(result.account && typeof result.account === 'object' && !Array.isArray(result.account) ? (result.account as Row) : result);
      }
    }
  };

  useEffect(() => {
    if (!enabled) return;
    const abort = new AbortController();
    void reload(abort.signal).catch((error) => {
      if (!abort.signal.aborted) setNotice(failure(error));
    });
    return () => abort.abort();
  }, [source, enabled]);

  const save = async () => {
    setBusy(true);
    setNotice('');
    try {
      const result = await request<{ settings: Row; version: number }>(path + '/settings', {
        method: 'PATCH',
        body: JSON.stringify({ settings, version, requestKey: crypto.randomUUID() }),
      });
      setSettings(result.settings);
      setVersion(result.version);
      setDirty(false);
      setNotice(t('站点设置已保存。'));
    } catch (error) {
      setNotice(failure(error) + t(' 当前草稿已保留，可重新读取后再保存。'));
    } finally {
      setBusy(false);
    }
  };

  const operation = async (action: string, enableFlag = true) => {
    setBusy(true);
    try {
      await request(path + '/' + action, {
        method: 'POST',
        body: JSON.stringify({ ...(action === 'managed' ? { confirmed: enableFlag, enabled: enableFlag } : {}), requestKey: crypto.randomUUID() }),
      });
      await reload();
      setNotice(t('账号状态已更新。'));
    } catch (error) {
      await reload().catch(() => {});
      setNotice(failure(error));
    } finally {
      setBusy(false);
    }
  };

  if (!enabled) return null;

  return (
    <>
      <SourceLoginControls
        source={source}
        verification
        onCompleted={() => setNotice(t('站点验证已完成，请返回内容页面重试。'))}
      />
      {manifest.account ? (
        <section className="settings-panel" aria-label={t('站点账号状态')}>
          <h2>{t('账号状态')}</h2>
          <p role="status">
            {account?.loggedIn === true
              ? t('已登录')
              : account?.configured === true && account.verified === false
                ? t('Cookie已保存，账号状态尚未验证')
                : account
                  ? t('未登录')
                  : t('正在读取账号状态')}
            {typeof account?.name === 'string' ? ' · ' + account.name : ''}
          </p>
          <div className="action-row">
            <button className="chip" disabled={busy} onClick={() => void reload().catch((error) => setNotice(failure(error)))}>
              {t('刷新账号状态')}
            </button>
            <button
              className="chip"
              disabled={busy}
              onClick={async () => {
                if (await confirmAction({ title: t('退出站点账号并清理会话') + '？', danger: true })) {
                  void operation('logout');
                }
              }}
            >
              {t('退出站点账号并清理会话')}
            </button>
            {(manifest.account as Row).managedAccount === true ? (
              <button
                className="chip"
                disabled={busy}
                onClick={async () => {
                  if (
                    await confirmAction(
                      t('确认向原站注册专用账号？凭据保存在本实例并用于自动重新登录；失败重试复用同一账号，已有手动账号不会被替换。'),
                    )
                  ) {
                    void operation('managed');
                  }
                }}
              >
                {t(settings.managedAccount === true ? '重试专用账号' : '启用专用自动维护账号')}
              </button>
            ) : null}
            {settings.managedAccount === true ? (
              <button className="chip" disabled={busy} onClick={() => void operation('managed', false)}>
                {t('关闭专用自动维护账号')}
              </button>
            ) : null}
          </div>
          {(manifest.account as Row).managedAccount === true ? (
            <p>
              {t(
                settings.managedAccount === true
                  ? '专用账号已启用；未就绪时请重试，已保存的凭据会被复用。'
                  : '专用账号已关闭。关闭或退出不会删除已保存的专用凭据。',
              )}
            </p>
          ) : null}
          {typeof (manifest.account as Row).registerUrl === 'string' ? (
            <a className="secondary-link" href={String((manifest.account as Row).registerUrl)} target="_blank" rel="noreferrer">
              {t('前往原站注册自己的账号')}
            </a>
          ) : null}
          {typeof (manifest.account as Row).loginUrl === 'string' ? (
            <SourceLoginControls
              source={source}
              onCompleted={() => {
                void reload().catch((error) => setNotice(failure(error)));
              }}
            />
          ) : null}
        </section>
      ) : null}

      {declarations.length ? (
        <section className="settings-panel" aria-label={t('站点设置')}>
          <h2>{t('站点设置')}</h2>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              void save();
            }}
          >
            {declarations.map((item) => {
              const options = item.values ?? item.options ?? [];
              const value = settings[item.key];
              const change = (next: unknown) => {
                setSettings((current) => ({ ...current, [item.key]: next }));
                setDirty(true);
              };
              if (item.type === 'multi') {
                const selectedArr = Array.isArray(value) ? value.map((v) => JSON.stringify(v)) : [];
                return (
                  <fieldset key={item.key}>
                    <legend>{pluginText(manifest, item.label)}</legend>
                    <div className="multi-pill-group">
                      {options.map((opt) => {
                        const ser = JSON.stringify(opt.value);
                        const active = selectedArr.includes(ser);
                        return (
                          <button
                            key={ser}
                            type="button"
                            className={`chip ${active ? 'active' : ''}`}
                            aria-pressed={active}
                            onClick={() => {
                              const nextArr = active ? selectedArr.filter((s) => s !== ser) : [...selectedArr, ser];
                              change(
                                nextArr
                                  .map((s) => options.find((c) => JSON.stringify(c.value) === s)?.value)
                                  .filter((v) => v !== undefined),
                              );
                            }}
                          >
                            {pluginText(manifest, opt.label)}
                          </button>
                        );
                      })}
                    </div>
                  </fieldset>
                );
              }
              return (
                <label key={item.key}>
                  {pluginText(manifest, item.label)}
                  {item.type === 'switch' ? (
                    <input
                      type="checkbox"
                      role="switch"
                      checked={value === true}
                      onChange={(event) => change(event.target.checked)}
                    />
                  ) : item.type === 'select' ? (
                    <select
                      value={value === undefined ? '' : JSON.stringify(value)}
                      onChange={(event) =>
                        change(options.find((option) => JSON.stringify(option.value) === event.target.value)?.value)
                      }
                    >
                      <option value="" disabled>
                        {t('请选择')}
                      </option>
                      {options.map((option) => (
                        <option key={JSON.stringify(option.value)} value={JSON.stringify(option.value)}>
                          {pluginText(manifest, option.label)}
                        </option>
                      ))}
                    </select>
                  ) : (
                    <input
                      type={item.type === 'number' ? 'number' : item.type === 'password' ? 'password' : 'text'}
                      value={typeof value === 'string' || typeof value === 'number' ? value : ''}
                      autoComplete="off"
                      onChange={(event) =>
                        change(item.type === 'number' ? Number(event.target.value) : event.target.value)
                      }
                    />
                  )}
                  <small>{item.description ? pluginText(manifest, item.description) : null}</small>
                </label>
              );
            })}
            <div className="action-row">
              <button className="primary-link" disabled={busy || !dirty}>
                {t('保存站点设置')}
              </button>
              <button
                className="chip"
                type="button"
                disabled={busy}
                onClick={async () => {
                  if (!dirty || (await confirmAction(t('重新读取将丢弃此标签页尚未保存的站点设置，继续？')))) {
                    void reload().catch((error) => setNotice(failure(error)));
                  }
                }}
              >
                {t('重新读取')}
              </button>
            </div>
          </form>
        </section>
      ) : null}

      {notice ? <p role="status">{notice}</p> : null}
    </>
  );
}
