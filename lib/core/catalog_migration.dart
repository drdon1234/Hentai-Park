import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../engine/source_identity.dart';
import 'storage.dart';

// 仅用于本地数据的一次性更名，不参与插件解析、更新或运行时路由。
final _renamed = {
  for (final site in [
    'dlsite',
    'toranoana',
    'fanza',
    'mgs',
    'fc2',
    'studios',
    'javmenu',
  ])
    'ranking-$site': 'catalog-$site',
};

String _reference(String value) {
  final colon = value.indexOf(':');
  final key = colon < 0 ? value : value.substring(0, colon);
  return _renamed.containsKey(key)
      ? '${_renamed[key]}${colon < 0 ? '' : value.substring(colon)}'
      : value;
}

/// 只改站点引用，不改用户输入、搜索词或插件筛选值。
Map<String, dynamic> migrateCatalogPreferences(Map<String, dynamic> values) {
  final result = Map<String, dynamic>.from(values);
  Map<String, dynamic> mapValues(Map value) => {
    for (final e in value.entries)
      '${e.key}': e.value is String ? _reference(e.value) : e.value,
  };
  for (final key in ['homeSources']) {
    if (result[key] case final Map value) result[key] = mapValues(value);
  }
  for (final key in [
    'homeHiddenSources',
    'homeExpandedSources',
    'libraryFilterSources',
    'aggregateExcluded',
    'tagDownloadIgnoredSources',
    'replyWithoutAsking',
  ]) {
    if (result[key] case final List value) {
      result[key] = [
        for (final item in value) item is String ? _reference(item) : item,
      ];
    }
  }
  if (result['ignoredSourceUpdates'] case final Map value) {
    result['ignoredSourceUpdates'] = {
      for (final e in value.entries) _reference('${e.key}'): e.value,
    };
  }
  if (result['rankingSelection'] case final Map value) {
    final selection = Map<String, dynamic>.from(value);
    if (selection['selected'] case final String selected) {
      selection['selected'] = _reference(selected);
    }
    for (final key in ['navigation', 'detailSources', 'searchSources']) {
      if (selection[key] case final Map entries) {
        selection[key] = mapValues(entries);
      }
    }
    if (selection['options'] case final Map entries) {
      selection['options'] = {
        for (final e in entries.entries) _reference('${e.key}'): e.value,
      };
    }
    result['rankingSelection'] = selection;
  }
  return result;
}

Future<Object?> _readJson(File file) async {
  if (!await file.exists()) return null;
  try {
    return jsonDecode(await file.readAsString());
  } on FormatException {
    // 原存储负责损坏恢复；迁移不能阻止原有恢复路径。
    return null;
  }
}

Future<void> _archive(File file) async {
  final target = '${file.path}.migrated';
  await file.rename(
    await File(target).exists()
        ? '$target-${DateTime.now().microsecondsSinceEpoch}'
        : target,
  );
}

/// 在配置、词包和插件加载之前执行。逐文件原子写入，可在中断后重试；
/// 新 key 已有的数据优先，旧站点文件归档原字节，不建立旧身份别名。
Future<void> migrateCatalogSources() async {
  final settings = AppPaths.dataFile('settings.json');
  if (await settings.exists()) {
    final value = await _readJson(settings);
    if (value is Map) {
      final migrated = jsonEncode(
        migrateCatalogPreferences(value.cast<String, dynamic>()),
      );
      if (jsonEncode(value) != migrated) {
        await writeFileAtomic(settings, utf8.encode(migrated));
      }
    }
  }
  final registry = AppPaths.dataFile('sources.json');
  if (!await registry.exists()) return;
  final value = await _readJson(registry);
  if (value is! Map || value['sources'] is! List) return;
  final records = List<dynamic>.from(value['sources'] as List);
  var changed = false;
  for (final record in records.whereType<Map>().toList()) {
    final oldKey = record['key'];
    final key = _renamed[oldKey];
    if (key == null || !['builtin', 'official'].contains(record['origin'])) {
      continue;
    }
    final oldState = AppPaths.dataFile('source_state_$oldKey.json');
    final newState = AppPaths.dataFile('source_state_$key.json');
    if (await oldState.exists() && !await newState.exists()) {
      await writeFileAtomic(newState, await oldState.readAsBytes());
    }
    if (await oldState.exists()) await _archive(oldState);
    final oldPacks = Directory(
      '${AppPaths.data.path}/tag_translations/${sourceIdentity(oldKey)}',
    );
    if (await oldPacks.exists()) {
      await for (final file in oldPacks.list(followLinks: false)) {
        if (file is! File || !file.path.endsWith('.json')) continue;
        final pack = await _readJson(file);
        if (pack is! Map ||
            pack['source'] != oldKey ||
            pack['locale'] is! String) {
          continue;
        }
        final locale = pack['locale'] as String;
        if (!RegExp(r'^[A-Za-z-]+$').hasMatch(locale)) continue;
        final target = AppPaths.dataFile(
          'tag_translations/${sourceIdentity(key)}/$locale.json',
        );
        if (!await target.exists()) {
          await target.parent.create(recursive: true);
          await writeFileAtomic(
            target,
            utf8.encode(jsonEncode({...pack, 'source': key})),
          );
        }
        // 归档原字节，词包管理不再把旧身份识别为已安装站点。
        await _archive(file);
      }
    }
    if (!records.whereType<Map>().any((entry) => entry['key'] == key)) {
      final code = await rootBundle.loadString('assets/sources/$key.js');
      final index = jsonDecode(
        await rootBundle.loadString('assets/sources/index.json'),
      ) as Map;
      final entry = (index['sources'] as List).cast<Map>().singleWhere(
        (entry) => entry['key'] == key,
      );
      final script = AppPaths.dataFile('sources/$key.js');
      await script.parent.create(recursive: true);
      await writeFileAtomic(script, utf8.encode(code));
      records.add({
        ...record,
        'key': key,
        'origin': 'builtin',
        'url': '',
        'version': entry['version'],
        'sha256': sha256.convert(utf8.encode(code)).toString(),
      });
    }
    records.remove(record);
    changed = true;
  }
  if (changed) {
    await writeFileAtomic(
      registry,
      utf8.encode(jsonEncode({...value, 'sources': records})),
    );
    for (final oldKey in _renamed.keys) {
      if (records.whereType<Map>().any((entry) => entry['key'] == oldKey)) {
        continue;
      }
      final script = AppPaths.dataFile('sources/$oldKey.js');
      if (await script.exists()) await _archive(script);
    }
  }
}
