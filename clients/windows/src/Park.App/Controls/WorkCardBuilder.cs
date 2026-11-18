using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Input;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Park.App.Services;
using Park.App.Theme;
using Park.Core.Configuration;
using Park.Core.Localization;
using Park.Core.Models;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Streams;
using Windows.System;
using Windows.UI.Core;

namespace Park.App.Controls;

public sealed record WorkNavigationCallbacks(
    Action<WorkItem, bool> OpenWork,
    Action<WorkItem> OpenInNewWindow,
    Action<string, string>? SearchTagInSource = null);

public static class WorkCardBuilder
{
    public static FrameworkElement CreateCard(WorkItem item, WorkNavigationCallbacks callbacks, double width = 186)
    {
        var c = ParkTheme.Current;
        var srcManifest = AppHost.Instance.Sources.GetSource(item.Source)?.Manifest;
        var isLive = srcManifest?.Category == "live";

        var coverHost = new Grid
        {
            Width = width,
            Height = isLive ? Math.Round(width * 0.58) : Math.Round(width * 1.36),
            Background = ParkTheme.Brush(c.ContainerHigh),
            CornerRadius = new CornerRadius(10),
            BorderBrush = ParkTheme.Brush(c.OutlineVariant),
            BorderThickness = new Thickness(1),
        };

        // Semantic icon placeholder per DESIGN.md (never broken-image icon)
        var placeholderIcon = new FontIcon
        {
            Glyph = ParkKit.MediaSemanticGlyph(item.MediaKind),
            FontSize = 28,
            Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        coverHost.Children.Add(placeholderIcon);

        var img = new Image
        {
            Stretch = Stretch.Uniform,
            Opacity = (AppSettings.Instance.BlurCovers || item.CoverBlurred) ? 0.18 : 1.0,
        };
        coverHost.Children.Add(img);

        if (!string.IsNullOrEmpty(item.Cover))
        {
            _ = LoadCoverIntoImageAsync(srcManifest, item.Cover, img, placeholderIcon);
        }

        // Single badge layer on cover per ANDROID.md / WINDOWS.md (omitted on live cards)
        if (!isLive && (!string.IsNullOrEmpty(item.Language) || !string.IsNullOrEmpty(item.Badge)))
        {
            var badgeText = !string.IsNullOrEmpty(item.Language) ? item.Language.ToUpperInvariant() : item.Badge;
            coverHost.Children.Add(new Border
            {
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(8),
                Padding = new Thickness(6, 2, 6, 2),
                CornerRadius = new CornerRadius(6),
                Background = new SolidColorBrush(Windows.UI.Color.FromArgb(185, 17, 16, 15)),
                Child = new TextBlock
                {
                    Text = badgeText,
                    FontFamily = ParkTheme.SansFont,
                    FontSize = 11,
                    FontWeight = FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 245, 243, 239)),
                },
            });
        }

        var rootStack = new StackPanel { Width = width, Spacing = 6 };
        rootStack.Children.Add(coverHost);

        // Live cards only show cover per DESIGN.md
        if (!isLive)
        {
            rootStack.Children.Add(new TextBlock
            {
                Text = item.Title,
                FontFamily = ParkTheme.SansFont,
                FontSize = 13,
                FontWeight = FontWeights.SemiBold,
                Foreground = ParkTheme.Brush(c.OnSurface),
                MaxLines = 2,
                TextTrimming = TextTrimming.CharacterEllipsis,
                TextWrapping = TextWrapping.Wrap,
            });

            var metaParts = new List<string>();
            if (srcManifest is not null) metaParts.Add(srcManifest.Name);
            if (item.Pages is > 0) metaParts.Add(L.Tr("{count} 页", new Dictionary<string, object?> { ["count"] = item.Pages }));
            if (!string.IsNullOrEmpty(item.Duration)) metaParts.Add(item.Duration);
            if (!string.IsNullOrEmpty(item.WorkCode)) metaParts.Add(item.WorkCode);

            if (metaParts.Count > 0)
            {
                rootStack.Children.Add(new TextBlock
                {
                    Text = string.Join(" · ", metaParts),
                    FontFamily = ParkTheme.SansFont,
                    FontSize = 11.5,
                    Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
                    TextWrapping = TextWrapping.Wrap,
                });
            }
        }

        var interactiveBorder = new Border
        {
            Padding = new Thickness(6),
            CornerRadius = new CornerRadius(12),
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0)),
            Child = rootStack,
            ContextFlyout = BuildContextMenu(item, callbacks),
        };

        ToolTipService.SetToolTip(interactiveBorder, item.Title);

        interactiveBorder.PointerEntered += (_, _) =>
        {
            interactiveBorder.Background = ParkTheme.Brush(c.ContainerHigh);
        };
        interactiveBorder.PointerExited += (_, _) =>
        {
            interactiveBorder.Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0));
        };
        interactiveBorder.PointerPressed += (_, e) =>
        {
            var props = e.GetCurrentPoint(interactiveBorder).Properties;
            if (props.IsMiddleButtonPressed)
            {
                e.Handled = true;
                callbacks.OpenWork(item, true);
            }
            else if (props.IsLeftButtonPressed)
            {
                var ctrlDown = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control).HasFlag(CoreVirtualKeyStates.Down);
                e.Handled = true;
                callbacks.OpenWork(item, ctrlDown);
            }
        };

        return interactiveBorder;
    }

    public static FrameworkElement CreateListRow(WorkItem item, WorkNavigationCallbacks callbacks)
    {
        var c = ParkTheme.Current;
        var srcManifest = AppHost.Instance.Sources.GetSource(item.Source)?.Manifest;
        var noCoverTextList = item.MediaKind == "novel" && string.IsNullOrEmpty(item.Cover);

        var grid = new Grid { ColumnSpacing = 14, Padding = new Thickness(12, 10, 12, 10) };
        if (!noCoverTextList)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(72) });
        }
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var textCol = 0;
        if (!noCoverTextList)
        {
            textCol = 1;
            var thumbBox = new Grid
            {
                Width = 72,
                Height = 98,
                CornerRadius = new CornerRadius(8),
                Background = ParkTheme.Brush(c.ContainerHigh),
                BorderBrush = ParkTheme.Brush(c.OutlineVariant),
                BorderThickness = new Thickness(1),
            };
            var icon = new FontIcon
            {
                Glyph = ParkKit.MediaSemanticGlyph(item.MediaKind),
                FontSize = 20,
                Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
            };
            var img = new Image
            {
                Stretch = Stretch.Uniform,
                Opacity = (AppSettings.Instance.BlurCovers || item.CoverBlurred) ? 0.18 : 1.0,
            };
            thumbBox.Children.Add(icon);
            thumbBox.Children.Add(img);
            if (!string.IsNullOrEmpty(item.Cover))
                _ = LoadCoverIntoImageAsync(srcManifest, item.Cover, img, icon);

            Grid.SetColumn(thumbBox, 0);
            grid.Children.Add(thumbBox);
        }

        var info = new StackPanel { Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
        info.Children.Add(new TextBlock
        {
            Text = item.Title,
            FontFamily = item.MediaKind is "article" or "novel" ? ParkTheme.SerifFont : ParkTheme.SansFont,
            FontSize = 15,
            FontWeight = FontWeights.SemiBold,
            Foreground = ParkTheme.Brush(c.OnSurface),
            TextWrapping = TextWrapping.Wrap,
        });

        if (!string.IsNullOrEmpty(item.Subtitle))
        {
            info.Children.Add(new TextBlock
            {
                Text = item.Subtitle,
                FontFamily = ParkTheme.SansFont,
                FontSize = 12.5,
                Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
                MaxLines = 2,
                TextTrimming = TextTrimming.CharacterEllipsis,
                TextWrapping = TextWrapping.Wrap,
            });
        }

        var meta = new List<string>();
        if (srcManifest is not null) meta.Add(srcManifest.Name);
        if (!string.IsNullOrEmpty(item.Language)) meta.Add(item.Language);
        if (item.Authors.Count > 0) meta.Add(string.Join(", ", item.Authors));
        if (item.Pages is > 0) meta.Add(L.Tr("{count} 页", new Dictionary<string, object?> { ["count"] = item.Pages }));
        if (!string.IsNullOrEmpty(item.Duration)) meta.Add(item.Duration);
        if (item.Rating is > 0) meta.Add(L.Tr("评分 {rating}", new Dictionary<string, object?> { ["rating"] = $"{item.Rating:F1}" }));
        if (!string.IsNullOrEmpty(item.Uploaded)) meta.Add(item.Uploaded);

        if (meta.Count > 0)
        {
            info.Children.Add(new TextBlock
            {
                Text = string.Join(" · ", meta),
                FontFamily = ParkTheme.SansFont,
                FontSize = 12,
                Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
                TextWrapping = TextWrapping.Wrap,
            });
        }

        Grid.SetColumn(info, textCol);
        grid.Children.Add(info);

        var rowCard = new Border
        {
            Background = ParkTheme.Brush(c.Card),
            BorderBrush = ParkTheme.Brush(c.OutlineVariant),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            Child = grid,
            ContextFlyout = BuildContextMenu(item, callbacks),
        };

        rowCard.PointerEntered += (_, _) => rowCard.Background = ParkTheme.Brush(c.ContainerHigh);
        rowCard.PointerExited += (_, _) => rowCard.Background = ParkTheme.Brush(c.Card);
        rowCard.PointerPressed += (_, e) =>
        {
            var props = e.GetCurrentPoint(rowCard).Properties;
            if (props.IsMiddleButtonPressed)
            {
                e.Handled = true;
                callbacks.OpenWork(item, true);
            }
            else if (props.IsLeftButtonPressed)
            {
                var ctrlDown = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control).HasFlag(CoreVirtualKeyStates.Down);
                e.Handled = true;
                callbacks.OpenWork(item, ctrlDown);
            }
        };

        return rowCard;
    }

    public static async Task LoadCoverIntoImageAsync(SourceManifest? source, string url, Image targetImage, UIElement? placeholderToHide = null)
    {
        try
        {
            var bytes = await AppHost.Instance.Images.FetchImageBytesAsync(source, url);
            using var stream = new InMemoryRandomAccessStream();
            await stream.WriteAsync(bytes.AsBuffer());
            stream.Seek(0);

            var bmp = new BitmapImage();
            await bmp.SetSourceAsync(stream);
            targetImage.Source = bmp;
            if (placeholderToHide is not null)
                placeholderToHide.Visibility = Visibility.Collapsed;
        }
        catch
        {
            // Keep clean semantic icon placeholder on failure
        }
    }

    private static MenuFlyout BuildContextMenu(WorkItem item, WorkNavigationCallbacks callbacks)
    {
        var menu = new MenuFlyout();

        var openTab = new MenuFlyoutItem
        {
            Text = L.Tr("在新标签页中打开"),
            Icon = new FontIcon { Glyph = "\uE8A7" },
        };
        openTab.Click += (_, _) => callbacks.OpenWork(item, true);
        menu.Items.Add(openTab);

        var openWin = new MenuFlyoutItem
        {
            Text = L.Tr("在独立窗口中打开"),
            Icon = new FontIcon { Glyph = "\uE78B" },
        };
        openWin.Click += (_, _) => callbacks.OpenInNewWindow(item);
        menu.Items.Add(openWin);

        menu.Items.Add(new MenuFlyoutSeparator());

        var favItem = new MenuFlyoutItem
        {
            Text = L.Tr("收藏"),
            Icon = new FontIcon { Glyph = "\uE734" },
        };
        favItem.Click += async (_, _) =>
        {
            var isFav = await AppHost.Instance.Library.IsFavoriteAsync(item.Source, item.Id);
            await AppHost.Instance.Library.SetFavoriteAsync(item, !isFav);
        };
        menu.Items.Add(favItem);

        var copyId = new MenuFlyoutItem
        {
            Text = L.Tr("复制"),
            Icon = new FontIcon { Glyph = "\uE8C8" },
        };
        copyId.Click += (_, _) =>
        {
            var pkg = new DataPackage();
            pkg.SetText(item.WorkCode ?? item.Title);
            Clipboard.SetContent(pkg);
        };
        menu.Items.Add(copyId);

        return menu;
    }
}
