import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/core/credential_paste.dart';

const _eh = ['ipb_member_id', 'ipb_pass_hash', 'igneous'];
const _pica = ['email', 'password'];

void main() {
  test('cookie text with no separators between pairs', () {
    expect(parsePastedCredentials('ipb_member_id: 1234567ipb_pass_hash: 0123456789abcdefigneous: zz9yy8', _eh, cookies: true), {
      'ipb_member_id': '1234567',
      'ipb_pass_hash': '0123456789abcdef',
      'igneous': 'zz9yy8',
    });
  });

  test('cookie header and mixed separators', () {
    expect(parsePastedCredentials('Cookie: ipb_member_id=42; ipb_pass_hash="abc"; nw=1', _eh, cookies: true), {'ipb_member_id': '42', 'ipb_pass_hash': 'abc'});
    expect(parsePastedCredentials('ipb_member_id : 7\nIPB_PASS_HASH= ff', _eh, cookies: true), {'ipb_member_id': '7', 'ipb_pass_hash': 'ff'});
  });

  test('cookie login never guesses from unlabeled text', () {
    expect(parsePastedCredentials('just some text', _eh, cookies: true), isEmpty);
  });

  test('username/password pairs', () {
    expect(parsePastedCredentials('someone/secret', _pica, cookies: false), {'email': 'someone', 'password': 'secret'});
    expect(parsePastedCredentials('someone:pa/ss:word', _pica, cookies: false), {'email': 'someone', 'password': 'pa/ss:word'});
    expect(parsePastedCredentials('someone  secret', _pica, cookies: false), {'email': 'someone', 'password': 'secret'});
    expect(parsePastedCredentials('someone\nsecret with space', _pica, cookies: false), {'email': 'someone', 'password': 'secret with space'});
    expect(parsePastedCredentials('email: a@b.c password: x', _pica, cookies: false), {'email': 'a@b.c', 'password': 'x'});
  });
}
