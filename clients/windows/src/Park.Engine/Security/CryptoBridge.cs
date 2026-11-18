using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Park.Core.Configuration;

namespace Park.Engine.Security;

/// <summary>
/// Native cryptography primitives exposed to source scripts via Park.crypto.* (aligned with lib/engine/crypto_bridge.dart).
/// </summary>
public static class CryptoBridge
{
    public static object? Invoke(string op, JsonElement args)
    {
        switch (op)
        {
            case "randomBytes":
            {
                if (!args.TryGetProperty("length", out var lenEl) || !lenEl.TryGetInt32(out var length) || length is < 1 or > 65536)
                    throw new ArgumentException("随机字节长度无效");
                return RandomNumberGenerator.GetBytes(length).Select(b => (int)b).ToArray();
            }

            case "digestBytes":
            {
                if (!args.TryGetProperty("bytes", out var bytesEl) || bytesEl.ValueKind != JsonValueKind.Array)
                    throw new ArgumentException("摘要数据无效");
                var count = bytesEl.GetArrayLength();
                if (count > 2_097_152) throw new ArgumentException("摘要数据无效");

                var buffer = new byte[count];
                var idx = 0;
                foreach (var item in bytesEl.EnumerateArray())
                {
                    if (!item.TryGetInt32(out var v) || v is < 0 or > 255)
                        throw new ArgumentException("摘要数据无效");
                    buffer[idx++] = (byte)v;
                }

                var algo = args.TryGetProperty("algorithm", out var alEl) ? alEl.GetString() : null;
                byte[] digest = algo switch
                {
                    "sha1" => SHA1.HashData(buffer),
                    "sha256" => SHA256.HashData(buffer),
                    _ => throw new ArgumentException("摘要算法无效"),
                };
                return digest.Select(b => (int)b).ToArray();
            }

            case "md5Hex":
            {
                if (!args.TryGetProperty("text", out var txtEl))
                    return Convert.ToHexStringLower(MD5.HashData([]));
                if (txtEl.ValueKind == JsonValueKind.Array)
                {
                    var list = new List<string>(txtEl.GetArrayLength());
                    foreach (var item in txtEl.EnumerateArray())
                    {
                        var str = item.ValueKind == JsonValueKind.String ? item.GetString() ?? string.Empty : item.ToString();
                        list.Add(Convert.ToHexStringLower(MD5.HashData(Encoding.UTF8.GetBytes(str))));
                    }
                    return list;
                }
                var single = txtEl.ValueKind == JsonValueKind.String ? txtEl.GetString() ?? string.Empty : txtEl.ToString();
                return Convert.ToHexStringLower(MD5.HashData(Encoding.UTF8.GetBytes(single)));
            }

            case "sha256Hex":
            {
                var text = args.TryGetProperty("text", out var t)
                    ? (t.ValueKind == JsonValueKind.String ? t.GetString() ?? string.Empty : t.ToString())
                    : string.Empty;
                return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
            }

            case "hmacSha256Hex":
            {
                var key = args.TryGetProperty("key", out var k) ? (k.GetString() ?? string.Empty) : string.Empty;
                var text = args.TryGetProperty("text", out var t) ? (t.GetString() ?? string.Empty) : string.Empty;
                var mac = HMACSHA256.HashData(Encoding.UTF8.GetBytes(key), Encoding.UTF8.GetBytes(text));
                return Convert.ToHexStringLower(mac);
            }

            case "aesEcbDecrypt":
            {
                var b64 = (args.TryGetProperty("base64", out var b) ? b.GetString() : null)?.Trim() ?? string.Empty;
                var keyStr = args.TryGetProperty("key", out var k) ? (k.GetString() ?? string.Empty) : string.Empty;
                var cipherBytes = Convert.FromBase64String(b64);
                var keyBytes = Encoding.UTF8.GetBytes(keyStr);
                using var aes = Aes.Create();
                aes.Key = keyBytes;
                aes.Mode = CipherMode.ECB;
                aes.Padding = PaddingMode.None;
                using var decryptor = aes.CreateDecryptor();
                var plain = decryptor.TransformFinalBlock(cipherBytes, 0, (cipherBytes.Length / 16) * 16);
                var end = plain.Length;
                var pad = end > 0 ? plain[end - 1] : 0;
                if (pad is > 0 and <= 16) end -= pad;
                return Encoding.UTF8.GetString(plain, 0, end);
            }

            case "aesGcmEncrypt":
            case "aesGcmDecrypt":
            {
                var encrypt = op == "aesGcmEncrypt";
                var key = ParseHex(args, "key", [16, 24, 32]);
                var iv = ParseHex(args, "iv", [12]);
                var data = ParseHex(args, encrypt ? "plaintext" : "ciphertext", null, encrypt ? 4080 : 4096, allowEmpty: encrypt);
                var aad = args.TryGetProperty("aad", out var aadEl) && aadEl.ValueKind == JsonValueKind.String
                    ? ParseHex(args, "aad", null, 4096, allowEmpty: true)
                    : [];

                using var gcm = new AesGcm(key, 16);
                if (encrypt)
                {
                    var ciphertext = new byte[data.Length + 16];
                    gcm.Encrypt(iv, data, ciphertext.AsSpan(0, data.Length), ciphertext.AsSpan(data.Length, 16), aad);
                    return ciphertext.Select(b => (int)b).ToArray();
                }
                else
                {
                    if (data.Length < 16) throw new ArgumentException("AES-GCM 密文无效");
                    var bodyLen = data.Length - 16;
                    var plaintext = new byte[bodyLen];
                    // Throws AuthenticationTagMismatchException on tampering; never returns unauthenticated data
                    gcm.Decrypt(iv, data.AsSpan(0, bodyLen), data.AsSpan(bodyLen, 16), plaintext, aad);
                    return plaintext.Select(b => (int)b).ToArray();
                }
            }

            case "uuid":
                return Guid.NewGuid().ToString("D");

            default:
                throw new NotSupportedException($"Unsupported crypto op: {op}");
        }
    }

    private static byte[] ParseHex(JsonElement obj, string propName, int[]? allowedByteLengths, int maxBytes = 4096, bool allowEmpty = false)
    {
        if (!obj.TryGetProperty(propName, out var el) || el.ValueKind != JsonValueKind.String)
            throw new ArgumentException("AES-GCM 参数无效");

        var hex = el.GetString()!;
        if ((!allowEmpty && hex.Length == 0) || hex.Length % 2 != 0 || hex.Length > maxBytes * 2)
            throw new ArgumentException("AES-GCM 参数无效");

        byte[] bytes;
        try
        {
            bytes = Convert.FromHexString(hex);
        }
        catch (FormatException)
        {
            throw new ArgumentException("AES-GCM 参数无效");
        }

        if (allowedByteLengths is not null && !allowedByteLengths.Contains(bytes.Length))
            throw new ArgumentException("AES-GCM 参数无效");

        return bytes;
    }
}

/// <summary>
/// Encrypts machine-local secrets (such as Tavern AI API keys) using Windows DPAPI CurrentUser scope.
/// </summary>
public static class SecretVault
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("HentaiPark.Windows.SecretVault.v1");

    public static async Task SaveSecretAsync(string id, string plaintextSecret, CancellationToken ct = default)
    {
        AppPaths.EnsureDirectories();
        var safeId = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(id)));
        var path = Path.Combine(AppPaths.SecretsDir, $"{safeId}.bin");
        if (string.IsNullOrEmpty(plaintextSecret))
        {
            if (File.Exists(path)) File.Delete(path);
            return;
        }
        var encrypted = ProtectedData.Protect(Encoding.UTF8.GetBytes(plaintextSecret), Entropy, DataProtectionScope.CurrentUser);
        await AppPaths.WriteFileAtomicAsync(path, encrypted, ct).ConfigureAwait(false);
    }

    public static async Task<string?> ReadSecretAsync(string id, CancellationToken ct = default)
    {
        var safeId = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(id)));
        var path = Path.Combine(AppPaths.SecretsDir, $"{safeId}.bin");
        if (!File.Exists(path)) return null;
        try
        {
            var encrypted = await File.ReadAllBytesAsync(path, ct).ConfigureAwait(false);
            var plain = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plain);
        }
        catch
        {
            return null;
        }
    }
}
