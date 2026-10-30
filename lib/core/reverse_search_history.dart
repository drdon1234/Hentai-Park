import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'settings.dart';
import 'storage.dart';

class ReverseSearchHistory extends ChangeNotifier {
  static final instance = ReverseSearchHistory();
  final _store = JsonStore('reverse_search_history.json');
  Future<void>? _loading;
  final List<Map<String, dynamic>> entries = [];

  Future<void> load() => _loading ??= () async {
    final data = await _store.load();
    if (data is List) {
      for (final entry in data.take(20)) {
        if (entry is Map<String, dynamic> &&
            entry['image'] is String &&
            entry['sources'] is List &&
            entry['id'] is String) {
          try {
            final encoded = entry['image'] as String;
            if (encoded.length > 2400000 || base64Decode(encoded).isEmpty) {
              continue;
            }
          } on FormatException {
            continue;
          }
          entries.add(entry);
        }
      }
    }
  }();

  Future<void> add(Uint8List image, Iterable<String> sources) async {
    if (AppSettings.instance.incognito) return;
    await load();
    if (AppSettings.instance.incognito) return;
    final id = sha256.convert(image).toString();
    entries.removeWhere((e) => e['id'] == id);
    entries.insert(0, {
      'id': id,
      'image': base64Encode(image),
      'sources': sources.toList(),
      'time': DateTime.now().toIso8601String(),
    });
    if (entries.length > 20) entries.removeRange(20, entries.length);
    _save();
  }

  void remove(String id) {
    entries.removeWhere((e) => e['id'] == id);
    _save();
  }

  void clear() {
    entries.clear();
    _save();
  }

  void _save() {
    _store.save(List.of(entries));
    notifyListeners();
  }
}
