using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Graphics;
using Windows.Security.Credentials.UI;
using WinRT.Interop;

namespace Park.App.Interop;

public static partial class NativeWindowHelper
{
    private const uint WDA_NONE = 0x00000000;
    private const uint WDA_EXCLUDEFROMCAPTURE = 0x00000011;

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetWindowDisplayAffinity(nint hWnd, uint dwAffinity);

    public static nint GetHwnd(Window window) => WindowNative.GetWindowHandle(window);

    public static AppWindow GetAppWindow(Window window)
    {
        var hwnd = GetHwnd(window);
        var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
        return AppWindow.GetFromWindowId(windowId);
    }

    /// <summary>
    /// Hardware-level anti-screenshot / screen-recording protection (Windows 10 2004+ / Windows 11).
    /// Equivalent to Android WindowManager.LayoutParams.FLAG_SECURE.
    /// </summary>
    public static bool ApplySecureScreen(Window window, bool enabled)
    {
        var hwnd = GetHwnd(window);
        if (hwnd == 0) return false;
        return SetWindowDisplayAffinity(hwnd, enabled ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE);
    }

    public static void ConfigureCustomTitleBar(Window window, UIElement customTitleBarElement, bool isDark)
    {
        var appWindow = GetAppWindow(window);
        if (!AppWindowTitleBar.IsCustomizationSupported()) return;

        window.ExtendsContentIntoTitleBar = true;
        window.SetTitleBar(customTitleBarElement);

        var titleBar = appWindow.TitleBar;
        titleBar.ExtendsContentIntoTitleBar = true;
        titleBar.PreferredHeightOption = TitleBarHeightOption.Tall;

        var fg = isDark ? Windows.UI.Color.FromArgb(255, 236, 233, 227) : Windows.UI.Color.FromArgb(255, 31, 30, 28);
        var muted = isDark ? Windows.UI.Color.FromArgb(255, 163, 158, 148) : Windows.UI.Color.FromArgb(255, 98, 94, 87);
        var hoverBg = isDark ? Windows.UI.Color.FromArgb(24, 255, 255, 255) : Windows.UI.Color.FromArgb(20, 0, 0, 0);

        titleBar.ButtonBackgroundColor = Colors.Transparent;
        titleBar.ButtonInactiveBackgroundColor = Colors.Transparent;
        titleBar.ButtonForegroundColor = fg;
        titleBar.ButtonInactiveForegroundColor = muted;
        titleBar.ButtonHoverBackgroundColor = hoverBg;
        titleBar.ButtonHoverForegroundColor = fg;
        titleBar.ButtonPressedBackgroundColor = hoverBg;
        titleBar.ButtonPressedForegroundColor = fg;
    }

    public static void ResizeWindow(Window window, int width, int height)
    {
        var appWindow = GetAppWindow(window);
        appWindow.Resize(new SizeInt32(width, height));
    }

    public static bool ToggleCompactOverlay(Window window)
    {
        var appWindow = GetAppWindow(window);
        if (appWindow.Presenter.Kind == AppWindowPresenterKind.CompactOverlay)
        {
            appWindow.SetPresenter(AppWindowPresenterKind.Overlapped);
            return false;
        }
        try
        {
            appWindow.SetPresenter(AppWindowPresenterKind.CompactOverlay);
            appWindow.Resize(new SizeInt32(480, 300));
            return true;
        }
        catch
        {
            return false;
        }
    }

    public static bool ToggleFullScreen(Window window)
    {
        var appWindow = GetAppWindow(window);
        if (appWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen)
        {
            appWindow.SetPresenter(AppWindowPresenterKind.Overlapped);
            return false;
        }
        appWindow.SetPresenter(AppWindowPresenterKind.FullScreen);
        return true;
    }

    public static async Task<bool> IsWindowsHelloAvailableAsync()
    {
        try
        {
            var availability = await UserConsentVerifier.CheckAvailabilityAsync();
            return availability == UserConsentVerifierAvailability.Available;
        }
        catch
        {
            return false;
        }
    }

    public static async Task<bool> AuthenticateWindowsHelloAsync(string reason)
    {
        try
        {
            var availability = await UserConsentVerifier.CheckAvailabilityAsync();
            if (availability != UserConsentVerifierAvailability.Available)
                return false;

            var result = await UserConsentVerifier.RequestVerificationAsync(reason);
            return result == UserConsentVerificationResult.Verified;
        }
        catch
        {
            return false;
        }
    }
}
