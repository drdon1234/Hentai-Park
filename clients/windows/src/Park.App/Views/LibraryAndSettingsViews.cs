using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Park.App.Controls;
using Park.App.Interop;
using Park.App.Services;
using Park.App.Shell;
using Park.App.Theme;
using Park.Core;
using Park.Core.Configuration;
using Park.Core.Diagnostics;
using Park.Core.Localization;
using Park.Engine.Sources;
using Park.Library;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Pickers;
using Windows.System;
using WinRT.Interop;

namespace Park.App.Views;

public static class LibraryAndSettingsViews
{
    public static FrameworkElement CreateLibraryView(WorkNavigationCallbacks callbacks)
    {
        var stack = new StackPanel { Spacing = 18, Padding = new Thickness(24, 18, 24, 36) };
        var mode = "favorites";
        string? categoryFilter = null;

        var topRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        var bodyHost = new StackPanel { Spacing = 12 };

        async Task RefreshAsync()
        {
            topRow.Children.Clear();
            topRow.Children.Add(ParkKit.SerifHeader(L.Tr("收藏"), 26));
            topRow.Children.Add(ParkKit.TonalButton(L.Tr("收藏"), selected: mode == "favorites", onClick: () => { mode = "favorites"; _ = RefreshAsync(); }));
            topRow.Children.Add(ParkKit.TonalButton(L.Tr("历史"), selected: mode == "history", onClick: () => { mode = "history"; _ = RefreshAsync(); }));

            var categories = await AppHost.Instance.Library.GetCategoriesAsync();
            if (mode == "favorites" && categories.Count > 0)
            {
                topRow.Children.Add(ParkKit.TonalButton(L.Tr("全部"), selected: categoryFilter is null, onClick: () => { categoryFilter = null; _ = RefreshAsync(); }));
                foreach (var cat in categories)
                {
                    var captured = cat.Name;
                    topRow.Children.Add(ParkKit.TonalButton(captured, selected: categoryFilter == captured, onClick: () => { categoryFilter = captured; _ = RefreshAsync(); }));
                }
            }

            bodyHost.Children.Clear();
            if (mode == "favorites")
            {
                var favs = await AppHost.Instance.Library.GetFavoritesAsync(categoryFilter: categoryFilter);
                if (favs.Count == 0)
                {
                    bodyHost.Children.Add(ParkKit.EmptyState("\uE8F1", L.Tr("收藏"), L.Tr("没有结果")));
                    return;
                }
                var gv = new GridView { SelectionMode = ListViewSelectionMode.None, IsItemClickEnabled = false };
                foreach (var entry in favs)
                    gv.Items.Add(WorkCardBuilder.CreateCard(entry.Item, callbacks));
                bodyHost.Children.Add(gv);
            }
            else
            {
                var hist = await AppHost.Instance.Library.GetHistoryAsync(150);
                if (hist.Count == 0)
                {
                    bodyHost.Children.Add(ParkKit.EmptyState("\uE81C", L.Tr("历史"), L.Tr("没有结果")));
                    return;
                }
                foreach (var h in hist)
                    bodyHost.Children.Add(WorkCardBuilder.CreateListRow(h.Item, callbacks));
            }
        }

        stack.Children.Add(topRow);
        stack.Children.Add(bodyHost);
        _ = RefreshAsync();
        return new ScrollViewer { Content = stack };
    }

    public static FrameworkElement CreateDownloadsView(WorkNavigationCallbacks callbacks)
    {
        var c = ParkTheme.Current;
        var stack = new StackPanel { Spacing = 18, Padding = new Thickness(24, 18, 24, 36) };

        var headerRow = new Grid();
        headerRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        headerRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        headerRow.Children.Add(ParkKit.SerifHeader(L.Tr("下载"), 26));

        var openFolderBtn = ParkKit.TonalButton(L.Tr("打开下载文件夹"), "\uE8B7", onClick: () =>
        {
            Directory.CreateDirectory(AppSettings.Instance.DownloadDirectory);
            _ = Launcher.LaunchFolderPathAsync(AppSettings.Instance.DownloadDirectory);
        });
        Grid.SetColumn(openFolderBtn, 1);
        headerRow.Children.Add(openFolderBtn);
        stack.Children.Add(headerRow);

        var listHost = new StackPanel { Spacing = 12 };
        stack.Children.Add(listHost);

        void RenderTasks()
        {
            listHost.Children.Clear();
            var tasks = AppHost.Instance.Downloads.Snapshot();
            if (tasks.Count == 0)
            {
                listHost.Children.Add(ParkKit.EmptyState("\uE896", L.Tr("下载"), L.Tr("没有结果")));
                return;
            }

            var rows = tasks.Select(t =>
            {
                var g = new Grid { ColumnSpacing = 14 };
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(180) });
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                var info = new StackPanel { Spacing = 4 };
                info.Children.Add(new TextBlock
                {
                    Text = $"{t.Work.Title} · {t.ChapterTitle}",
                    FontWeight = FontWeights.SemiBold,
                    Foreground = ParkTheme.Brush(c.OnSurface),
                });
                info.Children.Add(new TextBlock
                {
                    Text = $"{t.Status} · {t.CompletedUnits}/{t.TotalUnits}",
                    FontFamily = ParkTheme.MonoFont,
                    FontSize = 12,
                    Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
                });
                g.Children.Add(info);

                var pb = new ProgressBar
                {
                    Minimum = 0,
                    Maximum = 1,
                    Value = t.ProgressRatio,
                    VerticalAlignment = VerticalAlignment.Center,
                };
                Grid.SetColumn(pb, 1);
                g.Children.Add(pb);

                var btns = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
                var captured = t;
                if (t.Status == DownloadStatus.Running)
                    btns.Children.Add(ParkKit.TonalButton(L.Tr("暂停"), onClick: () => AppHost.Instance.Downloads.Pause(captured.Uid)));
                else if (t.Status is DownloadStatus.Paused or DownloadStatus.Failed)
                    btns.Children.Add(ParkKit.TonalButton(L.Tr("继续"), onClick: () => AppHost.Instance.Downloads.ResumeTask(captured.Uid)));

                btns.Children.Add(ParkKit.TonalButton("✕", onClick: () => _ = AppHost.Instance.Downloads.DeleteTaskAsync(captured.Uid)));
                Grid.SetColumn(btns, 2);
                g.Children.Add(btns);
                return (UIElement)g;
            });

            listHost.Children.Add(ParkKit.RowGroupCard(null, rows));
        }

        void Handler() => stack.DispatcherQueue.TryEnqueue(RenderTasks);
        AppHost.Instance.Downloads.TasksChanged += Handler;
        stack.Unloaded += (_, _) => AppHost.Instance.Downloads.TasksChanged -= Handler;

        RenderTasks();
        return new ScrollViewer { Content = stack };
    }

    public static FrameworkElement CreateSubscriptionsView(WorkNavigationCallbacks callbacks)
    {
        var stack = new StackPanel { Spacing = 18, Padding = new Thickness(24, 18, 24, 36) };
        stack.Children.Add(ParkKit.SerifHeader(L.Tr("订阅"), 26));

        var subSources = AppHost.Instance.Sources.AllSources
            .Where(s => s.Enabled && (s.Manifest.Capabilities.Subscription || s.Manifest.Capabilities.SubscriptionUpdates))
            .ToList();

        if (subSources.Count == 0)
        {
            stack.Children.Add(ParkKit.EmptyState("\uE787", L.Tr("订阅"), L.Tr("没有结果")));
            return new ScrollViewer { Content = stack };
        }

        var rows = subSources.Select(s =>
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.Children.Add(new TextBlock { Text = $"{s.Manifest.Name} · {L.DomainDisplayName(s.Manifest.Category)}", VerticalAlignment = VerticalAlignment.Center });
            var btn = ParkKit.TonalButton(L.Tr("详情"), onClick: () => callbacks.SearchTagInSource?.Invoke(s.Key, string.Empty));
            Grid.SetColumn(btn, 1);
            g.Children.Add(btn);
            return (UIElement)g;
        });

        stack.Children.Add(ParkKit.RowGroupCard(L.Tr("订阅"), rows));
        return new ScrollViewer { Content = stack };
    }

    public static FrameworkElement CreateSourceManageView(Action<InstalledSourceRecord> onOpenSource)
    {
        var c = ParkTheme.Current;
        var stack = new StackPanel { Spacing = 18, Padding = new Thickness(24, 18, 24, 36), MaxWidth = 960 };

        var header = new Grid { ColumnSpacing = 10 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(ParkKit.SerifHeader(L.Tr("站点管理"), 26));

        var statusBanner = new TextBlock
        {
            FontSize = 12.5,
            Foreground = ParkTheme.Brush(c.Primary),
            Visibility = Visibility.Collapsed,
        };

        var filterBox = new TextBox { PlaceholderText = L.Tr("搜索") };
        var listContainer = new StackPanel { Spacing = 12 };

        void RebuildList()
        {
            listContainer.Children.Clear();
            var q = filterBox.Text?.Trim() ?? string.Empty;
            var sources = AppHost.Instance.Sources.AllSources
                .Where(s => string.IsNullOrEmpty(q) ||
                            s.Manifest.Name.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                            s.Key.Contains(q, StringComparison.OrdinalIgnoreCase))
                .ToList();

            var rows = sources.Select(s =>
            {
                var g = new Grid { ColumnSpacing = 12 };
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                var meta = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
                var latencyTag = s.LastLatencyMs is { } ms and < 9000 ? $" · {ms} ms" : string.Empty;
                meta.Children.Add(new TextBlock
                {
                    Text = $"{s.Manifest.Name} ({L.DomainDisplayName(s.Manifest.Category)})",
                    FontWeight = FontWeights.SemiBold,
                    Foreground = ParkTheme.Brush(c.OnSurface),
                });
                meta.Children.Add(new TextBlock
                {
                    Text = $"{s.Key} · v{s.Manifest.Version}{latencyTag}",
                    FontFamily = ParkTheme.MonoFont,
                    FontSize = 11.5,
                    Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
                });
                g.Children.Add(meta);

                var captured = s;
                var openBtn = ParkKit.TonalButton("→", onClick: () => onOpenSource(captured));
                Grid.SetColumn(openBtn, 1);
                g.Children.Add(openBtn);

                var toggle = new ToggleSwitch
                {
                    IsOn = s.Enabled,
                    OnContent = string.Empty,
                    OffContent = string.Empty,
                    MinWidth = 48,
                };
                toggle.Toggled += (_, _) => AppHost.Instance.Sources.SetSourceEnabled(captured.Key, toggle.IsOn);
                Grid.SetColumn(toggle, 2);
                g.Children.Add(toggle);
                return (UIElement)g;
            });

            listContainer.Children.Add(ParkKit.RowGroupCard($"{sources.Count}", rows));
        }

        var speedBtn = ParkKit.PrimaryButton(L.Tr("一键站点测速"), "\uEC4A", async () =>
        {
            statusBanner.Text = L.Tr("正在测速…");
            statusBanner.Visibility = Visibility.Visible;
            await AppHost.Instance.Sources.RunLatencyTestAsync();
            statusBanner.Text = L.Tr("测速完成，已按响应耗时临时调整当前运行显示顺序");
            RebuildList();
        });
        Grid.SetColumn(speedBtn, 1);
        header.Children.Add(speedBtn);

        var resetOrderBtn = ParkKit.TonalButton(L.Tr("恢复原显示顺序"), "\uE777", onClick: () =>
        {
            AppHost.Instance.Sources.ResetLatencyOrder();
            statusBanner.Visibility = Visibility.Collapsed;
            RebuildList();
        });
        Grid.SetColumn(resetOrderBtn, 2);
        header.Children.Add(resetOrderBtn);

        filterBox.TextChanged += (_, _) => RebuildList();

        stack.Children.Add(header);
        stack.Children.Add(statusBanner);
        stack.Children.Add(filterBox);
        stack.Children.Add(listContainer);
        RebuildList();
        return new ScrollViewer { Content = stack };
    }

    public static FrameworkElement CreateSettingsView(MainWindow hostWindow)
    {
        var c = ParkTheme.Current;
        // Centered max-width 760epx SettingsBody aligned with ANDROID.md & WINDOWS.md
        var body = new StackPanel
        {
            MaxWidth = 760,
            Spacing = 22,
            Padding = new Thickness(24, 20, 24, 48),
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };

        body.Children.Add(ParkKit.SerifHeader(L.Tr("设置"), 28));

        // 1. Appearance & Accent Colors
        var themeCombo = new ComboBox { MinWidth = 180 };
        var themeOpts = new (string Key, string Label)[]
        {
            ("dark", L.Tr("暗色")),
            ("light", L.Tr("亮色")),
            ("system", L.Tr("跟随系统")),
        };
        foreach (var t in themeOpts) themeCombo.Items.Add(new ComboBoxItem { Content = t.Label, Tag = t.Key });
        themeCombo.SelectedIndex = Math.Max(0, Array.FindIndex(themeOpts, x => x.Key == AppSettings.Instance.ThemeMode));
        themeCombo.SelectionChanged += (_, _) =>
        {
            if (themeCombo.SelectedItem is ComboBoxItem ci && ci.Tag is string k)
                AppSettings.Instance.ThemeMode = k;
        };

        var langCombo = new ComboBox { MinWidth = 180 };
        foreach (var l in PublicContract.Languages)
            langCombo.Items.Add(new ComboBoxItem { Content = l.Name, Tag = l.Id });
        var curLoc = L.CurrentLocale;
        var locIdx = PublicContract.Languages.Select((l, i) => (l, i)).FirstOrDefault(x => x.l.Id == curLoc).i;
        langCombo.SelectedIndex = locIdx;
        langCombo.SelectionChanged += (_, _) =>
        {
            if (langCombo.SelectedItem is ComboBoxItem ci && ci.Tag is string lid && lid != L.CurrentLocale)
                AppSettings.Instance.Language = lid;
        };

        var accentDots = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        foreach (var (argb, labelKey) in AppSettings.PresetAccents)
        {
            var capturedArgb = argb;
            var swatchColor = ParkTheme.Hex(argb & 0xFFFFFF);
            var selected = !AppSettings.Instance.UseSystemAccent && AppSettings.Instance.SeedColor == argb;
            var dotBtn = new Button
            {
                Width = 36,
                Height = 36,
                Padding = new Thickness(0),
                CornerRadius = new CornerRadius(18),
                Background = ParkTheme.Brush(swatchColor),
                BorderBrush = ParkTheme.Brush(selected ? c.OnSurface : c.OutlineVariant),
                BorderThickness = new Thickness(selected ? 2.5 : 1),
            };
            ToolTipService.SetToolTip(dotBtn, L.Tr(labelKey));
            dotBtn.Click += (_, _) =>
            {
                AppSettings.Instance.UseSystemAccent = false;
                AppSettings.Instance.SeedColor = capturedArgb;
            };
            accentDots.Children.Add(dotBtn);
        }

        var sysAccentSwitch = new ToggleSwitch
        {
            IsOn = AppSettings.Instance.UseSystemAccent,
            OnContent = string.Empty,
            OffContent = string.Empty,
        };
        sysAccentSwitch.Toggled += (_, _) => AppSettings.Instance.UseSystemAccent = sysAccentSwitch.IsOn;

        body.Children.Add(ParkKit.RowGroupCard(L.Tr("主题"),
        [
            MakeSettingRow(L.Tr("主题"), themeCombo),
            MakeSettingRow(L.Tr("界面语言"), langCombo),
            MakeSettingRow(L.Tr("强调色"), accentDots),
            MakeSettingRow(L.Tr("跟随 Windows 系统强调色"), sysAccentSwitch),
        ]));

        // 2. Network & Proxy
        var proxyInput = new TextBox
        {
            Text = AppSettings.Instance.Proxy,
            PlaceholderText = "http://host:port",
            Width = 260,
        };
        proxyInput.LostFocus += (_, _) => AppSettings.Instance.Proxy = proxyInput.Text;

        body.Children.Add(ParkKit.RowGroupCard(L.Tr("HTTP 代理"),
        [
            MakeSettingRow(L.Tr("HTTP 代理"), proxyInput),
        ]));

        // 3. Content Blocklist Editor
        var blockInput = new TextBox
        {
            Text = string.Join(", ", AppSettings.Instance.BlockedTags),
            PlaceholderText = "ntr, female:*, title:regex:...",
            AcceptsReturn = false,
            MinWidth = 340,
        };
        blockInput.LostFocus += (_, _) =>
        {
            var items = blockInput.Text.Split([',', '，', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            AppSettings.Instance.BlockedTags = items;
        };
        body.Children.Add(ParkKit.RowGroupCard(L.Tr("内容屏蔽"),
        [
            MakeSettingRow(L.Tr("屏蔽标签与规则"), blockInput),
        ]));

        // 4. Privacy, Hardware Anti-Capture & Windows Hello AppLock
        var incognitoSwitch = new ToggleSwitch { IsOn = AppSettings.Instance.Incognito, OnContent = string.Empty, OffContent = string.Empty };
        incognitoSwitch.Toggled += (_, _) => AppSettings.Instance.Incognito = incognitoSwitch.IsOn;

        var secureSwitch = new ToggleSwitch { IsOn = AppSettings.Instance.SecureScreen, OnContent = string.Empty, OffContent = string.Empty };
        secureSwitch.Toggled += (_, _) => AppSettings.Instance.SecureScreen = secureSwitch.IsOn;

        var blurSwitch = new ToggleSwitch { IsOn = AppSettings.Instance.BlurCovers, OnContent = string.Empty, OffContent = string.Empty };
        blurSwitch.Toggled += (_, _) => AppSettings.Instance.BlurCovers = blurSwitch.IsOn;

        var lockSwitch = new ToggleSwitch { IsOn = AppSettings.Instance.AppLock, OnContent = string.Empty, OffContent = string.Empty };
        lockSwitch.Toggled += async (_, _) =>
        {
            if (lockSwitch.IsOn && !AppSettings.Instance.AppLock)
            {
                // Require successful verification before enabling AppLock so users cannot lock themselves out
                var verified = await NativeWindowHelper.AuthenticateWindowsHelloAsync(L.Tr("验证身份以开启应用锁"));
                if (!verified)
                {
                    lockSwitch.IsOn = false;
                    return;
                }
                AppSettings.Instance.AppLock = true;
            }
            else if (!lockSwitch.IsOn)
            {
                AppSettings.Instance.AppLock = false;
            }
        };

        body.Children.Add(ParkKit.RowGroupCard(L.Tr("隐私与安全"),
        [
            MakeSettingRow(L.Tr("无痕浏览"), incognitoSwitch),
            MakeSettingRow(L.Tr("已启用硬件防截屏保护"), secureSwitch),
            MakeSettingRow(L.Tr("模糊作品封面"), blurSwitch),
            MakeSettingRow(L.Tr("Windows Hello 应用锁"), lockSwitch),
        ]));

        // 5. Cross-Platform .parkbak Backup & Restore (Android <-> Windows bidirectional)
        var includeCredsCheck = new CheckBox { Content = L.Tr("包含站点登录与确认状态") };
        var backupFeedback = new TextBlock { FontSize = 12.5, Foreground = ParkTheme.Brush(c.Primary), TextWrapping = TextWrapping.Wrap };

        var exportBtn = ParkKit.PrimaryButton(L.Tr("导出 .parkbak 备份"), "\uEDE1", async () =>
        {
            try
            {
                var path = await AppHost.Instance.Backups.WriteToDirectoryAsync(
                    AppPaths.BackupsDir,
                    new BackupOptions(IncludeCredentials: includeCredsCheck.IsChecked == true),
                    cred => AppHost.Instance.Sources.ExportBackupJsonAsync(cred));
                backupFeedback.Text = L.Tr("备份已导出至：{path}", new Dictionary<string, object?> { ["path"] = path });
            }
            catch (Exception ex)
            {
                backupFeedback.Text = ex.Message;
            }
        });

        var importBtn = ParkKit.TonalButton(L.Tr("导入并合并 .parkbak 备份"), "\uE8E5", onClick: async () =>
        {
            try
            {
                var picker = new FileOpenPicker();
                InitializeWithWindow.Initialize(picker, NativeWindowHelper.GetHwnd(hostWindow));
                picker.FileTypeFilter.Add(".parkbak");
                var file = await picker.PickSingleFileAsync();
                if (file is null) return;

                var bytes = await File.ReadAllBytesAsync(file.Path);
                var report = await AppHost.Instance.Backups.RestoreAsync(
                    bytes,
                    srcJson => AppHost.Instance.Sources.ImportBackupJsonAsync(srcJson));
                backupFeedback.Text = L.Tr("合并恢复完成：{summary}", new Dictionary<string, object?> { ["summary"] = report.Summary });
            }
            catch (Exception ex)
            {
                backupFeedback.Text = ex.Message;
            }
        });

        var backupRow = new StackPanel { Spacing = 10 };
        backupRow.Children.Add(includeCredsCheck);
        var backupBtns = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        backupBtns.Children.Add(exportBtn);
        backupBtns.Children.Add(importBtn);
        backupRow.Children.Add(backupBtns);
        backupRow.Children.Add(backupFeedback);

        body.Children.Add(ParkKit.RowGroupCard(".parkbak (Android ⇄ Windows)", [backupRow]));

        // 6. Sanitized Diagnostics Log Viewer
        var redactedCheck = new CheckBox { Content = L.Tr("脱敏模式"), IsChecked = true };
        var logBox = new TextBox
        {
            IsReadOnly = true,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.NoWrap,
            FontFamily = ParkTheme.MonoFont,
            FontSize = 11.5,
            Height = 180,
        };

        void RefreshLogs()
        {
            var versions = AppHost.Instance.Sources.AllSources.Take(10).ToDictionary(s => s.Key, s => s.Manifest.Version);
            logBox.Text = AppLog.Instance.ExportReport(
                redacted: redactedCheck.IsChecked == true,
                hasProxy: !string.IsNullOrEmpty(AppSettings.Instance.Proxy),
                pluginVersions: versions);
        }
        redactedCheck.Checked += (_, _) => RefreshLogs();
        redactedCheck.Unchecked += (_, _) => RefreshLogs();

        var copyLogBtn = ParkKit.TonalButton(L.Tr("复制"), "\uE8C8", onClick: () =>
        {
            RefreshLogs();
            var dp = new DataPackage();
            dp.SetText(logBox.Text);
            Clipboard.SetContent(dp);
        });

        var diagHeader = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        diagHeader.Children.Add(redactedCheck);
        diagHeader.Children.Add(copyLogBtn);

        body.Children.Add(ParkKit.RowGroupCard($"HentaiPark Windows v{PublicContract.AppVersion}+{PublicContract.BuildNumber} · AGPL-3.0-only",
        [
            diagHeader,
            logBox,
        ]));

        RefreshLogs();
        return new ScrollViewer { Content = body };
    }

    private static Grid MakeSettingRow(string label, FrameworkElement control)
    {
        var g = new Grid { ColumnSpacing = 16 };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        g.Children.Add(new TextBlock
        {
            Text = label,
            FontFamily = ParkTheme.SansFont,
            FontSize = 14,
            Foreground = ParkTheme.Brush(ParkTheme.Current.OnSurface),
            VerticalAlignment = VerticalAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        });
        Grid.SetColumn(control, 1);
        g.Children.Add(control);
        return g;
    }
}
