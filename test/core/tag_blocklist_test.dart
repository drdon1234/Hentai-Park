import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/core/models.dart';
import 'package:hentai_park/core/tag_blocklist.dart';

void main() {
  final b = TagBlocklist(['Guro', 'female:scat', 'title:AI生成', '  ']);

  test('plain entries match any namespace, namespaced entries only their own', () {
    expect(b.match(title: 'x', tags: ['female:guro']), 'guro');
    expect(b.match(title: 'x', tags: ['guro']), 'guro');
    expect(b.match(title: 'x', tags: ['female:scat']), 'female:scat');
    expect(b.match(title: 'x', tags: ['male:scat']), isNull);
    expect(b.match(title: 'x', tags: ['guroish']), isNull);
  });

  test('title entries', () {
    expect(b.match(title: '[AI生成] 作品', tags: const []), 'title:ai生成');
    expect(TagBlocklist(const []).isEmpty, isTrue);
  });

  test('detail matching uses tag groups with namespaces', () {
    final d = WorkDetail({
      'id': '1',
      'title': 't',
      'tags': [
        {
          'namespace': 'female',
          'tags': [
            {'name': 'scat'},
          ],
        },
      ],
    }, 'ehentai');
    expect(b.matchDetail(d), ['female:scat']);
  });
}
