import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/core/titles.dart';

void main() {
  test('searchableTitle strips bracket noise', () {
    expect(searchableTitle('[Circle (Artist)] Some Title (COMIC 2024-01) [中国翻訳] [DL版]'), 'Some Title');
    expect(searchableTitle('【汉化】标题（全彩）'), '标题');
    expect(searchableTitle('[only brackets]'), '[only brackets]');
  });

  test('normalizeTitle makes cross-source titles comparable', () {
    expect(normalizeTitle('[A] My Title! (B)'), normalizeTitle('my   title'));
    expect(normalizeTitle('标题·第二部'), normalizeTitle('【汉化组】标题 第二部'));
    expect(normalizeTitle('Other'), isNot(normalizeTitle('Another')));
  });

  test('parseChapterNumber', () {
    expect(parseChapterNumber('第12话'), 12);
    expect(parseChapterNumber('第 3.5 話 標題'), 3.5);
    expect(parseChapterNumber('Ch. 7'), 7);
    expect(parseChapterNumber('Vol.2 Chapter 15'), 15);
    expect(parseChapterNumber('第十二回'), 12);
    expect(parseChapterNumber('第一百零五话'), 105);
    expect(parseChapterNumber('Vol.3 番外 4'), 4);
    expect(parseChapterNumber('番外篇'), isNull);
  });
}
