import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

/// Native crypto primitives exposed to source scripts (`Park.crypto.*`).
class CryptoBridge {
  static const _uuid = Uuid();

  static Object? call(String op, Map<String, dynamic> a) {
    switch (op) {
      case 'randomBytes':
        final length = a['length'];
        if (length is! int || length < 1 || length > 65536) {
          throw ArgumentError('随机字节长度无效');
        }
        final random = Random.secure();
        return List<int>.generate(length, (_) => random.nextInt(256));
      case 'digestBytes':
        final bytes = a['bytes'];
        if (bytes is! List ||
            bytes.length > 2097152 ||
            bytes.any((b) => b is! int || b < 0 || b > 255)) {
          throw ArgumentError('摘要数据无效');
        }
        final hash = switch (a['algorithm']) {
          'sha1' => c.sha1,
          'sha256' => c.sha256,
          _ => throw ArgumentError('摘要算法无效'),
        };
        return hash.convert(bytes.cast<int>()).bytes;
      case 'md5Hex':
        final text = a['text'];
        if (text is List) {
          return text
              .map((t) => c.md5.convert(utf8.encode('$t')).toString())
              .toList();
        }
        return c.md5.convert(utf8.encode('$text')).toString();
      case 'sha256Hex':
        return c.sha256.convert(utf8.encode('${a['text']}')).toString();
      case 'hmacSha256Hex':
        return c.Hmac(
          c.sha256,
          utf8.encode('${a['key']}'),
        ).convert(utf8.encode('${a['text']}')).toString();
      case 'aesEcbDecrypt':
        return aesEcbDecrypt(
          base64.decode('${a['base64']}'.trim()),
          utf8.encode('${a['key']}'),
        );
      case 'aesGcmDecrypt':
        Uint8List hex(String name, Set<int>? lengths, {int maximum = 4096}) {
          final value = a[name];
          if (value is! String ||
              value.length > maximum * 2 ||
              value.length.isOdd ||
              !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value) ||
              (lengths != null && !lengths.contains(value.length ~/ 2))) {
            throw ArgumentError('AES-GCM 参数无效');
          }
          return Uint8List.fromList([
            for (var i = 0; i < value.length; i += 2)
              int.parse(value.substring(i, i + 2), radix: 16),
          ]);
        }
        final key = hex('key', {16, 24, 32});
        final iv = hex('iv', {12});
        final data = hex('ciphertext', null);
        if (data.length < 16) throw ArgumentError('AES-GCM 密文无效');
        final cipher = GCMBlockCipher(AESEngine())
          ..init(
            false,
            AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
          );
        // 认证标签必须校验成功，不能把未认证的明文传给插件。
        return cipher.process(data).toList();
      case 'uuid':
        return _uuid.v4();
      default:
        throw UnsupportedError('crypto op $op');
    }
  }

  static String aesEcbDecrypt(Uint8List data, List<int> key) {
    final cipher = ECBBlockCipher(AESEngine())
      ..init(false, KeyParameter(Uint8List.fromList(key)));
    final out = Uint8List(data.length);
    for (var offset = 0; offset + 16 <= data.length; offset += 16) {
      cipher.processBlock(data, offset, out, offset);
    }
    var end = out.length;
    final pad = end > 0 ? out[end - 1] : 0;
    if (pad > 0 && pad <= 16) end -= pad;
    return utf8.decode(out.sublist(0, end), allowMalformed: true);
  }
}
