import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

/// Native crypto primitives exposed to source scripts (`Park.crypto.*`).
class CryptoBridge {
  static const _uuid = Uuid();

  static Object? call(String op, Map<String, dynamic> a) {
    switch (op) {
      case 'md5Hex':
        final text = a['text'];
        if (text is List) return text.map((t) => c.md5.convert(utf8.encode('$t')).toString()).toList();
        return c.md5.convert(utf8.encode('$text')).toString();
      case 'sha256Hex':
        return c.sha256.convert(utf8.encode('${a['text']}')).toString();
      case 'hmacSha256Hex':
        return c.Hmac(c.sha256, utf8.encode('${a['key']}')).convert(utf8.encode('${a['text']}')).toString();
      case 'aesEcbDecrypt':
        return aesEcbDecrypt(base64.decode('${a['base64']}'.trim()), utf8.encode('${a['key']}'));
      case 'uuid':
        return _uuid.v4();
      default:
        throw UnsupportedError('crypto op $op');
    }
  }

  static String aesEcbDecrypt(Uint8List data, List<int> key) {
    final cipher = ECBBlockCipher(AESEngine())..init(false, KeyParameter(Uint8List.fromList(key)));
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
