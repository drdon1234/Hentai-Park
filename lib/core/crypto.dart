import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Decrypts a complete AES-CBC payload with validated PKCS#7 padding.
Uint8List aesCbcDecrypt(Uint8List data, Uint8List key, Uint8List iv) {
  if (!const [16, 24, 32].contains(key.length) ||
      iv.length != 16 ||
      data.isEmpty ||
      data.length % 16 != 0) {
    throw ArgumentError('AES-CBC 参数或密文无效');
  }
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        false,
        PaddedBlockCipherParameters(
          ParametersWithIV(KeyParameter(key), iv),
          null,
        ),
      );
  return cipher.process(data);
}
