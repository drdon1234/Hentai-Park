using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Park.App.Controls;
using Park.App.Interop;
using Park.App.Services;
using Park.App.Shell;
using Park.App.Theme;
using Park.Core.Configuration;
using Park.Core.Localization;
using Park.Core.Models;
using Park.Library;
using Windows.Media.Core;
using Windows.Media.SpeechSynthesis;
using Windows.Storage.Streams;
using Windows.System;

namespace Park.App.Views;

public static class WorkDetailAndReadersViews
{
    public static FrameworkElement CreateWorkDetailView(
        WorkItem initialWork,
        MainWindow hostWindow,
        WorkNavigationCallbacks callbacks)
    {
        var c = ParkTheme.Current;
        var stageHost = new Grid { Padding = new Thickness(24, 18, 24, 32) };
        stageHost.Children.Add(new ProgressRing { IsActive = true, Width = 38, Height = 38 });

        var revealBlockedTemporarily = false;

        async Task LoadDetailAsync()
        {
            try
            {
                var srcRec = AppHost.Instance.Sources.GetSource(initialWork.Source);
                var detail = await AppHost.Instance.Sources.FetchDetailAsync(initialWork.Source, initialWork.Id, initialWork);
                var isFav = await AppHost.Instance.Library.IsFavoriteAsync(detail.Item.Source, detail.Item.Id);
                var chProgress = await AppHost.Instance.Library.GetChapterProgressAsync(detail.Item.Source, detail.Item.Id);
                var recentHist = (await AppHost.Instance.Library.GetHistoryAsync(50))
                    .FirstOrDefault(h => h.Item.Source == detail.Item.Source && h.Item.Id == detail.Item.Id);

                stageHost.DispatcherQueue.TryEnqueue(() =>
                {
                    stageHost.Children.Clear();
                    if (!revealBlockedTemporarily && AppHost.Instance.CurrentBlockEngine.IsBlocked(detail))
                    {
                        var revealBtn = ParkKit.TonalButton(L.Tr("临时显示本页已屏蔽内容"), "\uE7B3", onClick: () =>
                        {
                            revealBlockedTemporarily = true;
                            _ = LoadDetailAsync();
                        });
                        stageHost.Children.Add(ParkKit.EmptyState("\uE7BA", L.Tr("已隐藏屏蔽内容"), detail.Item.Source, revealBtn));
                        return;
                    }

                    var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                    var outer = new StackPanel { Spacing = 24, MaxWidth = 1220 };

                    // Wide-screen dual-column gallery header (cover left, title + actions + metadata right)
                    var heroGrid = new Grid { ColumnSpacing = 28, RowSpacing = 18 };
                    heroGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
                    heroGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                    var coverBox = new Grid
                    {
                        Width = 260,
                        MinHeight = 340,
                        MaxHeight = 420,
                        CornerRadius = new CornerRadius(12),
                        Background = ParkTheme.Brush(c.Card),
                        BorderBrush = ParkTheme.Brush(c.OutlineVariant),
                        BorderThickness = new Thickness(1),
                    };
                    var phIcon = new FontIcon
                    {
                        Glyph = ParkKit.MediaSemanticGlyph(detail.Item.MediaKind),
                        FontSize = 40,
                        Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
                    };
                    var coverImg = new Image { Stretch = Stretch.Uniform };
                    coverBox.Children.Add(phIcon);
                    coverBox.Children.Add(coverImg);
                    if (!string.IsNullOrEmpty(detail.Item.Cover))
                        _ = WorkCardBuilder.LoadCoverIntoImageAsync(srcRec?.Manifest, detail.Item.Cover, coverImg, phIcon);
                    heroGrid.Children.Add(coverBox);

                    var rightCol = new StackPanel { Spacing = 14 };
                    // Full natural-wrapping serif title per DESIGN.md
                    rightCol.Children.Add(ParkKit.SerifHeader(detail.Item.Title, 26));

                    if (!string.IsNullOrEmpty(detail.Item.Subtitle))
                    {
                        rightCol.Children.Add(new TextBlock
                        {
                            Text = detail.Item.Subtitle,
                            FontFamily = ParkTheme.SansFont,
                            FontSize = 14,
                            Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
                            TextWrapping = TextWrapping.Wrap,
                        });
                    }

                    // Primary + Secondary Action Bar
                    var continueTarget = PlaybackResolver.Resolve(detail, recentHist, chProgress);
                    var actionRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };

                    var primaryLabel = detail.Item.MediaKind switch
                    {
                        "video" or "voice" => L.Tr("播放"),
                        "novel" => L.Tr("阅读"),
                        "article" => L.Tr("阅读"),
                        _ => L.Tr("阅读"),
                    };

                    actionRow.Children.Add(ParkKit.PrimaryButton(primaryLabel, "\uE768", () =>
                    {
                        OpenConsumptionView(detail, continueTarget.ChapterId, continueTarget.ChapterTitle, continueTarget.Page, continueTarget.PositionSeconds, hostWindow);
                    }));

                    var favBtn = ParkKit.TonalButton(L.Tr("收藏"), isFav ? "\uE735" : "\uE734", selected: isFav);
                    favBtn.Click += async (_, _) =>
                    {
                        isFav = !isFav;
                        await AppHost.Instance.Library.SetFavoriteAsync(detail.Item, isFav);
                        _ = LoadDetailAsync();
                    };
                    actionRow.Children.Add(favBtn);

                    if (srcRec?.Manifest.Capabilities.Chapter == true)
                    {
                        actionRow.Children.Add(ParkKit.TonalButton(L.Tr("下载"), "\uE896", onClick: async () =>
                        {
                            foreach (var ch in detail.EffectiveChapters)
                                await AppHost.Instance.Downloads.EnqueueAsync(detail.Item, ch.Id, ch.Title);
                        }));
                    }

                    if (!string.IsNullOrEmpty(detail.Url) && Uri.TryCreate(detail.Url, UriKind.Absolute, out var origUri))
                    {
                        actionRow.Children.Add(ParkKit.TonalButton("URL", "\uE8A7", onClick: () => _ = Launcher.LaunchUriAsync(origUri)));
                    }

                    rightCol.Children.Add(actionRow);

                    // Description
                    if (!string.IsNullOrWhiteSpace(detail.Description))
                    {
                        rightCol.Children.Add(new TextBlock
                        {
                            Text = detail.Description,
                            FontFamily = ParkTheme.SansFont,
                            FontSize = 13.5,
                            Foreground = ParkTheme.Brush(c.OnSurface),
                            TextWrapping = TextWrapping.Wrap,
                            IsTextSelectionEnabled = true,
                        });
                    }

                    // Namespaced ActionTags
                    foreach (var group in detail.TagGroups)
                    {
                        var tagRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
                        tagRow.Children.Add(new TextBlock
                        {
                            Text = $"{L.TranslatePlugin(srcRec?.Manifest.I18n, group.Label)}:",
                            FontSize = 12.5,
                            FontWeight = FontWeights.SemiBold,
                            Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
                            VerticalAlignment = VerticalAlignment.Center,
                        });

                        var wrap = new GridView { SelectionMode = ListViewSelectionMode.None, IsItemClickEnabled = false };
                        foreach (var tag in group.Tags.Take(24))
                        {
                            var capturedKw = tag.Keyword;
                            var chip = ParkKit.TonalButton(tag.Name, onClick: () => callbacks.SearchTagInSource?.Invoke(detail.Item.Source, capturedKw));
                            chip.MinHeight = 28;
                            chip.Padding = new Thickness(10, 3, 10, 3);
                            wrap.Items.Add(chip);
                        }
                        rightCol.Children.Add(tagRow);
                        rightCol.Children.Add(wrap);
                    }

                    Grid.SetColumn(rightCol, 1);
                    heroGrid.Children.Add(rightCol);
                    outer.Children.Add(heroGrid);

                    // Article Sequential Blocks (for type: 'article' feed posts)
                    if (detail.Blocks.Count > 0)
                    {
                        var articleStack = new StackPanel { Spacing = 14, MaxWidth = 820 };
                        foreach (var blk in detail.Blocks)
                        {
                            if (blk.Type == "text" && !string.IsNullOrWhiteSpace(blk.Text))
                            {
                                articleStack.Children.Add(new TextBlock
                                {
                                    Text = blk.Text,
                                    FontFamily = ParkTheme.SansFont,
                                    FontSize = 15,
                                    LineHeight = 26,
                                    Foreground = ParkTheme.Brush(c.OnSurface),
                                    TextWrapping = TextWrapping.Wrap,
                                    IsTextSelectionEnabled = true,
                                });
                            }
                            else if (blk.Type == "image" && !string.IsNullOrEmpty(blk.Url))
                            {
                                var blkImg = new Image { MaxHeight = 680, Stretch = Stretch.Uniform };
                                _ = WorkCardBuilder.LoadCoverIntoImageAsync(srcRec?.Manifest, blk.Url, blkImg);
                                articleStack.Children.Add(blkImg);
                            }
                        }
                        outer.Children.Add(articleStack);
                    }

                    // Chapters / Episodes List
                    if (detail.EffectiveChapters.Count > 0 && detail.Blocks.Count == 0)
                    {
                        var chRows = detail.EffectiveChapters.Select(ch =>
                        {
                            chProgress.TryGetValue(ch.Id, out var snap);
                            var rowGrid = new Grid();
                            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                            rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                            var titleLbl = new TextBlock
                            {
                                Text = snap?.Read == true ? $"✓ {ch.Title}" : ch.Title,
                                FontFamily = ParkTheme.SansFont,
                                Foreground = ParkTheme.Brush(snap?.Read == true ? c.OnSurfaceVariant : c.OnSurface),
                                VerticalAlignment = VerticalAlignment.Center,
                            };
                            rowGrid.Children.Add(titleLbl);

                            var capturedCh = ch;
                            var openChBtn = ParkKit.TonalButton(primaryLabel, "\uE768", onClick: () =>
                            {
                                OpenConsumptionView(detail, capturedCh.Id, capturedCh.Title, snap?.LastPage ?? 0, snap?.Position ?? 0, hostWindow);
                            });
                            Grid.SetColumn(openChBtn, 1);
                            rowGrid.Children.Add(openChBtn);
                            return (UIElement)rowGrid;
                        });
                        outer.Children.Add(ParkKit.RowGroupCard($"{detail.EffectiveChapters.Count}", chRows));
                    }

                    // Related Works Shelf
                    if (detail.Related.Count > 0)
                    {
                        var relScroll = new ScrollViewer
                        {
                            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
                        };
                        var relRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
                        foreach (var r in detail.Related.Where(w => !AppHost.Instance.CurrentBlockEngine.IsBlocked(w)))
                            relRow.Children.Add(WorkCardBuilder.CreateCard(r, callbacks, width: 162));
                        relScroll.Content = relRow;
                        outer.Children.Add(relScroll);
                    }

                    scroll.Content = outer;
                    stageHost.Children.Add(scroll);
                });
            }
            catch (Exception ex)
            {
                stageHost.DispatcherQueue.TryEnqueue(() =>
                {
                    stageHost.Children.Clear();
                    var retry = ParkKit.PrimaryButton(L.Tr("重试"), "\uE72C", () => _ = LoadDetailAsync());
                    stageHost.Children.Add(ParkKit.EmptyState("\uE783", ex.Message, initialWork.Source, retry));
                });
            }
        }

        _ = LoadDetailAsync();
        return stageHost;
    }

    private static void OpenConsumptionView(
        WorkDetail detail,
        string chapterId,
        string chapterTitle,
        int startPage,
        int startPositionSec,
        MainWindow hostWindow)
    {
        if (detail.Item.MediaKind == "novel")
        {
            hostWindow.NavigatePrimary(() => CreateNovelReaderView(detail, chapterId, chapterTitle, hostWindow));
        }
        else if (detail.Item.MediaKind is "video" or "voice")
        {
            hostWindow.NavigatePrimary(() => CreateMediaPlayerView(detail, chapterId, chapterTitle, startPositionSec, hostWindow));
        }
        else
        {
            hostWindow.NavigatePrimary(() => CreateComicReaderView(detail, chapterId, chapterTitle, startPage, hostWindow));
        }
    }

    public static FrameworkElement CreateComicReaderView(
        WorkDetail detail,
        string chapterId,
        string chapterTitle,
        int initialPage,
        MainWindow hostWindow)
    {
        var c = ParkTheme.Current;
        var srcManifest = AppHost.Instance.Sources.GetSource(detail.Item.Source)?.Manifest;
        var root = new Grid
        {
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 11, 10, 9)),
            IsTabStop = true,
        };

        var canvasHost = new Grid();
        root.Children.Add(canvasHost);

        // Eye-care warm / dim filter overlay (hit-test invisible)
        var filterOverlay = new Border
        {
            IsHitTestVisible = false,
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(
                (byte)Math.Round(AppSettings.Instance.ReaderWarm * 90), 255, 190, 110)),
        };
        root.Children.Add(filterOverlay);

        // Floating Acrylic ReaderChrome (never reflows underlying comic image!)
        var pageBadge = new TextBlock
        {
            Text = "…",
            FontFamily = ParkTheme.MonoFont,
            FontSize = 13,
            Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 236, 233, 227)),
            VerticalAlignment = VerticalAlignment.Center,
        };

        var dualMode = AppSettings.Instance.ReaderDual;
        var verticalMode = AppSettings.Instance.ReaderMode == ReaderPageMode.Vertical;
        var pages = new List<ChapterPage>();
        var currentIndex = Math.Max(0, initialPage);

        var chromeBar = new Border
        {
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(24, 0, 24, 22),
            Padding = new Thickness(18, 10, 18, 10),
            CornerRadius = new CornerRadius(18),
            Background = ParkTheme.Brush(c.ContainerHigh),
            BorderBrush = ParkTheme.Brush(c.OutlineVariant),
            BorderThickness = new Thickness(1),
        };

        var chromeStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        var prevBtn = ParkKit.TonalButton("←");
        var nextBtn = ParkKit.TonalButton("→");
        var dualBtn = ParkKit.TonalButton(L.Tr("双页并排"), selected: dualMode);
        var fullBtn = ParkKit.TonalButton("F11", "\uE740", onClick: () => NativeWindowHelper.ToggleFullScreen(hostWindow));

        chromeStack.Children.Add(prevBtn);
        chromeStack.Children.Add(pageBadge);
        chromeStack.Children.Add(nextBtn);
        chromeStack.Children.Add(dualBtn);
        chromeStack.Children.Add(fullBtn);
        chromeBar.Child = chromeStack;
        root.Children.Add(chromeBar);

        void RenderCurrentSpread()
        {
            if (pages.Count == 0) return;
            currentIndex = Math.Clamp(currentIndex, 0, pages.Count - 1);
            pageBadge.Text = $"{currentIndex + 1} / {pages.Count}";

            _ = AppHost.Instance.Library.RecordReadingProgressAsync(
                detail.Item, chapterId, chapterTitle, currentIndex, pages.Count, currentIndex >= pages.Count - 1);

            canvasHost.Children.Clear();
            if (verticalMode)
            {
                var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, ZoomMode = ZoomMode.Enabled };
                var sp = new StackPanel { Spacing = 4, MaxWidth = 980, HorizontalAlignment = HorizontalAlignment.Center };
                foreach (var p in pages)
                {
                    var img = new Image { Stretch = Stretch.Uniform, MinHeight = 320 };
                    if (!string.IsNullOrEmpty(p.Url))
                        _ = WorkCardBuilder.LoadCoverIntoImageAsync(srcManifest, p.Url, img);
                    sp.Children.Add(img);
                }
                sv.Content = sp;
                canvasHost.Children.Add(sv);
                return;
            }

            var showSingleCover = dualMode && AppSettings.Instance.ReaderCoverSingle && currentIndex == 0;
            if (!dualMode || showSingleCover || currentIndex + 1 >= pages.Count)
            {
                var sv = new ScrollViewer { ZoomMode = ZoomMode.Enabled, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                var img = new Image { Stretch = Stretch.Uniform };
                if (!string.IsNullOrEmpty(pages[currentIndex].Url))
                    _ = WorkCardBuilder.LoadCoverIntoImageAsync(srcManifest, pages[currentIndex].Url!, img);
                sv.Content = img;
                canvasHost.Children.Add(sv);
            }
            else
            {
                var spreadGrid = new Grid { ColumnSpacing = 4, HorizontalAlignment = HorizontalAlignment.Center };
                spreadGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                spreadGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                var rtl = AppSettings.Instance.ReaderMode == ReaderPageMode.RightToLeft;
                var leftPage = rtl ? pages[currentIndex + 1] : pages[currentIndex];
                var rightPage = rtl ? pages[currentIndex] : pages[currentIndex + 1];

                var leftImg = new Image { Stretch = Stretch.Uniform, HorizontalAlignment = HorizontalAlignment.Right };
                var rightImg = new Image { Stretch = Stretch.Uniform, HorizontalAlignment = HorizontalAlignment.Left };
                if (!string.IsNullOrEmpty(leftPage.Url)) _ = WorkCardBuilder.LoadCoverIntoImageAsync(srcManifest, leftPage.Url, leftImg);
                if (!string.IsNullOrEmpty(rightPage.Url)) _ = WorkCardBuilder.LoadCoverIntoImageAsync(srcManifest, rightPage.Url, rightImg);

                Grid.SetColumn(leftImg, 0);
                Grid.SetColumn(rightImg, 1);
                spreadGrid.Children.Add(leftImg);
                spreadGrid.Children.Add(rightImg);
                canvasHost.Children.Add(spreadGrid);
            }
        }

        void StepPages(int delta)
        {
            if (pages.Count == 0 || verticalMode) return;
            var stride = dualMode && !(AppSettings.Instance.ReaderCoverSingle && currentIndex == 0 && delta > 0) ? 2 : 1;
            currentIndex = Math.Clamp(currentIndex + delta * stride, 0, pages.Count - 1);
            RenderCurrentSpread();
        }

        prevBtn.Click += (_, _) => StepPages(-1);
        nextBtn.Click += (_, _) => StepPages(1);
        dualBtn.Click += (_, _) =>
        {
            dualMode = !dualMode;
            AppSettings.Instance.ReaderDual = dualMode;
            verticalMode = false;
            RenderCurrentSpread();
        };

        root.KeyDown += (_, e) =>
        {
            if (e.Key is VirtualKey.Right or VirtualKey.D or VirtualKey.Space) { e.Handled = true; StepPages(1); }
            else if (e.Key is VirtualKey.Left or VirtualKey.A) { e.Handled = true; StepPages(-1); }
            else if (e.Key == VirtualKey.F11) { e.Handled = true; NativeWindowHelper.ToggleFullScreen(hostWindow); }
        };

        canvasHost.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(canvasHost).Properties.IsLeftButtonPressed)
                chromeBar.Visibility = chromeBar.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
        };

        _ = Task.Run(async () =>
        {
            try
            {
                var loaded = await AppHost.Instance.Sources.FetchChapterPagesAsync(detail.Item.Source, detail.Item.Id, chapterId);
                root.DispatcherQueue.TryEnqueue(() =>
                {
                    pages.AddRange(loaded);
                    RenderCurrentSpread();
                    root.Focus(FocusState.Programmatic);
                });
            }
            catch (Exception ex)
            {
                root.DispatcherQueue.TryEnqueue(() =>
                {
                    canvasHost.Children.Add(ParkKit.EmptyState("\uE783", ex.Message, detail.Item.Title));
                });
            }
        });

        return root;
    }

    public static FrameworkElement CreateNovelReaderView(
        WorkDetail detail,
        string chapterId,
        string chapterTitle,
        MainWindow hostWindow)
    {
        var c = ParkTheme.Current;
        var twoCol = AppSettings.Instance.NovelTwoColumn;
        SpeechSynthesizer? synth = null;
        MediaPlayerElement? ttsAudioHost = new() { Width = 0, Height = 0, AutoPlay = true };

        var outer = new Grid { Padding = new Thickness(28, 16, 28, 20), RowSpacing = 14 };
        outer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        outer.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var toolbar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        var colToggle = ParkKit.TonalButton(twoCol ? L.Tr("双栏书页") : L.Tr("单栏限宽"), "\uE8FD");
        var ttsBtn = ParkKit.TonalButton(L.Tr("朗读本章"), "\uE767");
        toolbar.Children.Add(ParkKit.SerifHeader(chapterTitle, 20));
        toolbar.Children.Add(colToggle);
        toolbar.Children.Add(ttsBtn);
        toolbar.Children.Add(ttsAudioHost);
        outer.Children.Add(toolbar);

        var bodyHost = new Border
        {
            Background = ParkTheme.Brush(c.Card),
            BorderBrush = ParkTheme.Brush(c.OutlineVariant),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(14),
            Padding = new Thickness(32, 26, 32, 26),
        };
        Grid.SetRow(bodyHost, 1);
        outer.Children.Add(bodyHost);

        TextChapterData? loadedText = null;

        void RenderNovel()
        {
            if (loadedText is null) return;
            var fontSize = AppSettings.Instance.NovelFontSize;
            var font = AppSettings.Instance.NovelFont == "serif" ? ParkTheme.SerifFont : ParkTheme.SansFont;

            if (!twoCol || loadedText.Paragraphs.Count < 4)
            {
                var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                var sp = new StackPanel { Spacing = 14, MaxWidth = 720, HorizontalAlignment = HorizontalAlignment.Center };
                foreach (var para in loadedText.Paragraphs)
                {
                    sp.Children.Add(new TextBlock
                    {
                        Text = "　　" + para,
                        FontFamily = font,
                        FontSize = fontSize,
                        LineHeight = fontSize * 1.75,
                        Foreground = ParkTheme.Brush(c.OnSurface),
                        TextWrapping = TextWrapping.Wrap,
                        IsTextSelectionEnabled = true,
                    });
                }
                sv.Content = sp;
                bodyHost.Child = sv;
            }
            else
            {
                var half = (loadedText.Paragraphs.Count + 1) / 2;
                var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                var twoGrid = new Grid { ColumnSpacing = 40 };
                twoGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                twoGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                StackPanel MakeCol(IEnumerable<string> items)
                {
                    var col = new StackPanel { Spacing = 14 };
                    foreach (var p in items)
                    {
                        col.Children.Add(new TextBlock
                        {
                            Text = "　　" + p,
                            FontFamily = font,
                            FontSize = fontSize,
                            LineHeight = fontSize * 1.75,
                            Foreground = ParkTheme.Brush(c.OnSurface),
                            TextWrapping = TextWrapping.Wrap,
                            IsTextSelectionEnabled = true,
                        });
                    }
                    return col;
                }

                var left = MakeCol(loadedText.Paragraphs.Take(half));
                var right = MakeCol(loadedText.Paragraphs.Skip(half));
                Grid.SetColumn(left, 0);
                Grid.SetColumn(right, 1);
                twoGrid.Children.Add(left);
                twoGrid.Children.Add(right);
                sv.Content = twoGrid;
                bodyHost.Child = sv;
            }
        }

        colToggle.Click += (_, _) =>
        {
            twoCol = !twoCol;
            AppSettings.Instance.NovelTwoColumn = twoCol;
            RenderNovel();
        };

        ttsBtn.Click += async (_, _) =>
        {
            if (loadedText is null) return;
            if (synth is not null)
            {
                ttsAudioHost.MediaPlayer?.Pause();
                synth.Dispose();
                synth = null;
                return;
            }
            try
            {
                synth = new SpeechSynthesizer();
                var textSample = loadedText.FullText.Length > 4000 ? loadedText.FullText[..4000] : loadedText.FullText;
                var speechStream = await synth.SynthesizeTextToStreamAsync(textSample);
                ttsAudioHost.Source = MediaSource.CreateFromStream(speechStream, speechStream.ContentType);
            }
            catch { /* TTS voice unavailable on stripped OS */ }
        };

        outer.Unloaded += (_, _) => synth?.Dispose();

        _ = Task.Run(async () =>
        {
            try
            {
                var data = await AppHost.Instance.Sources.FetchNovelChapterAsync(detail.Item.Source, detail.Item.Id, chapterId);
                await AppHost.Instance.Library.RecordReadingProgressAsync(detail.Item, chapterId, chapterTitle, 0, data.FullText.Length, false);
                outer.DispatcherQueue.TryEnqueue(() =>
                {
                    loadedText = data;
                    RenderNovel();
                });
            }
            catch (Exception ex)
            {
                outer.DispatcherQueue.TryEnqueue(() =>
                {
                    bodyHost.Child = ParkKit.EmptyState("\uE783", ex.Message, chapterTitle);
                });
            }
        });

        return outer;
    }

    public static FrameworkElement CreateMediaPlayerView(
        WorkDetail detail,
        string episodeId,
        string episodeTitle,
        int startPositionSec,
        MainWindow hostWindow)
    {
        var c = ParkTheme.Current;
        var rootGrid = new Grid { ColumnSpacing = 18, Padding = new Thickness(20, 14, 20, 20), IsTabStop = true };
        rootGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        rootGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(280) });

        var stageCol = new Grid { RowSpacing = 12 };
        stageCol.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        stageCol.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var playerElement = new MediaPlayerElement
        {
            AreTransportControlsEnabled = true,
            AutoPlay = true,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch,
        };

        var videoFrame = new Border
        {
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0, 0, 0)),
            CornerRadius = new CornerRadius(12),
            Child = playerElement,
        };
        stageCol.Children.Add(videoFrame);

        var controlsBar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        controlsBar.Children.Add(ParkKit.SerifHeader($"{detail.Item.Title} · {episodeTitle}", 18));

        var pipBtn = ParkKit.TonalButton(L.Tr("置顶画中画"), "\uE8A7", onClick: () => NativeWindowHelper.ToggleCompactOverlay(hostWindow));
        var theaterBtn = ParkKit.TonalButton(L.Tr("剧场宽屏"), "\uE740", onClick: () =>
        {
            rootGrid.ColumnDefinitions[1].Width = rootGrid.ColumnDefinitions[1].Width.Value > 0
                ? new GridLength(0)
                : new GridLength(280);
        });
        controlsBar.Children.Add(pipBtn);
        controlsBar.Children.Add(theaterBtn);
        Grid.SetRow(controlsBar, 1);
        stageCol.Children.Add(controlsBar);
        rootGrid.Children.Add(stageCol);

        // Right Episode Sidebar
        var epRows = detail.EffectiveChapters.Select(ep =>
        {
            var captured = ep;
            return (UIElement)ParkKit.TonalButton(
                ep.Title,
                selected: ep.Id == episodeId,
                onClick: () => hostWindow.NavigatePrimary(() => CreateMediaPlayerView(detail, captured.Id, captured.Title, 0, hostWindow), recordHistory: false));
        });
        var epSidebar = new ScrollViewer { Content = ParkKit.RowGroupCard(L.Tr("播放"), epRows) };
        Grid.SetColumn(epSidebar, 1);
        rootGrid.Children.Add(epSidebar);

        string? activeMediaToken = null;
        double savedPlaybackRate = 1.0;

        // Desktop video shortcuts: Space/K play/pause, Left/Right 10s seek, Up/Down 5% volume, M mute, F fullscreen, Hold Right/Pointer 2x speed
        rootGrid.KeyDown += (_, e) =>
        {
            var mp = playerElement.MediaPlayer;
            if (mp is null) return;
            switch (e.Key)
            {
                case VirtualKey.Space or VirtualKey.K:
                    e.Handled = true;
                    if (mp.PlaybackSession.PlaybackState == Windows.Media.Playback.MediaPlaybackState.Playing) mp.Pause();
                    else mp.Play();
                    break;
                case VirtualKey.Right:
                    e.Handled = true;
                    mp.PlaybackSession.Position += TimeSpan.FromSeconds(10);
                    break;
                case VirtualKey.Left:
                    e.Handled = true;
                    var nextPos = mp.PlaybackSession.Position - TimeSpan.FromSeconds(10);
                    mp.PlaybackSession.Position = nextPos < TimeSpan.Zero ? TimeSpan.Zero : nextPos;
                    break;
                case VirtualKey.Up:
                    e.Handled = true;
                    mp.Volume = Math.Clamp(mp.Volume + 0.05, 0.0, 1.0);
                    break;
                case VirtualKey.Down:
                    e.Handled = true;
                    mp.Volume = Math.Clamp(mp.Volume - 0.05, 0.0, 1.0);
                    break;
                case VirtualKey.M:
                    e.Handled = true;
                    mp.IsMuted = !mp.IsMuted;
                    break;
                case VirtualKey.F:
                    e.Handled = true;
                    NativeWindowHelper.ToggleFullScreen(hostWindow);
                    break;
            }
        };

        videoFrame.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(videoFrame).Properties.IsRightButtonPressed && playerElement.MediaPlayer is { } mp)
            {
                savedPlaybackRate = mp.PlaybackSession.PlaybackRate;
                mp.PlaybackSession.PlaybackRate = 2.0;
            }
        };
        videoFrame.PointerReleased += (_, _) =>
        {
            if (playerElement.MediaPlayer is { } mp && Math.Abs(mp.PlaybackSession.PlaybackRate - 2.0) < 0.01)
                mp.PlaybackSession.PlaybackRate = savedPlaybackRate;
        };

        rootGrid.Unloaded += (_, _) =>
        {
            if (playerElement.MediaPlayer is { } mp)
            {
                var posSec = (int)mp.PlaybackSession.Position.TotalSeconds;
                var durSec = (int)mp.PlaybackSession.NaturalDuration.TotalSeconds;
                _ = AppHost.Instance.Library.RecordPlaybackPositionAsync(detail.Item, episodeId, episodeTitle, posSec, durSec, false);
                mp.Pause();
            }
            playerElement.Source = null;
            if (activeMediaToken is not null)
                AppHost.Instance.MediaProxy.RevokeSession(activeMediaToken);
        };

        _ = Task.Run(async () =>
        {
            try
            {
                var streams = await AppHost.Instance.Sources.FetchVideosAsync(detail.Item.Source, detail.Item.Id, episodeId);
                var chosen = streams.FirstOrDefault(s => s.Preferred) ?? streams.OrderByDescending(s => s.Quality).FirstOrDefault();
                if (chosen is null || !Uri.TryCreate(chosen.Url, UriKind.Absolute, out var upUri)) return;

                var reg = AppHost.Instance.MediaProxy.RegisterSession(upUri, chosen.Headers, chosen.Format);
                activeMediaToken = reg.SessionId;

                rootGrid.DispatcherQueue.TryEnqueue(() =>
                {
                    playerElement.Source = MediaSource.CreateFromUri(reg.LocalPlaybackUri);
                    if (startPositionSec > 0 && playerElement.MediaPlayer is { } mp)
                        mp.PlaybackSession.Position = TimeSpan.FromSeconds(startPositionSec);
                    rootGrid.Focus(FocusState.Programmatic);
                });
            }
            catch
            {
                // Error logged via AppLog inside SourceManager
            }
        });

        return rootGrid;
    }
}
