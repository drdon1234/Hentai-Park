using System.Text.Json;
using Park.Core.Configuration;
using Park.Core.Diagnostics;
using Park.Core.Filtering;
using Park.Core.Lifecycle;
using Park.Core.Localization;
using Park.Engine.Images;
using Park.Engine.Media;
using Park.Engine.Network;
using Park.Engine.Runtime;
using Park.Engine.Sources;
using Park.Library;

namespace Park.App.Services;

public sealed class AppHost
{
    public static AppHost Instance { get; } = new();

    public ParkDatabase Database { get; private set; } = null!;
    public LibraryStore Library { get; private set; } = null!;
    public BackupService Backups { get; private set; } = null!;
    public DownloadCoordinator Downloads { get; private set; } = null!;
    public SourceCookieStore Cookies { get; private set; } = null!;
    public ParkHttpService Http { get; private set; } = null!;
    public ImagePipeline Images { get; private set; } = null!;
    public WebViewJsEngine JsEngine { get; private set; } = null!;
    public SourceManager Sources { get; private set; } = null!;
    public LocalMediaProxy MediaProxy { get; private set; } = null!;
    public DesktopShutdown Shutdown { get; private set; } = null!;

    public BlockRuleEngine CurrentBlockEngine { get; private set; } = new([]);

    private bool _initialized;

    public async Task InitializeAsync()
    {
        if (_initialized) return;
        AppPaths.EnsureDirectories();

        await AppLog.Instance.InitializeAsync();
        await AppSettings.Instance.LoadAsync();
        L.Initialize(AppSettings.Instance.Language);
        RebuildBlockEngine();

        AppSettings.Instance.Changed += (domain, key) =>
        {
            if (key == "language")
                L.SetLocale(AppSettings.Instance.Language);
            if (domain == SettingsDomain.Filter)
                RebuildBlockEngine();
        };

        Database = new ParkDatabase();
        await Database.InitializeAsync();

        Library = new LibraryStore(Database);
        Backups = new BackupService(Library);
        await Backups.RecoverPendingCheckpointsAsync();

        Downloads = new DownloadCoordinator(Database);
        Cookies = new SourceCookieStore();
        await Cookies.LoadAllAsync();

        Http = new ParkHttpService(Cookies);
        Images = new ImagePipeline(Http);

        JsEngine = new WebViewJsEngine(
            Http,
            Cookies,
            onPersist: (key, storeObj, flush) => Sources.HandleRuntimePersistAsync(key, storeObj, flush));

        Sources = new SourceManager(JsEngine, Http, Cookies);
        await Sources.InitializeAsync();

        MediaProxy = new LocalMediaProxy(Http);

        Downloads.ExecuteAdapter = ExecuteComicDownloadAsync;
        await Downloads.LoadFromDatabaseAsync();

        Shutdown = new DesktopShutdown(
            prepare: async () =>
            {
                await Downloads.SuspendAllAsync();
                await Backups.SuspendAsync();
                await JsEngine.SuspendAsync();
            },
            detach: () => Task.CompletedTask,
            flush: async () =>
            {
                await Library.FlushAsync();
                await AppSettings.Instance.FlushAsync();
            },
            stop: async () =>
            {
                MediaProxy.Dispose();
                await JsEngine.DisposeAsync();
                Http.Dispose();
                await Database.DisposeAsync();
            },
            resume: () =>
            {
                JsEngine.Resume();
                Backups.Resume();
                Downloads.ResumeAll();
                return Task.CompletedTask;
            });

        _initialized = true;
        AppLog.Instance.Record(new Dictionary<string, object?>
        {
            ["event"] = "startup",
            ["stage"] = "complete",
            ["outcome"] = "ready",
        });
    }

    private void RebuildBlockEngine()
    {
        CurrentBlockEngine = new BlockRuleEngine(AppSettings.Instance.BlockedTags, matchTitles: true);
    }

    private async Task ExecuteComicDownloadAsync(DownloadTaskItem task, int pageConcurrency, CancellationToken ct)
    {
        Directory.CreateDirectory(task.DirectoryPath);
        var src = Sources.GetSource(task.Work.Source)?.Manifest;
        var pages = await Sources.FetchChapterPagesAsync(task.Work.Source, task.Work.Id, task.ChapterId, ct);
        task.TotalUnits = pages.Count;
        Downloads.NotifyProgress();

        // Atomic pending.json before page downloads, published to pages.json upon full completion per DEVELOPMENT.md
        var pendingPath = Path.Combine(task.DirectoryPath, "pending.json");
        await AppPaths.WriteTextAtomicAsync(pendingPath, JsonSerializer.Serialize(new { total = pages.Count }), ct);

        using var sem = new SemaphoreSlim(pageConcurrency, pageConcurrency);
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(ct);

        var workers = pages.Select(async page =>
        {
            await sem.WaitAsync(linkedCts.Token);
            try
            {
                var filePath = Path.Combine(task.DirectoryPath, $"{page.Index:D4}.img");
                if (!File.Exists(filePath) && !string.IsNullOrEmpty(page.Url))
                {
                    var bytes = await Images.FetchImageBytesAsync(src, page.Url, page.Headers, linkedCts.Token);
                    await AppPaths.WriteFileAtomicAsync(filePath, bytes, linkedCts.Token);
                }
                task.CompletedUnits++;
                Downloads.NotifyProgress();
            }
            catch
            {
                // Cancel sibling page downloads immediately on first page failure per DEVELOPMENT.md
                await linkedCts.CancelAsync();
                throw;
            }
            finally
            {
                sem.Release();
            }
        });

        await Task.WhenAll(workers);

        var pagesPath = Path.Combine(task.DirectoryPath, "pages.json");
        await AppPaths.WriteTextAtomicAsync(pagesPath, JsonSerializer.Serialize(new { count = pages.Count, completed = true }), ct);
        if (File.Exists(pendingPath)) File.Delete(pendingPath);
    }
}
