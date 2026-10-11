import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/core/models.dart';
import 'package:hentai_park/engine/crypto_bridge.dart';

void main() {
  test('manifest link and id patterns', () {
    final jm = SourceManifest({
      'key': 'jm',
      'name': '禁漫天堂',
      'linkPatterns': [
        r'(?:18comic|jmcomic|jm-?comic|18-comic)[\w.-]*\.\w+/(?:album|photo)s?/(\d{3,9})',
        r'(?:^|[^a-zA-Z0-9])[Jj][Mm]\s*[-_:：#]?\s*(\d{3,9})(?!\d)',
      ],
      'idPattern': r'^(?:[Jj][Mm])?(\d{3,9})$',
    });
    expect(jm.extractIds('看看 JM350234 和 https://18comic.vip/album/123456/'), ['350234', '123456']);
    expect(jm.matchExplicitId('jm350234'), '350234');
    final eh = SourceManifest({
      'key': 'ehentai',
      'linkPatterns': [r'(?:e-hentai|exhentai)\.org/g/(\d+/[0-9a-f]{10})'],
      'idPattern': r'^(\d+)[_/ ]([0-9a-f]{10})/?$',
    });
    expect(eh.extractIds('https://e-hentai.org/g/4243424/4b093ae73b/'), ['4243424/4b093ae73b']);
    expect(eh.matchExplicitId('4243424_4b093ae73b'), '4243424/4b093ae73b');
  });

  test('crypto bridge matches known vectors', () {
    expect(CryptoBridge.call('md5Hex', {'text': 'abc'}), '900150983cd24fb0d6963f7d28e17f72');
    expect(
      CryptoBridge.call('md5Hex', {
        'text': ['a', 'b'],
      }),
      ['0cc175b9c0f1b6a831c399e269772661', '92eb5ffee6ae2fec3ad71c777531578f'],
    );
    expect(
      CryptoBridge.call('hmacSha256Hex', {'key': 'key', 'text': 'The quick brown fox jumps over the lazy dog'}),
      'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
    );
  });
}
