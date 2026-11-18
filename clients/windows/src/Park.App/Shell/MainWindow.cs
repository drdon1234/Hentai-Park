using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Park.App.Controls;
using Park.App.Interop;
using Park.App.Services;
using Park.App.Theme;
using Park.App.Views;
using Park.Core.Configuration;
using Park.Core.Localization;
using Park.Core.Models;
using Windows.System;

namespace Park.App.Shell;

public sealed class MainWindow : Window
{
    private readonly WorkItem? _standaloneWork;
    private readonly Stack<Func<FrameworkElement>> _backStack = new();
    private Func<FrameworkElement>? _currentPageBuilder;

    private Grid _rootGrid = null!;
    private Grid _titleBarDragRegion = null!;
    private Button _backButton = null!;
    private AutoSuggestBox _globalSearchBox = null!;
    private Border _incognitoPill = null!;
    private NavigationView _navView = null!;
    private TabView _workspaceTabs = null!;
    private Border _primaryStageHost = null!;
    private Grid _onboardingOverlay = null!;
    private Grid _lockOverlay = null!;
    private Grid _shutdownOverlay = null!;

    private string _activeSection = "discover";
    private string? _selectedDomainFilter;
    private DateTimeOffset? _deactivatedSince;
    private bool _locked;
    private bool _allowClose;

    public MainWindow(WorkItem? standaloneWork = null)
    {
        _standaloneWork = standaloneWork;
        Title = "HentaiPark";

        if (MicaController.IsSupported())
        {
            SystemBackdrop = new MicaBackdrop { Kind = MicaKind.BaseAlt };
        }
        else if (DesktopAcrylicController.IsSupported())
        {
            SystemBackdrop = new DesktopAcrylicBackdrop();
        }

        var hwnd = NativeWindowHelper.GetHwnd(this);
        if (AppHost.Instance.Sources.HostWindowHandle == 0)
        {
            AppHost.Instance.Sources.HostWindowHandle = hwnd;
        }

        NativeWindowHelper.ResizeWindow(this, standaloneWork is null ? 1440 : 1180, standaloneWork is null ? 900 : 840);

        _locked = AppSettings.Instance.AppLock;
        BuildShellLayout();
        ApplySecurityAndTheme();

        AppSettings.Instance.Changed += OnSettingsChanged;
        L.LocaleChanged += RebuildShellOnLocaleOrThemeChange;
        Activated += OnWindowActivated;

        var appWindow = NativeWindowHelper.GetAppWindow(this);
        appWindow.Closing += OnAppWindowClosing;
    }

    private WorkNavigationCallbacks CreateCallbacks() => new(
        OpenWork: (work, backgroundTab) =>
        {
            if (backgroundTab)
            {
                OpenWorkInTab(work, selectImmediately: false);
            }
            else
            {
                NavigatePrimary(() => WorkDetailAndReadersViews.CreateWorkDetailView(work, this, CreateCallbacks()));
            }
        },
        OpenInNewWindow: work =>
        {
            var win = new MainWindow(standaloneWork: work);
            win.Activate();
        },
        SearchTagInSource: (sourceKey, keyword) =>
        {
            NavigatePrimary(() => DiscoverAndSearchViews.CreateSourceBrowseView(sourceKey, keyword, CreateCallbacks()));
        });

    private void BuildShellLayout()
    {
        var c = ParkTheme.Current;
        _rootGrid = new Grid
        {
            Background = ParkTheme.Brush(c.Surface),
            FlowDirection = L.IsRtl ? FlowDirection.RightToLeft : FlowDirection.LeftToRight,
        };
        _rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(46) });
        _rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        // Global Ctrl+K & Alt+Left keyboard accelerators
        var ctrlK = new KeyboardAccelerator { Key = VirtualKey.K, Modifiers = VirtualKeyModifiers.Control };
        ctrlK.Invoked += (_, e) =>
        {
            e.Handled = true;
            _globalSearchBox.Focus(FocusState.Programmatic);
        };
        _rootGrid.KeyboardAccelerators.Add(ctrlK);

        var altLeft = new KeyboardAccelerator { Key = VirtualKey.Left, Modifiers = VirtualKeyModifiers.Menu };
        altLeft.Invoked += (_, e) =>
        {
            if (_backStack.Count > 0)
            {
                e.Handled = true;
                NavigateBack();
            }
        };
        _rootGrid.KeyboardAccelerators.Add(altLeft);

        // 1. Custom 46epx Immersive TitleBar
        var titleBar = BuildTitleBar(c);
        Grid.SetRow(titleBar, 0);
        _rootGrid.Children.Add(titleBar);

        // 2. Adaptive Workspace Body
        if (_standaloneWork is not null)
        {
            _primaryStageHost = new Border
            {
                Background = ParkTheme.Brush(c.Workspace),
                Padding = new Thickness(0),
            };
            Grid.SetRow(_primaryStageHost, 1);
            _rootGrid.Children.Add(_primaryStageHost);
            Content = _rootGrid;
            NativeWindowHelper.ConfigureCustomTitleBar(this, _titleBarDragRegion, c.IsDark);
            NavigatePrimary(() => WorkDetailAndReadersViews.CreateWorkDetailView(_standaloneWork, this, CreateCallbacks()), recordHistory: false);
            return;
        }

        _navView = BuildNavigationView(c);
        Grid.SetRow(_navView, 1);
        _rootGrid.Children.Add(_navView);

        // Overlays: Onboarding (18+ gate), AppLock (Windows Hello), Graceful Shutdown
        _onboardingOverlay = BuildOnboardingOverlay(c);
        Grid.SetRowSpan(_onboardingOverlay, 2);
        _rootGrid.Children.Add(_onboardingOverlay);

        _lockOverlay = BuildLockOverlay(c);
        Grid.SetRowSpan(_lockOverlay, 2);
        _rootGrid.Children.Add(_lockOverlay);

        _shutdownOverlay = BuildShutdownOverlay(c);
        Grid.SetRowSpan(_shutdownOverlay, 2);
        _rootGrid.Children.Add(_shutdownOverlay);

        Content = _rootGrid;
        NativeWindowHelper.ConfigureCustomTitleBar(this, _titleBarDragRegion, c.IsDark);

        RefreshOverlaysVisibility();
        SelectPrimarySection("discover", domainFilter: null);
    }

    private Grid BuildTitleBar(ParkColorScheme c)
    {
        var bar = new Grid
        {
            Height = 46,
            Padding = new Thickness(10, 0, 148, 0),
            ColumnSpacing = 10,
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0)),
        };
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        _backButton = new Button
        {
            Content = new FontIcon { Glyph = "\uE72B", FontSize = 14 },
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0)),
            BorderThickness = new Thickness(0),
            Width = 34,
            Height = 32,
            CornerRadius = new CornerRadius(6),
            IsEnabled = _backStack.Count > 0,
            Opacity = _backStack.Count > 0 ? 1.0 : 0.4,
        };
        ToolTipService.SetToolTip(_backButton, L.Tr("返回"));
        _backButton.Click += (_, _) => NavigateBack();
        Grid.SetColumn(_backButton, 0);
        bar.Children.Add(_backButton);

        var brandRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        brandRow.Children.Add(new Border
        {
            Width = 22,
            Height = 22,
            CornerRadius = new CornerRadius(6),
            Background = ParkTheme.Brush(c.Primary),
            Child = new TextBlock
            {
                Text = "P",
                FontFamily = ParkTheme.SerifFont,
                FontSize = 13,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = ParkTheme.Brush(c.OnPrimary),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        });
        brandRow.Children.Add(new TextBlock
        {
            Text = "HentaiPark",
            FontFamily = ParkTheme.SerifFont,
            FontSize = 16,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = ParkTheme.Brush(c.OnSurface),
            VerticalAlignment = VerticalAlignment.Center,
        });
        Grid.SetColumn(brandRow, 1);
        bar.Children.Add(brandRow);

        _titleBarDragRegion = new Grid { Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0)) };
        Grid.SetColumn(_titleBarDragRegion, 2);
        bar.Children.Add(_titleBarDragRegion);

        var centerTools = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };

        _globalSearchBox = new AutoSuggestBox
        {
            Width = 400,
            PlaceholderText = L.Tr("全局搜索、粘贴链接或输入番号 (Ctrl+K)"),
            QueryIcon = new SymbolIcon(Symbol.Find),
            VerticalAlignment = VerticalAlignment.Center,
        };
        _globalSearchBox.QuerySubmitted += (_, args) =>
        {
            var q = args.QueryText?.Trim() ?? string.Empty;
            if (string.IsNullOrEmpty(q)) return;

            var direct = AppHost.Instance.Sources.TryResolveDirectInput(q);
            if (direct is var (srcRec, workId))
            {
                var stub = new WorkItem(srcRec.Key, workId, workId, string.Empty, string.Empty, false, null, null, null, null, null, string.Empty, srcRec.Manifest.Category, string.Empty, null, string.Empty, string.Empty, srcRec.Manifest.Type, null, [], [], null, []);
                NavigatePrimary(() => WorkDetailAndReadersViews.CreateWorkDetailView(stub, this, CreateCallbacks()));
                return;
            }

            NavigatePrimary(() => DiscoverAndSearchViews.CreateAggregateSearchView(q, CreateCallbacks()));
        };
        centerTools.Children.Add(_globalSearchBox);

        // Incognito status capsule in titlebar (non-layout-shifting!)
        _incognitoPill = new Border
        {
            Background = ParkTheme.Brush(c.SecondaryContainer),
            CornerRadius = new CornerRadius(14),
            Padding = new Thickness(10, 4, 10, 4),
            Visibility = AppSettings.Instance.Incognito ? Visibility.Visible : Visibility.Collapsed,
            Child = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 6,
                Children =
                {
                    new FontIcon { Glyph = "\uED1A", FontSize = 13, Foreground = ParkTheme.Brush(c.OnSecondaryContainer) },
                    new TextBlock
                    {
                        Text = L.Tr("无痕浏览"),
                        FontSize = 12,
                        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                        Foreground = ParkTheme.Brush(c.OnSecondaryContainer),
                    },
                },
            },
        };
        _incognitoPill.PointerPressed += (_, _) => AppSettings.Instance.Incognito = false;
        centerTools.Children.Add(_incognitoPill);

        Grid.SetColumn(centerTools, 3);
        bar.Children.Add(centerTools);

        return bar;
    }

    private NavigationView BuildNavigationView(ParkColorScheme c)
    {
        var nav = new NavigationView
        {
            IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed,
            IsSettingsVisible = false,
            PaneDisplayMode = NavigationViewPaneDisplayMode.Auto,
            CompactModeThresholdWidth = 640,
            ExpandedModeThresholdWidth = 840,
            OpenPaneLength = 228,
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0)),
        };

        var discoverItem = new NavigationViewItem
        {
            Content = L.Tr("发现"),
            Tag = "discover",
            Icon = new FontIcon { Glyph = "\uE805" },
            SelectsOnInvoked = true,
        };

        foreach (var domainKey in AppSettings.Instance.DomainOrder)
        {
            discoverItem.MenuItems.Add(new NavigationViewItem
            {
                Content = L.DomainDisplayName(domainKey),
                Tag = $"domain:{domainKey}",
                Icon = new FontIcon { Glyph = "\uE8B7", FontSize = 13 },
            });
        }

        nav.MenuItems.Add(discoverItem);
        nav.MenuItems.Add(new NavigationViewItem
        {
            Content = L.Tr("收藏"),
            Tag = "library",
            Icon = new FontIcon { Glyph = "\uE8F1" },
        });
        nav.MenuItems.Add(new NavigationViewItem
        {
            Content = L.Tr("下载"),
            Tag = "downloads",
            Icon = new FontIcon { Glyph = "\uE896" },
        });
        nav.MenuItems.Add(new NavigationViewItem
        {
            Content = L.Tr("订阅"),
            Tag = "subscriptions",
            Icon = new FontIcon { Glyph = "\uE787" },
        });

        nav.FooterMenuItems.Add(new NavigationViewItem
        {
            Content = L.Tr("站点管理"),
            Tag = "sources",
            Icon = new FontIcon { Glyph = "\uE774" },
        });
        nav.FooterMenuItems.Add(new NavigationViewItem
        {
            Content = L.Tr("设置"),
            Tag = "settings",
            Icon = new FontIcon { Glyph = "\uE713" },
        });

        nav.ItemInvoked += (_, args) =>
        {
            var tag = (args.InvokedItemContainer as NavigationViewItem)?.Tag as string ?? "discover";
            if (tag.StartsWith("domain:", StringComparison.Ordinal))
            {
                SelectPrimarySection("discover", tag[7..]);
            }
            else
            {
                SelectPrimarySection(tag, null);
            }
        };

        // Multi-tab workspace inside NavigationView content
        _workspaceTabs = new TabView
        {
            IsAddTabButtonVisible = false,
            TabWidthMode = TabViewWidthMode.Equal,
            VerticalAlignment = VerticalAlignment.Stretch,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Background = ParkTheme.Brush(c.Workspace),
        };
        _workspaceTabs.TabCloseRequested += (_, e) =>
        {
            if (_workspaceTabs.TabItems.IndexOf(e.Tab) > 0)
            {
                _workspaceTabs.TabItems.Remove(e.Tab);
            }
        };

        _primaryStageHost = new Border
        {
            Background = ParkTheme.Brush(c.Workspace),
            CornerRadius = new CornerRadius(12, 0, 0, 0),
        };

        var mainTab = new TabViewItem
        {
            Header = L.Tr("工作区"),
            IconSource = new FontIconSource { Glyph = "\uE80F" },
            IsClosable = false,
            Content = _primaryStageHost,
        };
        _workspaceTabs.TabItems.Add(mainTab);
        _workspaceTabs.SelectedIndex = 0;

        nav.Content = _workspaceTabs;
        return nav;
    }

    public void OpenWorkInTab(WorkItem work, bool selectImmediately)
    {
        var tabContent = WorkDetailAndReadersViews.CreateWorkDetailView(work, this, CreateCallbacks());
        var tab = new TabViewItem
        {
            Header = work.Title.Length > 24 ? work.Title[..24] + "…" : work.Title,
            IconSource = new FontIconSource { Glyph = ParkKit.MediaSemanticGlyph(work.MediaKind) },
            IsClosable = true,
            Content = new Border
            {
                Background = ParkTheme.Brush(ParkTheme.Current.Workspace),
                Child = tabContent,
            },
        };
        _workspaceTabs.TabItems.Add(tab);
        if (selectImmediately)
            _workspaceTabs.SelectedItem = tab;
    }

    public void NavigatePrimary(Func<FrameworkElement> pageBuilder, bool recordHistory = true)
    {
        if (recordHistory && _currentPageBuilder is not null)
        {
            _backStack.Push(_currentPageBuilder);
        }
        _currentPageBuilder = pageBuilder;
        _primaryStageHost.Child = pageBuilder();
        if (_workspaceTabs is not null)
            _workspaceTabs.SelectedIndex = 0;
        UpdateBackButtonState();
    }

    private void NavigateBack()
    {
        if (_backStack.Count == 0) return;
        var prev = _backStack.Pop();
        _currentPageBuilder = prev;
        _primaryStageHost.Child = prev();
        UpdateBackButtonState();
    }

    private void UpdateBackButtonState()
    {
        if (_backButton is null) return;
        _backButton.IsEnabled = _backStack.Count > 0;
        _backButton.Opacity = _backStack.Count > 0 ? 1.0 : 0.4;
    }

    private void SelectPrimarySection(string section, string? domainFilter)
    {
        _activeSection = section;
        _selectedDomainFilter = domainFilter;
        _backStack.Clear();

        Func<FrameworkElement> builder = section switch
        {
            "discover" => () => DiscoverAndSearchViews.CreateDiscoverView(
                domainFilter,
                CreateCallbacks(),
                onSelectDomain: d => SelectPrimarySection("discover", d),
                onOpenSource: src => NavigatePrimary(() => DiscoverAndSearchViews.CreateSourceBrowseView(src.Key, null, CreateCallbacks())),
                onOpenRankings: () => NavigatePrimary(() => DiscoverAndSearchViews.CreateRankingsView(CreateCallbacks())),
                onOpenReverseSearch: () => NavigatePrimary(() => DiscoverAndSearchViews.CreateReverseSearchView(CreateCallbacks()))),
            "library" => () => LibraryAndSettingsViews.CreateLibraryView(CreateCallbacks()),
            "downloads" => () => LibraryAndSettingsViews.CreateDownloadsView(CreateCallbacks()),
            "subscriptions" => () => LibraryAndSettingsViews.CreateSubscriptionsView(CreateCallbacks()),
            "sources" => () => LibraryAndSettingsViews.CreateSourceManageView(
                src => NavigatePrimary(() => DiscoverAndSearchViews.CreateSourceBrowseView(src.Key, null, CreateCallbacks()))),
            "settings" => () => LibraryAndSettingsViews.CreateSettingsView(this),
            _ => () => DiscoverAndSearchViews.CreateDiscoverView(null, CreateCallbacks(), _ => { }, _ => { }, () => { }, () => { }),
        };

        NavigatePrimary(builder, recordHistory: false);
    }

    private Grid BuildOnboardingOverlay(ParkColorScheme c)
    {
        var overlay = new Grid
        {
            Background = ParkTheme.Brush(c.Surface),
            Visibility = Visibility.Collapsed,
        };

        var card = new StackPanel
        {
            MaxWidth = 520,
            Spacing = 20,
            Padding = new Thickness(36),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Background = ParkTheme.Brush(c.Card),
            CornerRadius = new CornerRadius(20),
            BorderBrush = ParkTheme.Brush(c.OutlineVariant),
            BorderThickness = new Thickness(1),
        };

        // Capsule step progress indicator
        var steps = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, HorizontalAlignment = HorizontalAlignment.Center };
        steps.Children.Add(new Border { Width = 28, Height = 6, CornerRadius = new CornerRadius(3), Background = ParkTheme.Brush(c.Primary) });
        steps.Children.Add(new Border { Width = 10, Height = 6, CornerRadius = new CornerRadius(3), Background = ParkTheme.Brush(c.ContainerHighest) });
        card.Children.Add(steps);

        card.Children.Add(new Border
        {
            Width = 56,
            Height = 56,
            CornerRadius = new CornerRadius(28),
            Background = ParkTheme.Brush(c.SecondaryContainer),
            HorizontalAlignment = HorizontalAlignment.Center,
            Child = new TextBlock
            {
                Text = "18+",
                FontFamily = ParkTheme.SansFont,
                FontSize = 18,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = ParkTheme.Brush(c.OnSecondaryContainer),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        });

        card.Children.Add(new TextBlock
        {
            Text = "HentaiPark",
            FontFamily = ParkTheme.SerifFont,
            FontSize = 28,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = ParkTheme.Brush(c.OnSurface),
            HorizontalAlignment = HorizontalAlignment.Center,
        });

        card.Children.Add(new TextBlock
        {
            Text = L.Tr("本应用仅面向已满 18 周岁的成年人，请在当地法律允许范围内使用。"),
            FontFamily = ParkTheme.SansFont,
            FontSize = 14,
            Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        });

        var confirmBtn = ParkKit.PrimaryButton(L.Tr("我已满 18 周岁并进入"), "\uE73E", () =>
        {
            AppSettings.Instance.AdultConfirmed = true;
            AppSettings.Instance.Onboarded = true;
            RefreshOverlaysVisibility();
        });
        confirmBtn.HorizontalAlignment = HorizontalAlignment.Stretch;
        card.Children.Add(confirmBtn);

        overlay.Children.Add(card);
        return overlay;
    }

    private Grid BuildLockOverlay(ParkColorScheme c)
    {
        var overlay = new Grid
        {
            Background = ParkTheme.Brush(c.Surface),
            Visibility = Visibility.Collapsed,
        };

        var panel = new StackPanel
        {
            Spacing = 16,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        panel.Children.Add(new FontIcon
        {
            Glyph = "\uE72E",
            FontSize = 42,
            Foreground = ParkTheme.Brush(c.Primary),
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        panel.Children.Add(new TextBlock
        {
            Text = L.Tr("HentaiPark 已锁定"),
            FontFamily = ParkTheme.SerifFont,
            FontSize = 24,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = ParkTheme.Brush(c.OnSurface),
            HorizontalAlignment = HorizontalAlignment.Center,
        });

        var unlockBtn = ParkKit.PrimaryButton(L.Tr("Windows Hello 解锁"), "\uE928", async () =>
        {
            if (await NativeWindowHelper.AuthenticateWindowsHelloAsync(L.Tr("验证身份以解锁 HentaiPark")))
            {
                _locked = false;
                _deactivatedSince = null;
                RefreshOverlaysVisibility();
                ApplySecurityAndTheme();
            }
        });
        unlockBtn.HorizontalAlignment = HorizontalAlignment.Center;
        panel.Children.Add(unlockBtn);

        overlay.Children.Add(panel);
        return overlay;
    }

    private static Grid BuildShutdownOverlay(ParkColorScheme c)
    {
        var overlay = new Grid
        {
            Background = ParkTheme.Brush(c.Surface),
            Opacity = 0.94,
            Visibility = Visibility.Collapsed,
        };
        var sp = new StackPanel
        {
            Spacing = 14,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        sp.Children.Add(new ProgressRing { IsActive = true, Width = 36, Height = 36 });
        sp.Children.Add(new TextBlock
        {
            Text = L.Tr("正在安全保存数据并关闭运行时…"),
            FontFamily = ParkTheme.SansFont,
            FontSize = 14,
            Foreground = ParkTheme.Brush(c.OnSurface),
        });
        overlay.Children.Add(sp);
        return overlay;
    }

    private void RefreshOverlaysVisibility()
    {
        if (_onboardingOverlay is null) return;
        var needsOnboarding = !AppSettings.Instance.AdultConfirmed || !AppSettings.Instance.Onboarded;
        _onboardingOverlay.Visibility = needsOnboarding ? Visibility.Visible : Visibility.Collapsed;
        _lockOverlay.Visibility = (!needsOnboarding && _locked) ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ApplySecurityAndTheme()
    {
        var secure = AppSettings.Instance.SecureScreen || AppSettings.Instance.AppLock || _locked;
        NativeWindowHelper.ApplySecureScreen(this, secure);
        if (_rootGrid is not null)
        {
            _rootGrid.RequestedTheme = ParkTheme.Current.IsDark ? ElementTheme.Dark : ElementTheme.Light;
        }
    }

    private void OnSettingsChanged(SettingsDomain domain, string key)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_incognitoPill is not null)
                _incognitoPill.Visibility = AppSettings.Instance.Incognito ? Visibility.Visible : Visibility.Collapsed;

            if (key is "secureScreen" or "appLock")
                ApplySecurityAndTheme();

            if (key is "themeMode" or "seedColor" or "useSystemAccent")
                RebuildShellOnLocaleOrThemeChange();
        });
    }

    private void RebuildShellOnLocaleOrThemeChange()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            var savedSection = _activeSection;
            var savedDomain = _selectedDomainFilter;
            BuildShellLayout();
            ApplySecurityAndTheme();
            if (_standaloneWork is null)
                SelectPrimarySection(savedSection, savedDomain);
        });
    }

    private void OnWindowActivated(object sender, WindowActivatedEventArgs args)
    {
        if (!AppSettings.Instance.AppLock) return;
        if (args.WindowActivationState == WindowActivationState.Deactivated)
        {
            _deactivatedSince ??= DateTimeOffset.UtcNow;
        }
        else if (_deactivatedSince is { } since)
        {
            var elapsed = (DateTimeOffset.UtcNow - since).TotalSeconds;
            _deactivatedSince = null;
            if (elapsed >= AppSettings.Instance.AppLockAfter)
            {
                _locked = true;
                RefreshOverlaysVisibility();
                ApplySecurityAndTheme();
            }
        }
    }

    private async void OnAppWindowClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (_standaloneWork is not null || _allowClose) return;

        args.Cancel = true;
        if (_shutdownOverlay is not null)
            _shutdownOverlay.Visibility = Visibility.Visible;

        var ok = await AppHost.Instance.Shutdown.ExitAsync();
        if (ok)
        {
            _allowClose = true;
            Close();
        }
        else if (_shutdownOverlay is not null)
        {
            _shutdownOverlay.Visibility = Visibility.Collapsed;
        }
    }
}
