using Microsoft.UI.Xaml;
using Park.App.Services;
using Park.App.Shell;
using Park.Core.Diagnostics;

namespace Park.App;

public partial class App : Application
{
    private MainWindow? _window;

    public App()
    {
        InitializeComponent();
        UnhandledException += OnUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            if (e.ExceptionObject is Exception ex)
                AppLog.Instance.RecordCrashSync(ex);
        };
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        await AppHost.Instance.InitializeAsync();
        _window = new MainWindow();
        _window.Activate();
    }

    private static void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        AppLog.Instance.RecordCrashSync(e.Exception);
    }
}
