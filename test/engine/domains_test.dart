import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/engine/domains.dart';

void main() {
  test('registrableDomain', () {
    expect(registrableDomain('e-hentai.org'), 'e-hentai.org');
    expect(registrableDomain('forums.e-hentai.org'), 'e-hentai.org');
    expect(registrableDomain('A.B.Example.CO.JP'), 'example.co.jp');
    expect(registrableDomain('127.0.0.1'), '127.0.0.1');
    expect(registrableDomain('localhost'), 'localhost');
  });

  test('hostInDomains matches the domain and its subdomains only', () {
    expect(hostInDomains('api.e-hentai.org', ['e-hentai.org']), isTrue);
    expect(hostInDomains('e-hentai.org', ['e-hentai.org']), isTrue);
    expect(hostInDomains('evil-e-hentai.org', ['e-hentai.org']), isFalse);
    expect(hostInDomains('e-hentai.org.evil.com', ['e-hentai.org']), isFalse);
  });

  test('declaredDomains prefers explicit domains, else derives them', () {
    expect(declaredDomains({'domains': ['E-Hentai.org', 'exhentai.org'], 'homepage': 'https://x.com'}), ['e-hentai.org', 'exhentai.org']);
    expect(
      declaredDomains({
        'homepage': 'https://www.hanime1.me',
        'network': {'origin': 'https://hanime1.me'},
        'account': {'loginUrl': 'https://forums.e-hentai.org/index.php'},
      })..sort(),
      ['e-hentai.org', 'hanime1.me'],
    );
    expect(declaredDomains({}), isEmpty);
  });
}
