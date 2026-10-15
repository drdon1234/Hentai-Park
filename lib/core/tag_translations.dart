import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../engine/background_downloads.dart';
import '../engine/network_client.dart';
import '../engine/official_repository.dart';
import '../engine/source_identity.dart';
import 'async_tasks.dart';
import 'localization.dart';
import 'settings.dart';
import 'storage.dart';
import 'versions.dart';

/// Official dictionaries affect presentation only; original tags stay intact.
class TagTranslationPack {
  TagTranslationPack._(
    this.source,
    this.locale,
    this.version,
    this.tags,
    this.provenance,
  );
  final String source;
  final String locale;
  final String version;
  final Map<String, String> tags;
  final List<Map<String, dynamic>> provenance;

  static final locales = AppLocalizations.languageNames.keys.toList(
    growable: false,
  );
  static const maxBytes = 8 * 1024 * 1024;
  static const maxTags = 100000;

  static TagTranslationPack parse(
    Object? data, {
    required String source,
    required String locale,
  }) {
    if (!isSourceKey(source) ||
        !locales.contains(locale) ||
        data is! Map ||
        data['schema'] != 1 ||
        data['source'] != source ||
        data['locale'] != locale ||
        data['version'] is! String ||
        !isReleaseVersion(data['version']) ||
        data['tags'] is! Map) {
      throw const FormatException('标签翻译包格式或语言不匹配');
    }
    final raw = data['tags'] as Map;
    final origins = data['provenance'];
    if (origins != null &&
        (origins is! List ||
            origins.length > 32 ||
            origins.any(
              (v) => v is! Map || v.keys.any((key) => key is! String),
            ))) {
      throw const FormatException('词包来源格式无效');
    }
    if (raw.isEmpty || raw.length > maxTags) {
      throw const FormatException('标签数量无效');
    }
    final tags = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('标签格式无效');
      }
      final key = (entry.key as String).trim();
      final value = (entry.value as String).trim();
      if (key.isEmpty ||
          key.length > 256 ||
          value.isEmpty ||
          value.length > 512 ||
          RegExp(
            r'^(?:TODO|TBD|N/A|\?+|-+)$',
            caseSensitive: false,
          ).hasMatch(value)) {
        throw const FormatException('标签译文无效');
      }
      final normalized = key.toLowerCase();
      if (tags.containsKey(normalized)) throw const FormatException('重复标签');
      tags[normalized] = value;
    }
    return TagTranslationPack._(
      source,
      locale,
      data['version'] as String,
      Map.unmodifiable(tags),
      List.unmodifiable(
        (data['provenance'] as List? ?? []).whereType<Map>().map(
          (e) => Map<String, dynamic>.unmodifiable(e.cast<String, dynamic>()),
        ),
      ),
    );
  }

  String? lookup(String label, {String namespace = ''}) {
    final key = label.trim().toLowerCase();
    if (namespace.isNotEmpty) {
      final value = tags['${namespace.trim().toLowerCase()}:$key'];
      if (value != null) return value;
    }
    return tags[key];
  }

  Map<String, Object> toJson() => {
    'schema': 1,
    'source': source,
    'locale': locale,
    'version': version,
    'tags': tags,
    if (provenance.isNotEmpty) 'provenance': provenance,
  };
}

class TagTranslations extends ChangeNotifier {
  TagTranslations({Future<String> Function(String)? readRemote})
    : _readRemote = readRemote ?? _readRemoteDefault;
  static final instance = TagTranslations();
  final Future<String> Function(String) _readRemote;
  static const indexUrl = '$officialRawBase/tag-translations/index.json';
  // 安装状态与词表分离；启动只发现文件，词表按源和语言按需读取。
  final _installed = <String>{};
  final _packs = <String, TagTranslationPack>{};
  final _loading = <String, Future<void>>{};
  final _pending = <String, Future<void>>{};
  final _revisions = <String, int>{};
  final _installs = SerialExecutor();
  final _bundled = <String>{};
  bool _guideBusy = false;
  bool _guideDeferred = false;
  bool claimDownloadGuide(String source, String locale) {
    if (_guideBusy ||
        _guideDeferred ||
        !AppSettings.instance.tagDownloadReminders ||
        installed(source, locale) ||
        (!bundled(source, locale) && !remoteAvailable(source, locale))) {
      return false;
    }
    _guideBusy = true;
    return true;
  }

  void finishDownloadGuide({bool deferred = false, bool never = false}) {
    _guideBusy = false;
    _guideDeferred = deferred;
    if (never) AppSettings.instance.tagDownloadReminders = false;
  }

  Directory get _directory =>
      Directory(p.join(AppPaths.data.path, 'tag_translations'));

  File _file(String source, String locale) {
    if (!isSourceKey(source) || !locales.contains(locale)) {
      throw const FormatException('不支持的站点或语言');
    }
    // 可逆字节编码防止 Windows 大小写不敏感文件系统混淆两个源身份。
    return File(
      p.join(_directory.path, sourceIdentity(source), '$locale.json'),
    );
  }

  Future<TagTranslationPack> _readPack(String source, String locale) async {
    final file = _file(source, locale);
    if (await file.length() > TagTranslationPack.maxBytes) {
      throw const FormatException('词包过大');
    }
    return TagTranslationPack.parse(
      jsonDecode(await file.readAsString()),
      source: source,
      locale: locale,
    );
  }

  /// 只加载明确请求的站点和语言；同站并发查词共用一次读取。
  Future<void> ensureLoaded(String source, String locale) {
    if (!isSourceKey(source) || !locales.contains(locale)) {
      return Future.value();
    }
    final key = '$source/$locale';
    if (_packs.containsKey(key) || !_installed.contains(key)) {
      return Future.value();
    }
    return _loading[key] ??= _installs
        .run(() async {
          if (_packs.containsKey(key) || !_installed.contains(key)) return;
          _packs[key] = await _readPack(source, locale);
          notifyListeners();
        })
        .whenComplete(() {
          _loading.remove(key);
        });
  }

  Future<void> remove(String source, String locale) {
    final file = _file(source, locale);
    final key = '$source/$locale';
    // 删除使本站此前的下载失效，后续显式下载可立即开启新请求。
    _revisions[key] = (_revisions[key] ?? 0) + 1;
    _pending.remove(key);
    return _installs.run(() async {
      if (await file.exists()) await file.delete();
      _installed.remove(key);
      _packs.remove(key);
      notifyListeners();
    });
  }

  Map<String, TagPackAsset> _remote = {};
  List<String> get sources => {
    ..._bundled.map((k) => k.split('/').first),
    ..._remote.values.map((p) => p.source),
    ..._installed.map((key) => key.split('/').first),
  }.toList()..sort();
  List<String> get bundledSources =>
      _bundled.map((k) => k.split('/').first).toSet().toList()..sort();
  bool bundled(String source, String locale) =>
      _bundled.contains('$source/$locale');
  bool remoteAvailable(String source, String locale) =>
      _remote.containsKey('$source/$locale');
  List<String> availableLocales(String source) => locales
      .where(
        (locale) =>
            bundled(source, locale) ||
            remoteAvailable(source, locale) ||
            installed(source, locale),
      )
      .toList();
  List<String> get locales => TagTranslationPack.locales;

  Future<void> init() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final pattern = RegExp(
      r'^assets/tag_translations/([A-Za-z0-9_-]+)/([A-Za-z-]+)\.json$',
    );
    _bundled.clear();
    for (final asset in manifest.listAssets()) {
      final match = pattern.firstMatch(asset);
      if (match != null &&
          isSourceKey(match[1]) &&
          locales.contains(match[2])) {
        _bundled.add('${match[1]}/${match[2]}');
      }
    }
    await _installs.run(() async {
      _packs.clear();
      _installed.clear();
      await _migrateInstalledPacks();
      if (!await _directory.exists()) return;
      await for (final directory in _directory.list(followLinks: false)) {
        if (directory is! Directory) continue;
        final encoded = p.basename(directory.path);
        if (!RegExp(r'^(?:[0-9a-f]{2}){1,100}$').hasMatch(encoded)) continue;
        String source;
        try {
          source = utf8.decode([
            for (var i = 0; i < encoded.length; i += 2)
              int.parse(encoded.substring(i, i + 2), radix: 16),
          ]);
        } on FormatException {
          continue;
        }
        if (!isSourceKey(source)) continue;
        await for (final file in directory.list(followLinks: false)) {
          if (file is! File) continue;
          final locale = p.basenameWithoutExtension(file.path);
          if (p.extension(file.path) == '.json' && locales.contains(locale)) {
            _installed.add('$source/$locale');
          }
        }
      }
    });
  }

  /// 一次性拆分旧安装文件，成功后归档原字节，不保留双写或兼容查词路径。
  Future<void> _migrateInstalledPacks() async {
    final old = AppPaths.dataFile('tag_translations.json');
    if (!await old.exists()) return;
    Object? data;
    try {
      data = jsonDecode(await old.readAsString());
    } on FormatException {
      return;
    } // 损坏原文件保留，不影响独立词包加载。
    if (data is! List) return;
    for (final entry in data) {
      TagTranslationPack pack;
      try {
        if (entry is! Map ||
            entry['source'] is! String ||
            entry['locale'] is! String) {
          continue;
        }
        pack = TagTranslationPack.parse(
          entry,
          source: entry['source'],
          locale: entry['locale'],
        );
      } on FormatException {
        continue;
      }
      final file = _file(pack.source, pack.locale);
      if (await file.exists()) continue;
      await file.parent.create(recursive: true);
      await writeFileAtomic(file, utf8.encode(jsonEncode(pack.toJson())));
    }
    final archive = '${old.path}.migrated';
    await old.rename(
      await File(archive).exists()
          ? '$archive-${DateTime.now().microsecondsSinceEpoch}'
          : archive,
    );
  }

  bool installed(String source, String locale) =>
      _installed.contains('$source/$locale');
  TagTranslationPack? pack(String source, String locale) =>
      _packs['$source/$locale'];
  String? lookup(
    String source,
    String locale,
    String label, {
    String namespace = '',
  }) => _packs['$source/$locale']?.lookup(label, namespace: namespace);

  /// Explicit installation works offline before the repository's first publication.
  Future<void> download(String source, String locale) =>
      _run(source, locale, (revision, token) async {
        final text = await rootBundle.loadString(
          'assets/tag_translations/$source/$locale.json',
        );
        if (utf8.encode(text).length > TagTranslationPack.maxBytes) {
          throw const FormatException('词包过大');
        }
        if (token.cancelError case final error?) throw error;
        await _install(
          TagTranslationPack.parse(
            jsonDecode(text),
            source: source,
            locale: locale,
          ),
          revision,
        );
      });

  /// User-initiated update; an unavailable repository preserves the installed pack.
  Future<void> updateFromRepository(String source, String locale) =>
      _run(source, locale, (revision, token) async {
        await refreshRepository();
        if (token.cancelError case final error?) throw error;
        final entry = _remote['$source/$locale'];
        if (entry == null) throw const FormatException('词包索引缺失或重复');
        final text = await _readRemote(entry.url);
        if (token.cancelError case final error?) throw error;
        if (utf8.encode(text).length > TagTranslationPack.maxBytes) {
          throw const FormatException('词包过大');
        }
        if (sha256.convert(utf8.encode(text)).toString() != entry.digest) {
          throw const FormatException('词包完整性校验失败');
        }
        final pack = TagTranslationPack.parse(
          jsonDecode(text),
          source: source,
          locale: locale,
        );
        if (pack.version != entry.version) {
          throw const FormatException('词包版本不一致');
        }
        final existing = _packs['$source/$locale'];
        if (existing != null &&
            compareReleaseVersions(pack.version, existing.version) < 0) {
          throw const FormatException('拒绝降级词包');
        }
        await _install(pack, revision);
      });

  Future<void> _run(
    String source,
    String locale,
    Future<void> Function(int revision, CancelToken token) operation,
  ) {
    if (!isSourceKey(source) || !locales.contains(locale)) {
      return Future.error(const FormatException('不支持的站点或语言'));
    }
    final key = '$source/$locale';
    final existing = _pending[key];
    if (existing != null) return existing;
    final revision = _revisions[key] ?? 0;
    late final Future<void> pending;
    pending = BackgroundDownloads.instance
        .run((token) async {
          await operation(revision, token);
        })
        .whenComplete(() {
          if (identical(_pending[key], pending)) _pending.remove(key);
        });
    _pending[key] = pending;
    return pending;
  }

  Future<void> _install(TagTranslationPack pack, int revision) {
    return _installs.run(() async {
      final key = '${pack.source}/${pack.locale}';
      if ((_revisions[key] ?? 0) != revision) return;
      final file = _file(pack.source, pack.locale);
      var existing = _packs[key];
      if (existing == null && await file.exists()) {
        try {
          existing = await _readPack(pack.source, pack.locale);
        } on FormatException {
          // 已校验的新包可修复损坏的本站安装，写入失败原文件仍保留。
        }
      }
      if (existing != null &&
          compareReleaseVersions(pack.version, existing.version) < 0) {
        throw const FormatException('拒绝降级词包');
      }
      await file.parent.create(recursive: true);
      await writeFileAtomic(file, utf8.encode(jsonEncode(pack.toJson())));
      _installed.add(key);
      _packs[key] = pack;
      notifyListeners();
    });
  }

  static Map<String, TagPackAsset> parseIndex(Object? data) {
    if (data is! Map ||
        data['schema'] != 1 ||
        data['packs'] is! List ||
        (data['packs'] as List).length > 10000) {
      throw const FormatException('词包索引无效');
    }
    final assets = <String, TagPackAsset>{};
    for (final entry in data['packs'] as List) {
      if (entry is! Map ||
          !isSourceKey(entry['source']) ||
          !TagTranslationPack.locales.contains(entry['locale']) ||
          !isReleaseVersion(entry['version']) ||
          !isSha256(entry['sha256']) ||
          !isOfficialAsset(
            entry['url'],
            'assets/tag_translations/${entry['source']}/${entry['locale']}.json',
          )) {
        throw const FormatException('词包索引条目无效');
      }
      final asset = TagPackAsset(
        entry['source'] as String,
        entry['locale'] as String,
        entry['version'] as String,
        entry['url'] as String,
        entry['sha256'] as String,
      );
      final key = '${asset.source}/${asset.locale}';
      if (assets.containsKey(key)) throw const FormatException('重复词包索引');
      assets[key] = asset;
    }
    return assets;
  }

  Future<void> refreshRepository() async {
    final next = parseIndex(jsonDecode(await _readRemote(indexUrl)));
    _remote = next;
    notifyListeners();
  }

  static Future<String> _readRemoteDefault(String url) async {
    try {
      return await readPublicText(
        url,
        maxBytes: TagTranslationPack.maxBytes,
        proxy: AppSettings.instance.proxy,
      );
    } catch (_) {
      throw const FormatException('官方词包网络请求失败');
    }
  }
}

class TagPackAsset {
  const TagPackAsset(
    this.source,
    this.locale,
    this.version,
    this.url,
    this.digest,
  );
  final String source, locale, version, url, digest;
}
