import { useState } from 'react';
import { EmptyState, confirmAction, showToast } from '@hentai-park/design-system';
import { api } from '../api.js';
import { navigateClick } from '../app/app-context.js';
import { t } from '../i18n.js';
import { PageHeader, StateView, errorMessage, useAsync } from '../page-ui.js';

export function LogsPage({ navigate }: { navigate: (to: string) => void }) {
  const [attempt, setAttempt] = useState(0);
  const [busy, setBusy] = useState(false);
  const state = useAsync(() => api.diagnosticsLogs(300), [attempt]);
  const items = state.data?.items ?? [];

  const copyLogs = async () => {
    await navigator.clipboard.writeText(JSON.stringify(items, null, 2));
    showToast(t('已复制脱敏诊断日志'), 'success');
  };

  const clearLogs = async () => {
    const ok = await confirmAction({
      title: t('清空诊断日志？'),
      confirmLabel: t('清空'),
      danger: true,
    });
    if (!ok) return;
    setBusy(true);
    try {
      await api.clearDiagnosticsLogs();
      setAttempt((n) => n + 1);
      showToast(t('日志已清空'), 'success');
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <PageHeader
        title={t('运行与诊断日志')}
        description={t('仅记录白名单事件与状态码，自动过滤账号、Cookie、Token、请求体、作品内容与本机路径。')}
      >
        <button type="button" className="chip" onClick={() => setAttempt((n) => n + 1)}>
          {t('刷新')}
        </button>
        <button type="button" className="chip" disabled={!items.length} onClick={() => void copyLogs()}>
          {t('复制日志')}
        </button>
        <button type="button" className="chip danger-action" disabled={busy || !items.length} onClick={() => void clearLogs()}>
          {t('清空日志')}
        </button>
        <a
          className="chip"
          href="/settings?section=about"
          onClick={(e) => navigateClick(e, navigate, '/settings?section=about')}
        >
          {t('关于')}
        </a>
      </PageHeader>
      <StateView loading={state.loading} error={state.error ? errorMessage(state.error) : undefined} empty={!items.length}>
        {!items.length ? (
          <EmptyState title={t('暂无诊断记录')} detail={t('系统运行正常，白名单事件触发后将按时间记录在此。')} />
        ) : (
          <section className="settings-panel">
            <pre className="diagnostics" style={{ maxHeight: '70dvh' }} tabIndex={0}>
              {items
                .map((entry) => {
                  const meta = Object.fromEntries(
                    Object.entries(entry).filter(([k, v]) => !['at', 'level', 'event'].includes(k) && v !== undefined),
                  );
                  return `[${entry.at}] [${entry.level.toUpperCase()}] ${entry.event}${
                    Object.keys(meta).length ? ' ' + JSON.stringify(meta) : ''
                  }`;
                })
                .join('\n')}
            </pre>
          </section>
        )}
      </StateView>
    </>
  );
}

const OPEN_SOURCE_COMPONENTS = [
  { name: 'HentaiPark', license: 'AGPL-3.0-only', note: 'Main application & Web workspace' },
  { name: 'React & React DOM', license: 'MIT', note: 'UI component runtime' },
  { name: 'Fastify', license: 'MIT', note: 'HTTP server & API routing' },
  { name: 'QuickJS (quickjs-emscripten)', license: 'MIT', note: 'Isolated source plugin JS runtime' },
  { name: 'Playwright Core', license: 'Apache-2.0', note: 'Headless browser verification & media gateway' },
  { name: 'hls.js', license: 'Apache-2.0', note: 'HTTP Live Streaming media source engine' },
];

export function LicensesPage({ navigate }: { navigate: (to: string) => void }) {
  return (
    <>
      <PageHeader title={t('开源许可与声明')} description="GNU Affero General Public License v3.0 (AGPL-3.0-only)">
        <a
          className="chip"
          href="/settings?section=about"
          onClick={(e) => navigateClick(e, navigate, '/settings?section=about')}
        >
          {t('返回关于')}
        </a>
      </PageHeader>
      <section className="settings-panel">
        <h2>HentaiPark · AGPL-3.0-only</h2>
        <p style={{ lineHeight: 1.7 }}>
          {t(
            'HentaiPark 采用 GNU Affero General Public License v3.0 (AGPL-3.0-only) 许可发布。修改或通过网络提供本软件服务时，须按许可证要求公开完整对应源代码并保留原始版权及许可声明。',
          )}
        </p>
      </section>
      <section className="settings-panel">
        <h2>{t('第三方开源组件')}</h2>
        <ul className="chapter-list">
          {OPEN_SOURCE_COMPONENTS.map((item) => (
            <li key={item.name}>
              <span>
                <strong>{item.name}</strong>
                <small className="chapter-state">{item.note}</small>
              </span>
              <span className="chip">{item.license}</span>
            </li>
          ))}
        </ul>
      </section>
    </>
  );
}
