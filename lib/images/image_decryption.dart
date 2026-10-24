import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/crypto.dart';
import '../core/models.dart';
import '../engine/domains.dart';

/// Source-declared payload decryption, applied before image validation and caching.
class ImageDecryption {
  ImageDecryption._(this._key, this._iv, this.domains, this.identity);

  final Uint8List _key;
  final Uint8List _iv;
  final List<String> domains;
  final String identity;

  static ImageDecryption? fromJson(Object? value) {
    if (value == null || value is Map && value.isEmpty) return null;
    if (value is! Map ||
        value['type'] != 'aes-cbc' ||
        value['key'] is! String ||
        value['iv'] is! String ||
        value['domains'] is! List) {
      throw SourceError('CONFIG', '图片解密配置无效');
    }
    final key = Uint8List.fromList(utf8.encode(value['key'] as String));
    final iv = Uint8List.fromList(utf8.encode(value['iv'] as String));
    final declared = value['domains'] as List;
    if (!const [16, 24, 32].contains(key.length) ||
        iv.length != 16 ||
        declared.isEmpty ||
        declared.any(
          (d) =>
              d is! String ||
              d.trim().isEmpty ||
              d.contains(RegExp(r'[/\s?#@]')),
        )) {
      throw SourceError('CONFIG', '图片解密配置无效');
    }
    final domains =
        declared
            .cast<String>()
            .map((d) => d.toLowerCase().trim())
            .toSet()
            .toList()
          ..sort();
    final identity = sha256
        .convert(
          utf8.encode(
            jsonEncode(['aes-cbc', value['key'], value['iv'], domains]),
          ),
        )
        .toString();
    return ImageDecryption._(key, iv, List.unmodifiable(domains), identity);
  }

  String cacheKey(String key) => '$key:decrypt:$identity';

  /// 声明域内的图片必须解密；图片 CDN 换到其他主机时，原始字节不是图片才尝试解密，
  /// 结果仍需通过 [looksLikeImage] 检查，不会把普通图片误当密文。
  Uint8List decode(
    Uint8List bytes,
    String url, {
    bool Function(Uint8List)? looksLikeImage,
  }) {
    if (!hostInDomains(Uri.tryParse(url)?.host ?? '', domains)) {
      if (looksLikeImage == null || looksLikeImage(bytes)) return bytes;
      try {
        final decoded = aesCbcDecrypt(bytes, _key, _iv);
        return looksLikeImage(decoded) ? decoded : bytes;
      } catch (_) {
        return bytes;
      }
    }
    try {
      return aesCbcDecrypt(bytes, _key, _iv);
    } catch (_) {
      throw SourceError('PARSE', '图片解密失败', url: url);
    }
  }
}
