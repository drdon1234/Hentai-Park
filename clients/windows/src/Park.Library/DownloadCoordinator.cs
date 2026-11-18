using System.Collections.Concurrent;
using System.Text.Json;
using Park.Core.Configuration;
using Park.Core.Models;

namespace Park.Library;

public enum DownloadStatus
{
    Queued,
    Running,
    Paused,
    Completed,
    Failed,
    Cancelling,
}

public sealed class DownloadTaskItem
{
    public required string Uid { get; init; }
    public required WorkItem Work { get; init; }
    public required string ChapterId { get; init; }
    public required string ChapterTitle { get; init; }
    public required string DirectoryPath { get; init; }
    public DownloadStatus Status { get; set; } = DownloadStatus.Queued;
    public int CompletedUnits { get; set; }
    public int TotalUnits { get; set; }
    public string? ErrorMessage { get; set; }
    public long CreatedAt { get; init; } = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
    internal CancellationTokenSource? ActiveCts { get; set; }

    public double ProgressRatio => TotalUnits > 0 ? Math.Clamp((double)CompletedUnits / TotalUnits, 0.0, 1.0) : 0.0;
}

/// <summary>
/// Three-tier concurrency download scheduler aligned with DEVELOPMENT.md:
/// - downloadSiteConcurrency (default 3): max active sites simultaneously
/// - downloadTaskConcurrency (default 1): max active tasks per site
/// - downloadConcurrency (default 3): max concurrent pages inside a comic chapter task
/// Supports atomic pending.json -> pages.json publication and deletion intents.
/// </summary>
public sealed class DownloadCoordinator
{
    private readonly ParkDatabase _db;
    private readonly Lock _lock = new();
    private readonly List<DownloadTaskItem> _tasks = [];
    private readonly HashSet<string> _activeSites = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _activeTasksPerSite = new(StringComparer.Ordinal);
    private bool _suspended;

    public event Action? TasksChanged;

    public Func<DownloadTaskItem, int, CancellationToken, Task>? ExecuteAdapter { get; set; }

    public DownloadCoordinator(ParkDatabase db)
    {
        _db = db;
    }

    public IReadOnlyList<DownloadTaskItem> Snapshot()
    {
        lock (_lock) return [.. _tasks];
    }

    public async Task LoadFromDatabaseAsync(CancellationToken ct = default)
    {
        var loaded = await _db.ReadAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT uid, source, json, dir, created_at FROM download_tasks ORDER BY created_at DESC;";
            var list = new List<DownloadTaskItem>();
            await using var r = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            while (await r.ReadAsync(ct).ConfigureAwait(false))
            {
                try
                {
                    var uid = r.GetString(0);
                    var src = r.GetString(1);
                    using var doc = JsonDocument.Parse(r.GetString(2));
                    var root = doc.RootElement;
                    var dir = r.GetString(3);
                    var created = r.GetInt64(4);
                    var statusStr = root.TryGetProperty("status", out var st) ? st.GetString() : "Paused";
                    var status = Enum.TryParse<DownloadStatus>(statusStr, true, out var parsed) ? parsed : DownloadStatus.Paused;
                    if (status is DownloadStatus.Running or DownloadStatus.Cancelling)
                        status = DownloadStatus.Queued;

                    var workObj = System.Text.Json.Nodes.JsonNode.Parse(root.GetProperty("work").GetRawText()) as System.Text.Json.Nodes.JsonObject ?? [];
                    list.Add(new DownloadTaskItem
                    {
                        Uid = uid,
                        Work = WorkItem.FromJson(src, workObj),
                        ChapterId = root.GetProperty("chapterId").GetString() ?? "_",
                        ChapterTitle = root.GetProperty("chapterTitle").GetString() ?? string.Empty,
                        DirectoryPath = dir,
                        Status = status,
                        CompletedUnits = root.TryGetProperty("completed", out var cu) ? cu.GetInt32() : 0,
                        TotalUnits = root.TryGetProperty("total", out var tu) ? tu.GetInt32() : 0,
                        CreatedAt = created,
                    });
                }
                catch
                {
                    // Keep malformed records safe without crashing startup
                }
            }
            return list;
        }, ct).ConfigureAwait(false);

        lock (_lock)
        {
            _tasks.Clear();
            _tasks.AddRange(loaded);
        }
        PumpQueue();
    }

    public async Task<DownloadTaskItem> EnqueueAsync(WorkItem work, string chapterId, string chapterTitle, CancellationToken ct = default)
    {
        var uid = $"{work.Source}:{work.Id}:{chapterId}";
        DownloadTaskItem? existing;
        lock (_lock)
        {
            existing = _tasks.FirstOrDefault(t => t.Uid == uid);
            if (existing is not null)
            {
                if (existing.Status is DownloadStatus.Paused or DownloadStatus.Failed)
                {
                    existing.Status = DownloadStatus.Queued;
                    existing.ErrorMessage = null;
                }
            }
        }

        if (existing is not null)
        {
            await PersistTaskAsync(existing, ct).ConfigureAwait(false);
            TasksChanged?.Invoke();
            PumpQueue();
            return existing;
        }

        var safeFolder = Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(uid)))[..24];
        var dir = Path.Combine(AppSettings.Instance.DownloadDirectory, work.Source, safeFolder);
        var item = new DownloadTaskItem
        {
            Uid = uid,
            Work = work,
            ChapterId = chapterId,
            ChapterTitle = chapterTitle,
            DirectoryPath = dir,
        };

        lock (_lock)
        {
            _tasks.Insert(0, item);
        }
        await PersistTaskAsync(item, ct).ConfigureAwait(false);
        TasksChanged?.Invoke();
        PumpQueue();
        return item;
    }

    public void Pause(string uid)
    {
        DownloadTaskItem? target;
        lock (_lock)
        {
            target = _tasks.FirstOrDefault(t => t.Uid == uid);
            if (target is null) return;
            if (target.Status == DownloadStatus.Queued)
            {
                target.Status = DownloadStatus.Paused;
            }
            else if (target.Status == DownloadStatus.Running)
            {
                target.Status = DownloadStatus.Paused;
                target.ActiveCts?.Cancel();
            }
        }
        _ = PersistTaskAsync(target);
        TasksChanged?.Invoke();
    }

    public void ResumeTask(string uid)
    {
        DownloadTaskItem? target;
        lock (_lock)
        {
            target = _tasks.FirstOrDefault(t => t.Uid == uid);
            if (target is null || target.Status is not (DownloadStatus.Paused or DownloadStatus.Failed)) return;
            target.Status = DownloadStatus.Queued;
            target.ErrorMessage = null;
        }
        _ = PersistTaskAsync(target);
        TasksChanged?.Invoke();
        PumpQueue();
    }

    public async Task DeleteTaskAsync(string uid, CancellationToken ct = default)
    {
        DownloadTaskItem? target;
        lock (_lock)
        {
            target = _tasks.FirstOrDefault(t => t.Uid == uid);
            if (target is null) return;
            target.Status = DownloadStatus.Cancelling;
            target.ActiveCts?.Cancel();
        }
        TasksChanged?.Invoke();

        // Persist deletion intent before deleting files & DB row per DEVELOPMENT.md
        await PersistTaskAsync(target, ct).ConfigureAwait(false);

        if (Directory.Exists(target.DirectoryPath))
        {
            var fullTarget = Path.GetFullPath(target.DirectoryPath);
            var allowedRoot = Path.GetFullPath(AppSettings.Instance.DownloadDirectory);
            if (fullTarget.StartsWith(allowedRoot, StringComparison.OrdinalIgnoreCase))
            {
                Directory.Delete(fullTarget, recursive: true);
            }
        }

        await _db.WriteTransactionAsync(async (conn, tx) =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.Transaction = tx;
            cmd.CommandText = "DELETE FROM download_tasks WHERE uid = $u;";
            cmd.Parameters.AddWithValue("$u", uid);
            await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
        }, ct).ConfigureAwait(false);

        lock (_lock)
        {
            _tasks.Remove(target);
        }
        TasksChanged?.Invoke();
    }

    public async Task SuspendAllAsync()
    {
        List<CancellationTokenSource> runningTokens;
        lock (_lock)
        {
            _suspended = true;
            runningTokens = _tasks.Where(t => t.ActiveCts is not null).Select(t => t.ActiveCts!).ToList();
        }
        foreach (var cts in runningTokens) cts.Cancel();
        await Task.Delay(50).ConfigureAwait(false);
    }

    public void ResumeAll()
    {
        lock (_lock) _suspended = false;
        PumpQueue();
    }

    private void PumpQueue()
    {
        var maxSites = AppSettings.Instance.DownloadSiteConcurrency;
        var maxTasksPerSite = AppSettings.Instance.DownloadTaskConcurrency;
        var pageConcurrency = AppSettings.Instance.DownloadConcurrency;

        var toStart = new List<(DownloadTaskItem Task, CancellationTokenSource Cts)>();
        lock (_lock)
        {
            if (_suspended || ExecuteAdapter is null) return;
            foreach (var candidate in _tasks.Where(t => t.Status == DownloadStatus.Queued))
            {
                var src = candidate.Work.Source;
                _activeTasksPerSite.TryGetValue(src, out var siteRunning);
                if (siteRunning >= maxTasksPerSite) continue;
                if (siteRunning == 0 && _activeSites.Count >= maxSites) continue;

                var cts = new CancellationTokenSource();
                candidate.Status = DownloadStatus.Running;
                candidate.ActiveCts = cts;
                _activeSites.Add(src);
                _activeTasksPerSite[src] = siteRunning + 1;
                toStart.Add((candidate, cts));
            }
        }

        foreach (var (task, cts) in toStart)
        {
            TasksChanged?.Invoke();
            _ = RunSingleTaskAsync(task, pageConcurrency, cts);
        }
    }

    private async Task RunSingleTaskAsync(DownloadTaskItem task, int pageConcurrency, CancellationTokenSource cts)
    {
        try
        {
            var adapter = ExecuteAdapter;
            if (adapter is not null)
            {
                await adapter(task, pageConcurrency, cts.Token).ConfigureAwait(false);
                lock (_lock)
                {
                    if (task.Status == DownloadStatus.Running)
                        task.Status = DownloadStatus.Completed;
                }
            }
        }
        catch (OperationCanceledException)
        {
            lock (_lock)
            {
                if (task.Status == DownloadStatus.Running)
                    task.Status = DownloadStatus.Paused;
            }
        }
        catch (Exception ex)
        {
            lock (_lock)
            {
                if (task.Status == DownloadStatus.Running)
                {
                    task.Status = DownloadStatus.Failed;
                    task.ErrorMessage = ex.Message;
                }
            }
        }
        finally
        {
            lock (_lock)
            {
                task.ActiveCts = null;
                var src = task.Work.Source;
                if (_activeTasksPerSite.TryGetValue(src, out var c))
                {
                    if (c <= 1)
                    {
                        _activeTasksPerSite.Remove(src);
                        _activeSites.Remove(src);
                    }
                    else
                    {
                        _activeTasksPerSite[src] = c - 1;
                    }
                }
            }
            cts.Dispose();
            if (task.Status != DownloadStatus.Cancelling)
            {
                await PersistTaskAsync(task).ConfigureAwait(false);
            }
            TasksChanged?.Invoke();
            PumpQueue();
        }
    }

    public void NotifyProgress() => TasksChanged?.Invoke();

    private Task PersistTaskAsync(DownloadTaskItem item, CancellationToken ct = default)
    {
        var payload = JsonSerializer.Serialize(new
        {
            status = item.Status.ToString(),
            work = item.Work.RawJson,
            chapterId = item.ChapterId,
            chapterTitle = item.ChapterTitle,
            completed = item.CompletedUnits,
            total = item.TotalUnits,
        });

        return _db.WriteTransactionAsync(async (conn, tx) =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.Transaction = tx;
            cmd.CommandText = """
                INSERT INTO download_tasks (uid, source, json, dir, created_at)
                VALUES ($u, $s, $j, $d, $c)
                ON CONFLICT(uid) DO UPDATE SET json = excluded.json, dir = excluded.dir;
                """;
            cmd.Parameters.AddWithValue("$u", item.Uid);
            cmd.Parameters.AddWithValue("$s", item.Work.Source);
            cmd.Parameters.AddWithValue("$j", payload);
            cmd.Parameters.AddWithValue("$d", item.DirectoryPath);
            cmd.Parameters.AddWithValue("$c", item.CreatedAt);
            await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
        }, ct);
    }
}
