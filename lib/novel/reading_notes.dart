import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/storage.dart';

class ReadingNote {
  ReadingNote({
    required this.id,
    required this.uid,
    required this.chapterId,
    required this.offset,
    required this.quote,
    required this.note,
    required this.time,
  });
  final String id, uid, chapterId, quote, note;
  final int offset;
  final DateTime time;
  Map<String, dynamic> toJson() => {
    'id': id,
    'uid': uid,
    'chapterId': chapterId,
    'offset': offset,
    'quote': quote,
    'note': note,
    'time': time.millisecondsSinceEpoch,
  };
  static ReadingNote? parse(Object? raw) {
    if (raw is! Map ||
        raw['id'] is! String ||
        raw['uid'] is! String ||
        raw['chapterId'] is! String ||
        raw['offset'] is! int ||
        raw['time'] is! int ||
        raw['quote'] is! String ||
        raw['note'] is! String ||
        (raw['offset'] as int) < 0 ||
        (raw['time'] as int).abs() > 8640000000000000) {
      return null;
    }
    return ReadingNote(
      id: raw['id'],
      uid: raw['uid'],
      chapterId: raw['chapterId'],
      offset: raw['offset'],
      quote: raw['quote'],
      note: raw['note'],
      time: DateTime.fromMillisecondsSinceEpoch(raw['time']),
    );
  }
}

/// 与正文下载分开保存，删除下载不会删除用户的书签与标注。
class ReadingNotes extends ChangeNotifier {
  static final instance = ReadingNotes();
  final _store = JsonStore('reading_notes.json');
  final Map<String, ReadingNote> _notes = {};
  Future<void> load() async {
    final data = await _store.load();
    final parsed = <String, ReadingNote>{};
    var invalid = data != null && data is! List;
    for (final raw in data is List ? data : const []) {
      final note = ReadingNote.parse(raw);
      if (note == null) {
        invalid = true;
      } else {
        parsed[note.id] = note;
      }
    }
    if (invalid) {
      // 标注无法重建；在后续保存替换文件之前保留全部原始记录。
      final file = AppPaths.dataFile('reading_notes.json');
      if (await file.exists()) {
        await file.copy(
          '${file.path}.invalid-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
    }
    _notes
      ..clear()
      ..addAll(parsed);
  }

  List<ReadingNote> forWork(String uid) =>
      _notes.values.where((n) => n.uid == uid).toList()
        ..sort((a, b) => b.time.compareTo(a.time));
  List<Map<String, dynamic>> exportJson() =>
      _notes.values.map((n) => n.toJson()).toList();
  Future<void> _save() async {
    _store.save(exportJson());
    await _store.flush();
    notifyListeners();
  }

  Future<void> add({
    required String uid,
    required String chapterId,
    required int offset,
    String quote = '',
    String note = '',
  }) async {
    final entry = ReadingNote(
      id: const Uuid().v4(),
      uid: uid,
      chapterId: chapterId,
      offset: offset.clamp(0, 1 << 31),
      quote: quote,
      note: note,
      time: DateTime.now(),
    );
    _notes[entry.id] = entry;
    await _save();
  }

  Future<void> remove(String id) async {
    _notes.remove(id);
    await _save();
  }

  Future<void> update(String id, {required String note}) async {
    final old = _notes[id];
    if (old == null) return;
    _notes[id] = ReadingNote(
      id: old.id,
      uid: old.uid,
      chapterId: old.chapterId,
      offset: old.offset,
      quote: old.quote,
      note: note,
      time: DateTime.now(),
    );
    await _save();
  }

  Future<void> merge(Object? data) async {
    if (data is! List) return;
    for (final raw in data) {
      final entry = ReadingNote.parse(raw);
      if (entry != null &&
          (_notes[entry.id] == null ||
              entry.time.isAfter(_notes[entry.id]!.time))) {
        _notes[entry.id] = entry;
      }
    }
    await _save();
  }

  List<Map<String, dynamic>> prepareMerge(Object? data) {
    final next = {..._notes};
    if (data != null && data is! List) throw const FormatException('备份数据无效');
    for (final raw in data is List ? data : const []) {
      final entry = ReadingNote.parse(raw);
      if (entry == null) throw const FormatException('备份数据无效');
      if (next[entry.id] == null || entry.time.isAfter(next[entry.id]!.time)) {
        next[entry.id] = entry;
      }
    }
    return next.values.map((e) => e.toJson()).toList();
  }

  Future<void> reload() async {
    await load();
    notifyListeners();
  }
}
