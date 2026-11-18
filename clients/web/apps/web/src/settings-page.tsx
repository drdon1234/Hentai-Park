import { useEffect, useRef, useState, type MouseEvent, type ReactNode } from 'react';
import { StatusMessage, applySeedTheme, confirmAction, hexToSeedColor, seedColorToHex, showToast } from '@hentai-park/design-system';
import { api } from './api.js';
import { BlockPreferences } from './block-preferences.js';
import { CollectionPreferences } from './collection-preferences.js';
import { FilePicker } from './file-picker.js';
import { SourceOrderPreferences } from './home-preferences.js';
import { languageNames, t } from './i18n.js';
import { LanguageTools } from './language-tools.js';
import { MaintenanceStatus } from './maintenance-status.js';
import { resolveThemePreference, setThemeMode } from './native.js';
import { PageHeader, StateView, errorMessage, useAsync } from './page-ui.js';
import { PreferenceFields, comicKeys, novelKeys } from './preference-fields.js';
import { RuntimeSettings } from './runtime-settings.js';
import { StorageControls } from './storage-controls.js';

export const settingsSectionTitles = {
  appearance: '外观',
  reading: '阅读',
  shortVideo: '短视频',
  shelf: '收藏与下载',
  search: '搜索与翻译',
  network: '网络',
  privacy: '隐私与安全',
  subscriptions: '订阅与通知',
  filter: '内容过滤',
  storage: '存储',
  backup: '备份',
  about: '关于',
} as const;

const SEED_PRESETS = ['#2f6fae', '#6366f1', '#ec4899', '#10b981', '#f59e0b', '#8b5cf6'];

export function SettingsPage({ navigate }: { navigate: (url: string) => void }) {
  const [pendingBackup, setPendingBackup] = useState<Record<string, unknown>>();
  const [pendingParkbakFile, setPendingParkbakFile] = useState<File>();
  const [preview, setPreview] = useState<Awaited<ReturnType<typeof api.backupPreview>>>();
  const state = useAsync(() => Promise.all([api.session.get(), api.settings(), api.diagnostics()]), []);
  const [settings, setSettings] = useState<Record<string, unknown>>({});
  const [version, setVersion] = useState(0);
  const [saveMessage, setSaveMessage] = useState('');
  const [backupMessage, setBackupMessage] = useState('');
  const [pinDraft, setPinDraft] = useState('');
  const [hasPin, setHasPin] = useState(false);
  const [busy, setBusy] = useState(false);
  const [external, setExternal] = useState(false);
  const [include, setInclude] = useState([
    'sourceRegistry',
    'sourceSettings',
    'works',
    'chapters',
    'categories',
    'history',
    'library',
    'subscriptions',
    'subscriptionSeen',
    'subscriptionEvents',
    'eventReadStates',
    'novelNotes',
    'tavernAssets',
    'tavernConversations',
    'tavernConnections',
    'worldbookTerms',
    'subscriptionEventTargets',
    'settings',
  ]);
  const currentVersion = useRef(version);
  currentVersion.current = version;

  useEffect(() => {
    if (state.data) {
      setHasPin(state.data[0].hasPin === true);
      setSettings(state.data[1].settings);
      setVersion(state.data[1].version);
    }
  }, [state.data]);

  useEffect(() => {
    const check = () => {
      void api
        .settings()
        .then((value) => {
          if (value.version !== currentVersion.current) setExternal(true);
        })
        .catch((error) => setSaveMessage(errorMessage(error)));
    };
    window.addEventListener('hp:server-update', check);
    window.addEventListener('hp:invalidate', check);
    return () => {
      window.removeEventListener('hp:server-update', check);
      window.removeEventListener('hp:invalidate', check);
    };
  }, []);

  const reload = async () => {
    if (!(await confirmAction(t('重新读取服务端设置将丢弃当前未保存修改，继续？')))) return;
    try {
      const value = await api.settings();
      setSettings(value.settings);
      setVersion(value.version);
      currentVersion.current = value.version;
      setExternal(false);
      setSaveMessage(t('已加载最新设置'));
    } catch (error) {
      setSaveMessage(errorMessage(error));
    }
  };

  const save = async () => {
    const invalid = document.querySelector<HTMLInputElement>('.settings-section-content input:invalid');
    if (invalid) {
      let ancestor: HTMLElement | null = invalid.parentElement;
      while (ancestor) {
        if (ancestor instanceof HTMLDetailsElement) ancestor.open = true;
        ancestor = ancestor.parentElement;
      }
      invalid.reportValidity();
      invalid.focus();
      return;
    }
    setBusy(true);
    setSaveMessage(t('正在保存…'));
    try {
      const value = await api.updateSettings(settings, version);
      setSettings(value.settings);
      setVersion(value.version);
      currentVersion.current = value.version;
      setExternal(false);
      setSaveMessage(t('设置已保存'));
      if (settings.ageConfirmed !== true) window.dispatchEvent(new Event('hp:recheck-session'));
    } catch (error) {
      setSaveMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const confirmSensitiveExport = async () => {
    const hasSensitive = include.some((k) => ['accounts', 'cookies', 'tavernConnectionSecrets'].includes(k));
    if (!hasSensitive) return true;
    return confirmAction({
      title: t('备份包含未加密的账号或密钥'),
      description: t('你勾选了站点账号、Cookie 或模型 API 密钥。导出的备份文件以明文或压缩格式存储这些凭据，请勿公开分享。确认继续导出？'),
      confirmLabel: t('确认导出'),
      danger: true,
    });
  };

  const exportBackup = async (format: 'parkbak' | 'json') => {
    if (!(await confirmSensitiveExport())) return;
    if (format === 'parkbak') {
      const link = document.createElement('a');
      link.href = api.backupExportParkbakUrl(include);
      link.download = `hentai-park-${new Date().toISOString().slice(0, 10)}.parkbak`;
      link.click();
      setBackupMessage(t('已触发 .parkbak 备份下载（兼容 Android 客户端）'));
      return;
    }
    setBusy(true);
    try {
      const value = await api.backupExport(include);
      const blob = new Blob([JSON.stringify(value)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'hentai-park-backup.json';
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      setBackupMessage(t('备份已导出'));
    } catch (error) {
      setBackupMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const importBackup = async (file: File) => {
    setPendingBackup(undefined);
    setPendingParkbakFile(undefined);
    setPreview(undefined);
    setBusy(true);
    setBackupMessage('');
    try {
      if (file.size > 128 * 1024 * 1024 - 4096) throw new Error(t('备份超过128MiB限制，请按分区分别导入。'));
      const isGzipOrParkbak = /\.parkbak$|\.gz$/i.test(file.name) || file.type === 'application/gzip';
      if (isGzipOrParkbak) {
        const value = await api.backupPreviewParkbak(file);
        setPendingParkbakFile(file);
        setPreview(value);
      } else {
        let backup: Record<string, unknown>;
        try {
          backup = JSON.parse(await file.text()) as Record<string, unknown>;
        } catch {
          throw new Error(t('无法读取备份文件，请选择有效的 .parkbak 或 JSON 备份。'));
        }
        const value = await api.backupPreview(backup);
        setPendingBackup(backup);
        setPreview(value);
      }
      setBackupMessage(t('预览完成，尚未写入当前实例。'));
    } catch (error) {
      setBackupMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const confirmImport = async () => {
    if (!pendingBackup && !pendingParkbakFile) return;
    setBusy(true);
    try {
      const value = pendingParkbakFile
        ? await api.backupImportParkbak(pendingParkbakFile)
        : await api.backupImport(pendingBackup!);
      if (value.imported !== true) throw new Error(t('服务端未确认导入完成'));
      setBackupMessage(t('备份已合并，请加载最新设置和相关页面。'));
      setPendingBackup(undefined);
      setPendingParkbakFile(undefined);
      setPreview(undefined);
      setExternal(true);
      showToast(t('备份导入成功'), 'success');
    } catch (error) {
      setBackupMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const saveAppLockPin = async () => {
    if (pinDraft.trim().length < 4) {
      setSaveMessage(t('应用锁 PIN 至少需要 4 个字符。'));
      return;
    }
    setBusy(true);
    try {
      const res = await api.session.setAppLockPin(pinDraft.trim());
      setHasPin(res.hasPin);
      setPinDraft('');
      showToast(t('应用锁 PIN 已更新'), 'success');
    } catch (err) {
      setSaveMessage(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  const requested = new URLSearchParams(window.location.search).get('section') ?? '';
  const backupOptions = [
    ['works', t('作品')],
    ['chapters', t('章节')],
    ['history', t('历史')],
    ['library', t('收藏')],
    ['subscriptions', t('订阅')],
    ['settings', t('应用设置')],
    ['sourceRegistry', t('站点注册')],
    ['sourceSettings', t('站点设置')],
    ['categories', t('分类')],
    ['subscriptionSeen', t('订阅基线')],
    ['subscriptionEvents', t('订阅更新历史')],
    ['eventReadStates', t('事件已读状态')],
    ['novelNotes', t('小说书签与标注')],
    ['tavernAssets', t('酒馆资源')],
    ['tavernConversations', t('酒馆会话')],
    ['tavernConnections', t('模型连接设置')],
    ['worldbookTerms', t('世界书术语词包')],
    ['tavernConnectionSecrets', t('模型API密钥（敏感）')],
    ['subscriptionEventTargets', t('更新关联目标')],
    ['accounts', t('站点账号（敏感）')],
    ['cookies', t('站点Cookie（敏感）')],
    ['downloads', t('下载元数据')],
  ];
  const backupLabels = Object.fromEntries(backupOptions);
  const backupGroups = [
    { title: '作品', keys: ['works', 'chapters', 'history', 'library', 'categories', 'novelNotes', 'downloads'] },
    { title: '订阅', keys: ['subscriptions', 'subscriptionSeen', 'subscriptionEvents', 'eventReadStates', 'subscriptionEventTargets'] },
    { title: '站点设置', keys: ['settings', 'sourceRegistry', 'sourceSettings'] },
    { title: '酒馆', keys: ['tavernAssets', 'tavernConversations', 'tavernConnections', 'worldbookTerms'] },
    { title: '隐私与安全', keys: ['tavernConnectionSecrets', 'accounts', 'cookies'] },
  ];
  const sections = [
    'appearance',
    'reading',
    'shortVideo',
    'shelf',
    'search',
    'network',
    'privacy',
    'subscriptions',
    'filter',
    'storage',
    'backup',
    'about',
  ] as const;
  type Section = (typeof sections)[number];
  const section = sections.includes(requested as Section) ? (requested as Section) : undefined;
  const active: Section = section ?? 'appearance';
  const titles = settingsSectionTitles;

  const link = (event: MouseEvent<HTMLAnchorElement>) => {
    if (event.button === 0 && !event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) {
      event.preventDefault();
      navigate(event.currentTarget.getAttribute('href')!);
    }
  };

  const immediateSetting = async (key: string, value: unknown) => {
    if (busy || external) return;
    const previousTheme = resolveThemePreference(settings.theme);
    if (key === 'theme') setThemeMode(resolveThemePreference(value));
    if (key === 'seedColor') applySeedTheme(value as number | string | undefined, resolveThemePreference(settings.theme));
    setBusy(true);
    setSaveMessage(t('正在保存…'));
    try {
      const result = await api.updateSettings({ [key]: value }, currentVersion.current);
      currentVersion.current = result.version;
      setVersion(result.version);
      setSettings((prior) => ({ ...prior, [key]: value }));
      if (key === 'theme') setThemeMode(resolveThemePreference(result.settings.theme));
      setExternal(false);
      setSaveMessage(t('设置已保存'));
    } catch (error) {
      if (key === 'theme') setThemeMode(previousTheme);
      setSaveMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const summary: Record<string, string> = {
    appearance:
      t(settings.theme === 'system' ? '跟随系统' : settings.theme === 'light' ? '浅色' : '深色') +
      ' · ' +
      (languageNames[String(settings.language ?? '')] ?? t('跟随系统')),
    reading: t('朗读速度') + ' · ' + String(settings.novelSpeechRate ?? 1) + '×',
    shortVideo: t('预加载') + ' ' + String(settings.shortVideoPreloadCount ?? 3) + ' · ' + t('保留已看') + ' ' + String(settings.shortVideoRetainedCount ?? 2),
    shelf: t('下载') + ' · ' + t('管理分类'),
    search: t('启用内容和多语言搜索翻译'),
    network: t('管理站点与验证状态'),
    privacy: [settings.coverBlur ? t('模糊封面') : '', settings.appLockEnabled ? t('应用锁') : ''].filter(Boolean).join(' · '),
    storage: t('缓存与本地数据'),
    subscriptions: t(settings.subscriptionsEnabled === false ? '已关闭' : '自动检查'),
    filter: t('屏蔽词'),
    backup: '.parkbak · JSON',
    about: 'HentaiPark · AGPL-3.0',
  };

  const groups: Array<{ title: string; items: Array<{ key: string; title: string; href: string }> }> = [
    {
      title: '使用',
      items: ['appearance', 'reading', 'shortVideo', 'shelf', 'search'].map((key) => ({
        key,
        title: titles[key as Section],
        href: '/settings?section=' + key,
      })),
    },
    {
      title: '连接与隐私',
      items: ['network', 'privacy', 'subscriptions', 'filter'].map((key) => ({
        key,
        title: titles[key as Section],
        href: '/settings?section=' + key,
      })),
    },
    {
      title: '数据',
      items: [
        { key: 'sites', title: '站点', href: '/sources' },
        ...['storage', 'backup', 'about'].map((key) => ({
          key,
          title: titles[key as Section],
          href: '/settings?section=' + key,
        })),
      ],
    },
  ];

  const field = (key: string, label: string, checked: boolean) => (
    <label className="settings-toggle">
      <span>{t(label)}</span>
      <input
        type="checkbox"
        role={key === 'ageConfirmed' ? undefined : 'switch'}
        checked={checked}
        disabled={busy || external}
        onChange={(event) =>
          key === 'ageConfirmed'
            ? setSettings((prior) => ({ ...prior, [key]: event.target.checked }))
            : void immediateSetting(key, event.target.checked)
        }
      />
    </label>
  );

  const saveButton = (
    <button className="primary-link" disabled={busy || external} onClick={() => void save()}>
      {t('保存设置')}
    </button>
  );

  let content: ReactNode;
  switch (active) {
    case 'appearance':
      content = (
        <section className="settings-panel">
          <fieldset className="theme-options">
            <legend>{t('主题')}</legend>
            <div className="action-row">
              {(
                [
                  ['light', '浅色'],
                  ['dark', '深色'],
                  ['system', '跟随系统'],
                ] as const
              ).map(([value, label]) => (
                <button
                  key={value}
                  className="chip"
                  aria-pressed={(settings.theme ?? 'dark') === value}
                  disabled={busy || external}
                  onClick={() => void immediateSetting('theme', value)}
                >
                  {t(label)}
                </button>
              ))}
            </div>
          </fieldset>

          <label>
            {t('主题强调色')}
            <div className="action-row" style={{ margin: 0 }}>
              {SEED_PRESETS.map((hex) => (
                <button
                  key={hex}
                  type="button"
                  aria-label={hex}
                  disabled={busy || external}
                  onClick={() => void immediateSetting('seedColor', hexToSeedColor(hex))}
                  style={{
                    width: 30,
                    height: 30,
                    minWidth: 30,
                    minHeight: 30,
                    padding: 0,
                    borderRadius: '50%',
                    background: hex,
                    border: seedColorToHex(settings.seedColor as number | string | undefined) === hex.toLowerCase() ? '3px solid var(--browse-text)' : '2px solid transparent',
                  }}
                />
              ))}
              <input
                type="color"
                aria-label={t('自定义强调色')}
                value={seedColorToHex(settings.seedColor as number | string | undefined) ?? '#2f6fae'}
                disabled={busy || external}
                onChange={(e) => void immediateSetting('seedColor', hexToSeedColor(e.target.value))}
                style={{ width: 38, height: 34, padding: 2 }}
              />
            </div>
          </label>

          <label>
            {t('界面语言')}
            <select
              value={String(settings.language ?? '')}
              disabled={busy || external}
              onChange={(event) => void immediateSetting('language', event.target.value)}
            >
              <option value="">{t('跟随系统')}</option>
              {Object.entries(languageNames).map(([key, label]) => (
                <option key={key} value={key}>
                  {label}
                </option>
              ))}
            </select>
          </label>

          <PreferenceFields
            keys={['gridColumns', 'albumColumns', 'albumCollapsed']}
            settings={settings}
            onChange={(patch) => setSettings({ ...settings, ...patch })}
          />
          <details className="advanced-options">
            <summary>{t('首页内容与顺序')}</summary>
            <CollectionPreferences kind="home" settings={settings} onChange={(patch) => setSettings({ ...settings, ...patch })} />
            <SourceOrderPreferences settings={settings} onChange={(patch) => setSettings({ ...settings, ...patch })} />
          </details>
          {saveButton}
        </section>
      );
      break;

    case 'reading':
      content = (
        <section className="settings-panel reading-settings">
          <details className="preference-settings-group">
            <summary>{t('漫画阅读')}</summary>
            <div className="preference-group-fields">
              <PreferenceFields keys={comicKeys} settings={settings} onChange={(patch) => setSettings({ ...settings, ...patch })} />
            </div>
          </details>
          <details className="preference-settings-group">
            <summary>{t('小说阅读')}</summary>
            <div className="preference-group-fields">
              <PreferenceFields keys={novelKeys} settings={settings} onChange={(patch) => setSettings({ ...settings, ...patch })} />
              <label>
                {t('朗读速度')}
                <input
                  type="number"
                  min={0.5}
                  max={2}
                  step={0.1}
                  value={Number(settings.novelSpeechRate ?? 1)}
                  onChange={(event) => setSettings({ ...settings, novelSpeechRate: Number(event.target.value) })}
                />
              </label>
            </div>
          </details>
          <details className="preference-settings-group">
            <summary>{t('音视频播放')}</summary>
            <div className="preference-group-fields">
              <PreferenceFields
                keys={['shortVideoPreloadCount', 'shortVideoRetainedCount', 'voiceBackgroundPlayback', 'playbackRate', 'danmakuArea']}
                settings={settings}
                onChange={(patch) => setSettings({ ...settings, ...patch })}
              />
            </div>
          </details>
          {saveButton}
        </section>
      );
      break;

    case 'shortVideo':
      content = (
        <section className="settings-panel">
          <PreferenceFields
            keys={['shortVideoPreloadCount', 'shortVideoRetainedCount', 'playbackRate', 'danmakuArea', 'voiceBackgroundPlayback']}
            settings={settings}
            onChange={(patch) => setSettings({ ...settings, ...patch })}
          />
          {saveButton}
        </section>
      );
      break;

    case 'shelf':
      content = (
        <section className="settings-panel">
          <div className="action-row">
            <a className="chip" href="/library" onClick={link}>
              {t('收藏')}
            </a>
            <a className="chip" href="/library#library-management" onClick={link}>
              {t('管理分类')}
            </a>
            <a className="chip" href="/downloads" onClick={link}>
              {t('查看后台下载与进度')}
            </a>
          </div>
          <RuntimeSettings settings={settings} onChange={setSettings} section="downloads" />
          <PreferenceFields
            keys={[
              'pdfPagesPerFile',
              'askCategoryOnFavorite',
              'librarySort',
              'librarySortAsc',
              'libraryDisplay',
              'historyDisplay',
              'downloadDisplay',
              'libraryFilterKind',
              'libraryFilterDownloaded',
              'libraryFilterUnread',
              'badgeUnread',
              'badgeDownloaded',
              'badgeSource',
              'libraryUpdateHours',
              'updateOnlyMultiChapter',
              'updateSkipUnread',
              'updateSkipNotStarted',
              'autoDownloadNew',
              'deleteAfterRead',
            ]}
            settings={settings}
            onChange={(patch) => setSettings({ ...settings, ...patch })}
          />
          {saveButton}
        </section>
      );
      break;

    case 'search':
      content = (
        <>
          <section className="settings-panel">
            <PreferenceFields
              keys={['autoTranslateContent', 'tagDownloadReminders']}
              settings={settings}
              onChange={(patch) =>
                setSettings({ ...settings, ...patch, ...(patch.autoTranslateContent === true ? { contentTranslationEnabled: true } : {}) })
              }
            />
            <CollectionPreferences kind="languages" settings={settings} onChange={(patch) => setSettings({ ...settings, ...patch })} />
            <CollectionPreferences kind="sources" settings={settings} onChange={(patch) => setSettings({ ...settings, ...patch })} />
            {saveButton}
            {field('contentTranslationEnabled', '启用内容和多语言搜索翻译', settings.contentTranslationEnabled === true)}
            <p>{t('手动翻译或启用自动翻译后，将相应文字发送至Google翻译服务；原文始终保留。')}</p>
          </section>
          <LanguageTools />
        </>
      );
      break;

    case 'network':
      content = (
        <section className="settings-panel">
          <PreferenceFields
            keys={['dataSavingMode', 'imageConcurrency', 'cacheLimitMb', 'autoSourceUpdates']}
            settings={settings}
            onChange={(patch) => setSettings({ ...settings, ...patch })}
          />
          <div className="action-row">
            {saveButton}
            <a className="secondary-link" href="/sources" onClick={link}>
              {t('管理站点与验证状态')}
            </a>
          </div>
          <details className="advanced-options">
            <summary>{t('详细信息')}</summary>
            <p>{t('访问边界由各站点声明和宿主校验；代理、数据路径和下载根目录由部署配置管理，重启生效。')}</p>
          </details>
        </section>
      );
      break;

    case 'privacy':
      content = (
        <section className="settings-panel">
          {field('coverBlur', '模糊封面', settings.coverBlur === true)}
          {field('appLockEnabled', '启用应用锁', settings.appLockEnabled === true)}
          <PreferenceFields
            keys={['appLockAfter']}
            settings={settings}
            onChange={(patch) => setSettings({ ...settings, ...patch })}
          />
          <div className="form-row" style={{ marginBlock: 12 }}>
            <label style={{ flex: 1 }}>
              {hasPin ? t('更新应用锁 PIN') : t('设置应用锁 PIN（推荐）')}
              <input
                type="password"
                autoComplete="new-password"
                minLength={4}
                maxLength={64}
                value={pinDraft}
                onChange={(e) => setPinDraft(e.target.value)}
                placeholder={hasPin ? t('已配置独立 PIN；输入新 PIN 可替换') : t('至少 4 位字符')}
              />
            </label>
            <button
              type="button"
              className="chip"
              disabled={busy || pinDraft.trim().length < 4}
              onClick={() => void saveAppLockPin()}
            >
              {t('保存 PIN')}
            </button>
            {(hasPin || state.data?.[0].mode === 'server') ? (
              <button
                type="button"
                className="chip"
                disabled={busy}
                onClick={() =>
                  void api.session.lock().then(() => window.dispatchEvent(new Event('hp:app-locked'))).catch(() => {})
                }
              >
                {t('立即锁定')}
              </button>
            ) : null}
          </div>
          <p>{t('应用锁触发时以毛玻璃遮罩锁定画面，不会卸载阅读或播放进度。')}</p>
          {field('ageConfirmed', '已确认18+', settings.ageConfirmed === true)}
          <div className="action-row">
            {saveButton}
            <button
              className="secondary-link"
              disabled={busy}
              onClick={() => void api.session.logout().catch((error) => setSaveMessage(errorMessage(error)))}
            >
              {t('退出会话')}
            </button>
          </div>
        </section>
      );
      break;

    case 'subscriptions':
      content = (
        <section className="settings-panel">
          {field('subscriptionsEnabled', '启用后台订阅检查', settings.subscriptionsEnabled !== false)}
          <RuntimeSettings settings={settings} onChange={setSettings} section="subscriptions" />
          {field('notificationsEnabled', '页面内订阅更新通知', settings.notificationsEnabled === true)}
          <div className="action-row">
            {saveButton}
            <a className="chip" href="/subscriptions" onClick={link}>
              {t('订阅')}
            </a>
          </div>
        </section>
      );
      break;

    case 'filter':
      content = (
        <section className="settings-panel">
          {field('hidePreviews', '隐藏仅预览内容', settings.hidePreviews === true)}
          <label>
            {t('屏蔽词（每行一个）')}
            <textarea
              rows={4}
              value={Array.isArray(settings.blockedWords) ? settings.blockedWords.join('\n') : ''}
              onChange={(event) =>
                setSettings({
                  ...settings,
                  blockedWords: event.target.value
                    .split('\n')
                    .map((word) => word.trim())
                    .filter(Boolean),
                })
              }
            />
          </label>
          <RuntimeSettings settings={settings} onChange={setSettings} section="filter" />
          <BlockPreferences settings={settings} onChange={(patch) => setSettings({ ...settings, ...patch })} />
          {saveButton}
        </section>
      );
      break;

    case 'storage':
      content = (
        <section className="settings-panel">
          <StorageControls />
          <MaintenanceStatus />
          <PreferenceFields
            keys={['cacheLimitMb', 'dataSavingMode']}
            settings={settings}
            onChange={(patch) => setSettings({ ...settings, ...patch })}
          />
          <p>{t('缓存和下载文件由当前实例统一管理；清理和离线内容入口分别位于下载页。')}</p>
          {saveButton}
        </section>
      );
      break;

    case 'backup':
      content = (
        <section className="settings-panel" id="backup" tabIndex={-1}>
          <MaintenanceStatus />
          <PreferenceFields
            keys={['autoBackupHours', 'autoBackupKeep']}
            settings={settings}
            onChange={(patch) => setSettings({ ...settings, ...patch })}
          />
          {saveButton}
          <div className="backup-groups">
            {backupGroups.map((group) => (
              <details className="backup-group" key={group.title}>
                <summary>
                  <span>{t(group.title)}</span>
                  <span className="backup-count">
                    {group.keys.filter((key) => include.includes(key)).length} / {group.keys.length}
                  </span>
                </summary>
                <fieldset className="backup-options">
                  <legend className="sr-only">{t(group.title)}</legend>
                  {group.keys.map((key) => (
                    <label key={key}>
                      <input
                        type="checkbox"
                        disabled={busy}
                        checked={include.includes(key)}
                        onChange={(event) =>
                          setInclude((values) =>
                            event.target.checked ? [...new Set([...values, key])] : values.filter((value) => value !== key),
                          )
                        }
                      />
                      {backupLabels[key]}
                    </label>
                  ))}
                </fieldset>
              </details>
            ))}
          </div>
          <p className="muted">
            {t('支持与 Android 客户端互通的 .parkbak 压缩备份及 Web JSON 备份。导出敏感分区前会确认明文凭据风险。')}
          </p>
          <div className="action-row">
            <button className="primary-link" disabled={busy} onClick={() => void exportBackup('parkbak')}>
              {t('导出 .parkbak 备份')}
            </button>
            <button className="secondary-link" disabled={busy} onClick={() => void exportBackup('json')}>
              {t('导出 JSON 备份')}
            </button>
            <FilePicker
              label={t('导入备份')}
              accept=".parkbak,.json,application/json,application/gzip"
              disabled={busy}
              onChange={(event) => {
                const file = event.target.files?.[0];
                if (file) void importBackup(file);
                event.target.value = '';
              }}
            />
          </div>
          {preview ? (
            <section aria-label={t('备份合并预览')}>
              <h3>{t('合并预览')}</h3>
              <p>{t('确认时按服务端当时状态重新检查并合并；冲突保留较新记录，恢复的站点保持禁用。')}</p>
              <div className="table-scroll" tabIndex={0} role="region" aria-label={t('备份合并预览')}>
                <table className="backup-preview-table">
                  <thead>
                    <tr>
                      <th>{t('分区')}</th>
                      <th>{t('输入')}</th>
                      <th>{t('新增')}</th>
                      <th>{t('替换')}</th>
                      <th>{t('保留')}</th>
                      <th>{t('冲突')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {Object.entries(preview.partitions).map(([name, row]) => (
                      <tr key={name}>
                        <th scope="row">{backupLabels[name] ?? name}</th>
                        <td>{row.incoming}</td>
                        <td>{row.added}</td>
                        <td>{row.replaced}</td>
                        <td>{row.retained}</td>
                        <td>{row.conflicts}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="action-row">
                <button className="primary-link" disabled={busy} onClick={() => void confirmImport()}>
                  {t('确认合并备份')}
                </button>
                <button
                  className="chip"
                  disabled={busy}
                  onClick={() => {
                    setPendingBackup(undefined);
                    setPendingParkbakFile(undefined);
                    setPreview(undefined);
                    setBackupMessage(t('已取消导入，当前数据未改变。'));
                  }}
                >
                  {t('取消导入')}
                </button>
              </div>
            </section>
          ) : null}
          {backupMessage ? <p role="status">{backupMessage}</p> : null}
        </section>
      );
      break;

    case 'about':
      content = (
        <section className="settings-panel">
          <h2>HentaiPark</h2>
          <p>{t('HentaiPark · 浏览、阅读与管理来自不同站点的内容。')}</p>
          <div className="action-row" style={{ marginBottom: 16 }}>
            <a className="chip" href="/logs" onClick={link}>
              {t('运行与诊断日志')}
            </a>
            <a className="chip" href="/licenses" onClick={link}>
              {t('开源许可与声明')}
            </a>
          </div>
          <details>
            <summary>{t('关于与诊断')}</summary>
            <pre className="diagnostics" tabIndex={0} role="region" aria-label={t('详细信息')}>
              {JSON.stringify(state.data?.[2], null, 2)}
            </pre>
          </details>
        </section>
      );
      break;
  }

  return (
    <div className={'settings-layout ' + (section ? 'settings-detail' : 'settings-root')}>
      <StateView loading={state.loading} error={state.error} empty={false}>
        {state.data ? (
          <>
            {external || saveMessage ? (
              <div className="settings-feedback-region">
                {external ? (
                  <StatusMessage tone="warning" title={t('设置已在其他页面更新')}>
                    {t('当前草稿已保留，请重新读取后再保存。')}
                    <button className="chip" disabled={busy} onClick={() => void reload()}>
                      {t('加载最新设置')}
                    </button>
                  </StatusMessage>
                ) : null}
                {saveMessage ? (
                  <p className="settings-feedback" role="status">
                    {saveMessage}
                  </p>
                ) : null}
              </div>
            ) : null}
            <aside className="settings-index" aria-label={t('设置分组')}>
              {section ? <h2>{t('设置')}</h2> : <PageHeader title={t('我的')} />}
              <label className="settings-toggle settings-incognito">
                <span>
                  <strong>{t('无痕模式')}</strong>
                  <small>{t('暂停记录历史、阅读进度与已读状态')}</small>
                </span>
                <input
                  type="checkbox"
                  role="switch"
                  checked={settings.incognito === true}
                  disabled={busy || external}
                  onChange={(event) => void immediateSetting('incognito', event.target.checked)}
                />
              </label>
              {groups.map((group) => (
                <section className="settings-index-group" key={group.title}>
                  <h2>{t(group.title)}</h2>
                  {group.items.map((item) => (
                    <a
                      className={'settings-index-link ' + (item.key === active ? 'active' : '')}
                      aria-current={section && item.key === active ? 'page' : undefined}
                      key={item.key}
                      href={item.href}
                      onClick={link}
                    >
                      <span>
                        <strong>{t(item.title)}</strong>
                        {summary[item.key] ? <small>{summary[item.key]}</small> : null}
                      </span>
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" aria-hidden="true">
                        <path d="m9 5 7 7-7 7" />
                      </svg>
                    </a>
                  ))}
                </section>
              ))}
            </aside>
            <div className="settings-section-content">
              <a className="settings-back" href="/settings" onClick={link}>
                {t('设置')}
              </a>
              {section ? <PageHeader title={t(titles[active])} /> : <h2>{t(titles[active])}</h2>}
              {content}
            </div>
          </>
        ) : null}
      </StateView>
    </div>
  );
}
