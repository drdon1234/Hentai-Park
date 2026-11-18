import {
  StrictMode,
  Suspense,
  lazy,
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type FormEvent,
} from 'react';
import { createRoot } from 'react-dom/client';
import { ConfirmProvider, StatusMessage, ToastHost, applySeedTheme } from '@hentai-park/design-system';
import { chapterIdentityKey, workIdentityKey } from '@hentai-park/domain-model';
import './tokens.css';
import './styles.css';
import './controls.css';
import './desktop.css';
import './refactor-ux.css';
import appIcon from './app-icon.png';
import { allPages, api, request, subscribeEvents, type Session } from './api.js';
import {
  CategoryNames,
  KeepAliveView,
  SourceCatalog,
  SourceNames,
  currentRoute,
  navigateClick,
  routes,
  type Route,
} from './app/app-context.js';
import { AppLockGate } from './app-lock.js';
import { clearBrowseSessions, handleBrowseSessionEvent } from './browse-session-cache.js';
import { NavigationIcon, categoryLabels, domainHref, domainOrder } from './browse-ui.js';
import { configureCoverCache } from './cover-image.js';
import { DesktopBack, DesktopScrollTop } from './desktop-navigation.js';
import { languageNames, pluginText, setLanguage, t, useLanguage } from './i18n.js';
import {
  downloadKey,
  recordInternalPush,
  resolveThemePreference,
  setThemeMode,
  sharedStateStore,
  usePageLifecycle,
  useScrollRestoration,
  useSharedState,
  useThemeMode,
} from './native.js';
import { PageHeader, errorMessage, useAsync, useServerVersion } from './page-ui.js';
import { DiscoverPage } from './pages/discover-page.js';
import { OfflinePage } from './data-controls.js';
import { DownloadsPage } from './pages/downloads-page.js';
import { LibraryPage } from './pages/library-page.js';
import { PreferenceSettingsContext as PreferenceContext, PreferencesProvider, usePreferences } from './preferences.js';
import { SettingsPage, settingsSectionTitles } from './settings-page.js';

/* Route-level React.lazy code splitting for secondary/heavy views */
const SearchPage = lazy(() => import('./pages/search-page.js').then((m) => ({ default: m.SearchPage })));
const ReverseSearch = lazy(() => import('./pages/search-page.js').then((m) => ({ default: m.ReverseSearch })));
const SourcePage = lazy(() => import('./pages/source-page.js').then((m) => ({ default: m.SourcePage })));
const SourcesPage = lazy(() => import('./pages/source-page.js').then((m) => ({ default: m.SourcesPage })));
const WorkPage = lazy(() => import('./pages/work-page.js').then((m) => ({ default: m.WorkPage })));
const ReaderPage = lazy(() => import('./pages/reader-page.js').then((m) => ({ default: m.ReaderPage })));
const AlbumPage = lazy(() => import('./pages/album-page.js').then((m) => ({ default: m.AlbumPage })));
const RankingsPage = lazy(() => import('./rankings.js').then((m) => ({ default: m.RankingsPage })));
const SubscriptionsPage = lazy(() => import('./subscriptions-page.js').then((m) => ({ default: m.SubscriptionsPage })));
const ChannelPage = lazy(() => import('./extended-pages.js').then((m) => ({ default: m.ChannelPage })));
const PostPage = lazy(() => import('./extended-pages.js').then((m) => ({ default: m.PostPage })));
const TavernLibraryPage = lazy(() => import('./extended-pages.js').then((m) => ({ default: m.TavernLibraryPage })));
const LogsPage = lazy(() => import('./pages/logs-and-licenses.js').then((m) => ({ default: m.LogsPage })));
const LicensesPage = lazy(() => import('./pages/logs-and-licenses.js').then((m) => ({ default: m.LicensesPage })));

function SessionGate() {
  const [session, setSession] = useState<Session>();
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [token, setToken] = useState('');
  const [ageConfirmed, setAgeConfirmed] = useState<boolean>();
  const [initialSettings, setInitialSettings] = useState<Record<string, unknown>>();
  const [check, setCheck] = useState(0);

  useEffect(() => {
    const recheck = () => setCheck((value) => value + 1);
    window.addEventListener('hp:recheck-session', recheck);
    return () => window.removeEventListener('hp:recheck-session', recheck);
  }, []);

  useEffect(() => {
    if (!session?.authenticated) {
      setAgeConfirmed(undefined);
      setInitialSettings(undefined);
      return;
    }
    let live = true;
    void api
      .settings()
      .then(async (value) => {
        await setLanguage(String(value.settings.language ?? ''));
        if (live) {
          setInitialSettings(value.settings);
          setAgeConfirmed(value.settings.ageConfirmed === true);
        }
      })
      .catch((reason) => {
        if (live && session.locked !== true) setError(errorMessage(reason));
      });
    return () => {
      live = false;
    };
  }, [session?.authenticated, session?.locked, check]);

  useEffect(() => {
    clearBrowseSessions();
  }, [session?.sessionId, session?.authenticated]);

  const refresh = useCallback(() => {
    setError(undefined);
    void api.session
      .get()
      .then(setSession)
      .catch((reason) => setError(errorMessage(reason)));
  }, []);

  useEffect(() => {
    refresh();
    const expire = () =>
      setSession((value) => (value ? { ...value, authenticated: false } : { sessionId: '', mode: 'server', authenticated: false }));
    window.addEventListener('hp:unauthorized', expire);
    window.addEventListener('hp:retry-read', refresh);
    return () => {
      window.removeEventListener('hp:unauthorized', expire);
      window.removeEventListener('hp:retry-read', refresh);
    };
  }, [refresh]);

  const login = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setError(undefined);
    try {
      const value = await api.session.login(token);
      setToken('');
      setSession(value);
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setBusy(false);
    }
  };

  if (session?.authenticated && session.locked === true) {
    return (
      <AppLockGate initialLocked>
        <div style={{ minHeight: '100dvh' }} />
      </AppLockGate>
    );
  }
  if (session?.authenticated && ageConfirmed === true && initialSettings?.onboarded === false) {
    return (
      <WebOnboarding
        initial={initialSettings}
        onComplete={() => setInitialSettings((value) => ({ ...(value ?? {}), onboarded: true, onboardingCompleted: true }))}
      />
    );
  }
  if (session?.authenticated && ageConfirmed === true) {
    return (
      <PreferencesProvider key={session.sessionId}>
        <AppLockGate initialLocked={session.locked === true}>
          <App mode={session.mode} />
        </AppLockGate>
      </PreferencesProvider>
    );
  }
  if (session?.authenticated) {
    return (
      <main className="session-gate">
        <section className="session-panel">
          <div className="session-brand">
            <img src={appIcon} alt="" />
            <strong>HentaiPark</strong>
          </div>
          <h1>{ageConfirmed === false ? t('年龄与隐私确认') : t('正在读取实例设置')}</h1>
          <p>{t('本实例包含仅供成年人浏览的内容。收藏、进度与后台任务由整个单用户实例共享；图片反搜上传仅用于本次查询。')}</p>
          {ageConfirmed === false ? (
            <button
              className="primary-link"
              disabled={busy}
              onClick={() => {
                setBusy(true);
                void api
                  .updateSettings({ ageConfirmed: true })
                  .then(() => setAgeConfirmed(true))
                  .catch((reason) => setError(errorMessage(reason)))
                  .finally(() => setBusy(false));
              }}
            >
              {t('我已满18岁并继续')}
            </button>
          ) : null}
          {error ? (
            <StatusMessage tone="danger" title={t('读取或确认失败')}>
              {error}
              <button className="chip" onClick={refresh}>
                {t('重试')}
              </button>
            </StatusMessage>
          ) : null}
        </section>
      </main>
    );
  }
  return (
    <main className="session-gate">
      <section className="session-panel">
        <div className="session-brand">
          <img src={appIcon} alt="" />
          <strong>HentaiPark</strong>
        </div>
        <h1>{session ? t('登录实例') : t('正在连接实例')}</h1>
        <p>{t('当前页面地址会保留，认证后继续。')}</p>
        {!session ? <p className="session-help">{t('请确认实例已启动且当前地址可访问。')}</p> : null}
        {session ? (
          <form onSubmit={(e) => void login(e)}>
            <label>
              {t('实例访问凭据')}
              <input
                type="password"
                value={token}
                onChange={(event) => setToken(event.target.value)}
                autoComplete="current-password"
                required={session.mode === 'server'}
              />
            </label>
            <button className="primary-link" disabled={busy} type="submit">
              {busy ? t('正在登录') : t('登录')}
            </button>
          </form>
        ) : null}
        {error ? (
          <StatusMessage tone="danger" title={t('连接或认证失败')}>
            {error}
          </StatusMessage>
        ) : null}
      </section>
    </main>
  );
}

function WebOnboarding({ initial, onComplete }: { initial: Record<string, unknown>; onComplete: () => void }) {
  const [step, setStep] = useState<'privacy' | 'interests'>('privacy');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [blur, setBlur] = useState(initial.coverBlur === true);
  const [lock, setLock] = useState(initial.appLockEnabled === true);
  const [categories, setCategories] = useState<string[]>(
    Array.isArray(initial.homeCategories) ? initial.homeCategories.filter((item): item is string => typeof item === 'string') : [],
  );

  const finish = async (nextCategories = categories) => {
    setBusy(true);
    setError('');
    try {
      await api.updateSettings({
        coverBlur: blur,
        appLockEnabled: lock,
        homeCategories: nextCategories,
        onboarded: true,
        onboardingCompleted: true,
      });
      onComplete();
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="session-gate">
      <section className="session-panel">
        <div className="session-brand">
          <img src={appIcon} alt="" />
          <strong>HentaiPark</strong>
        </div>
        <nav className="onboarding-steps" aria-label={t('设置分组')}>
          <span aria-current={step === 'privacy' ? 'step' : undefined}>{t('隐私与安全')}</span>
          <span aria-current={step === 'interests' ? 'step' : undefined}>{t('首页内容')}</span>
        </nav>
        {step === 'privacy' ? (
          <>
            <h1>{t('隐私与安全')}</h1>
            <p>{t('先确认封面和应用锁偏好，之后可在“我的”中随时修改。')}</p>
            <label className="settings-toggle">
              <span>{t('模糊封面')}</span>
              <input type="checkbox" role="switch" checked={blur} onChange={(event) => setBlur(event.target.checked)} />
            </label>
            <label className="settings-toggle">
              <span>{t('启用应用锁')}</span>
              <input type="checkbox" role="switch" checked={lock} onChange={(event) => setLock(event.target.checked)} />
            </label>
            <button className="primary-link" onClick={() => setStep('interests')}>
              {t('继续')}
            </button>
          </>
        ) : (
          <>
            <h1>{t('首页内容')}</h1>
            <p>{t('选择后会用于发现页的默认内容分类；也可以跳过。')}</p>
            <div className="multi-pill-group" style={{ marginBottom: 20 }}>
              {domainOrder.map((category) => {
                const checked = categories.length === 0 || categories.includes(category);
                return (
                  <button
                    key={category}
                    type="button"
                    className={`chip ${checked ? 'active' : ''}`}
                    aria-pressed={checked}
                    onClick={() =>
                      setCategories((current) =>
                        checked
                          ? current.length === 0
                            ? domainOrder.filter((item) => item !== category)
                            : current.filter((item) => item !== category)
                          : [...new Set([...current, category])]
                      )
                    }
                  >
                    {t(categoryLabels[category] ?? category)}
                  </button>
                );
              })}
            </div>
            <div className="action-row">
              <button className="chip" onClick={() => setStep('privacy')}>
                {t('上一步')}
              </button>
              <button className="chip" disabled={busy} onClick={() => void finish([])}>
                {t('跳过')}
              </button>
              <button className="primary-link" disabled={busy} onClick={() => void finish()}>
                {busy ? t('正在保存') : t('完成')}
              </button>
            </div>
          </>
        )}
        {error ? (
          <StatusMessage tone="danger" title={t('操作未完成，请重试。')}>
            {error}
            <button className="chip" onClick={() => void finish()}>
              {t('重试')}
            </button>
          </StatusMessage>
        ) : null}
      </section>
    </main>
  );
}

function App({ mode: _mode }: { mode: Session['mode'] }) {
  const language = useLanguage();
  const preferences = usePreferences();
  const sourceNameVersion = useServerVersion(['plugin.installed']);
  const sourceNameState = useAsync(() => allPages(api.sources), [], undefined, { refreshKey: sourceNameVersion });
  const sourceNames = Object.fromEntries(
    (sourceNameState.data ?? []).map((item) => [
      item.source,
      pluginText(item.manifest ?? {}, String(item.manifest?.name ?? item.source)),
    ]),
  );
  const [categoryNames, setCategoryNames] = useState<Record<string, string>>({});

  useEffect(() => {
    let active = true;
    const load = () =>
      void request<{ items: Array<{ id: string; name: string }> }>('/api/v1/categories')
        .then((value) => {
          if (active) setCategoryNames(Object.fromEntries(value.items.map((item) => [item.id, item.name])));
        })
        .catch(() => {});
    load();
    window.addEventListener('hp:server-update', load);
    return () => {
      active = false;
      window.removeEventListener('hp:server-update', load);
    };
  }, []);

  const [location, setLocation] = useState(currentRoute());
  const shared = useSharedState();
  const theme = useThemeMode();
  const themePreference = useRef<unknown>(preferences.settings.theme);
  themePreference.current = preferences.settings.theme;
  const [mobileOpen, setMobileOpen] = useState(false);
  const [navigationCollapsed, setNavigationCollapsed] = useState(() => {
    try {
      return localStorage.getItem('hp:desktop-navigation-collapsed') === 'true';
    } catch {
      return false;
    }
  });

  const setTheme = (next: 'light' | 'dark') => {
    const previous = theme;
    setThemeMode(next);
    void api
      .updateSettings({ theme: next })
      .then((result) => setThemeMode(resolveThemePreference(result.settings.theme)))
      .catch((error) => {
        setThemeMode(previous);
        window.dispatchEvent(new CustomEvent('hp:sync-error', { detail: errorMessage(error) }));
      });
  };

  const toggleNavigation = () =>
    setNavigationCollapsed((previous) => {
      const next = !previous;
      try {
        localStorage.setItem('hp:desktop-navigation-collapsed', String(next));
      } catch {
        /* ignore */
      }
      return next;
    });

  const [syncError, setSyncError] = useState('');
  const [notice, setNotice] = useState('');

  useEffect(() => {
    const handler = (event: Event) => setSyncError(String((event as CustomEvent).detail ?? t('同步失败')));
    window.addEventListener('hp:sync-error', handler);
    return () => window.removeEventListener('hp:sync-error', handler);
  }, []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && mobileOpen) {
        setMobileOpen(false);
        document.getElementById('navigation-toggle')?.focus();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [mobileOpen]);

  useEffect(() => {
    if (mobileOpen) document.querySelector<HTMLAnchorElement>('#mobile-navigation nav a')?.focus();
  }, [mobileOpen]);

  const currentPath = location.split('?')[0]!.split('#')[0]!;
  const isConsuming = /^\/(?:read|watch)\//.test(currentPath);

  useScrollRestoration(location, shared.incognito, !isConsuming);
  usePageLifecycle(
    useCallback((visible: boolean) => window.dispatchEvent(new CustomEvent('hp:page-visibility', { detail: { visible } })), []),
  );

  useEffect(() => {
    const onPop = () => setLocation(currentRoute());
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);

  useLayoutEffect(() => {
    const root = document.documentElement;
    root.dataset.themeChanging = 'true';
    root.dataset.theme = theme;
    root.dataset.coverBlur = String(shared.coverBlur);
    applySeedTheme(
      preferences.settings.seedColor as number | string | undefined,
      theme,
      isConsuming ? '#080b10' : undefined,
    );
    let secondFrame = 0;
    const firstFrame = requestAnimationFrame(() => {
      secondFrame = requestAnimationFrame(() => {
        delete root.dataset.themeChanging;
      });
    });
    return () => {
      cancelAnimationFrame(firstFrame);
      if (secondFrame) cancelAnimationFrame(secondFrame);
      delete root.dataset.themeChanging;
    };
  }, [theme, shared.coverBlur, preferences.settings.seedColor, isConsuming]);

  useEffect(() => {
    let live = true;
    let generation = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let running = false;
    let pending = false;
    const openedAt = Date.now();
    const refresh = async () => {
      if (running) {
        pending = true;
        return;
      }
      running = true;
      const id = ++generation;
      try {
        const [library, history, downloads, settings] = await Promise.all([
          allPages(api.library),
          allPages(api.history),
          allPages(api.downloads),
          api.settings(),
        ]);
        if (!live || id !== generation) return;
        void setLanguage(String(settings.settings.language ?? '')).catch((error) => setSyncError(errorMessage(error)));
        configureCoverCache(Number(settings.settings.cacheLimitMb ?? 1024));
        setThemeMode(resolveThemePreference(settings.settings.theme));
        sharedStateStore.setState(
          {
            collections: Object.fromEntries(library.map((item) => [workIdentityKey({ source: item.source, id: item.workId }), item])),
            collectionsReady: true,
            downloads: Object.fromEntries(
              downloads.map((item) => {
                const key = downloadKey(item);
                return [key, { key, status: item.status, updatedAt: Date.parse(item.updatedAt ?? '') || 0 }];
              }),
            ),
            progress: Object.fromEntries(
              history.map((item) => [
                item.chapterId
                  ? chapterIdentityKey({ source: item.source, workId: item.workId, chapterId: item.chapterId })
                  : workIdentityKey({ source: item.source, id: item.workId }),
                { position: item.position ?? 0, page: item.page ?? undefined, updatedAt: Date.parse(item.updatedAt ?? '') || 0 },
              ]),
            ),
            incognito: settings.settings.incognito === true,
            notificationsEnabled: settings.settings.notificationsEnabled === true,
            blockedWords: Array.isArray(settings.settings.blockedWords)
              ? settings.settings.blockedWords.filter((x): x is string => typeof x === 'string')
              : [],
            coverBlur: settings.settings.coverBlur === true,
          },
          false,
        );
        setSyncError('');
      } catch (error) {
        if (live) window.dispatchEvent(new CustomEvent('hp:sync-error', { detail: errorMessage(error) }));
      } finally {
        running = false;
        if (pending && live) {
          pending = false;
          schedule();
        }
      }
    };

    const colorScheme = matchMedia('(prefers-color-scheme: dark)');
    const themeChanged = () => {
      if (themePreference.current === 'system') setThemeMode(resolveThemePreference('system'));
    };
    colorScheme.addEventListener('change', themeChanged);
    window.addEventListener('languagechange', themeChanged);

    const changedTypes = new Set<string>();
    const schedule = (event?: Event | { eventType: string }) => {
      const evtType = event && 'eventType' in event ? event.eventType : 'sync.required';
      if (evtType === 'download.telemetry') return;
      changedTypes.add(evtType);
      generation++;
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => {
        const eventTypes = [...changedTypes];
        changedTypes.clear();
        window.dispatchEvent(new CustomEvent('hp:server-update', { detail: { eventTypes } }));
        void refresh();
      }, 140);
    };

    const invalidateBrowse = () => clearBrowseSessions();
    window.addEventListener('hp:invalidate', invalidateBrowse);

    const committed = (event: Event) => {
      const detail = (event as CustomEvent<{ path?: string; keys?: unknown }>).detail;
      const visualSettings = ['theme', 'seedColor', 'language', 'desktopScale'];
      if (
        detail?.path === '/api/v1/settings' &&
        Array.isArray(detail.keys) &&
        detail.keys.length > 0 &&
        detail.keys.every((key) => typeof key === 'string' && visualSettings.includes(key))
      ) {
        return;
      }
      sharedStateStore.setState((value) => value);
      schedule();
    };

    window.addEventListener('hp:committed', committed);
    window.addEventListener('hp:invalidate', schedule);
    void refresh();
    const stop = subscribeEvents((event) => {
      handleBrowseSessionEvent(event);
      if (
        event.eventType === 'subscription.updated' &&
        event.payload?.contentId &&
        event.payload?.notify !== false &&
        Date.parse(event.createdAt ?? '') >= openedAt &&
        sharedStateStore.getSnapshot().notificationsEnabled
      ) {
        setNotice(t('订阅有新内容'));
      }
      schedule(event);
    });

    return () => {
      live = false;
      colorScheme.removeEventListener('change', themeChanged);
      window.removeEventListener('languagechange', themeChanged);
      window.removeEventListener('hp:invalidate', invalidateBrowse);
      if (timer) clearTimeout(timer);
      stop();
      window.removeEventListener('hp:committed', committed);
      window.removeEventListener('hp:invalidate', schedule);
    };
  }, []);

  const rootDestinations = useRef<Record<string, string>>({});
  if (
    currentPath === '/discover' ||
    currentPath === '/' ||
    currentPath.startsWith('/domain/') ||
    (currentPath === '/subscriptions' && new URLSearchParams(window.location.search).get('view') !== 'updates')
  ) {
    rootDestinations.current['/discover'] = location;
  }
  if (currentPath === '/library' || currentPath === '/downloads') {
    rootDestinations.current[currentPath] = location;
  }

  const previousPath = useRef(window.location.pathname);
  useEffect(() => {
    const path = location.split('?')[0]!.split('#')[0]!;
    if (previousPath.current !== path) {
      previousPath.current = path;
      if (!location.includes('#')) document.getElementById('page-content')?.focus({ preventScroll: true });
    }
  }, [location]);

  const navigate = useCallback((to: string, replace = false) => {
    if (to === currentRoute()) return;
    if (!window.dispatchEvent(new CustomEvent('hp:before-navigate', { cancelable: true }))) return;
    if (replace) {
      window.history.replaceState({}, '', to);
    } else {
      recordInternalPush();
      window.history.pushState({ hpFrom: currentRoute() }, '', to);
    }
    setLocation(to);
    setMobileOpen(false);
  }, []);

  const active = window.location.pathname.startsWith('/offline/')
    ? '/downloads'
    : window.location.pathname.startsWith('/search')
      ? '/search'
      : routes.find((route) => window.location.pathname.startsWith(route.path))?.path ?? '/discover';

  const rootNavigation =
    /^\/(?:discover|domain(?:\/[^/?#]+)?|library|downloads|settings)?(?:[?#]|$)/.test(location) &&
    !(window.location.pathname === '/settings' && new URLSearchParams(window.location.search).has('section'));

  return (
    <PreferenceContext.Provider value={preferences.settings}>
      <SourceCatalog.Provider value={sourceNameState}>
        <SourceNames.Provider value={sourceNames}>
          <CategoryNames.Provider value={categoryNames}>
            <div
              data-navigation-collapsed={navigationCollapsed}
              className={'app-shell' + (rootNavigation ? ' has-root-navigation' : '') + (isConsuming ? ' is-consuming' : '')}
            >
              <aside
                onBlur={(event) => {
                  if (mobileOpen && event.relatedTarget instanceof Node && !event.currentTarget.contains(event.relatedTarget)) {
                    setMobileOpen(false);
                  }
                }}
                id="mobile-navigation"
                className={'sidebar ' + (mobileOpen ? 'mobile-open' : '')}
                aria-label={t('主导航')}
              >
                {mobileOpen ? (
                  <button
                    className="chip nav-close"
                    onClick={() => {
                      setMobileOpen(false);
                      document.getElementById('navigation-toggle')?.focus();
                    }}
                  >
                    {t('关闭导航')}
                  </button>
                ) : null}
                <a className="brand" href="/discover" onClick={(event) => navigateClick(event, navigate, '/discover')}>
                  <span className="brand-mark">
                    <img src={appIcon} alt="" />
                  </span>
                  <span className="brand-copy">
                    <strong>HentaiPark</strong>
                    <small>{t('内容管理工作台')}</small>
                  </span>
                </a>
                <nav>
                  {[
                    { label: '主导航', paths: ['/discover', '/library', '/downloads', '/settings'] },
                    { label: '更多', paths: ['/search', '/tavern', '/sites', '/history', '/subscriptions', '/sources'] },
                  ].map((group) => (
                    <section className="navigation-group" key={group.label}>
                      <span className="nav-heading">{t(group.label)}</span>
                      {group.paths.map((path) => {
                        const route = routes.find((item) => item.path === path)!;
                        return <NavLink key={path} route={route} active={active === path} navigate={navigate} />;
                      })}
                    </section>
                  ))}
                </nav>
                <div className="sidebar-footer desktop-preferences">
                  <div className="desktop-theme-options" role="group" aria-label={t('主题')}>
                    {(['light', 'dark'] as const).map((optionTheme) => (
                      <button
                        key={optionTheme}
                        type="button"
                        aria-pressed={theme === optionTheme}
                        onClick={() => setTheme(optionTheme)}
                      >
                        {t(optionTheme === 'light' ? '浅色' : '深色')}
                      </button>
                    ))}
                  </div>
                  <a
                    className="desktop-language"
                    title={t('界面语言')}
                    href="/settings?section=appearance"
                    onClick={(event) => navigateClick(event, navigate, '/settings?section=appearance')}
                  >
                    {languageNames[language]}
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
                      <path d="m9 5 7 7-7 7" />
                    </svg>
                  </a>
                </div>
              </aside>

              <div className="main-column">
                <header className="topbar">
                  <button
                    type="button"
                    className="desktop-navigation-toggle"
                    aria-controls="mobile-navigation"
                    aria-expanded={!navigationCollapsed}
                    aria-label={t(navigationCollapsed ? '展开' : '收起') + ' ' + t('主导航')}
                    title={t(navigationCollapsed ? '展开' : '收起') + ' ' + t('主导航')}
                    onClick={toggleNavigation}
                  >
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
                      <rect x="3" y="4" width="18" height="16" rx="2" />
                      <path d="M9 4v16" />
                      <path d={navigationCollapsed ? 'm13 9 3 3-3 3' : 'm16 9-3 3 3 3'} />
                    </svg>
                  </button>
                  <button
                    id="navigation-toggle"
                    className="mobile-menu"
                    type="button"
                    aria-label={mobileOpen ? t('关闭导航') : t('打开导航')}
                    aria-expanded={mobileOpen}
                    aria-controls="mobile-navigation"
                    onClick={() => setMobileOpen(!mobileOpen)}
                  >
                    <svg width="20" height="20" viewBox="0 0 24 24" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
                      <path d="M4 6h16M4 12h16M4 18h16" />
                    </svg>
                  </button>
                  <LocationTrail location={location} navigate={navigate} />
                  <div className="top-actions">
                    <a
                      className="workspace-search"
                      href="/search"
                      onClick={(event) => navigateClick(event, navigate, '/search')}
                      aria-label={t('全局搜索')}
                    >
                      <NavigationIcon name="/search" />
                      <span>{t('搜索')}</span>
                    </a>
                    <GlobalStatus syncError={syncError} navigate={navigate} />
                    <a
                      className="chip top-preference"
                      href="/settings?section=appearance"
                      onClick={(event) => navigateClick(event, navigate, '/settings?section=appearance')}
                    >
                      {languageNames[language]}
                    </a>
                    <button
                      className="icon-button top-preference"
                      aria-label={t('切换主题')}
                      onClick={() => setTheme(theme === 'light' ? 'dark' : 'light')}
                    >
                      {theme === 'light' ? t('深色') : t('浅色')}
                    </button>
                    <a
                      className="avatar top-preference"
                      aria-label={t('打开设置')}
                      href="/settings"
                      onClick={(event) => navigateClick(event, navigate, '/settings')}
                    >
                      {t('设置')}
                    </a>
                  </div>
                </header>

                <main id="main-content" className="content">
                  <a className="skip-link" href="#page-content">
                    {t('跳到页面内容')}
                  </a>
                  {syncError ? (
                    <StatusMessage tone="danger" title={t('状态同步失败')}>
                      {syncError}
                      <button className="chip" onClick={() => window.dispatchEvent(new Event('hp:invalidate'))}>
                        {t('重试同步')}
                      </button>
                    </StatusMessage>
                  ) : null}
                  {notice && shared.notificationsEnabled ? (
                    <StatusMessage title={notice}>
                      <a href="/subscriptions?view=updates" onClick={(event) => navigateClick(event, navigate, '/subscriptions?view=updates')}>
                        {t('查看订阅更新')}
                      </a>
                      <button className="chip" onClick={() => setNotice('')}>
                        {t('关闭通知')}
                      </button>
                    </StatusMessage>
                  ) : null}
                  <div id="page-content" tabIndex={-1}>
                    <DesktopBack location={location} navigate={navigate} />
                    <RouterSwitch location={location} navigate={navigate} />
                    <DesktopScrollTop />
                  </div>
                </main>
              </div>
              {rootNavigation ? (
                <MobileNav
                  destinations={rootDestinations.current}
                  active={active === '/subscriptions' ? '/discover' : active}
                  navigate={navigate}
                />
              ) : null}
            </div>
          </CategoryNames.Provider>
        </SourceNames.Provider>
      </SourceCatalog.Provider>
    </PreferenceContext.Provider>
  );
}

function LocationTrail({ location, navigate }: { location: string; navigate: (url: string) => void }) {
  const path = location.split('?')[0]!.split('#')[0]!;
  const parts = path.split('/');
  const nested = ['source', 'work', 'read', 'watch', 'channel', 'post', 'album'].includes(parts[1] ?? '');
  const source = nested ? decodeURIComponent(parts[2] ?? '') : '';
  const state = useAsync(() => (source ? api.source(source) : Promise.resolve(undefined)), [source]);
  const category = parts[1] === 'domain' ? decodeURIComponent(parts[2] ?? '') : String(state.data?.manifest?.category ?? '');
  const settingsSection = path === '/settings' ? new URLSearchParams(location.split('?')[1] ?? '').get('section') : null;
  const settingsTitle =
    settingsSection && Object.hasOwn(settingsSectionTitles, settingsSection)
      ? settingsSectionTitles[settingsSection as keyof typeof settingsSectionTitles]
      : undefined;
  const label =
    settingsTitle ??
    routes.find((route) => route.path === path)?.label ??
    (
      {
        domain: categoryLabels[category] ?? category,
        source: String(state.data?.manifest?.name ?? source),
        work: '作品详情',
        read: '阅读',
        watch: '播放',
        rankings: '榜单',
        channel: '频道',
        post: '帖子',
        album: '相册',
        tavern: '酒馆',
        offline: '离线内容',
        sites: '全部站点',
        history: '历史',
        'reverse-search': '图片反搜',
        logs: '诊断日志',
        licenses: '开源许可',
      } as Record<string, string>
    )[parts[1] ?? ''] ??
    '页面';
  const link = (href: string, text: string) => (
    <a href={href} onClick={(event) => navigateClick(event, navigate, href)}>
      {t(text)}
    </a>
  );
  return (
    <nav className="breadcrumbs" aria-label={t('当前位置')}>
      {path !== '/discover' && path !== '/' ? (
        <span className="breadcrumb-parent">
          {link('/discover', '发现')}
          <span aria-hidden="true">/</span>
        </span>
      ) : null}
      {settingsTitle ? (
        <span className="breadcrumb-parent">
          {link('/settings', '设置')}
          <span aria-hidden="true">/</span>
        </span>
      ) : null}
      {nested && category ? (
        <span className="breadcrumb-parent">
          {link(domainHref(category), categoryLabels[category] ?? category)}
          <span aria-hidden="true">/</span>
        </span>
      ) : null}
      {source && parts[1] !== 'source' ? (
        <span className="breadcrumb-parent">
          {link('/source/' + encodeURIComponent(source), String(state.data?.manifest?.name ?? source))}
          <span aria-hidden="true">/</span>
        </span>
      ) : null}
      <strong aria-current="page">{t(path === '/' ? '发现' : label)}</strong>
    </nav>
  );
}

function GlobalStatus({ syncError, navigate }: { syncError: string; navigate: (to: string) => void }) {
  const shared = useSharedState();
  const [online, setOnline] = useState(navigator.onLine);
  const updates = useAsync(() => api.subscriptions({ limit: 1 }), []);
  const unread = Number(updates.data?.unreadCount ?? 0);
  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    window.addEventListener('online', update);
    window.addEventListener('offline', update);
    return () => {
      window.removeEventListener('online', update);
      window.removeEventListener('offline', update);
    };
  }, []);
  const pending = Object.values(shared.downloads).filter((task) => !['completed', 'cancelled'].includes(task.status)).length;
  return (
    <>
      {unread > 0 ? (
        <a
          className="chip"
          href="/subscriptions?view=updates"
          onClick={(event) => navigateClick(event, navigate, '/subscriptions?view=updates')}
        >
          {t('更新')} {unread}
        </a>
      ) : null}
      {pending > 0 ? (
        <a className="chip" href="/downloads" onClick={(event) => navigateClick(event, navigate, '/downloads')}>
          {t('下载')} {pending}
        </a>
      ) : null}
      {!online || syncError ? (
        <span className="instance-status" role="status">
          {!online ? t('浏览器离线') : t('同步异常')}
        </span>
      ) : null}
    </>
  );
}

function NavLink({ route, active, navigate }: { route: Route; active: boolean; navigate: (to: string) => void }) {
  const href = route.href ?? route.path;
  return (
    <a
      href={href}
      className={'nav-link ' + (active ? 'active' : '')}
      title={t(route.label)}
      aria-current={active ? 'page' : undefined}
      onClick={(event) => navigateClick(event, navigate, href)}
    >
      <span aria-hidden="true" className="nav-icon">
        <NavigationIcon name={route.path === '/tavern' ? '/library' : route.path} />
      </span>
      <span className="nav-label">{t(route.label)}</span>
    </a>
  );
}

function MobileNav({
  active,
  navigate,
  destinations,
}: {
  active: string;
  navigate: (to: string) => void;
  destinations: Record<string, string>;
}) {
  return (
    <nav className="mobile-nav" aria-label={t('移动端导航')}>
      {[
        { path: '/discover', label: '发现' },
        { path: '/library', label: '收藏' },
        { path: '/downloads', label: '下载' },
        { path: '/settings', label: '我的' },
      ].map((route) => (
        <NavLink
          key={route.path}
          route={{ ...route, href: destinations[route.path] ?? route.path }}
          active={active === route.path}
          navigate={navigate}
        />
      ))}
    </nav>
  );
}

function RouterSwitch({ location, navigate }: { location: string; navigate: (to: string) => void }) {
  const [path, search] = location.split('#')[0]!.split('?');
  const params = new URLSearchParams(search?.split('#')[0]);
  const query = params.get('q') ?? '';

  const isDiscoverRoot = path === '/' || path === '/discover';
  const isLibraryRoot = path === '/library';
  const isDownloadsRoot = path === '/downloads';
  const isSettingsRoot = path === '/settings';

  const [mountedRoots, setMountedRoots] = useState(() => ({
    discover: isDiscoverRoot,
    library: isLibraryRoot,
    downloads: isDownloadsRoot,
    settings: isSettingsRoot,
  }));

  useEffect(() => {
    setMountedRoots((prev) => ({
      discover: prev.discover || isDiscoverRoot,
      library: prev.library || isLibraryRoot,
      downloads: prev.downloads || isDownloadsRoot,
      settings: prev.settings || isSettingsRoot,
    }));
  }, [isDiscoverRoot, isLibraryRoot, isDownloadsRoot, isSettingsRoot]);

  const isAnyRoot = isDiscoverRoot || isLibraryRoot || isDownloadsRoot || isSettingsRoot;

  return (
    <>
      {mountedRoots.discover ? (
        <KeepAliveView active={isDiscoverRoot}>
          <DiscoverPage navigate={navigate} />
        </KeepAliveView>
      ) : null}
      {mountedRoots.library ? (
        <KeepAliveView active={isLibraryRoot}>
          <LibraryPage
            navigate={navigate}
            view={params.get('view') === 'recent' ? 'recent' : 'favorites'}
            category={params.get('category') ?? ''}
          />
        </KeepAliveView>
      ) : null}
      {mountedRoots.downloads ? (
        <KeepAliveView active={isDownloadsRoot}>
          <DownloadsPage navigate={navigate} />
        </KeepAliveView>
      ) : null}
      {mountedRoots.settings ? (
        <KeepAliveView active={isSettingsRoot}>
          <SettingsPage navigate={navigate} />
        </KeepAliveView>
      ) : null}

      {!isAnyRoot ? (
        <Suspense fallback={<StatusMessage title={t('正在加载')} />}>
          {path === '/sites' ? (
            <DiscoverPage sitesOnly navigate={navigate} />
          ) : path === '/history' ? (
            <LibraryPage view={params.get('mode') === 'continue' ? 'continue' : 'history'} category="" navigate={navigate} />
          ) : path.startsWith('/domain/') ? (
            <DiscoverPage key={path} category={decodeURIComponent(path.split('/')[2] ?? '')} navigate={navigate} />
          ) : path === '/rankings' ? (
            <RankingsPage search={search ?? ''} navigate={navigate} />
          ) : path === '/reverse-search' || (path === '/search' && params.get('mode') === 'reverse') ? (
            <ReverseSearch navigate={navigate} />
          ) : path === '/search' ? (
            <SearchPage
              selection={JSON.stringify({
                sources: params.getAll('sources'),
                mediaKind: params.get('mediaKind') ?? undefined,
                category: params.get('category') ?? undefined,
              })}
              initialKeywords={params.get('keywords') ?? ''}
              initialFilters={params.get('filters') ?? ''}
              initialQuery={query}
              initialScope={params.get('scope') ?? 'all'}
              initialSource={params.get('source') ?? ''}
              initialCursor={params.get('cursor') ?? ''}
              initialLimit={Number(params.get('limit') ?? '24')}
              initialView={
                params.get('view') === 'grouped'
                  ? 'grouped'
                  : params.get('view') === 'grid'
                    ? 'grid'
                    : params.get('view') === 'list'
                      ? 'list'
                      : 'grouped'
              }
              navigate={navigate}
            />
          ) : path.startsWith('/album/') ? (
            <AlbumPage key={path + '?' + (search ?? '')} source={decodeURIComponent(path.split('/')[2] ?? '')} search={search ?? ''} navigate={navigate} />
          ) : path === '/sources' ? (
            <SourcesPage navigate={navigate} />
          ) : path.startsWith('/source/') ? (
            <SourcePage
              key={decodeURIComponent(path.split('/')[2] ?? '')}
              source={decodeURIComponent(path.split('/')[2] ?? '')}
              navigate={navigate}
              renderEmbeddedReader={(parts, active) => (
                <ReaderPage key={JSON.stringify(parts)} active={active} embedded mode="watch" parts={parts} navigate={navigate} />
              )}
            />
          ) : path.startsWith('/work/') ? (
            <WorkPage
              key={path}
              parts={path.split('/').slice(2)}
              directory={params.get('directory') ?? undefined}
              navigate={navigate}
              renderArticleReader={(parts) => <ReaderPage key={parts.join(':')} mode="read" parts={parts} navigate={navigate} embedded />}
            />
          ) : path.startsWith('/read/') || path.startsWith('/watch/') ? (
            <ReaderPage
              key={path}
              mode={path.startsWith('/watch/') ? 'watch' : 'read'}
              parts={path.split('/').slice(2)}
              navigate={navigate}
            />
          ) : path === '/subscriptions' ? (
            <SubscriptionsPage navigate={navigate} />
          ) : path.startsWith('/channel/') ? (
            <ChannelPage
              source={decodeURIComponent(path.split('/')[2] ?? '')}
              target={params.get('target') ?? undefined}
              kind={params.get('kind') ?? undefined}
              navigate={navigate}
            />
          ) : path.startsWith('/post/') ? (
            <PostPage source={decodeURIComponent(path.split('/')[2] ?? '')} workId={decodeURIComponent(path.split('/')[3] ?? '')} />
          ) : path === '/tavern' ? (
            <TavernLibraryPage />
          ) : path.startsWith('/offline/') ? (
            <OfflinePage taskId={decodeURIComponent(path.slice('/offline/'.length))} />
          ) : path === '/logs' ? (
            <LogsPage navigate={navigate} />
          ) : path === '/licenses' ? (
            <LicensesPage navigate={navigate} />
          ) : (
            <>
              <PageHeader title={t('页面不存在')} description={t('请检查链接，或返回发现继续浏览。')} />
              <a href="/discover" onClick={(event) => navigateClick(event, navigate, '/discover')}>
                {t('返回发现')}
              </a>
            </>
          )}
        </Suspense>
      ) : null}
    </>
  );
}

if (
  typeof navigator !== 'undefined' &&
  'serviceWorker' in navigator &&
  !((import.meta as ImportMeta & { env?: { DEV?: boolean } }).env?.DEV)
) {
  window.addEventListener('load', () => {
    void navigator.serviceWorker.register('/sw.js').catch(() => {});
  });
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ConfirmProvider translate={t}>
      <SessionGate />
      <ToastHost />
    </ConfirmProvider>
  </StrictMode>,
);
