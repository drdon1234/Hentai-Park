import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/crypto.dart';
import '../core/models.dart';

/// Source-declared payload decryption, applied before image validation and caching.
class ImageDecryption {
  ImageDecryption._(this._key, this._iv, this.identity);

  final Uint8List _key;
  final Uint8List _iv;
  final String identity;

  static ImageDecryption? fromJson(Object? value) {
    if (value == null || value is Map && value.isEmpty) return null;
    if (value is! Map ||
        value['type'] != 'aes-cbc' ||
        value['key'] is! String ||
        value['iv'] is! String) {
      throw SourceError('CONFIG', '图片解密配置无效');
    }
    final key = Uint8List.fromList(utf8.encode(value['key'] as String));
    final iv = Uint8List.fromList(utf8.encode(value['iv'] as String));
    if (!const [16, 24, 32].contains(key.length) || iv.length != 16) {
      throw SourceError('CONFIG', '图片解密配置无效');
    }
    final identity = sha256
        .convert(
          utf8.encode(jsonEncode(['aes-cbc', value['key'], value['iv']])),
        )
        .toString();
    return ImageDecryption._(key, iv, identity);
  }

  String cacheKey(String key) => '$key:decrypt:$identity';

  /// 通过内容格式区分明文图片与密文，不依赖 CDN 主机。
  Uint8List decode(
    Uint8List bytes, {
    required bool Function(Uint8List) looksLikeImage,
  }) {
    if (looksLikeImage(bytes)) return bytes;
    try {
      final decoded = aesCbcDecrypt(bytes, _key, _iv);
      if (looksLikeImage(decoded)) return decoded;
    } catch (_) {}
    throw SourceError('PARSE', '图片解密失败');
  }
}
