using System.Runtime.InteropServices.WindowsRuntime;
using System.Text.Json.Nodes;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Park.App.Controls;
using Park.App.Services;
using Park.App.Theme;
using Park.Core;
using Park.Core.Configuration;
using Park.Core.Localization;
using Park.Core.Models;
using Park.Engine.Sources;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Streams;

namespace Park.App.Views;

public static class DiscoverAndSearchViews
{
    public static FrameworkElement CreateDiscoverView(
        string? activeDomain,
        WorkNavigationCallbacks callbacks,
        Action<string?> onSelectDomain,
        Action<InstalledSourceRecord> onOpenSource,
        Action onOpenRankings,
        Action onOpenReverseSearch)
    {
        var c = ParkTheme.Current;
        var rootScroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        var contentStack = new StackPanel { Spacing = 20, Padding = new Thickness(24, 18, 24, 36) };

        // 1. Page Header + Quick Tools (Rankings & Reverse Image Search)
        var headerGrid = new Grid();
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var titleText = activeDomain is null ? L.Tr("发现") : L.DomainDisplayName(activeDomain);
        headerGrid.Children.Add(ParkKit.SerifHeader(titleText, 28));

        var toolsRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        toolsRow.Children.Add(ParkKit.TonalButton(L.Tr("排行榜"), "\uE8CB", onClick: onOpenRankings));
        toolsRow.Children.Add(ParkKit.TonalButton(L.Tr("图片反搜"), "\uE722", onClick: onOpenReverseSearch));
        Grid.SetColumn(toolsRow, 1);
        headerGrid.Children.Add(toolsRow);
        contentStack.Children.Add(headerGrid);

        // 2. Dual Dimension & Media Filters (aligned with ANDROID.md: 内容范围 + 媒体类型)
        var filterBar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };

        var dimCombo = new ComboBox { Header = L.Tr("内容范围"), MinWidth = 160 };
        var dimItems = new (string Key, string Label)[]
        {
            ("all", L.Tr("全部")),
            ("twoD", L.Tr("二次元")),
            ("threeD", L.Tr("三次元")),
        };
        foreach (var d in dimItems) dimCombo.Items.Add(new ComboBoxItem { Content = d.Label, Tag = d.Key });
        dimCombo.SelectedIndex = Math.Max(0, Array.FindIndex(dimItems, x => x.Key == AppSettings.Instance.HomeDimension));

        var mediaCombo = new ComboBox { Header = L.Tr("媒体类型"), MinWidth = 160 };
        var mediaItems = new (string Key, string Label)[]
        {
            ("all", L.Tr("全部")),
            ("image", L.Tr("图片")),
            ("video", L.Tr("视频")),
            ("other", L.Tr("其他")),
        };
        foreach (var m in mediaItems) mediaCombo.Items.Add(new ComboBoxItem { Content = m.Label, Tag = m.Key });
        mediaCombo.SelectedIndex = Math.Max(0, Array.FindIndex(mediaItems, x => x.Key == AppSettings.Instance.HomeMedia));

        filterBar.Children.Add(dimCombo);
        filterBar.Children.Add(mediaCombo);
        contentStack.Children.Add(filterBar);

        // 3. Horizontal Domain Capsule Strip
        var domainStripScroll = new ScrollViewer
        {
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            HorizontalScrollMode = ScrollMode.Enabled,
            VerticalScrollMode = ScrollMode.Disabled,
        };
        var domainRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Padding = new Thickness(0, 2, 0, 6) };
        domainRow.Children.Add(ParkKit.TonalButton(L.Tr("全部"), selected: activeDomain is null, onClick: () => onSelectDomain(null)));

        var visibleDomains = FilterDomains(AppSettings.Instance.DomainOrder, AppSettings.Instance.HomeDimension, AppSettings.Instance.HomeMedia);
        foreach (var dom in visibleDomains)
        {
            var captured = dom;
            domainRow.Children.Add(ParkKit.TonalButton(
                L.DomainDisplayName(captured),
                selected: activeDomain == captured,
                onClick: () => onSelectDomain(captured)));
        }
        domainStripScroll.Content = domainRow;
        contentStack.Children.Add(domainStripScroll);

        dimCombo.SelectionChanged += (_, _) =>
        {
            if (dimCombo.SelectedItem is ComboBoxItem ci && ci.Tag is string k && k != AppSettings.Instance.HomeDimension)
            {
                AppSettings.Instance.HomeDimension = k;
                onSelectDomain(null);
            }
        };
        mediaCombo.SelectionChanged += (_, _) =>
        {
            if (mediaCombo.SelectedItem is ComboBoxItem ci && ci.Tag is string k && k != AppSettings.Instance.HomeMedia)
            {
                AppSettings.Instance.HomeMedia = k;
                onSelectDomain(null);
            }
        };

        // 4. Continue Reading / Watching Shelf (from real SQLite History)
        var continueHost = new StackPanel { Spacing = 10 };
        contentStack.Children.Add(continueHost);
        _ = PopulateContinueShelfAsync(continueHost, callbacks);

        // 5. Domain-Grouped Source Shelves
        var targetDomains = activeDomain is not null ? [activeDomain] : visibleDomains;
        var allSources = AppHost.Instance.Sources.AllSources
            .Where(s => s.Enabled && !s.Manifest.Capabilities.MetadataOnly && !s.Manifest.Capabilities.RankingOnly && !s.Manifest.Capabilities.ReverseSearch)
            .ToList();

        var anyRendered = false;
        foreach (var dom in targetDomains)
        {
            var domSources = allSources.Where(s => s.Manifest.Category == dom).ToList();
            if (domSources.Count == 0) continue;
            anyRendered = true;

            var sectionBox = new StackPanel { Spacing = 12 };
            var secHeader = new Grid();
            secHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            secHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            secHeader.Children.Add(new TextBlock
            {
                Text = L.DomainDisplayName(dom),
                FontFamily = ParkTheme.SerifFont,
                FontSize = 20,
                FontWeight = FontWeights.SemiBold,
                Foreground = ParkTheme.Brush(c.OnSurface),
            });

            if (activeDomain is null)
            {
                var capturedDom = dom;
                var enterBtn = ParkKit.TonalButton($"{L.DomainDisplayName(dom)} ({domSources.Count})", "\uE76C", onClick: () => onSelectDomain(capturedDom));
                Grid.SetColumn(enterBtn, 1);
                secHeader.Children.Add(enterBtn);
            }
            sectionBox.Children.Add(secHeader);

            var sitesWrap = new GridView
            {
                SelectionMode = ListViewSelectionMode.None,
                IsItemClickEnabled = false,
            };

            var displaySources = activeDomain is null ? domSources.Take(4) : domSources;
            foreach (var src in displaySources)
            {
                var capturedSrc = src;
                sitesWrap.Items.Add(BuildSourceEntryTile(capturedSrc, () => onOpenSource(capturedSrc)));
            }

            sectionBox.Children.Add(sitesWrap);
            contentStack.Children.Add(sectionBox);
        }

        if (!anyRendered)
        {
            contentStack.Children.Add(ParkKit.EmptyState(
                "\uE721",
                L.Tr("没有结果"),
                L.Tr("可切换分类，或通过站点入口浏览和搜索")));
        }

        rootScroll.Content = contentStack;
        return rootScroll;
    }

    public static FrameworkElement CreateSourceBrowseView(
        string sourceKey,
        string? initialKeyword,
        WorkNavigationCallbacks callbacks)
    {
        var c = ParkTheme.Current;
        var rec = AppHost.Instance.Sources.GetSource(sourceKey);
        if (rec is null)
            return ParkKit.EmptyState("\uE783", L.Tr("内容不存在"), sourceKey);

        var pageGrid = new Grid { Padding = new Thickness(24, 18, 24, 18), RowSpacing = 14 };
        pageGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        pageGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        pageGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        // Top source header + in-source search + layout toggle
        var topGrid = new Grid { ColumnSpacing = 12 };
        topGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        topGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(280) });
        topGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var brandStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, VerticalAlignment = VerticalAlignment.Center };
        var avatarColor = ParkTheme.ParseHexColor(rec.Manifest.Color, c.Primary);
        brandStack.Children.Add(new Border
        {
            Width = 34,
            Height = 34,
            CornerRadius = new CornerRadius(8),
            Background = ParkTheme.Brush(avatarColor),
            Child = new TextBlock
            {
                Text = rec.Manifest.Name[..1].ToUpperInvariant(),
                FontWeight = FontWeights.SemiBold,
                Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 255, 255, 255)),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        });
        var nameCol = new StackPanel();
        nameCol.Children.Add(ParkKit.SerifHeader(rec.Manifest.Name, 22));
        if (!string.IsNullOrEmpty(rec.Manifest.Description))
        {
            nameCol.Children.Add(new TextBlock
            {
                Text = L.TranslatePlugin(rec.Manifest.I18n, rec.Manifest.Description),
                FontSize = 12,
                Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
            });
        }
        brandStack.Children.Add(nameCol);
        topGrid.Children.Add(brandStack);

        var isListLayout = rec.Manifest.BrowseLayout == "list" || rec.Manifest.Type is "novel" or "article";
        var currentKeyword = initialKeyword ?? string.Empty;
        var currentFeed = rec.Manifest.DefaultFeed ?? rec.Manifest.Feeds.FirstOrDefault()?.Key;
        var currentPage = 1;
        string? currentCursor = null;

        string FilterScope() => new JsonArray(sourceKey, string.IsNullOrEmpty(currentKeyword) ? currentFeed : null).ToJsonString();
        var settings = AppSettings.Instance;
        var preset = settings.RememberedFilters(FilterScope()) ?? new JsonObject();
        int requestGeneration = 0;
        bool pageLoading = false;

        var searchBox = new AutoSuggestBox
        {
            Text = currentKeyword,
            PlaceholderText = L.Tr("搜索"),
            QueryIcon = new SymbolIcon(Symbol.Find),
            VerticalAlignment = VerticalAlignment.Center,
            Visibility = rec.Manifest.Capabilities.Search ? Visibility.Visible : Visibility.Collapsed,
        };
        Grid.SetColumn(searchBox, 1);
        topGrid.Children.Add(searchBox);

        var layoutToggleBtn = ParkKit.TonalButton(
            isListLayout ? L.Tr("切换为卡片") : L.Tr("切换为单行列表"),
            isListLayout ? "\uF0E2" : "\uE8FD");
        Grid.SetColumn(layoutToggleBtn, 2);
        topGrid.Children.Add(layoutToggleBtn);
        pageGrid.Children.Add(topGrid);

        // Feed tabs strip
        var feedStrip = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        Grid.SetRow(feedStrip, 1);
        pageGrid.Children.Add(feedStrip);

        // Content stage
        var resultsScroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetRow(resultsScroll, 2);
        pageGrid.Children.Add(resultsScroll);

        var cachedItems = new List<WorkItem>();
        var hasNextPage = false;

        void RenderItems()
        {
            var from = preset["start"]?.ToString();
            var to = preset["end"]?.ToString();
            bool MatchesDate(WorkItem work)
            {
                if (from is null && to is null) return true;
                if (!DateTimeOffset.TryParse(work.Uploaded, out var date)) return false;
                var day = date.LocalDateTime.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
                return (from is null || string.CompareOrdinal(day, from) >= 0) &&
                       (to is null || string.CompareOrdinal(day, to) <= 0);
            }
            var visible = cachedItems.Where(w => MatchesDate(w) && !AppHost.Instance.CurrentBlockEngine.IsBlocked(w)).ToList();
            if (visible.Count == 0 && !hasNextPage)
            {
                resultsScroll.Content = ParkKit.EmptyState("\uE721", L.Tr("没有结果"), rec.Manifest.Name);
                return;
            }

            var container = new StackPanel { Spacing = 14, Padding = new Thickness(0, 4, 0, 28) };
            if (isListLayout)
            {
                foreach (var w in visible)
                    container.Children.Add(WorkCardBuilder.CreateListRow(w, callbacks));
            }
            else
            {
                var gv = new GridView { SelectionMode = ListViewSelectionMode.None, IsItemClickEnabled = false };
                foreach (var w in visible)
                    gv.Items.Add(WorkCardBuilder.CreateCard(w, callbacks));
                container.Children.Add(gv);
            }

            if (hasNextPage)
            {
                var moreBtn = ParkKit.TonalButton(L.Tr("加载更多"), "\uE74B", onClick: () => _ = LoadPageAsync(append: true));
                moreBtn.HorizontalAlignment = HorizontalAlignment.Center;
                container.Children.Add(moreBtn);
            }

            resultsScroll.Content = container;
        }

        async Task LoadPageAsync(bool append)
        {
            if (append && pageLoading) return;
            pageLoading = true;
            var generation = ++requestGeneration;
            if (!append)
            {
                currentPage = 1;
                currentCursor = null;
                cachedItems.Clear();
                resultsScroll.Content = new ProgressRing { IsActive = true, Width = 36, Height = 36, Margin = new Thickness(0, 48, 0, 0) };
            }
            else
            {
                currentPage++;
            }

            try
            {
                var page = !string.IsNullOrWhiteSpace(currentKeyword)
                    ? await AppHost.Instance.Sources.SearchSourceAsync(sourceKey, currentKeyword, currentPage, currentCursor, preset["filters"] as JsonObject)
                    : await AppHost.Instance.Sources.FetchFeedAsync(sourceKey, currentFeed, currentPage, currentCursor, preset["filters"] as JsonObject);
                if (generation != requestGeneration) return;

                currentCursor = page.Cursor;
                hasNextPage = page.HasNext;
                cachedItems.AddRange(page.Items);
                foreach (var sec in page.Sections) cachedItems.AddRange(sec.Items);
                RenderItems();
            }
            catch (SourceError se)
            {
                var translated = L.TranslatePlugin(rec.Manifest.I18n, se.RawMessage, se.Params);
                if (generation != requestGeneration) return;
                var retryBtn = ParkKit.PrimaryButton(L.Tr("重试"), "\uE72C", () => _ = LoadPageAsync(append: false));
                resultsScroll.Content = ParkKit.EmptyState("\uE783", translated, rec.Manifest.VpnHint ? "VPN / Proxy" : se.Code, retryBtn);
            }
            catch (Exception ex)
            {
                if (generation != requestGeneration) return;
                var retryBtn = ParkKit.PrimaryButton(L.Tr("重试"), "\uE72C", () => _ = LoadPageAsync(append: false));
                resultsScroll.Content = ParkKit.EmptyState("\uE783", ex.Message, rec.Manifest.Name, retryBtn);
            }
            finally
            {
                if (generation == requestGeneration) pageLoading = false;
            }
        }

        async Task EditFiltersAsync()
        {
            var scope = FilterScope();
            var filters = preset["filters"]?.DeepClone() as JsonObject ?? new JsonObject();
            var fields = new StackPanel { Spacing = 8 };
            var definitions = string.IsNullOrEmpty(currentKeyword)
                ? rec.Manifest.Feeds.FirstOrDefault(f => f.Key == currentFeed)?.Options
                : rec.Manifest.SearchFilters;
            foreach (var option in definitions ?? [])
            {
                if (option.Dynamic || option.DependsOn?.Count > 0) continue;
                var label = L.TranslatePlugin(rec.Manifest.I18n, option.Label);
                if (option.Type == "select" && option.Values.Count > 0)
                {
                    var combo = new ComboBox { Header = label, HorizontalAlignment = HorizontalAlignment.Stretch };
                    foreach (var choice in option.Values)
                        combo.Items.Add(new ComboBoxItem { Content = L.TranslatePlugin(rec.Manifest.I18n, choice.Label), Tag = choice.Value });
                    combo.SelectedItem = combo.Items.Cast<ComboBoxItem>().FirstOrDefault(item =>
                        (string)item.Tag == (filters[option.Key]?.ToString() ?? option.DefaultValue));
                    combo.SelectionChanged += (_, _) => { if (combo.SelectedItem is ComboBoxItem selected) filters[option.Key] = (string)selected.Tag; };
                    fields.Children.Add(combo);
                }
                else if (option.Type == "number" && option.Minimum is double min && option.Maximum is double max && max > min && option.Step > 0)
                {
                    var culture = System.Globalization.CultureInfo.InvariantCulture;
                    var slider = new Slider { Minimum = min, Maximum = max, StepFrequency = option.Step, SmallChange = option.Step };
                    slider.Value = double.TryParse(filters[option.Key]?.ToString() ?? option.DefaultValue, culture, out var initial)
                        ? Math.Clamp(initial, min, max) : min;
                    var digits = option.Step.ToString(culture).Split('.').ElementAtOrDefault(1)?.Length ?? 0;
                    var heading = new Grid();
                    heading.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    heading.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                    heading.Children.Add(new TextBlock { Text = label });
                    var number = new TextBlock { Text = slider.Value.ToString($"F{digits}") };
                    Grid.SetColumn(number, 1);
                    heading.Children.Add(number);
                    Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(slider, label);
                    slider.ValueChanged += (_, args) => {
                        number.Text = args.NewValue.ToString($"F{digits}");
                        filters[option.Key] = Math.Round(args.NewValue, digits);
                    };
                    fields.Children.Add(heading);
                    fields.Children.Add(slider);
                }
                else if (option.Type == "number")
                {
                    var input = new NumberBox { Header = label, Minimum = option.Minimum ?? 0,
                        Maximum = option.Maximum ?? double.MaxValue, SmallChange = 1,
                        SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact };
                    if (double.TryParse(filters[option.Key]?.ToString() ?? option.DefaultValue,
                        System.Globalization.CultureInfo.InvariantCulture, out var initial) && initial != 0) input.Value = initial;
                    input.ValueChanged += (_, args) => {
                        if (double.IsNaN(args.NewValue)) filters.Remove(option.Key);
                        else filters[option.Key] = Math.Truncate(args.NewValue);
                    };
                    fields.Children.Add(input);
                }
                else if (option.Type == "text")
                {
                    var input = new TextBox { Header = label, Text = filters[option.Key]?.ToString() ?? option.DefaultValue };
                    input.TextChanged += (_, _) => filters[option.Key] = input.Text;
                    fields.Children.Add(input);
                }
            }
            CalendarDatePicker DateField(string key, string label)
            {
                var picker = new CalendarDatePicker { Header = L.Tr(label) };
                if (DateTimeOffset.TryParse(preset[key]?.ToString(), out var date)) picker.Date = date;
                fields.Children.Add(picker);
                return picker;
            }
            var from = DateField("start", "起始日期");
            var to = DateField("end", "结束日期");
            fields.Children.Add(ParkKit.TonalButton(L.Tr("清除日期"), onClick: () => { from.Date = null; to.Date = null; }));
            var remember = new CheckBox { Content = L.Tr("记住筛选项"), IsChecked = settings.RememberedFilters(scope) is not null };
            fields.Children.Add(remember);
            var dialog = new ContentDialog {
                Title = L.Tr("筛选"), XamlRoot = pageGrid.XamlRoot,
                Content = new ScrollViewer { Content = fields },
                PrimaryButtonText = L.Tr("应用筛选"), CloseButtonText = L.Tr("取消")
            };
            void Validate() => dialog.IsPrimaryButtonEnabled = from.Date is null || to.Date is null || from.Date <= to.Date;
            from.DateChanged += (_, _) => Validate();
            to.DateChanged += (_, _) => Validate();
            if (await dialog.ShowAsync() != ContentDialogResult.Primary || scope != FilterScope()) return;
            preset = new JsonObject { ["filters"] = filters, ["common"] = new JsonObject() };
            if (from.Date is { } start) preset["start"] = start.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
            if (to.Date is { } end) preset["end"] = end.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
            settings.RememberFilters(scope, remember.IsChecked == true ? preset : null);
            await LoadPageAsync(false);
        }

        void RebuildFeedTabs()
        {
            feedStrip.Children.Clear();
            feedStrip.Children.Add(ParkKit.TonalButton(L.Tr("筛选"), "\uE71C", onClick: () => _ = EditFiltersAsync()));
            foreach (var f in rec.Manifest.Feeds)
            {
                var fKey = f.Key;
                var label = L.TranslatePlugin(rec.Manifest.I18n, f.Label);
                feedStrip.Children.Add(ParkKit.TonalButton(
                    label,
                    selected: string.IsNullOrEmpty(currentKeyword) && currentFeed == fKey,
                    onClick: () =>
                    {
                        currentKeyword = string.Empty;
                        searchBox.Text = string.Empty;
                        currentFeed = fKey;
                        preset = settings.RememberedFilters(FilterScope()) ?? new JsonObject();
                        RebuildFeedTabs();
                        _ = LoadPageAsync(append: false);
                    }));
            }
        }

        layoutToggleBtn.Click += (_, _) =>
        {
            isListLayout = !isListLayout;
            if (cachedItems.Count > 0) RenderItems();
        };

        searchBox.QuerySubmitted += (sender, e) =>
        {
            var previousScope = FilterScope();
            currentKeyword = e.QueryText?.Trim() ?? string.Empty;
            if (FilterScope() != previousScope) preset = settings.RememberedFilters(FilterScope()) ?? new JsonObject();
            RebuildFeedTabs();
            _ = LoadPageAsync(append: false);
        };

        RebuildFeedTabs();
        _ = LoadPageAsync(append: false);
        return pageGrid;
    }

    public static FrameworkElement CreateAggregateSearchView(string initialKeyword, WorkNavigationCallbacks callbacks)
    {
        var c = ParkTheme.Current;
        var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        var stack = new StackPanel { Spacing = 18, Padding = new Thickness(24, 18, 24, 36) };

        stack.Children.Add(ParkKit.SerifHeader($"{L.Tr("搜索")} · {initialKeyword}", 24));

        var resultsHost = new StackPanel { Spacing = 20 };
        stack.Children.Add(resultsHost);
        scroll.Content = stack;

        // Exclude metadataOnly and rankingOnly plugins from normal aggregate search per DEVELOPMENT.md
        var searchable = AppHost.Instance.Sources.AllSources
            .Where(s => s.Enabled && s.Manifest.Capabilities.Search && !s.Manifest.Capabilities.MetadataOnly && !s.Manifest.Capabilities.RankingOnly)
            .Take(8)
            .ToList();

        foreach (var src in searchable)
        {
            var groupBox = new StackPanel { Spacing = 8 };
            var statusTitle = new TextBlock
            {
                Text = $"{src.Manifest.Name} · …",
                FontFamily = ParkTheme.SansFont,
                FontSize = 15,
                FontWeight = FontWeights.SemiBold,
                Foreground = ParkTheme.Brush(c.OnSurface),
            };
            groupBox.Children.Add(statusTitle);
            var rowScroll = new ScrollViewer
            {
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            };
            groupBox.Children.Add(rowScroll);
            resultsHost.Children.Add(groupBox);

            var captured = src;
            _ = Task.Run(async () =>
            {
                try
                {
                    var page = await AppHost.Instance.Sources.SearchSourceAsync(captured.Key, initialKeyword, 1);
                    groupBox.DispatcherQueue.TryEnqueue(() =>
                    {
                        var visible = page.Items.Where(w => !AppHost.Instance.CurrentBlockEngine.IsBlocked(w)).Take(12).ToList();
                        statusTitle.Text = $"{captured.Manifest.Name} ({visible.Count})";
                        var hRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
                        foreach (var item in visible)
                            hRow.Children.Add(WorkCardBuilder.CreateCard(item, callbacks, width: 156));
                        rowScroll.Content = hRow;
                    });
                }
                catch (Exception ex)
                {
                    groupBox.DispatcherQueue.TryEnqueue(() =>
                    {
                        statusTitle.Text = $"{captured.Manifest.Name} · {ex.Message}";
                        statusTitle.Foreground = ParkTheme.Brush(c.OnSurfaceVariant);
                    });
                }
            });
        }

        return scroll;
    }

    public static FrameworkElement CreateReverseSearchView(WorkNavigationCallbacks callbacks)
    {
        var c = ParkTheme.Current;
        var stack = new StackPanel { Spacing = 18, Padding = new Thickness(24, 18, 24, 36) };
        stack.Children.Add(ParkKit.SerifHeader(L.Tr("图片反搜"), 26));

        var statusLabel = new TextBlock
        {
            Text = L.Tr("拖入图片或按 Ctrl+V 粘贴剪贴板截图"),
            FontFamily = ParkTheme.SansFont,
            FontSize = 14,
            Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
            HorizontalAlignment = HorizontalAlignment.Center,
        };

        var dropZone = new Border
        {
            Height = 180,
            AllowDrop = true,
            Background = ParkTheme.Brush(c.Card),
            BorderBrush = ParkTheme.Brush(c.Outline),
            BorderThickness = new Thickness(1.5),
            CornerRadius = new CornerRadius(16),
            Child = new StackPanel
            {
                Spacing = 10,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Children =
                {
                    new FontIcon { Glyph = "\uEB9F", FontSize = 32, Foreground = ParkTheme.Brush(c.Primary) },
                    statusLabel,
                },
            },
        };

        byte[]? selectedImageBytes = null;

        dropZone.DragOver += (_, e) => e.AcceptedOperation = DataPackageOperation.Copy;
        dropZone.Drop += async (_, e) =>
        {
            if (e.DataView.Contains(StandardDataFormats.StorageItems))
            {
                var items = await e.DataView.GetStorageItemsAsync();
                if (items.FirstOrDefault() is Windows.Storage.StorageFile file)
                {
                    var buf = await Windows.Storage.FileIO.ReadBufferAsync(file);
                    selectedImageBytes = buf.ToArray();
                    statusLabel.Text = $"{file.Name} ({L.FormatBytes(selectedImageBytes.Length)})";
                }
            }
        };

        var pasteAccel = new Microsoft.UI.Xaml.Input.KeyboardAccelerator { Key = Windows.System.VirtualKey.V, Modifiers = Windows.System.VirtualKeyModifiers.Control };
        pasteAccel.Invoked += async (_, e) =>
        {
            var view = Clipboard.GetContent();
            if (view.Contains(StandardDataFormats.Bitmap))
            {
                e.Handled = true;
                var bmpRef = await view.GetBitmapAsync();
                using var stream = await bmpRef.OpenReadAsync();
                var bytes = new byte[stream.Size];
                await stream.ReadAsync(bytes.AsBuffer(), (uint)bytes.Length, InputStreamOptions.None);
                selectedImageBytes = bytes;
                statusLabel.Text = $"Clipboard ({L.FormatBytes(bytes.Length)})";
            }
        };
        stack.KeyboardAccelerators.Add(pasteAccel);
        stack.Children.Add(dropZone);

        // Reverse-search services grouped by general / gallery / anime / jav per SOURCE_API.md
        var revSources = AppHost.Instance.Sources.AllSources.Where(s => s.Manifest.Capabilities.ReverseSearch).ToList();
        var checkBoxes = new List<(InstalledSourceRecord Rec, CheckBox Box)>();
        var servicesWrap = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 14 };
        foreach (var rs in revSources)
        {
            var cb = new CheckBox { Content = rs.Manifest.Name, IsChecked = true };
            checkBoxes.Add((rs, cb));
            servicesWrap.Children.Add(cb);
        }
        stack.Children.Add(servicesWrap);

        var resultsHost = new StackPanel { Spacing = 10 };
        var startBtn = ParkKit.PrimaryButton(L.Tr("搜索"), "\uE721", () =>
        {
            if (selectedImageBytes is null || selectedImageBytes.Length == 0) return;
            resultsHost.Children.Clear();
            resultsHost.Children.Add(new TextBlock
            {
                Text = $"{L.FormatBytes(selectedImageBytes.Length)} · {checkBoxes.Count(x => x.Box.IsChecked == true)} services queued",
                Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
            });
        });
        stack.Children.Add(startBtn);
        stack.Children.Add(resultsHost);

        return new ScrollViewer { Content = stack };
    }

    public static FrameworkElement CreateRankingsView(WorkNavigationCallbacks callbacks)
    {
        var stack = new StackPanel { Spacing = 16, Padding = new Thickness(24, 18, 24, 36) };
        stack.Children.Add(ParkKit.SerifHeader(L.Tr("排行榜"), 26));

        var rankingSources = AppHost.Instance.Sources.AllSources
            .Where(s => s.Enabled && s.Manifest.Capabilities.Rankings)
            .ToList();

        if (rankingSources.Count == 0)
        {
            stack.Children.Add(ParkKit.EmptyState("\uE8CB", L.Tr("排行榜"), L.Tr("没有结果")));
            return new ScrollViewer { Content = stack };
        }

        var rows = rankingSources.Select(s =>
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.Children.Add(new TextBlock
            {
                Text = $"{s.Manifest.Name} · {L.DomainDisplayName(s.Manifest.Category)}",
                VerticalAlignment = VerticalAlignment.Center,
            });
            var openBtn = ParkKit.TonalButton(L.Tr("详情"), onClick: () => callbacks.SearchTagInSource?.Invoke(s.Key, string.Empty));
            Grid.SetColumn(openBtn, 1);
            g.Children.Add(openBtn);
            return (UIElement)g;
        });

        stack.Children.Add(ParkKit.RowGroupCard(L.Tr("排行榜"), rows));
        return new ScrollViewer { Content = stack };
    }

    private static Border BuildSourceEntryTile(InstalledSourceRecord src, Action onClick)
    {
        var c = ParkTheme.Current;
        var brand = ParkTheme.ParseHexColor(src.Manifest.Color, c.Primary);

        var row = new Grid { Width = 256, ColumnSpacing = 12, Padding = new Thickness(12, 10, 12, 10) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        row.Children.Add(new Border
        {
            Width = 36,
            Height = 36,
            CornerRadius = new CornerRadius(8),
            Background = ParkTheme.Brush(brand),
            Child = new TextBlock
            {
                Text = src.Manifest.Name[..1].ToUpperInvariant(),
                FontWeight = FontWeights.SemiBold,
                Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 255, 255, 255)),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        });

        var info = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 2 };
        info.Children.Add(new TextBlock
        {
            Text = src.Manifest.Name,
            FontFamily = ParkTheme.SansFont,
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            Foreground = ParkTheme.Brush(c.OnSurface),
            MaxLines = 1,
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        var sub = src.LastLatencyMs is { } ms and < 9000 ? $"{ms} ms · v{src.Manifest.Version}" : $"v{src.Manifest.Version}";
        info.Children.Add(new TextBlock
        {
            Text = sub,
            FontFamily = ParkTheme.MonoFont,
            FontSize = 11,
            Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
        });
        Grid.SetColumn(info, 1);
        row.Children.Add(info);

        var arrow = new FontIcon
        {
            Glyph = "\uE76C",
            FontSize = 12,
            Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(arrow, 2);
        row.Children.Add(arrow);

        var tile = new Border
        {
            Background = ParkTheme.Brush(c.Card),
            BorderBrush = ParkTheme.Brush(c.OutlineVariant),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            Child = row,
        };
        tile.PointerEntered += (_, _) => tile.Background = ParkTheme.Brush(c.ContainerHigh);
        tile.PointerExited += (_, _) => tile.Background = ParkTheme.Brush(c.Card);
        tile.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(tile).Properties.IsLeftButtonPressed)
                onClick();
        };
        return tile;
    }

    private static async Task PopulateContinueShelfAsync(StackPanel host, WorkNavigationCallbacks callbacks)
    {
        var history = await AppHost.Instance.Library.GetHistoryAsync(limit: 12);
        if (history.Count == 0) return;

        host.DispatcherQueue.TryEnqueue(() =>
        {
            host.Children.Clear();
            host.Children.Add(new TextBlock
            {
                Text = L.Tr("历史"),
                FontFamily = ParkTheme.SerifFont,
                FontSize = 19,
                FontWeight = FontWeights.SemiBold,
                Foreground = ParkTheme.Brush(ParkTheme.Current.OnSurface),
            });

            var hScroll = new ScrollViewer
            {
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            };
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
            foreach (var h in history)
                row.Children.Add(WorkCardBuilder.CreateCard(h.Item, callbacks, width: 152));
            hScroll.Content = row;
            host.Children.Add(hScroll);
        });
    }

    private static List<string> FilterDomains(IReadOnlyList<string> domains, string dimension, string media)
    {
        return domains.Where(d =>
        {
            var dimOk = dimension switch
            {
                "twoD" => PublicContract.TwoDDomains.Contains(d) || d is "onlineGame" or "other",
                "threeD" => PublicContract.ThreeDDomains.Contains(d) || d is "onlineGame" or "other",
                _ => true,
            };
            if (!dimOk) return false;

            return media switch
            {
                "image" => PublicContract.ImageMediaDomains.Contains(d),
                "video" => PublicContract.VideoMediaDomains.Contains(d),
                "other" => !PublicContract.ImageMediaDomains.Contains(d) && !PublicContract.VideoMediaDomains.Contains(d),
                _ => true,
            };
        }).ToList();
    }
}
