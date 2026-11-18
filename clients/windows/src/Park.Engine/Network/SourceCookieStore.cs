using System.Collections.Concurrent;
using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using Park.Core.Configuration;

namespace Park.Engine.Network;

public sealed record StoredCookie(
    string Name,
    string Value,
    string Domain,
    string Path,
    bool Secure,
    bool HttpOnly,
    long? ExpiresAtMs);

/// <summary>
/// Strictly partitioned cookie jar per source plugin.
/// Secure cookies are never sent over plain HTTP; clear/export/import stay isolated per partition.
/// </summary>
public sealed class SourceCookieStore
{
    private readonly ConcurrentDictionary<string, List<StoredCookie>> _partitions = new(StringComparer.Ordinal);
    private readonly Lock _sync = new();

    public async Task LoadAllAsync(CancellationToken ct = default)
    {
        AppPaths.EnsureDirectories();
        foreach (var file in Directory.EnumerateFiles(AppPaths.CookiesDir, "*.json"))
        {
            var partition = Path.GetFileNameWithoutExtension(file);
            try
            {
                var raw = await File.ReadAllTextAsync(file, ct).ConfigureAwait(false);
                var list = JsonSerializer.Deserialize<List<StoredCookie>>(raw) ?? [];
                _partitions[partition] = PruneExpired(list);
            }
            catch
            {
                // Ignore damaged cache file
            }
        }
    }

    public Dictionary<string, string> GetCookies(string partition, Uri uri)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        if (!_partitions.TryGetValue(partition, out var list)) return result;

        var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var isHttps = string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase);
        var host = uri.Host.ToLowerInvariant();
        var reqPath = string.IsNullOrEmpty(uri.AbsolutePath) ? "/" : uri.AbsolutePath;

        lock (_sync)
        {
            foreach (var c in list)
            {
                if (c.ExpiresAtMs is { } exp && exp <= now) continue;
                if (c.Secure && !isHttps) continue;
                if (!DomainMatches(host, c.Domain)) continue;
                if (!reqPath.StartsWith(c.Path, StringComparison.Ordinal)) continue;
                result[c.Name] = c.Value;
            }
        }
        return result;
    }

    public string BuildCookieHeader(string partition, Uri uri)
    {
        var map = GetCookies(partition, uri);
        return map.Count == 0 ? string.Empty : string.Join("; ", map.Select(kv => $"{kv.Key}={kv.Value}"));
    }

    public async Task SetCookiesAsync(string partition, Uri uri, IReadOnlyDictionary<string, string> values, bool? forceSecure = null, CancellationToken ct = default)
    {
        var isHttps = forceSecure ?? string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase);
        var host = uri.Host.ToLowerInvariant();
        List<StoredCookie> snapshot;

        lock (_sync)
        {
            var list = _partitions.GetOrAdd(partition, _ => []);
            foreach (var (name, val) in values)
            {
                if (string.IsNullOrWhiteSpace(name)) continue;
                list.RemoveAll(c => string.Equals(c.Name, name, StringComparison.Ordinal) && DomainMatches(host, c.Domain));
                list.Add(new StoredCookie(name.Trim(), val ?? string.Empty, host, "/", isHttps, false, null));
            }
            snapshot = PruneExpired(list);
            _partitions[partition] = snapshot;
        }

        await PersistPartitionAsync(partition, snapshot, ct).ConfigureAwait(false);
    }

    public async Task CaptureSetCookieHeadersAsync(string partition, Uri uri, IEnumerable<string> setCookieHeaders, CancellationToken ct = default)
    {
        var container = new CookieContainer();
        foreach (var header in setCookieHeaders)
        {
            try { container.SetCookies(uri, header); } catch { /* ignore malformed upstream cookie */ }
        }

        var parsed = container.GetCookies(uri);
        if (parsed.Count == 0) return;

        List<StoredCookie> snapshot;
        lock (_sync)
        {
            var list = _partitions.GetOrAdd(partition, _ => []);
            foreach (Cookie c in parsed)
            {
                var domain = string.IsNullOrEmpty(c.Domain) ? uri.Host.ToLowerInvariant() : c.Domain.TrimStart('.').ToLowerInvariant();
                var path = string.IsNullOrEmpty(c.Path) ? "/" : c.Path;
                long? exp = c.Expires != DateTime.MinValue ? new DateTimeOffset(c.Expires.ToUniversalTime()).ToUnixTimeMilliseconds() : null;

                list.RemoveAll(existing =>
                    string.Equals(existing.Name, c.Name, StringComparison.Ordinal) &&
                    string.Equals(existing.Domain, domain, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(existing.Path, path, StringComparison.Ordinal));

                if (!c.Expired)
                {
                    list.Add(new StoredCookie(c.Name, c.Value, domain, path, c.Secure, c.HttpOnly, exp));
                }
            }
            snapshot = PruneExpired(list);
            _partitions[partition] = snapshot;
        }

        await PersistPartitionAsync(partition, snapshot, ct).ConfigureAwait(false);
    }

    public async Task ClearAsync(string partition, Uri? uri = null, CancellationToken ct = default)
    {
        List<StoredCookie>? snapshot = null;
        lock (_sync)
        {
            if (uri is null)
            {
                _partitions.TryRemove(partition, out _);
            }
            else if (_partitions.TryGetValue(partition, out var list))
            {
                var host = uri.Host.ToLowerInvariant();
                list.RemoveAll(c => DomainMatches(host, c.Domain));
                snapshot = [.. list];
            }
        }

        var path = GetPartitionPath(partition);
        if (uri is null)
        {
            if (File.Exists(path)) File.Delete(path);
        }
        else if (snapshot is not null)
        {
            await PersistPartitionAsync(partition, snapshot, ct).ConfigureAwait(false);
        }
    }

    public JsonObject ExportAll()
    {
        var obj = new JsonObject();
        lock (_sync)
        {
            foreach (var (part, list) in _partitions)
            {
                var pruned = PruneExpired(list);
                if (pruned.Count == 0) continue;
                obj[part] = JsonSerializer.SerializeToNode(pruned);
            }
        }
        return obj;
    }

    public async Task ImportValidatedAsync(string partition, JsonArray cookieNodes, IReadOnlyList<string> allowedDomains, CancellationToken ct = default)
    {
        var accepted = new List<StoredCookie>();
        var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        foreach (var node in cookieNodes.OfType<JsonObject>())
        {
            var domain = node["Domain"]?.GetValue<string>() ?? node["domain"]?.GetValue<string>() ?? string.Empty;
            if (!PublicAddressValidator.HostInDomains(domain, allowedDomains)) continue;
            var name = node["Name"]?.GetValue<string>() ?? node["name"]?.GetValue<string>() ?? string.Empty;
            var val = node["Value"]?.GetValue<string>() ?? node["value"]?.GetValue<string>() ?? string.Empty;
            var path = node["Path"]?.GetValue<string>() ?? node["path"]?.GetValue<string>() ?? "/";
            var secure = node["Secure"]?.GetValue<bool>() ?? node["secure"]?.GetValue<bool>() ?? true;
            var httpOnly = node["HttpOnly"]?.GetValue<bool>() ?? node["httpOnly"]?.GetValue<bool>() ?? false;
            long? exp = node["ExpiresAtMs"] is JsonValue ev && ev.TryGetValue<long>(out var el) ? el : null;
            if (exp is not null && exp.Value <= now) continue;
            if (!string.IsNullOrEmpty(name))
                accepted.Add(new StoredCookie(name, val, domain.TrimStart('.').ToLowerInvariant(), path, secure, httpOnly, exp));
        }

        lock (_sync)
        {
            _partitions[partition] = accepted;
        }
        await PersistPartitionAsync(partition, accepted, ct).ConfigureAwait(false);
    }

    private static List<StoredCookie> PruneExpired(IEnumerable<StoredCookie> items)
    {
        var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        return items.Where(c => c.ExpiresAtMs is null || c.ExpiresAtMs.Value > now).ToList();
    }

    private static bool DomainMatches(string requestHost, string cookieDomain)
    {
        var d = cookieDomain.TrimStart('.').ToLowerInvariant();
        return requestHost == d || requestHost.EndsWith("." + d, StringComparison.Ordinal);
    }

    private static string GetPartitionPath(string partition)
    {
        var safe = string.Concat(partition.Where(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-'));
        if (string.IsNullOrEmpty(safe)) safe = "_default";
        return Path.Combine(AppPaths.CookiesDir, $"{safe}.json");
    }

    private static Task PersistPartitionAsync(string partition, List<StoredCookie> cookies, CancellationToken ct)
    {
        var json = JsonSerializer.Serialize(cookies);
        return AppPaths.WriteTextAtomicAsync(GetPartitionPath(partition), json, ct);
    }
}
