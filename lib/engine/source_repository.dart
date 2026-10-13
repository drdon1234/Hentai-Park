import 'dart:convert';

import 'source_identity.dart';
import 'official_repository.dart';
import '../core/versions.dart';

import '../core/models.dart';
import 'http_service.dart';

/// A validated script published by the official source repository.
class SourceRepositoryEntry {
  const SourceRepositoryEntry({
    required this.key,
    required this.name,
    required this.version,
    required this.url,
    required this.sha256,
    required this.apiVersion,
  });

  final String key;
  final String name;
  final String version;
  final String url;
  final String sha256;
  final int apiVersion;
}

class SourceRepositoryIndex {
  SourceRepositoryIndex({
    required List<SourceRepositoryEntry> entries,
    Map<String, String> failures = const {},
  }) : entries = List.unmodifiable(entries),
       failures = Map.unmodifiable(failures);

  final List<SourceRepositoryEntry> entries;
  final Map<String, String> failures;
}

/// The repository index may move, but each script must point to a Git commit.
class SourceRepository {
  SourceRepository({Future<String> Function(String url)? read})
    : _read = read ?? _download;

  static const indexUrl = '$officialRawBase/sources/index.json';
  static const supportedApiVersion = 1;
  final Future<String> Function(String url) _read;

  static Future<String> _download(String url) async {
    final res = await HttpService.instance.send(method: 'GET', url: url);
    if (!res.ok) {
      throw SourceError('HTTP', '仓库返回 HTTP ${res.status}', status: res.status);
    }
    return res.text;
  }

  Future<SourceRepositoryIndex> fetch() async {
    final text = await _read(indexUrl);
    try {
      return parse(jsonDecode(text));
    } on FormatException {
      throw SourceError('CONFIG', '官方源索引格式无效');
    }
  }

  static SourceRepositoryIndex parse(Object? data) {
    if (data is! Map ||
        data['apiVersion'] is! int ||
        data['sources'] is! List) {
      throw SourceError('CONFIG', '官方源索引格式无效');
    }
    if (data['apiVersion'] != supportedApiVersion) {
      throw SourceError('UNSUPPORTED', '官方源索引需要更新应用后才能使用');
    }
    final entries = <String, SourceRepositoryEntry>{};
    final failures = <String, String>{};
    final seen = <String>{};
    final names = <String, String>{};
    var position = 0;
    for (final raw in data['sources'] as List) {
      position++;
      final name =
          raw is Map &&
              raw['name'] is String &&
              (raw['name'] as String).trim().isNotEmpty
          ? raw['name'] as String
          : raw is Map && isSourceKey(raw['key'])
          ? raw['key'] as String
          : '#$position';
      if (raw is Map && isSourceKey(raw['key'])) {
        final key = raw['key'] as String;
        if (!seen.add(key)) {
          entries.remove(key);
          failures[names[key]!] = '官方源标识重复：$key';
          continue;
        }
        names[key] = name;
      }
      try {
        final entry = _parseEntry(raw);
        entries[entry.key] = entry;
      } on SourceError catch (error) {
        failures[name] = error.rawMessage;
      }
    }
    return SourceRepositoryIndex(
      entries: entries.values.toList(),
      failures: failures,
    );
  }

  static SourceRepositoryEntry _parseEntry(Object? raw) {
    if (raw is! Map ||
        !isSourceKey(raw['key']) ||
        raw['name'] is! String ||
        (raw['name'] as String).trim().isEmpty ||
        !isReleaseVersion(raw['version']) ||
        !isSha256(raw['sha256']) ||
        raw['apiVersion'] is! int ||
        (raw['apiVersion'] as int) < 1) {
      throw SourceError('CONFIG', '官方源条目缺少有效的必填字段');
    }
    if (!isOfficialAsset(raw['url'], 'assets/sources/${raw['key']}.js')) {
      throw SourceError('CONFIG', '官方源脚本地址必须指向官方仓库的固定提交');
    }
    return SourceRepositoryEntry(
      key: raw['key'] as String,
      name: raw['name'] as String,
      version: raw['version'] as String,
      url: raw['url'] as String,
      sha256: (raw['sha256'] as String).toLowerCase(),
      apiVersion: raw['apiVersion'] as int,
    );
  }
}
