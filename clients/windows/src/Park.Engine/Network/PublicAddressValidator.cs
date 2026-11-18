using System.Net;
using System.Net.Sockets;
using Park.Core.Models;

namespace Park.Engine.Network;

/// <summary>
/// Validates public DNS addresses per DEVELOPMENT.md:
/// Accepts public unicast addresses plus proxy fake-ip benchmark blocks 198.18.0.0/15 and 2001:2::/48;
/// rejects loopback, private, link-local, CGNAT, multicast, and reserved ranges.
/// </summary>
public static class PublicAddressValidator
{
    public static bool IsAllowedRemoteAddress(IPAddress address, bool allowProxyFakeIp = true)
    {
        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }

        if (IPAddress.IsLoopback(address)) return false;

        if (address.AddressFamily == AddressFamily.InterNetwork)
        {
            Span<byte> b = stackalloc byte[4];
            address.TryWriteBytes(b, out _);

            // 198.18.0.0/15 (proxy fake-ip benchmark block)
            if (b[0] == 198 && (b[1] == 18 || b[1] == 19))
                return allowProxyFakeIp;

            if (b[0] == 0) return false;                                 // 0.0.0.0/8
            if (b[0] == 10) return false;                                // 10.0.0.0/8
            if (b[0] == 100 && (b[1] & 0xC0) == 64) return false;        // 100.64.0.0/10 CGNAT
            if (b[0] == 127) return false;                               // 127.0.0.0/8
            if (b[0] == 169 && b[1] == 254) return false;                // 169.254.0.0/16 Link-local
            if (b[0] == 172 && b[1] is >= 16 and <= 31) return false;    // 172.16.0.0/12
            if (b[0] == 192 && b[1] == 0 && b[2] == 0) return false;     // 192.0.0.0/24
            if (b[0] == 192 && b[1] == 0 && b[2] == 2) return false;     // 192.0.2.0/24 TEST-NET-1
            if (b[0] == 192 && b[1] == 168) return false;                // 192.168.0.0/16
            if (b[0] == 198 && b[1] == 51 && b[2] == 100) return false;  // 198.51.100.0/24 TEST-NET-2
            if (b[0] == 203 && b[1] == 0 && b[2] == 113) return false;   // 203.0.113.0/24 TEST-NET-3
            if (b[0] >= 224) return false;                               // Multicast & reserved 224.0.0.0/4+
            return true;
        }

        if (address.AddressFamily == AddressFamily.InterNetworkV6)
        {
            if (address.IsIPv6LinkLocal || address.IsIPv6Multicast || address.IsIPv6SiteLocal)
                return false;

            Span<byte> b = stackalloc byte[16];
            address.TryWriteBytes(b, out _);

            // ::/128 unspecified
            var allZero = true;
            for (var i = 0; i < 16; i++) if (b[i] != 0) { allZero = false; break; }
            if (allZero) return false;

            // fc00::/7 Unique Local
            if ((b[0] & 0xFE) == 0xFC) return false;

            // 2001:db8::/32 Documentation
            if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0D && b[3] == 0xB8) return false;

            // 2001:2::/48 Benchmarking / proxy fake-ip
            if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x00 && b[3] == 0x02 && b[4] == 0x00 && b[5] == 0x00)
                return allowProxyFakeIp;

            return true;
        }

        return false;
    }

    public static bool HostInDomains(string host, IEnumerable<string> declaredDomains)
    {
        if (string.IsNullOrWhiteSpace(host)) return false;
        var h = host.Trim().TrimEnd('.').ToLowerInvariant();
        foreach (var raw in declaredDomains)
        {
            var d = raw.Trim().TrimStart('.').TrimEnd('.').ToLowerInvariant();
            if (string.IsNullOrEmpty(d)) continue;
            if (h == d || h.EndsWith("." + d, StringComparison.Ordinal))
                return true;
        }
        return false;
    }

    public static async Task<IPAddress[]> ResolveValidatedAddressesAsync(string host, bool allowFakeIp, CancellationToken ct)
    {
        if (IPAddress.TryParse(host, out var literal))
        {
            if (!IsAllowedRemoteAddress(literal, allowProxyFakeIp: false))
                throw CreateNetworkError(host, "PRIVATE_ADDRESS", "不允许访问私网或保留地址");
            return [literal];
        }

        if (host.EndsWith(".localhost", StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith(".local", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(host, "localhost", StringComparison.OrdinalIgnoreCase))
        {
            throw CreateNetworkError(host, "PRIVATE_ADDRESS", "不允许访问私网或保留地址");
        }

        IPAddress[] addresses;
        try
        {
            addresses = await Dns.GetHostAddressesAsync(host, ct).ConfigureAwait(false);
        }
        catch (Exception)
        {
            throw CreateNetworkError(host, "DNS", "域名解析失败");
        }

        if (addresses.Length == 0 || addresses.Any(ip => !IsAllowedRemoteAddress(ip, allowFakeIp)))
        {
            throw CreateNetworkError(host, "PRIVATE_ADDRESS", "目标解析到了不允许的私网或保留地址");
        }

        return addresses;
    }

    private static SourceError CreateNetworkError(string host, string reason, string message) =>
        new("NETWORK", message, diagnostics: new Dictionary<string, string>
        {
            ["host"] = host,
            ["transport"] = "native",
            ["reason"] = reason,
        });
}
