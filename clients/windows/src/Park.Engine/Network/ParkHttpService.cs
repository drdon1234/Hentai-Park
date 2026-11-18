using System.Net;
using System.Net.Http.Headers;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Text;
using System.Text.Json;
using Park.Core.Configuration;
using Park.Core.Models;

namespace Park.Engine.Network;

public sealed record ParkHttpResponse(
    int Status,
    IReadOnlyDictionary<string, string> Headers,
    string Body,
    string FinalUrl);

/// <summary>
/// Secure native HTTP client aligned with SOURCE_API.md & WEB_PLUGIN_HOST.md:
/// - Public DNS validation + IP pinning + original hostname TLS SNI & system certificate verification
/// - Optional connectAddress (public IPv4 on HTTPS 443) without bypassing user proxy
/// - Hop-by-hop redirect guard (max 5 hops): strips sensitive headers and stops re-injecting source cookies across origins
/// - Read-only retry policy for bodyless GET/HEAD and explicit readOnly:true text POST
/// </summary>
public sealed class ParkHttpService : IDisposable
{
    private static readonly IReadOnlySet<string> CrossOriginSafeHeaders = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "User-Agent", "Accept", "Accept-Language", "Accept-Encoding", "Range", "Cache-Control", "Pragma",
    };

    private readonly SourceCookieStore _cookies;
    private readonly Lock _poolLock = new();
    private string _currentProxy = string.Empty;
    private HttpMessageInvoker? _defaultInvoker;

    public string DefaultUserAgent { get; set; } =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";

    public Func<string, Uri, IReadOnlyList<string>, CancellationToken, Task<ParkHttpResponse?>>? BrowserFallbackHandler { get; set; }

    public ParkHttpService(SourceCookieStore cookies)
    {
        _cookies = cookies;
    }

    public async Task<ParkHttpResponse> SendSourceRequestAsync(
        string partition,
        IReadOnlyList<string> declaredDomains,
        string networkMode,
        JsonElement options,
        CancellationToken ct)
    {
        var rawUrl = options.TryGetProperty("url", out var uEl) ? uEl.GetString() : null;
        if (!Uri.TryCreate(rawUrl, UriKind.Absolute, out var targetUri) ||
            (targetUri.Scheme != Uri.UriSchemeHttps && targetUri.Scheme != Uri.UriSchemeHttp) ||
            !string.IsNullOrEmpty(targetUri.UserInfo))
        {
            throw new SourceError("CONFIG", "无效的请求地址");
        }

        var methodStr = (options.TryGetProperty("method", out var mEl) ? mEl.GetString() : "GET")?.ToUpperInvariant() ?? "GET";
        var followRedirects = !options.TryGetProperty("followRedirects", out var frEl) || frEl.ValueKind != JsonValueKind.False;
        var responseType = options.TryGetProperty("responseType", out var rtEl) ? rtEl.GetString() ?? "text" : "text";
        var timeoutMs = options.TryGetProperty("timeout", out var toEl) && toEl.TryGetInt32(out var tms) ? Math.Clamp(tms, 1000, 120_000) : 20_000;
        var readOnlyPost = options.TryGetProperty("readOnly", out var roEl) && roEl.ValueKind == JsonValueKind.True;
        var connectAddress = options.TryGetProperty("connectAddress", out var caEl) && caEl.ValueKind == JsonValueKind.String
            ? caEl.GetString()?.Trim()
            : null;

        IPAddress? pinnedConnectIp = null;
        if (!string.IsNullOrEmpty(connectAddress))
        {
            if (targetUri.Scheme != Uri.UriSchemeHttps || targetUri.Port != 443 ||
                !IPAddress.TryParse(connectAddress, out var parsedIp) ||
                parsedIp.AddressFamily != AddressFamily.InterNetwork ||
                !PublicAddressValidator.IsAllowedRemoteAddress(parsedIp, allowProxyFakeIp: false))
            {
                throw new SourceError("CONFIG", "connectAddress 仅支持公网 IPv4 的 HTTPS 443 请求");
            }
            pinnedConnectIp = parsedIp;
        }

        var customHeaders = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (options.TryGetProperty("headers", out var hdrEl) && hdrEl.ValueKind == JsonValueKind.Object)
        {
            foreach (var prop in hdrEl.EnumerateObject())
            {
                customHeaders[prop.Name] = prop.Value.ValueKind == JsonValueKind.String ? prop.Value.GetString() ?? string.Empty : prop.Value.ToString();
            }
        }

        var (bodyBytes, contentType) = BuildRequestBody(options);
        var isSafeRetryable = (methodStr is "GET" or "HEAD" && bodyBytes is null) ||
                              (methodStr == "POST" && readOnlyPost && bodyBytes is not null && !options.TryGetProperty("bodyBase64", out _) && !options.TryGetProperty("multipart", out _));

        var maxAttempts = isSafeRetryable ? 3 : 1;
        Exception? lastFailure = null;

        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            try
            {
                var res = await ExecuteWithRedirectGuardAsync(
                    partition, declaredDomains, targetUri, methodStr, customHeaders, bodyBytes, contentType,
                    followRedirects, responseType, timeoutMs, pinnedConnectIp, ct).ConfigureAwait(false);

                if (isSafeRetryable && attempt < maxAttempts && res.Status is 502 or 503 or 504)
                {
                    await Task.Delay(attempt * 300, ct).ConfigureAwait(false);
                    continue;
                }

                // Auto browser fallback on Cloudflare / 403 / 429 for HTTPS same-domain bodyless GET/HEAD
                if (networkMode == "auto" &&
                    followRedirects &&
                    pinnedConnectIp is null &&
                    methodStr is "GET" or "HEAD" &&
                    bodyBytes is null &&
                    targetUri.Scheme == Uri.UriSchemeHttps &&
                    PublicAddressValidator.HostInDomains(targetUri.Host, declaredDomains) &&
                    (res.Status is 403 or 429 || LooksLikeCloudflareChallenge(res)) &&
                    BrowserFallbackHandler is not null)
                {
                    var fallback = await BrowserFallbackHandler(partition, targetUri, declaredDomains, ct).ConfigureAwait(false);
                    if (fallback is not null) return fallback;
                }

                return res;
            }
            catch (SourceError se) when (isSafeRetryable && attempt < maxAttempts && IsTransientReason(se))
            {
                lastFailure = se;
                await Task.Delay(attempt * 300, ct).ConfigureAwait(false);
            }
        }

        throw lastFailure ?? new SourceError("NETWORK", "网络请求失败");
    }

    private async Task<ParkHttpResponse> ExecuteWithRedirectGuardAsync(
        string partition,
        IReadOnlyList<string> declaredDomains,
        Uri initialUri,
        string initialMethod,
        Dictionary<string, string> initialHeaders,
        byte[]? initialBody,
        string? initialContentType,
        bool followRedirects,
        string responseType,
        int timeoutMs,
        IPAddress? connectAddress,
        CancellationToken outerCt)
    {
        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(outerCt);
        timeoutCts.CancelAfter(timeoutMs);
        var ct = timeoutCts.Token;

        var currentUri = initialUri;
        var currentMethod = initialMethod;
        var currentHeaders = new Dictionary<string, string>(initialHeaders, StringComparer.OrdinalIgnoreCase);
        var currentBody = initialBody;
        var currentContentType = initialContentType;
        var crossedOrigin = false;

        HttpMessageInvoker? oneShotInvoker = null;
        try
        {
            for (var hop = 0; hop <= 5; hop++)
            {
                var usePinned = hop == 0 && connectAddress is not null;
                var invoker = usePinned
                    ? (oneShotInvoker = CreateInvoker(AppSettings.Instance.Proxy, connectAddress))
                    : GetOrCreateSharedInvoker();

                using var req = new HttpRequestMessage(new HttpMethod(currentMethod), currentUri);
                if (!currentHeaders.ContainsKey("User-Agent"))
                    req.Headers.TryAddWithoutValidation("User-Agent", DefaultUserAgent);

                foreach (var (hk, hv) in currentHeaders)
                {
                    if (string.Equals(hk, "Content-Type", StringComparison.OrdinalIgnoreCase)) continue;
                    req.Headers.TryAddWithoutValidation(hk, hv);
                }

                // Inject partition cookies only if within declared domains and chain has not crossed origin
                if (!crossedOrigin &&
                    !currentHeaders.ContainsKey("Cookie") &&
                    PublicAddressValidator.HostInDomains(currentUri.Host, declaredDomains))
                {
                    var cookieHdr = _cookies.BuildCookieHeader(partition, currentUri);
                    if (!string.IsNullOrEmpty(cookieHdr))
                        req.Headers.TryAddWithoutValidation("Cookie", cookieHdr);
                }

                if (currentBody is not null)
                {
                    var content = new ByteArrayContent(currentBody);
                    if (!string.IsNullOrEmpty(currentContentType))
                        content.Headers.ContentType = MediaTypeHeaderValue.Parse(currentContentType);
                    req.Content = content;
                }

                HttpResponseMessage resp;
                try
                {
                    resp = await invoker.SendAsync(req, ct).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (!outerCt.IsCancellationRequested)
                {
                    throw new SourceError("TIMEOUT", "{host}: 连接超时",
                        new Dictionary<string, string> { ["host"] = currentUri.Host },
                        diagnostics: new Dictionary<string, string> { ["host"] = currentUri.Host, ["transport"] = "native", ["reason"] = "CONNECT_TIMEOUT" });
                }
                catch (AuthenticationException)
                {
                    throw new SourceError("NETWORK", "TLS 证书校验失败",
                        diagnostics: new Dictionary<string, string> { ["host"] = currentUri.Host, ["transport"] = "native", ["reason"] = "TLS_CERTIFICATE" });
                }
                catch (HttpRequestException hre)
                {
                    var terminated = hre.InnerException?.Message.Contains("Connection terminated during handshake", StringComparison.OrdinalIgnoreCase) == true;
                    throw new SourceError("NETWORK", "{host}: 无法连接（{error}）",
                        new Dictionary<string, string> { ["host"] = currentUri.Host, ["error"] = hre.HttpRequestError.ToString() },
                        diagnostics: new Dictionary<string, string>
                        {
                            ["host"] = currentUri.Host,
                            ["transport"] = "native",
                            ["reason"] = terminated ? "TLS_HANDSHAKE_TERMINATED" : "CONNECTION",
                        });
                }

                using (resp)
                {
                    if (!crossedOrigin &&
                        PublicAddressValidator.HostInDomains(currentUri.Host, declaredDomains) &&
                        resp.Headers.TryGetValues("Set-Cookie", out var setCookies))
                    {
                        await _cookies.CaptureSetCookieHeadersAsync(partition, currentUri, setCookies, ct).ConfigureAwait(false);
                    }

                    var code = (int)resp.StatusCode;
                    if (followRedirects && code is 301 or 302 or 303 or 307 or 308 && resp.Headers.Location is { } loc)
                    {
                        if (hop == 5)
                            throw new SourceError("NETWORK", "重定向次数过多");

                        var nextUri = loc.IsAbsoluteUri ? loc : new Uri(currentUri, loc);
                        if ((nextUri.Scheme != Uri.UriSchemeHttps && nextUri.Scheme != Uri.UriSchemeHttp) || !string.IsNullOrEmpty(nextUri.UserInfo))
                            throw new SourceError("BLOCKED", "访问受限");

                        var sameOrigin = Uri.Compare(currentUri, nextUri, UriComponents.SchemeAndServer, UriFormat.SafeUnescaped, StringComparison.OrdinalIgnoreCase) == 0;
                        if (!sameOrigin) crossedOrigin = true;

                        if (code == 303 && currentMethod != "HEAD")
                        {
                            currentMethod = "GET";
                            currentBody = null;
                            currentContentType = null;
                        }
                        else if (code is 301 or 302 && currentMethod == "POST")
                        {
                            currentMethod = "GET";
                            currentBody = null;
                            currentContentType = null;
                        }
                        else if (!sameOrigin && (currentBody is not null || currentMethod is not ("GET" or "HEAD")))
                        {
                            // Refuse cross-origin redirect with body or non-GET/HEAD method per SOURCE_API.md
                            throw new SourceError("BLOCKED", "拒绝携带请求体的跨来源重定向");
                        }

                        if (!sameOrigin)
                        {
                            var safeCopy = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                            foreach (var (k, v) in currentHeaders)
                            {
                                if (CrossOriginSafeHeaders.Contains(k)) safeCopy[k] = v;
                            }
                            currentHeaders = safeCopy;
                        }

                        currentUri = nextUri;
                        continue;
                    }

                    var rawBytes = await ReadBoundedBytesAsync(resp.Content, maxBytes: 24 * 1024 * 1024, ct).ConfigureAwait(false);
                    var headersOut = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    foreach (var h in resp.Headers) headersOut[h.Key.ToLowerInvariant()] = string.Join(", ", h.Value);
                    foreach (var h in resp.Content.Headers) headersOut[h.Key.ToLowerInvariant()] = string.Join(", ", h.Value);

                    var bodyOut = responseType == "base64"
                        ? Convert.ToBase64String(rawBytes)
                        : DecodeResponseText(rawBytes, resp.Content.Headers.ContentType?.CharSet);

                    return new ParkHttpResponse(code, headersOut, bodyOut, currentUri.AbsoluteUri);
                }
            }
            throw new SourceError("NETWORK", "网络请求异常中止");
        }
        finally
        {
            oneShotInvoker?.Dispose();
        }
    }

    public async Task<byte[]> DownloadBytesValidatedAsync(
        Uri uri,
        IReadOnlyDictionary<string, string>? headers,
        int maxBytes,
        CancellationToken ct)
    {
        if (uri.Scheme != Uri.UriSchemeHttps || !string.IsNullOrEmpty(uri.UserInfo) || (!uri.IsDefaultPort && uri.Port != 443))
            throw new SourceError("BLOCKED", "仅允许公网 HTTPS 443 媒体地址");

        var currentUri = uri;
        var currentHeaders = headers is not null
            ? new Dictionary<string, string>(headers, StringComparer.OrdinalIgnoreCase)
            : new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        for (var hop = 0; hop <= 5; hop++)
        {
            var invoker = GetOrCreateSharedInvoker();
            using var req = new HttpRequestMessage(HttpMethod.Get, currentUri);
            req.Headers.TryAddWithoutValidation("User-Agent", DefaultUserAgent);
            foreach (var (k, v) in currentHeaders)
                req.Headers.TryAddWithoutValidation(k, v);

            using var resp = await invoker.SendAsync(req, ct).ConfigureAwait(false);
            var code = (int)resp.StatusCode;
            if (code is 301 or 302 or 303 or 307 or 308 && resp.Headers.Location is { } loc)
            {
                var next = loc.IsAbsoluteUri ? loc : new Uri(currentUri, loc);
                if (next.Scheme != Uri.UriSchemeHttps || !string.IsNullOrEmpty(next.UserInfo))
                    throw new SourceError("BLOCKED", "重定向地址不被允许");

                var sameOrigin = Uri.Compare(currentUri, next, UriComponents.SchemeAndServer, UriFormat.SafeUnescaped, StringComparison.OrdinalIgnoreCase) == 0;
                if (!sameOrigin)
                {
                    currentHeaders = currentHeaders
                        .Where(kv => CrossOriginSafeHeaders.Contains(kv.Key))
                        .ToDictionary(kv => kv.Key, kv => kv.Value, StringComparer.OrdinalIgnoreCase);
                }
                currentUri = next;
                continue;
            }

            if (code is < 200 or >= 300)
                throw new SourceError("HTTP", "站点返回 HTTP {status}", new Dictionary<string, string> { ["status"] = code.ToString() }, status: code);

            return await ReadBoundedBytesAsync(resp.Content, maxBytes, ct).ConfigureAwait(false);
        }
        throw new SourceError("NETWORK", "重定向次数过多");
    }

    private HttpMessageInvoker GetOrCreateSharedInvoker()
    {
        var proxy = AppSettings.Instance.Proxy;
        lock (_poolLock)
        {
            if (_defaultInvoker is not null && string.Equals(_currentProxy, proxy, StringComparison.Ordinal))
                return _defaultInvoker;

            var old = _defaultInvoker;
            _currentProxy = proxy;
            _defaultInvoker = CreateInvoker(proxy, pinnedIp: null);
            if (old is not null)
            {
                _ = Task.Delay(TimeSpan.FromSeconds(30)).ContinueWith(_ => old.Dispose(), TaskScheduler.Default);
            }
            return _defaultInvoker;
        }
    }

    private static HttpMessageInvoker CreateInvoker(string proxyRaw, IPAddress? pinnedIp)
    {
        var hasProxy = !string.IsNullOrWhiteSpace(proxyRaw);
        var handler = new SocketsHttpHandler
        {
            AllowAutoRedirect = false,
            UseCookies = false,
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate | DecompressionMethods.Brotli,
            PooledConnectionLifetime = TimeSpan.FromMinutes(3),
            ConnectTimeout = TimeSpan.FromSeconds(12),
            SslOptions = new SslClientAuthenticationOptions
            {
                EnabledSslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13,
                // System root CA verification strictly kept ON per AGENTS.md
            },
        };

        if (hasProxy)
        {
            var normalized = proxyRaw.Contains("://", StringComparison.Ordinal) ? proxyRaw : $"http://{proxyRaw}";
            handler.Proxy = new WebProxy(normalized);
            handler.UseProxy = true;
        }
        else
        {
            handler.UseProxy = false;
            handler.ConnectCallback = async (context, token) =>
            {
                var host = context.DnsEndPoint.Host;
                var port = context.DnsEndPoint.Port;
                var candidates = pinnedIp is not null
                    ? [pinnedIp]
                    : await PublicAddressValidator.ResolveValidatedAddressesAsync(host, allowFakeIp: true, token).ConfigureAwait(false);

                var socket = new Socket(SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
                try
                {
                    await socket.ConnectAsync(candidates, port, token).ConfigureAwait(false);
                    return new NetworkStream(socket, ownsSocket: true);
                }
                catch
                {
                    socket.Dispose();
                    throw;
                }
            };
        }

        return new HttpMessageInvoker(handler, disposeHandler: true);
    }

    private static (byte[]? Bytes, string? ContentType) BuildRequestBody(JsonElement options)
    {
        if (options.TryGetProperty("json", out var jsonEl) && jsonEl.ValueKind != JsonValueKind.Undefined && jsonEl.ValueKind != JsonValueKind.Null)
        {
            return (Encoding.UTF8.GetBytes(jsonEl.GetRawText()), "application/json; charset=utf-8");
        }

        if (options.TryGetProperty("form", out var formEl) && formEl.ValueKind == JsonValueKind.Object)
        {
            var pairs = new List<string>();
            foreach (var p in formEl.EnumerateObject())
            {
                if (p.Value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) continue;
                pairs.Add($"{Uri.EscapeDataString(p.Name)}={Uri.EscapeDataString(p.Value.ToString())}");
            }
            return (Encoding.UTF8.GetBytes(string.Join('&', pairs)), "application/x-www-form-urlencoded");
        }

        if (options.TryGetProperty("bodyBase64", out var b64El) && b64El.ValueKind == JsonValueKind.String)
        {
            var raw = Convert.FromBase64String(b64El.GetString()!);
            if (raw.Length > 2 * 1024 * 1024) throw new SourceError("CONFIG", "二进制请求体超过 2 MiB 上限");
            return (raw, "application/octet-stream");
        }

        if (options.TryGetProperty("multipart", out var mpEl) && mpEl.ValueKind == JsonValueKind.Object)
        {
            var boundary = $"----ParkBoundary{Guid.NewGuid():N}";
            using var ms = new MemoryStream();
            if (mpEl.TryGetProperty("fields", out var fieldsEl) && fieldsEl.ValueKind == JsonValueKind.Object)
            {
                foreach (var f in fieldsEl.EnumerateObject())
                {
                    var header = $"--{boundary}\r\nContent-Disposition: form-data; name=\"{f.Name}\"\r\n\r\n{f.Value}\r\n";
                    ms.Write(Encoding.UTF8.GetBytes(header));
                }
            }
            if (mpEl.TryGetProperty("file", out var fileEl) && fileEl.ValueKind == JsonValueKind.Object)
            {
                var fname = fileEl.GetProperty("filename").GetString() ?? "image.png";
                var ffield = fileEl.GetProperty("name").GetString() ?? "file";
                var fmime = fileEl.GetProperty("mimeType").GetString() ?? "image/png";
                var fbytes = Convert.FromBase64String(fileEl.GetProperty("base64").GetString() ?? string.Empty);
                var header = $"--{boundary}\r\nContent-Disposition: form-data; name=\"{ffield}\"; filename=\"{fname}\"\r\nContent-Type: {fmime}\r\n\r\n";
                ms.Write(Encoding.UTF8.GetBytes(header));
                ms.Write(fbytes);
                ms.Write("\r\n"u8);
            }
            ms.Write(Encoding.UTF8.GetBytes($"--{boundary}--\r\n"));
            if (ms.Length > 2 * 1024 * 1024) throw new SourceError("CONFIG", "上传数据超过 2 MiB 上限");
            return (ms.ToArray(), $"multipart/form-data; boundary={boundary}");
        }

        if (options.TryGetProperty("body", out var bodyEl) && bodyEl.ValueKind == JsonValueKind.String)
        {
            return (Encoding.UTF8.GetBytes(bodyEl.GetString()!), "text/plain; charset=utf-8");
        }

        return (null, null);
    }

    private static async Task<byte[]> ReadBoundedBytesAsync(HttpContent content, int maxBytes, CancellationToken ct)
    {
        if (content.Headers.ContentLength is { } len && len > maxBytes)
            throw new SourceError("BLOCKED", "响应体积超过安全上限");

        await using var stream = await content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        using var ms = new MemoryStream();
        var buffer = new byte[32768];
        while (true)
        {
            var read = await stream.ReadAsync(buffer, ct).ConfigureAwait(false);
            if (read == 0) break;
            if (ms.Length + read > maxBytes)
                throw new SourceError("BLOCKED", "响应体积超过安全上限");
            ms.Write(buffer, 0, read);
        }
        return ms.ToArray();
    }

    private static string DecodeResponseText(byte[] bytes, string? charset)
    {
        if (!string.IsNullOrWhiteSpace(charset))
        {
            try
            {
                Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
                return Encoding.GetEncoding(charset.Trim('"', '\'')).GetString(bytes);
            }
            catch
            {
                // Fall back to UTF-8
            }
        }
        return Encoding.UTF8.GetString(bytes);
    }

    private static bool LooksLikeCloudflareChallenge(ParkHttpResponse res) =>
        res.Status is 403 or 503 &&
        (res.Headers.ContainsKey("cf-mitigated") ||
         res.Body.Contains("challenges.cloudflare.com", StringComparison.OrdinalIgnoreCase) ||
         res.Body.Contains("__cf_chl_opt", StringComparison.OrdinalIgnoreCase));

    private static bool IsTransientReason(SourceError err) =>
        err.Diagnostics.TryGetValue("reason", out var r) &&
        r is "CONNECTION" or "CONNECT_TIMEOUT" or "RECEIVE_TIMEOUT" or "TLS_HANDSHAKE_TERMINATED";

    public void Dispose()
    {
        lock (_poolLock)
        {
            _defaultInvoker?.Dispose();
            _defaultInvoker = null;
        }
    }
}
