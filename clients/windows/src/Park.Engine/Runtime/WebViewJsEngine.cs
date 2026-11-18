using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Web.WebView2.Core;
using Park.Core.Configuration;
using Park.Core.Diagnostics;
using Park.Core.Models;
using Park.Engine.Network;
using Park.Engine.Security;

namespace Park.Engine.Runtime;

public sealed record ScriptProbeResult(string Key, SourceManifest Manifest);

/// <summary>
/// Hosts each source plugin in its own isolated headless WebView2 instance with:
/// - Strict CSP (default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval')
/// - Unique virtual origin https://&lt;source&gt;.source.park.invalid/
/// - Zero direct browser network loads (all WebResourceRequested aborted except initial sandbox document)
/// - Attributed Park.__native postMessage bridge
/// - Pool cap of 6 active runtimes and 5-minute idle LRU eviction per SOURCE_API.md
/// - Multi-profile isolation helper for WebGames (park_game_&lt;sha256&gt;) and WebVideo (InPrivate)
/// </summary>
public sealed class WebViewJsEngine : IAsyncDisposable
{
    private const int MaxPoolSize = 6;
    private static readonly TimeSpan IdleTimeout = TimeSpan.FromMinutes(5);

    private readonly ParkHttpService _http;
    private readonly SourceCookieStore _cookies;
    private readonly Func<string, JsonObject, bool, Task>? _onPersist;
    private readonly SemaphoreSlim _envLock = new(1, 1);
    private CoreWebView2Environment? _environment;
    private string? _runtimeJs;
    private string? _runtimeSha256;
    private bool _suspended;
    private bool _disposed;

    private readonly ConcurrentDictionary<string, IsolatedSourceRuntime> _pool = new(StringComparer.Ordinal);

    public WebViewJsEngine(
        ParkHttpService http,
        SourceCookieStore cookies,
        Func<string, JsonObject, bool, Task>? onPersist = null)
    {
        _http = http;
        _cookies = cookies;
        _onPersist = onPersist;
    }

    public async Task<string> GetRuntimeHashAsync(CancellationToken ct = default)
    {
        if (_runtimeSha256 is not null) return _runtimeSha256;
        var code = await GetRuntimeCodeAsync(ct).ConfigureAwait(false);
        _runtimeSha256 = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(code)));
        return _runtimeSha256;
    }

    public async Task<string> GetRuntimeCodeAsync(CancellationToken ct = default)
    {
        if (_runtimeJs is not null) return _runtimeJs;
        var path = Path.Combine(AppPaths.AssetsRoot, "runtime", "park_runtime.js");
        _runtimeJs = await File.ReadAllTextAsync(path, Encoding.UTF8, ct).ConfigureAwait(false);
        return _runtimeJs;
    }

    public async Task<CoreWebView2Environment> EnsureEnvironmentAsync()
    {
        if (_environment is not null) return _environment;
        await _envLock.WaitAsync();
        try
        {
            if (_environment is not null) return _environment;
            AppPaths.EnsureDirectories();
            var opts = new CoreWebView2EnvironmentOptions
            {
                AreBrowserExtensionsEnabled = false,
            };
            var proxy = AppSettings.Instance.Proxy;
            if (!string.IsNullOrWhiteSpace(proxy))
            {
                var normalized = proxy.Contains("://", StringComparison.Ordinal) ? proxy : $"http://{proxy}";
                opts.AdditionalBrowserArguments = $"--proxy-server=\"{normalized}\" --disable-features=msSmartScreenProtection";
            }
            _environment = await CoreWebView2Environment.CreateAsync(
                browserExecutableFolder: null,
                userDataFolder: AppPaths.WebViewProfilesDir,
                options: opts);
            return _environment;
        }
        finally
        {
            _envLock.Release();
        }
    }

    /// <summary>
    /// Creates a verified persistent profile name for an online game per DEVELOPMENT.md:
    /// Caller must verify CoreWebView2.Profile.ProfileName == ExpectedGameProfileName before navigating!
    /// </summary>
    public static string BuildGameProfileName(string sourceKey, string storageId)
    {
        var digest = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes($"{sourceKey}:{storageId}")));
        return $"park_game_{digest}";
    }

    /// <summary>
    /// Evaluates an untrusted plugin script inside a throwaway sandboxed WebView2 that refuses all bridge calls.
    /// Must be invoked on the UI DispatcherQueue thread.
    /// </summary>
    public async Task<ScriptProbeResult> ProbeScriptAsync(string scriptCode, nint hostWindowHandle, CancellationToken ct = default)
    {
        if (_disposed || _suspended) throw new SourceError("CANCELLED", "应用正在关闭");
        var env = await EnsureEnvironmentAsync();
        var runtimeJs = await GetRuntimeCodeAsync(ct);

        await using var sandbox = new IsolatedSourceRuntime(string.Empty, sandboxed: true, env, runtimeJs, _http, _cookies, _onPersist);
        return await sandbox.LoadAndProbeAsync(scriptCode, hostWindowHandle, ct);
    }

    public async Task<JsonNode?> InvokeAsync(
        string sourceKey,
        string scriptCode,
        JsonObject initialState,
        string method,
        object?[] args,
        nint hostWindowHandle,
        CancellationToken ct = default)
    {
        if (_disposed || _suspended) throw new SourceError("CANCELLED", "应用正在关闭");
        await EvictIdleOrOverflowAsync();

        var env = await EnsureEnvironmentAsync();
        var runtimeJs = await GetRuntimeCodeAsync(ct);

        if (!_pool.TryGetValue(sourceKey, out var runtime))
        {
            runtime = new IsolatedSourceRuntime(sourceKey, sandboxed: false, env, runtimeJs, _http, _cookies, _onPersist);
            await runtime.LoadAndSetupAsync(scriptCode, initialState, hostWindowHandle, ct);
            _pool[sourceKey] = runtime;
        }

        return await runtime.InvokeMethodAsync(method, args, ct);
    }

    public async Task SuspendAsync()
    {
        _suspended = true;
        foreach (var rt in _pool.Values)
            await rt.WaitPendingBridgeCallsAsync();
    }

    public void Resume() => _suspended = false;

    public async Task DisposeRuntimeAsync(string sourceKey)
    {
        if (_pool.TryRemove(sourceKey, out var rt))
            await rt.DisposeAsync();
    }

    private async Task EvictIdleOrOverflowAsync()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var (k, rt) in _pool)
        {
            if (now - rt.LastUsedUtc > IdleTimeout && _pool.TryRemove(k, out var stale))
            {
                await stale.DisposeAsync();
            }
        }

        while (_pool.Count >= MaxPoolSize)
        {
            var oldest = _pool.OrderBy(kv => kv.Value.LastUsedUtc).FirstOrDefault();
            if (oldest.Key is null) break;
            if (_pool.TryRemove(oldest.Key, out var victim))
                await victim.DisposeAsync();
        }
    }

    public async ValueTask DisposeAsync()
    {
        _disposed = true;
        var items = _pool.Values.ToArray();
        _pool.Clear();
        foreach (var rt in items)
        {
            await rt.DisposeAsync();
        }
    }
}

internal sealed class IsolatedSourceRuntime : IAsyncDisposable
{
    private const string BootstrapJs = """
        (function () {
          let seq = 0;
          const pending = new Map();
          window.chrome.webview.addEventListener('message', (ev) => {
            const msg = typeof ev.data === 'string' ? JSON.parse(ev.data) : ev.data;
            if (!msg || !msg.id) return;
            const entry = pending.get(msg.id);
            if (!entry) return;
            pending.delete(msg.id);
            if (msg.__error) entry.reject(msg.__error);
            else entry.resolve(msg.__value ?? null);
          });
          function call(name, payload) {
            return new Promise((resolve, reject) => {
              const id = String(++seq);
              pending.set(id, { resolve, reject });
              window.chrome.webview.postMessage(JSON.stringify({ id, name, payload }));
            });
          }
          function post(name, payload) {
            window.chrome.webview.postMessage(JSON.stringify({ id: '', name, payload }));
          }
          window.Park = { __native: {
            request: (o) => call('park_request', o),
            chatRequest: (o) => call('park_chat_request', o),
            crypto: (op, args) => call('park_crypto', { op, args }),
            cookies: (op, args) => call('park_cookies', { op, args }),
            persist: (key, data, flush = false) => call('park_persist', { data, flush }),
            log: (key, level, message) => post('park_log', { level, message }),
          } };
        })();
        """;

    private readonly string _sourceKey;
    private readonly bool _sandboxed;
    private readonly CoreWebView2Environment _env;
    private readonly string _runtimeJs;
    private readonly ParkHttpService _http;
    private readonly SourceCookieStore _cookies;
    private readonly Func<string, JsonObject, bool, Task>? _onPersist;
    private readonly ConcurrentDictionary<Task, byte> _bridgeTasks = new();

    private CoreWebView2Controller? _controller;
    private CoreWebView2? _webView;
    private SourceManifest? _manifest;
    private bool _disposed;

    public DateTimeOffset LastUsedUtc { get; private set; } = DateTimeOffset.UtcNow;

    public IsolatedSourceRuntime(
        string sourceKey,
        bool sandboxed,
        CoreWebView2Environment env,
        string runtimeJs,
        ParkHttpService http,
        SourceCookieStore cookies,
        Func<string, JsonObject, bool, Task>? onPersist)
    {
        _sourceKey = sourceKey;
        _sandboxed = sandboxed;
        _env = env;
        _runtimeJs = runtimeJs;
        _http = http;
        _cookies = cookies;
        _onPersist = onPersist;
    }

    private async Task EnsureWebViewAsync(nint hostHwnd, CancellationToken ct)
    {
        if (_webView is not null) return;
        var opts = _env.CreateCoreWebView2ControllerOptions();
        opts.IsInPrivateModeEnabled = true;

        _controller = await _env.CreateCoreWebView2ControllerAsync(hostHwnd, opts);
        _controller.IsVisible = false;
        _webView = _controller.CoreWebView2;

        // Sync real system WebView2 User-Agent to native HTTP client
        var ua = _webView.Settings.UserAgent;
        if (!string.IsNullOrWhiteSpace(ua))
            _http.DefaultUserAgent = ua;

        _webView.Settings.AreDevToolsEnabled = false;
        _webView.Settings.AreDefaultContextMenusEnabled = false;
        _webView.Settings.IsStatusBarEnabled = false;
        _webView.Settings.IsWebMessageEnabled = true;

        var safeHost = string.IsNullOrEmpty(_sourceKey) ? "probe" : _sourceKey.ToLowerInvariant();
        var originHtml = "<!doctype html><html><head><meta charset=\"utf-8\">" +
                         "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; connect-src 'none'; img-src 'none'; frame-src 'none'; worker-src 'none'\">" +
                         "</head><body></body></html>";

        // Block all external network loads from JS sandbox WebView
        _webView.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        var initialServed = false;
        var virtualOrigin = $"https://{safeHost}.source.park.invalid/";

        _webView.WebResourceRequested += (_, e) =>
        {
            if (!initialServed && string.Equals(e.Request.Uri, virtualOrigin, StringComparison.OrdinalIgnoreCase))
            {
                initialServed = true;
                var stream = new MemoryStream(Encoding.UTF8.GetBytes(originHtml));
                e.Response = _env.CreateWebResourceResponse(stream, 200, "OK", "Content-Type: text/html; charset=utf-8");
                return;
            }
            e.Response = _env.CreateWebResourceResponse(Stream.Null, 403, "Blocked", string.Empty);
        };

        _webView.NavigationStarting += (_, e) =>
        {
            if (!string.Equals(e.Uri, virtualOrigin, StringComparison.OrdinalIgnoreCase))
                e.Cancel = true;
        };

        _webView.WebMessageReceived += OnWebMessageReceived;

        var navDone = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        void Handler(object? s, CoreWebView2NavigationCompletedEventArgs args)
        {
            _webView.NavigationCompleted -= Handler;
            if (args.IsSuccess) navDone.TrySetResult();
            else navDone.TrySetException(new SourceError("CONFIG", "站点运行环境初始化失败"));
        }
        _webView.NavigationCompleted += Handler;
        _webView.Navigate(virtualOrigin);
        await navDone.Task.WaitAsync(ct);

        await _webView.ExecuteScriptAsync(BootstrapJs).WaitAsync(ct);
        await _webView.ExecuteScriptAsync(_runtimeJs).WaitAsync(ct);
    }

    public async Task<ScriptProbeResult> LoadAndProbeAsync(string scriptCode, nint hostHwnd, CancellationToken ct)
    {
        await EnsureWebViewAsync(hostHwnd, ct);
        var evalExpr = $$"""
            (() => {
              Park.__pending = null;
              (0, eval)({{JsonSerializer.Serialize(scriptCode)}});
              const def = Park.__pending;
              return def ? { key: def.key, manifest: Park.manifest(def.key) } : null;
            })()
            """;
        var raw = await _webView!.ExecuteScriptAsync(evalExpr).WaitAsync(ct);
        var node = JsonNode.Parse(raw) as JsonObject
                   ?? throw new SourceError("CONFIG", "脚本没有调用 Park.register");

        var key = node["key"]?.GetValue<string>() ?? string.Empty;
        var manifestObj = node["manifest"] as JsonObject ?? throw new SourceError("CONFIG", "站点清单无效");
        var manifest = SourceManifest.FromJson(manifestObj);
        _manifest = manifest;
        return new ScriptProbeResult(key, manifest);
    }

    public async Task<SourceManifest> LoadAndSetupAsync(string scriptCode, JsonObject state, nint hostHwnd, CancellationToken ct)
    {
        var probed = await LoadAndProbeAsync(scriptCode, hostHwnd, ct);
        if (!string.IsNullOrEmpty(_sourceKey) && !string.Equals(probed.Key, _sourceKey, StringComparison.Ordinal))
        {
            throw new SourceError("CONFIG", "脚本注册的标识与安装记录不一致");
        }

        var setupScript = $$"""
            Park.setup({{JsonSerializer.Serialize(_sourceKey)}}, {{state.ToJsonString()}}, { waitForInit: true })
            """;
        // Execute async setup via Promise wrapper into WebMessage or polling helper
        var raw = await EvaluateAsyncPromiseAsync(setupScript, ct);
        if (raw is JsonObject updatedManifest)
            _manifest = SourceManifest.FromJson(updatedManifest);

        return _manifest!;
    }

    public async Task<JsonNode?> InvokeMethodAsync(string method, object?[] args, CancellationToken ct)
    {
        LastUsedUtc = DateTimeOffset.UtcNow;
        var argsJson = JsonSerializer.Serialize(args);
        var expr = $"Park.invoke({JsonSerializer.Serialize(_sourceKey)}, {JsonSerializer.Serialize(method)}, {argsJson}, undefined)";
        var envelope = await EvaluateAsyncPromiseAsync(expr, ct) as JsonObject
                       ?? throw new SourceError("PARSE", "站点返回了无效结果");

        if (envelope["ok"]?.GetValue<bool>() == true)
            return envelope["value"];

        using var errDoc = JsonDocument.Parse(envelope["error"]?.ToJsonString() ?? "{}");
        throw SourceError.FromJson(errDoc.RootElement);
    }

    private async Task<JsonNode?> EvaluateAsyncPromiseAsync(string promiseExpression, CancellationToken ct)
    {
        var callId = $"__eval_{Guid.NewGuid():N}";
        var slotScript = $$"""
            (() => {
              window.__parkEvalSlots = window.__parkEvalSlots || {};
              window.__parkEvalSlots[{{JsonSerializer.Serialize(callId)}}] = { done: false };
              Promise.resolve({{promiseExpression}}).then(
                v => { window.__parkEvalSlots[{{JsonSerializer.Serialize(callId)}}] = { done: true, ok: true, value: v === undefined ? null : v }; },
                e => { window.__parkEvalSlots[{{JsonSerializer.Serialize(callId)}}] = { done: true, ok: false, error: String(e && e.message || e) }; }
              );
            })()
            """;
        await _webView!.ExecuteScriptAsync(slotScript).WaitAsync(ct);

        var pollExpr = $$"""
            (() => {
              const s = window.__parkEvalSlots && window.__parkEvalSlots[{{JsonSerializer.Serialize(callId)}}];
              if (!s || !s.done) return null;
              delete window.__parkEvalSlots[{{JsonSerializer.Serialize(callId)}}];
              return s;
            })()
            """;

        while (true)
        {
            ct.ThrowIfCancellationRequested();
            var raw = await _webView.ExecuteScriptAsync(pollExpr).WaitAsync(ct);
            if (!string.IsNullOrEmpty(raw) && raw != "null")
            {
                var res = JsonNode.Parse(raw) as JsonObject;
                if (res?["ok"]?.GetValue<bool>() == true)
                    return res["value"];
                throw new SourceError("PARSE", res?["error"]?.GetValue<string>() ?? "站点调用失败");
            }
            await Task.Delay(16, ct);
        }
    }

    private void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        if (sender is not CoreWebView2 wv) return;
        var json = args.TryGetWebMessageAsString();
        if (string.IsNullOrEmpty(json)) return;

        var task = HandleBridgeMessageAsync(wv, json);
        _bridgeTasks[task] = 0;
        _ = task.ContinueWith(t => _bridgeTasks.TryRemove(t, out _), TaskScheduler.Default);
    }

    private async Task HandleBridgeMessageAsync(CoreWebView2 sender, string rawJson)
    {
        using var doc = JsonDocument.Parse(rawJson);
        var root = doc.RootElement;
        var id = root.TryGetProperty("id", out var idEl) ? idEl.GetString() ?? string.Empty : string.Empty;
        var name = root.GetProperty("name").GetString() ?? string.Empty;
        var payload = root.TryGetProperty("payload", out var pEl) ? pEl : default;

        if (name == "park_log")
        {
            if (payload.ValueKind == JsonValueKind.Object &&
                payload.TryGetProperty("message", out var msgObj) &&
                msgObj.ValueKind == JsonValueKind.Object)
            {
                var dict = new Dictionary<string, object?>(StringComparer.Ordinal)
                {
                    ["event"] = "plugin",
                    ["site"] = string.IsNullOrEmpty(_sourceKey) ? "probe" : _sourceKey,
                };
                foreach (var p in msgObj.EnumerateObject())
                    dict[p.Name] = p.Value.ToString();
                AppLog.Instance.Record(dict);
            }
            return;
        }

        if (string.IsNullOrEmpty(id)) return;

        try
        {
            if (_disposed) throw new SourceError("CONFIG", "站点运行环境已关闭");
            if (_sandboxed) throw new SourceError("CONFIG", "安装前预览时不允许访问网络与存储");

            object? result = name switch
            {
                "park_crypto" => CryptoBridge.Invoke(
                    payload.GetProperty("op").GetString() ?? string.Empty,
                    payload.TryGetProperty("args", out var ca) ? ca : default),
                "park_cookies" => await HandleCookiesAsync(payload),
                "park_persist" => await HandlePersistAsync(payload),
                "park_request" or "park_chat_request" => await HandleHttpAsync(payload),
                _ => throw new SourceError("UNSUPPORTED", $"Unknown bridge handler {name}"),
            };

            var reply = JsonSerializer.Serialize(new { id, __value = result });
            sender.PostWebMessageAsJson(reply);
        }
        catch (SourceError se)
        {
            var errReply = JsonSerializer.Serialize(new
            {
                id,
                __error = new
                {
                    code = se.Code,
                    message = se.RawMessage,
                    @params = se.Params,
                    status = se.Status,
                    url = se.Url,
                    diagnostics = se.Diagnostics,
                },
            });
            sender.PostWebMessageAsJson(errReply);
        }
        catch (Exception ex)
        {
            var errReply = JsonSerializer.Serialize(new
            {
                id,
                __error = new { code = "NETWORK", message = ex.Message },
            });
            sender.PostWebMessageAsJson(errReply);
        }
    }

    private async Task<object?> HandleHttpAsync(JsonElement payload)
    {
        var domains = _manifest?.Domains ?? [];
        var mode = _manifest?.NetworkMode ?? "auto";
        var resp = await _http.SendSourceRequestAsync(_sourceKey, domains, mode, payload, CancellationToken.None);
        return new
        {
            status = resp.Status,
            headers = resp.Headers,
            body = resp.Body,
            url = resp.FinalUrl,
        };
    }

    private async Task<object?> HandleCookiesAsync(JsonElement payload)
    {
        var op = payload.GetProperty("op").GetString();
        var args = payload.GetProperty("args");
        var uri = new Uri(args.GetProperty("url").GetString()!);

        switch (op)
        {
            case "get":
                return _cookies.GetCookies(_sourceKey, uri);
            case "set":
            {
                var map = new Dictionary<string, string>(StringComparer.Ordinal);
                if (args.TryGetProperty("cookies", out var cObj) && cObj.ValueKind == JsonValueKind.Object)
                {
                    foreach (var kv in cObj.EnumerateObject())
                        map[kv.Name] = kv.Value.ToString();
                }
                await _cookies.SetCookiesAsync(_sourceKey, uri, map);
                return true;
            }
            case "clear":
                await _cookies.ClearAsync(_sourceKey, uri);
                return true;
            default:
                return null;
        }
    }

    private async Task<object?> HandlePersistAsync(JsonElement payload)
    {
        if (_onPersist is null) return null;
        var flush = payload.TryGetProperty("flush", out var f) && f.ValueKind == JsonValueKind.True;
        var dataNode = payload.TryGetProperty("data", out var d)
            ? JsonNode.Parse(d.GetRawText()) as JsonObject ?? []
            : [];
        await _onPersist(_sourceKey, dataNode, flush);
        return null;
    }

    public Task WaitPendingBridgeCallsAsync() => Task.WhenAll(_bridgeTasks.Keys);

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;
        await WaitPendingBridgeCallsAsync();
        if (_webView is not null)
        {
            _webView.WebMessageReceived -= OnWebMessageReceived;
            _webView = null;
        }
        _controller?.Close();
        _controller = null;
    }
}
