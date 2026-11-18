using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Park.Core.Configuration;
using Park.Core.Localization;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace Park.App.Theme;

public sealed record ParkColorScheme(
    bool IsDark,
    Color Surface,
    Color Workspace,
    Color Card,
    Color ContainerHigh,
    Color ContainerHighest,
    Color OnSurface,
    Color OnSurfaceVariant,
    Color Outline,
    Color OutlineVariant,
    Color Primary,
    Color OnPrimary,
    Color SecondaryContainer,
    Color OnSecondaryContainer,
    Color Error,
    Color OnError);

/// <summary>
/// Park Fluent Editorial token engine aligned with lib/ui/theme.dart &amp; docs/design/WINDOWS.md:
/// - Warm neutral surfaces so covers carry the color
/// - WCAG AA (4.5:1) contrast calibration for all 6 preset accents + Windows system accent
/// - Dual-voice typography (Segoe UI Variable + script-matched CJK sans vs ParkSerif reading voice)
/// </summary>
public static class ParkTheme
{
    public static ParkColorScheme Current => BuildScheme(IsEffectiveDark(), ResolveSeedColor());

    public static bool IsEffectiveDark()
    {
        var mode = AppSettings.Instance.ThemeMode;
        if (mode == "light") return false;
        if (mode == "dark") return true;
        try
        {
            var ui = new UISettings();
            var bg = ui.GetColorValue(UIColorType.Background);
            return (bg.R + bg.G + bg.B) < 382;
        }
        catch
        {
            return true;
        }
    }

    public static Color ResolveSeedColor()
    {
        if (AppSettings.Instance.UseSystemAccent)
        {
            try
            {
                return new UISettings().GetColorValue(UIColorType.Accent);
            }
            catch { /* fallback */ }
        }
        var argb = AppSettings.Instance.SeedColor;
        return Color.FromArgb(
            255,
            (byte)((argb >> 16) & 0xFF),
            (byte)((argb >> 8) & 0xFF),
            (byte)(argb & 0xFF));
    }

    public static ParkColorScheme BuildScheme(bool dark, Color accent)
    {
        var primary = dark && accent == Color.FromArgb(255, 0xC9, 0x64, 0x42)
            ? Color.FromArgb(255, 0xD9, 0x77, 0x57)
            : (dark ? AdjustLightness(accent, 0.08) : accent);

        var textSurface = dark ? Hex(0x34322E) : Hex(0xDCD8D0);
        for (var i = 0; i < 100 && ContrastRatio(primary, textSurface) < 4.5; i++)
        {
            primary = AdjustLightness(primary, dark ? 0.01 : -0.01);
        }

        var white = Hex(0xFFFFFF);
        var deep = Hex(0x1A1714);
        var onPrimary = ContrastRatio(white, primary) >= ContrastRatio(deep, primary) ? white : deep;
        for (var i = 0; i < 20 && ContrastRatio(onPrimary, primary) < 4.5; i++)
        {
            primary = AdjustLightness(primary, onPrimary == white ? -0.02 : 0.02);
        }

        if (dark)
        {
            return new ParkColorScheme(
                IsDark: true,
                Surface: Hex(0x11100F),
                Workspace: Hex(0x181715),
                Card: Hex(0x1E1D1A),
                ContainerHigh: Hex(0x272522),
                ContainerHighest: Hex(0x312F2B),
                OnSurface: Hex(0xECE9E3),
                OnSurfaceVariant: Hex(0xA39E94),
                Outline: Hex(0x827C72),
                OutlineVariant: Hex(0x34322E),
                Primary: primary,
                OnPrimary: onPrimary,
                SecondaryContainer: AlphaBlend(primary, 0.18, Hex(0x1C1B19)),
                OnSecondaryContainer: AdjustLightness(primary, 0.16),
                Error: Hex(0xF08A84),
                OnError: Hex(0x2B0B09));
        }

        return new ParkColorScheme(
            IsDark: false,
            Surface: Hex(0xF5F3EF),
            Workspace: Hex(0xFAF9F6),
            Card: Hex(0xFFFFFF),
            ContainerHigh: Hex(0xEAE7E1),
            ContainerHighest: Hex(0xDCD8D0),
            OnSurface: Hex(0x1F1E1C),
            OnSurfaceVariant: Hex(0x625E57),
            Outline: Hex(0x827C72),
            OutlineVariant: Hex(0xE0DCD4),
            Primary: primary,
            OnPrimary: onPrimary,
            SecondaryContainer: AlphaBlend(primary, 0.14, Hex(0xF5F3EF)),
            OnSecondaryContainer: AdjustLightness(primary, -0.14),
            Error: Hex(0xB3261E),
            OnError: Hex(0xFFFFFF));
    }

    public static FontFamily SansFont => new(L.CurrentLocale switch
    {
        "ja" => "Segoe UI Variable, Yu Gothic UI, Microsoft YaHei UI",
        "ko" => "Segoe UI Variable, Malgun Gothic, Microsoft YaHei UI",
        "zh-Hant" => "Segoe UI Variable, Microsoft JhengHei UI, Microsoft YaHei UI",
        _ => "Segoe UI Variable, Microsoft YaHei UI",
    });

    public static FontFamily SerifFont => new(L.CurrentLocale switch
    {
        "ja" => "Source Han Serif JP, Noto Serif CJK JP, Yu Mincho, Georgia",
        "ko" => "Source Han Serif KR, Noto Serif CJK KR, Batang, Georgia",
        "zh-Hant" => "Source Han Serif TC, Noto Serif CJK TC, PMingLiU, Georgia",
        _ => "Source Han Serif SC, Noto Serif CJK SC, Georgia, SimSun",
    });

    public static FontFamily MonoFont => new("Cascadia Mono, Consolas, Courier New");

    public static SolidColorBrush Brush(Color c) => new(c);

    public static Color ParseHexColor(string? hex, Color fallback)
    {
        if (string.IsNullOrWhiteSpace(hex)) return fallback;
        var clean = hex.Trim().TrimStart('#');
        if (clean.Length == 6 && uint.TryParse(clean, System.Globalization.NumberStyles.HexNumber, null, out var rgb))
        {
            return Hex(rgb);
        }
        return fallback;
    }

    public static Color Hex(uint rgb) => Color.FromArgb(
        255,
        (byte)((rgb >> 16) & 0xFF),
        (byte)((rgb >> 8) & 0xFF),
        (byte)(rgb & 0xFF));

    private static Color AlphaBlend(Color fg, double alpha, Color bg) => Color.FromArgb(
        255,
        (byte)Math.Clamp(Math.Round(fg.R * alpha + bg.R * (1 - alpha)), 0, 255),
        (byte)Math.Clamp(Math.Round(fg.G * alpha + bg.G * (1 - alpha)), 0, 255),
        (byte)Math.Clamp(Math.Round(fg.B * alpha + bg.B * (1 - alpha)), 0, 255));

    private static double RelativeLuminance(Color c)
    {
        static double Channel(byte v)
        {
            var s = v / 255.0;
            return s <= 0.03928 ? s / 12.92 : Math.Pow((s + 0.055) / 1.055, 2.4);
        }
        return 0.2126 * Channel(c.R) + 0.7152 * Channel(c.G) + 0.0722 * Channel(c.B);
    }

    private static double ContrastRatio(Color a, Color b)
    {
        var la = RelativeLuminance(a);
        var lb = RelativeLuminance(b);
        return (Math.Max(la, lb) + 0.05) / (Math.Min(la, lb) + 0.05);
    }

    private static Color AdjustLightness(Color c, double delta)
    {
        double r = c.R / 255.0, g = c.G / 255.0, b = c.B / 255.0;
        double max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b));
        double h = 0, s = 0, l = (max + min) / 2.0;

        if (Math.Abs(max - min) > 1e-6)
        {
            var d = max - min;
            s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min);
            if (Math.Abs(max - r) < 1e-6) h = (g - b) / d + (g < b ? 6 : 0);
            else if (Math.Abs(max - g) < 1e-6) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6.0;
        }

        l = Math.Clamp(l + delta, 0.0, 1.0);
        if (s == 0)
        {
            var gray = (byte)Math.Round(l * 255);
            return Color.FromArgb(255, gray, gray, gray);
        }

        static double Hue2Rgb(double p, double q, double t)
        {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
            if (t < 1.0 / 2.0) return q;
            if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
            return p;
        }

        var qv = l < 0.5 ? l * (1 + s) : l + s - l * s;
        var pv = 2 * l - qv;
        return Color.FromArgb(
            255,
            (byte)Math.Round(Hue2Rgb(pv, qv, h + 1.0 / 3.0) * 255),
            (byte)Math.Round(Hue2Rgb(pv, qv, h) * 255),
            (byte)Math.Round(Hue2Rgb(pv, qv, h - 1.0 / 3.0) * 255));
    }
}

public static class ParkKit
{
    public static TextBlock SerifHeader(string text, double size = 26) => new()
    {
        Text = text,
        FontFamily = ParkTheme.SerifFont,
        FontSize = size,
        FontWeight = FontWeights.SemiBold,
        Foreground = ParkTheme.Brush(ParkTheme.Current.OnSurface),
        TextWrapping = TextWrapping.Wrap,
    };

    public static Button PrimaryButton(string label, string? glyph = null, Action? onClick = null)
    {
        var c = ParkTheme.Current;
        var sp = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        if (!string.IsNullOrEmpty(glyph))
            sp.Children.Add(new FontIcon { Glyph = glyph, FontSize = 14, Foreground = ParkTheme.Brush(c.OnPrimary) });
        sp.Children.Add(new TextBlock
        {
            Text = label,
            FontFamily = ParkTheme.SansFont,
            FontWeight = FontWeights.SemiBold,
            Foreground = ParkTheme.Brush(c.OnPrimary),
        });

        var btn = new Button
        {
            Content = sp,
            Background = ParkTheme.Brush(c.Primary),
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(18, 8, 18, 8),
            MinHeight = 36,
        };
        if (onClick is not null) btn.Click += (_, _) => onClick();
        return btn;
    }

    public static Button TonalButton(string label, string? glyph = null, bool selected = false, Action? onClick = null)
    {
        var c = ParkTheme.Current;
        var fg = selected ? c.OnSecondaryContainer : c.OnSurface;
        var bg = selected ? c.SecondaryContainer : c.ContainerHighest;

        var sp = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        if (!string.IsNullOrEmpty(glyph))
            sp.Children.Add(new FontIcon { Glyph = glyph, FontSize = 14, Foreground = ParkTheme.Brush(fg) });
        sp.Children.Add(new TextBlock
        {
            Text = label,
            FontFamily = ParkTheme.SansFont,
            FontWeight = selected ? FontWeights.SemiBold : FontWeights.Medium,
            Foreground = ParkTheme.Brush(fg),
        });

        var btn = new Button
        {
            Content = sp,
            Background = ParkTheme.Brush(bg),
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(14, 7, 14, 7),
            MinHeight = 34,
        };
        if (onClick is not null) btn.Click += (_, _) => onClick();
        return btn;
    }

    public static Border RowGroupCard(string? sectionTitle, IEnumerable<UIElement> rows, string? footer = null)
    {
        var c = ParkTheme.Current;
        var outer = new StackPanel { Spacing = 8 };
        if (!string.IsNullOrEmpty(sectionTitle))
        {
            outer.Children.Add(new TextBlock
            {
                Text = sectionTitle,
                FontFamily = ParkTheme.SansFont,
                FontSize = 13,
                FontWeight = FontWeights.SemiBold,
                Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
                Margin = new Thickness(4, 0, 0, 2),
            });
        }

        var cardStack = new StackPanel();
        var list = rows.ToList();
        for (var i = 0; i < list.Count; i++)
        {
            if (i > 0)
            {
                cardStack.Children.Add(new Border
                {
                    Height = 1,
                    Background = ParkTheme.Brush(c.OutlineVariant),
                    Margin = new Thickness(16, 0, 16, 0),
                });
            }
            cardStack.Children.Add(new Border
            {
                Padding = new Thickness(16, 12, 16, 12),
                Child = list[i],
            });
        }

        var card = new Border
        {
            Background = ParkTheme.Brush(c.Card),
            BorderBrush = ParkTheme.Brush(c.OutlineVariant),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            Child = cardStack,
        };
        outer.Children.Add(card);

        if (!string.IsNullOrEmpty(footer))
        {
            outer.Children.Add(new TextBlock
            {
                Text = footer,
                FontFamily = ParkTheme.SansFont,
                FontSize = 12,
                Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(4, 0, 4, 0),
            });
        }

        return new Border { Child = outer };
    }

    public static Border EmptyState(string iconGlyph, string title, string subtitle, Button? action = null)
    {
        var c = ParkTheme.Current;
        var sp = new StackPanel
        {
            Spacing = 12,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            MaxWidth = 440,
            Padding = new Thickness(24),
        };
        sp.Children.Add(new Border
        {
            Width = 56,
            Height = 56,
            CornerRadius = new CornerRadius(28),
            Background = ParkTheme.Brush(c.ContainerHigh),
            HorizontalAlignment = HorizontalAlignment.Center,
            Child = new FontIcon
            {
                Glyph = iconGlyph,
                FontSize = 24,
                Foreground = ParkTheme.Brush(c.Primary),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        });
        sp.Children.Add(new TextBlock
        {
            Text = title,
            FontFamily = ParkTheme.SerifFont,
            FontSize = 20,
            FontWeight = FontWeights.SemiBold,
            Foreground = ParkTheme.Brush(c.OnSurface),
            HorizontalAlignment = HorizontalAlignment.Center,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        });
        sp.Children.Add(new TextBlock
        {
            Text = subtitle,
            FontFamily = ParkTheme.SansFont,
            FontSize = 13,
            Foreground = ParkTheme.Brush(c.OnSurfaceVariant),
            HorizontalAlignment = HorizontalAlignment.Center,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        });
        if (action is not null)
        {
            action.HorizontalAlignment = HorizontalAlignment.Center;
            sp.Children.Add(action);
        }
        return new Border { Child = sp, Padding = new Thickness(0, 32, 0, 32) };
    }

    /// <summary>
    /// Semantic placeholder glyph per DESIGN.md (never use broken-image icon when cover is absent):
    /// Audio -> Headphones, Novel/Comic -> Book, Game -> Controller, Video -> Film, Article -> Document.
    /// </summary>
    public static string MediaSemanticGlyph(string? mediaKind) => mediaKind switch
    {
        "voice" => "\uE7F6",   // Headphones
        "video" => "\uE714",   // Video film
        "game" => "\uE7FC",    // Gamepad
        "article" => "\uE8A5", // Document
        _ => "\uE736",         // Book / Reading
    };
}
