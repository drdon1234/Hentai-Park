using System.Security.Cryptography;
using System.Text;

namespace Park.Core.Configuration;

public static class AppPaths
{
    private static string? _dataRootOverride;
    private static string? _assetsRootOverride;

    public static void ConfigureForTesting(string dataRoot, string? assetsRoot = null)
    {
        _dataRootOverride = Path.GetFullPath(dataRoot);
        if (assetsRoot is not null)
        {
            _assetsRootOverride = Path.GetFullPath(assetsRoot);
        }
        EnsureDirectories();
    }

    public static bool IsPortable
    {
        get
        {
            if (_dataRootOverride is not null) return false;
            var baseDir = AppContext.BaseDirectory;
            return File.Exists(Path.Combine(baseDir, "portable.flag"));
        }
    }

    public static string DataRoot
    {
        get
        {
            if (_dataRootOverride is not null) return _dataRootOverride;
            if (IsPortable)
            {
                return Path.Combine(AppContext.BaseDirectory, "data");
            }
            var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(localAppData, "HentaiPark");
        }
    }

    public static string AssetsRoot
    {
        get
        {
            if (_assetsRootOverride is not null) return _assetsRootOverride;
            var candidate = Path.Combine(AppContext.BaseDirectory, "assets");
            if (Directory.Exists(candidate)) return candidate;

            // Walk upward during local development runs to locate clients/windows/assets
            var cursor = new DirectoryInfo(AppContext.BaseDirectory);
            for (var i = 0; i < 6 && cursor is not null; i++, cursor = cursor.Parent)
            {
                var probe = Path.Combine(cursor.FullName, "assets");
                if (File.Exists(Path.Combine(probe, "runtime", "park_runtime.js")))
                {
                    return probe;
                }
            }
            return candidate;
        }
    }

    public static string DatabaseFile => Path.Combine(DataRoot, "park.db");
    public static string SettingsFile => Path.Combine(DataRoot, "settings.json");
    public static string LogPreferencesFile => Path.Combine(DataRoot, "log_preferences.json");
    public static string ExportDirectoriesFile => Path.Combine(DataRoot, "export_directories.json");
    public static string InstalledSourcesDir => Path.Combine(DataRoot, "sources");
    public static string SourceStateDir => Path.Combine(DataRoot, "source_state");
    public static string CookiesDir => Path.Combine(DataRoot, "cookies");
    public static string SecretsDir => Path.Combine(DataRoot, "secrets");
    public static string BackupsDir => Path.Combine(DataRoot, "backups");
    public static string LogsDir => Path.Combine(DataRoot, "logs");
    public static string CacheDir => Path.Combine(DataRoot, "cache");
    public static string WebViewProfilesDir => Path.Combine(DataRoot, "webview_profiles");
    public static string DefaultDownloadsDir => Path.Combine(DataRoot, "downloads");

    public static void EnsureDirectories()
    {
        foreach (var dir in new[]
        {
            DataRoot,
            InstalledSourcesDir,
            SourceStateDir,
            CookiesDir,
            SecretsDir,
            BackupsDir,
            LogsDir,
            CacheDir,
            WebViewProfilesDir,
            DefaultDownloadsDir,
        })
        {
            Directory.CreateDirectory(dir);
        }
    }

    public static async Task WriteFileAtomicAsync(string destinationPath, ReadOnlyMemory<byte> content, CancellationToken ct = default)
    {
        var directory = Path.GetDirectoryName(destinationPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var tempName = $".{Path.GetFileName(destinationPath)}.{Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(6))}.tmp";
        var tempPath = Path.Combine(directory ?? ".", tempName);
        try
        {
            await using (var stream = new FileStream(tempPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, FileOptions.WriteThrough | FileOptions.Asynchronous))
            {
                await stream.WriteAsync(content, ct).ConfigureAwait(false);
                await stream.FlushAsync(ct).ConfigureAwait(false);
            }
            File.Move(tempPath, destinationPath, overwrite: true);
        }
        catch
        {
            try { if (File.Exists(tempPath)) File.Delete(tempPath); } catch { /* ignore cleanup failure */ }
            throw;
        }
    }

    public static Task WriteTextAtomicAsync(string destinationPath, string text, CancellationToken ct = default) =>
        WriteFileAtomicAsync(destinationPath, Encoding.UTF8.GetBytes(text), ct);
}
