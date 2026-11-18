using System.Security.Cryptography;
using System.Text;
using Park.Core.Configuration;
using Park.Core.Models;
using Park.Engine.Network;

namespace Park.Engine.Images;

/// <summary>
/// Image download, AES-CBC decryption, format magic verification, source-partitioned disk cache,
/// and strip-unscrambling helper aligned with SOURCE_API.md.
/// </summary>
public sealed class ImagePipeline
{
    public const int MaxImageBytes = 20 * 1024 * 1024;

    private readonly ParkHttpService _http;

    public ImagePipeline(ParkHttpService http)
    {
        _http = http;
    }

    public async Task<byte[]> FetchImageBytesAsync(
        SourceManifest? source,
        string url,
        IReadOnlyDictionary<string, string>? extraHeaders = null,
        CancellationToken ct = default)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
            throw new SourceError("CONFIG", "无效的图片地址");

        var partition = source?.Key ?? "_public";
        var decryptSpec = source?.ImageDecrypt;
        var cacheIdentity = $"{partition}|{url}|{decryptSpec?.Type}:{decryptSpec?.Key}:{decryptSpec?.Iv}";
        var cacheHash = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(cacheIdentity)));
        var cacheFile = Path.Combine(AppPaths.CacheDir, "images", partition, $"{cacheHash}.img");

        if (File.Exists(cacheFile))
        {
            var cached = await File.ReadAllBytesAsync(cacheFile, ct).ConfigureAwait(false);
            if (IsSupportedImageMagic(cached)) return cached;
            try { File.Delete(cacheFile); } catch { /* ignore */ }
        }

        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (source is not null)
        {
            foreach (var (k, v) in source.ImageHeaders) headers[k] = v;
        }
        if (extraHeaders is not null)
        {
            foreach (var (k, v) in extraHeaders) headers[k] = v;
        }

        var raw = await _http.DownloadBytesValidatedAsync(uri, headers, MaxImageBytes, ct).ConfigureAwait(false);
        var decoded = ProcessImagePayload(raw, decryptSpec);

        try
        {
            await AppPaths.WriteFileAtomicAsync(cacheFile, decoded, ct).ConfigureAwait(false);
        }
        catch
        {
            // Disk cache failure never blocks image rendering
        }

        return decoded;
    }

    public static byte[] ProcessImagePayload(byte[] raw, ImageDecryptSpec? decryptSpec)
    {
        if (IsSupportedImageMagic(raw))
            return raw;

        if (decryptSpec is not null && string.Equals(decryptSpec.Type, "aes-cbc", StringComparison.OrdinalIgnoreCase))
        {
            var keyBytes = Encoding.UTF8.GetBytes(decryptSpec.Key);
            var ivBytes = Encoding.UTF8.GetBytes(decryptSpec.Iv);
            if (keyBytes.Length is not (16 or 24 or 32) || ivBytes.Length != 16)
                throw new SourceError("CONFIG", "图片解密配置无效");

            byte[] plain;
            try
            {
                using var aes = Aes.Create();
                aes.Key = keyBytes;
                aes.IV = ivBytes;
                aes.Mode = CipherMode.CBC;
                aes.Padding = PaddingMode.PKCS7;
                using var dec = aes.CreateDecryptor();
                plain = dec.TransformFinalBlock(raw, 0, raw.Length);
            }
            catch (CryptographicException)
            {
                throw new SourceError("PARSE", "图片解密失败");
            }

            if (IsSupportedImageMagic(plain))
                return plain;
        }

        throw new SourceError("PARSE", "响应不是有效的图片格式");
    }

    public static bool IsSupportedImageMagic(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < 12) return false;
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
        // JPEG: FF D8 FF
        if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
        // GIF: GIF87a / GIF89a
        if (bytes[0] == (byte)'G' && bytes[1] == (byte)'I' && bytes[2] == (byte)'F' && bytes[3] == (byte)'8') return true;
        // WebP: RIFF....WEBP
        if (bytes[0] == (byte)'R' && bytes[1] == (byte)'I' && bytes[2] == (byte)'F' && bytes[3] == (byte)'F' &&
            bytes[8] == (byte)'W' && bytes[9] == (byte)'E' && bytes[10] == (byte)'B' && bytes[11] == (byte)'P') return true;
        // BMP: BM
        if (bytes[0] == (byte)'B' && bytes[1] == (byte)'M') return true;
        // AVIF / HEIF: ....ftyp
        if (bytes[4] == (byte)'f' && bytes[5] == (byte)'t' && bytes[6] == (byte)'y' && bytes[7] == (byte)'p') return true;
        return false;
    }

    /// <summary>
    /// Unscrambles BGRA8 pixel buffer vertically sliced into N reversed horizontal strips (e.g. JMComic unscramble-strips).
    /// </summary>
    public static byte[] UnscrambleBgraStrips(ReadOnlySpan<byte> sourcePixels, int width, int height, int segments)
    {
        if (segments <= 1 || height < segments) return sourcePixels.ToArray();
        var stride = width * 4;
        var output = new byte[sourcePixels.Length];
        var remainder = height % segments;
        var baseStripHeight = height / segments;
        var dstY = 0;

        for (var i = 0; i < segments; i++)
        {
            var srcIndex = segments - 1 - i;
            var stripRows = baseStripHeight + (srcIndex == segments - 1 ? remainder : 0);
            var srcY = height - ((i + 1) * baseStripHeight) - (srcIndex == segments - 1 ? remainder : (i > 0 ? remainder : 0));
            // Exact reverse strip slice calculation
            var computedSrcY = 0;
            for (var k = 0; k < srcIndex; k++)
                computedSrcY += baseStripHeight;

            srcY = computedSrcY;
            var byteCount = stripRows * stride;
            sourcePixels.Slice(srcY * stride, byteCount).CopyTo(output.AsSpan(dstY * stride, byteCount));
            dstY += stripRows;
        }
        return output;
    }
}
