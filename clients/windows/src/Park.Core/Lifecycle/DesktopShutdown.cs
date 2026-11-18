namespace Park.Core.Lifecycle;

/// <summary>
/// Executes async operations strictly in FIFO order; supports awaiting queue settlement.
/// </summary>
public sealed class SerialExecutor
{
    private readonly Lock _lock = new();
    private Task _tail = Task.CompletedTask;

    public Task Settled
    {
        get { lock (_lock) return _tail; }
    }

    public Task<T> RunAsync<T>(Func<Task<T>> action)
    {
        lock (_lock)
        {
            var next = _tail.ContinueWith(_ => action(), TaskScheduler.Default).Unwrap();
            _tail = next.ContinueWith(_ => { }, TaskScheduler.Default);
            return next;
        }
    }

    public Task RunAsync(Func<Task> action) =>
        RunAsync(async () =>
        {
            await action().ConfigureAwait(false);
            return true;
        });
}

/// <summary>
/// Tracks async native resource teardowns kicked off from synchronous UI Unloaded/Closed callbacks.
/// </summary>
public sealed class PendingDisposals
{
    public static PendingDisposals Instance { get; } = new();

    private readonly Lock _lock = new();
    private readonly HashSet<Task> _pending = [];

    public void Add(Task task)
    {
        if (task.IsCompleted) return;
        lock (_lock)
        {
            _pending.Add(task);
        }
        _ = task.ContinueWith(t =>
        {
            lock (_lock) _pending.Remove(t);
        }, TaskScheduler.Default);
    }

    public async Task DrainAsync()
    {
        while (true)
        {
            Task[] current;
            lock (_lock)
            {
                if (_pending.Count == 0) return;
                current = [.. _pending];
            }
            await Task.WhenAll(current).ConfigureAwait(false);
        }
    }
}

/// <summary>
/// Four-stage desktop shutdown barrier aligned with lib/engine/desktop_shutdown.dart:
/// Reversible before Flush completes; once committed, retries Stop until databases and runtimes close cleanly.
/// </summary>
public sealed class DesktopShutdown(
    Func<Task> prepare,
    Func<Task> detach,
    Func<Task> flush,
    Func<Task> stop,
    Func<Task> resume)
{
    private bool _busy;
    private bool _committed;

    public bool Detached { get; private set; }
    public bool Failed { get; private set; }
    public event Action? StateChanged;

    public async Task<bool> ExitAsync()
    {
        if (_busy) return false;
        _busy = true;
        Failed = false;
        StateChanged?.Invoke();

        try
        {
            if (!_committed)
            {
                await prepare().ConfigureAwait(false);
                Detached = true;
                StateChanged?.Invoke();
                await detach().ConfigureAwait(false);
                await PendingDisposals.Instance.DrainAsync().ConfigureAwait(false);
                await flush().ConfigureAwait(false);
                _committed = true;
            }
            await stop().ConfigureAwait(false);
            return true;
        }
        catch
        {
            if (_committed)
            {
                Failed = true;
            }
            else
            {
                Detached = false;
                StateChanged?.Invoke();
                await resume().ConfigureAwait(false);
            }
            return false;
        }
        finally
        {
            _busy = false;
            StateChanged?.Invoke();
        }
    }
}
