import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../library/library.dart';
import 'backup.dart';
import 'models.dart';
import 'store.dart';

class TavernTransfer {
  static bool _isLorebookJson(Object? value) {
    if (value is! Map) return false;
    if (value['entries'] is List || value['entries'] is Map) return true;
    final data = value['data'];
    if (data is Map && data['name'] is! String) {
      final book = data['character_book'];
      return book is Map && (book['entries'] is List || book['entries'] is Map);
    }
    return false;
  }

  static Future<void> importBytes(
    Uint8List bytes,
    String name, {
    String? expectedKind,
  }) async {
    if (bytes.isEmpty || bytes.length > 32 * 1024 * 1024) {
      throw const FormatException('酒馆资源格式无效');
    }
    final png =
        bytes.length > 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
    final value = png ? null : jsonDecode(utf8.decode(bytes));
    if (value is Map &&
        value['resources'] is List &&
        value['sessions'] is List) {
      validateTavernBackup(value);
      await Library.instance.db.transaction(
        () => mergeTavernBackup(Library.instance.db, value),
      );
      TavernStore.instance.restored();
      return;
    }
    final kind = !png && _isLorebookJson(value) ? 'lorebook' : 'character';
    if (expectedKind != null && expectedKind != kind) {
      throw const FormatException('导入文件类型不匹配');
    }
    final format = png ? 'png' : 'json';
    final resource = TavernResource.parse(kind, format, bytes);
    final item = WorkItem({
      'id': const Uuid().v4(),
      'title': resource.name.isEmpty ? name : resource.name,
      'mediaKind': 'tavern',
      'tavernKind': kind,
    }, 'tavern-local');
    await TavernStore.instance.save(item, resource, format, bytes);
  }

  static Future<Uint8List> exportSession(TavernSession session) async {
    final resources = <Map<String, dynamic>>[];
    for (final uid in {session.resourceUid, ...session.books}) {
      var saved = await TavernStore.instance.get(uid);
      if (saved == null && uid == session.resourceUid) {
        final split = uid.indexOf(':');
        if (split < 1) throw const FormatException('酒馆会话格式无效');
        saved = SavedTavernResource(
          item: WorkItem({
            'id': uid.substring(split + 1),
            'title': session.title,
            'mediaKind': 'tavern',
            'tavernKind': 'character',
          }, uid.substring(0, split)),
          resource: TavernResource(kind: 'character', raw: session.card),
          format: 'json',
          bytes: Uint8List.fromList(utf8.encode(jsonEncode(session.card))),
        );
      }
      if (saved == null) throw const FormatException('关联的资源已不存在');
      resources.add({
        'item': saved.item.toJson(),
        'kind': saved.resource.kind,
        'format': saved.format,
        'original': base64Encode(saved.bytes),
        'savedAt': session.updatedAt,
      });
    }
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'resources': resources,
          'sessions': [session.toJson()],
        }),
      ),
    );
  }
}
