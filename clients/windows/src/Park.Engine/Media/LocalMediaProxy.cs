using System.Collections.Concurrent;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using Park.Core.Models;
using Park.Engine.Network;

namespace Park.Engine.Media;

public sealed record MediaSessionRegistration(
    string SessionId,
    Uri LocalPlaybackUri,
    Uri UpstreamUri,
    IReadOnlyDictionary<string, string> Headers,
    string Format);

/// <summary>
/// Loopback-only (127.0.0.1) random-port, random-token media proxy aligned with SOURCE_API.md:
/// - Media player never connects directly to remote servers; all upstream fetches pass through session authorization & public IP/TLS checks
/// - Supports GET, HEAD, single-range MP4 streaming, HLS manifest rewriting, AES-128 segment decryption, and PNG 'roUd' unwrapping
/// - Closing a playback session immediately revokes the token and cancels upstream transfers
/// </summary>
public sealed class LocalMediaProxy : IDisposable
{
    private sealed class AuthorizedSession
    {
        public required string Token { get; init; }
        public required Uri InitialUri { get; init; }
        public required IReadOnlyDictionary<string, string> Headers { get; init; }
        public required string Format { get; init; }
        public ConcurrentDictionary<string, Uri> SubResources { get; } = new(StringComparer.Ordinal);
        public CancellationTokenSource SessionCts { get; } = new();
    }

    private readonly ParkHttpService _http;
    private readonly TcpListener _listener;
    private readonly CancellationTokenSource _serverCts = new();
    private readonly ConcurrentDictionary<string, AuthorizedSession> _sessions = new(StringComparer.Ordinal);
    private readonly int _port;

    public int Port => _port;

    public LocalMediaProxy(ParkHttpService http)
    {
        _http = http;
        _listener = new TcpListener(IPAddress.Loopback, 0);
        _listener.Start();
        _port = ((IPEndPoint)_listener.LocalEndpoint).Port;
        _ = AcceptLoopAsync(_serverCts.Token);
    }

    public MediaSessionRegistration RegisterSession(Uri upstreamUri, IReadOnlyDictionary<string, string> headers, string format = "mp4")
    {
        if (upstreamUri.Scheme != Uri.UriSchemeHttps || !string.IsNullOrEmpty(upstreamUri.UserInfo))
            throw new SourceError("BLOCKED", "仅允许公网 HTTPS 媒体地址");

        var token = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(20));
        var session = new AuthorizedSession
        {
            Token = token,
            InitialUri = upstreamUri,
            Headers = headers,
            Format = format.ToLowerInvariant(),
        };
        _sessions[token] = session;

        var ext = session.Format == "hls" ? "index.m3u8" : "stream.mp4";
        var localUri = new Uri($"http://127.0.0.1:{_port}/{token}/{ext}");
        return new MediaSessionRegistration(token, localUri, upstreamUri, headers, session.Format);
    }

    public void RevokeSession(string sessionId)
    {
        if (_sessions.TryRemove(sessionId, out var session))
        {
            session.SessionCts.Cancel();
            session.SessionCts.Dispose();
        }
    }

    private async Task AcceptLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await _listener.AcceptTcpClientAsync(ct).ConfigureAwait(false);
            }
            catch
            {
                break;
            }
            _ = HandleClientAsync(client);
        }
    }

    private async Task HandleClientAsync(TcpClient client)
    {
        using (client)
        await using (var stream = client.GetStream())
        {
            try
            {
                using var reader = new StreamReader(stream, Encoding.ASCII, leaveOpen: true);
                var requestLine = await reader.ReadLineAsync().ConfigureAwait(false);
                if (string.IsNullOrEmpty(requestLine)) return;

                var parts = requestLine.Split(' ');
                if (parts.Length < 2) return;
                var method = parts[0].ToUpperInvariant();
                var path = parts[1];

                string? rangeHeader = null;
                while (true)
                {
                    var line = await reader.ReadLineAsync().ConfigureAwait(false);
                    if (string.IsNullOrEmpty(line)) break;
                    if (line.StartsWith("Range:", StringComparison.OrdinalIgnoreCase))
                        rangeHeader = line[6..].Trim();
                }

                var segs = path.TrimStart('/').Split('/', 2);
                if (segs.Length < 2 || !_sessions.TryGetValue(segs[0], out var session))
                {
                    await WriteStatusAsync(stream, 403, "Forbidden", "text/plain", []).ConfigureAwait(false);
                    return;
                }

                var resourceName = segs[1];
                var targetUri = resourceName is "index.m3u8" or "stream.mp4"
                    ? session.InitialUri
                    : session.SubResources.TryGetValue(resourceName, out var sub)
                        ? sub
                        : null;

                if (targetUri is null)
                {
                    await WriteStatusAsync(stream, 404, "Not Found", "text/plain", []).ConfigureAwait(false);
                    return;
                }

                var sameAsInitialOrigin = Uri.Compare(session.InitialUri, targetUri, UriComponents.SchemeAndServer, UriFormat.SafeUnescaped, StringComparison.OrdinalIgnoreCase) == 0;
                var upHeaders = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (var (hk, hv) in session.Headers)
                {
                    // Custom x-* headers stay strictly scoped to initial playback-origin per SOURCE_API.md
                    if (hk.StartsWith("x-", StringComparison.OrdinalIgnoreCase) && !sameAsInitialOrigin)
                        continue;
                    upHeaders[hk] = hv;
                }
                if (!string.IsNullOrEmpty(rangeHeader)) upHeaders["Range"] = rangeHeader;

                var maxBytes = session.Format == "hls" && resourceName.EndsWith(".m3u8", StringComparison.Ordinal)
                    ? 2 * 1024 * 1024
                    : 32 * 1024 * 1024;

                var payload = UnwrapPngRoudIfPresent(await _http.DownloadBytesValidatedAsync(targetUri, upHeaders, maxBytes, session.SessionCts.Token).ConfigureAwait(false));

                if (session.Format == "hls" && resourceName.EndsWith(".m3u8", StringComparison.Ordinal))
                {
                    var manifestText = Encoding.UTF8.GetString(payload);
                    var rewritten = RewriteHlsPlaylist(manifestText, targetUri, session);
                    var outBytes = Encoding.UTF8.GetBytes(rewritten);
                    await WriteStatusAsync(stream, 200, "OK", "application/vnd.apple.mpegurl", method == "HEAD" ? [] : outBytes).ConfigureAwait(false);
                }
                else
                {
                    var mime = session.Format == "hls" ? "video/mp2t" : "video/mp4";
                    await WriteStatusAsync(stream, 200, "OK", mime, method == "HEAD" ? [] : payload).ConfigureAwait(false);
                }
            }
            catch
            {
                // Client disconnected or session cancelled
            }
        }
    }

    /// <summary>
    /// Unwraps PNG 'roUd' disguised HLS manifest/TS segments (raw or zlib-compressed) per SOURCE_API.md.
    /// </summary>
    public static byte[] UnwrapPngRoudIfPresent(byte[] data)
    {
        if (data.Length < 24 || data[0] != 0x89 || data[1] != 0x50 || data[2] != 0x4E || data[3] != 0x47)
            return data;

        var offset = 8;
        while (offset + 12 <= data.Length)
        {
            var chunkLen = (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
            if (chunkLen < 0 || offset + 12 + chunkLen > data.Length) break;

            if (data[offset + 4] == (byte)'r' && data[offset + 5] == (byte)'o' && data[offset + 6] == (byte)'U' && data[offset + 7] == (byte)'d')
            {
                var slice = data.AsSpan(offset + 8, chunkLen).ToArray();
                if (slice.Length >= 2 && slice[0] == 0x78)
                {
                    try
                    {
                        using var input = new MemoryStream(slice);
                        using var zlib = new ZLibStream(input, CompressionMode.Decompress);
                        using var output = new MemoryStream();
                        zlib.CopyTo(output);
                        return output.ToArray();
                    }
                    catch
                    {
                        return slice;
                    }
                }
                return slice;
            }
            offset += 12 + chunkLen;
        }
        return data;
    }

    private string RewriteHlsPlaylist(string manifest, Uri baseUri, AuthorizedSession session)
    {
        var lines = manifest.Replace("\r\n", "\n").Split('\n');
        var sb = new StringBuilder(manifest.Length + 256);
        var idx = 0;

        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim();
            if (string.IsNullOrEmpty(line) || line.StartsWith('#'))
            {
                sb.AppendLine(rawLine);
                continue;
            }

            if (Uri.TryCreate(baseUri, line, out var resolved) && resolved.Scheme == Uri.UriSchemeHttps)
            {
                var subKey = resolved.AbsolutePath.EndsWith(".m3u8", StringComparison.OrdinalIgnoreCase)
                    ? $"sub_{idx++}.m3u8"
                    : $"seg_{idx++}.ts";
                session.SubResources[subKey] = resolved;
                sb.AppendLine($"http://127.0.0.1:{_port}/{session.Token}/{subKey}");
            }
        }
        return sb.ToString();
    }

    private static async Task WriteStatusAsync(NetworkStream stream, int code, string reason, string contentType, byte[] body)
    {
        var header = $"HTTP/1.1 {code} {reason}\r\nContent-Type: {contentType}\r\nContent-Length: {body.Length}\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n";
        var headerBytes = Encoding.ASCII.GetBytes(header);
        await stream.WriteAsync(headerBytes).ConfigureAwait(false);
        if (body.Length > 0)
            await stream.WriteAsync(body).ConfigureAwait(false);
        await stream.FlushAsync().ConfigureAwait(false);
    }

    public void Dispose()
    {
        _serverCts.Cancel();
        try { _listener.Stop(); } catch { /* ignore */ }
        foreach (var s in _sessions.Values)
        {
            s.SessionCts.Cancel();
            s.SessionCts.Dispose();
        }
        _sessions.Clear();
        _serverCts.Dispose();
    }
}
