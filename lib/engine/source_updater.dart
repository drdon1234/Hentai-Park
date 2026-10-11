import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/localization.dart';
import '../core/models.dart';
import '../core/settings.dart';
import 'source_manager.dart';
import 'source_repository.dart';

class SourceUpdateResult {
  const SourceUpdateResult({
    this.updated = const [],
    this.failures = const {},
    this.checked = 0,
  });

  final List<String> updated;
  final Map<String, String> failures;
  final int checked;
}

/// Keeps installed official sources current without taking over URL installations.
class SourceUpdater extends ChangeNotifier {
  SourceUpdater({
    SourceRepository? repository,
    Future<void> Function()? ready,
    List<InstalledSource> Function()? sources,
    Future<InstallPreview> Function(SourceRepositoryEntry entry)? preview,
    Future<String> Function(InstallPreview preview)? install,
    bool Function()? autoEnabled,
    int Function()? lastAttempt,
    Future<void> Function(int timestamp)? recordAttempt,
    DateTime Function()? now,
  }) : _repository = repository ?? SourceRepository(),
       _ready = ready ?? (() => SourceManager.instance.ready),
       _sources = sources ?? (() => SourceManager.instance.all),
       _preview = preview ?? _previewOfficial,
       _install = install ?? _installOfficial,
       _autoEnabled =
           autoEnabled ?? (() => AppSettings.instance.autoSourceUpdates),
       _lastAttempt =
           lastAttempt ?? (() => AppSettings.instance.lastSourceUpdate),
       _recordAttempt = recordAttempt ?? _saveAttempt,
       _now = now ?? DateTime.now;

  static final SourceUpdater instance = SourceUpdater();
  static const interval = Duration(hours: 12);

  final SourceRepository _repository;
  final Future<void> Function() _ready;
  final List<InstalledSource> Function() _sources;
  final Future<InstallPreview> Function(SourceRepositoryEntry) _preview;
  final Future<String> Function(InstallPreview) _install;
  final bool Function() _autoEnabled;
  final int Function() _lastAttempt;
  final Future<void> Function(int) _recordAttempt;
  final DateTime Function() _now;
  Future<SourceUpdateResult>? _flight;
  int? _attemptedAt;

  bool get running => _flight != null;
  SourceUpdateResult? lastResult;

  static Future<InstallPreview> _previewOfficial(SourceRepositoryEntry entry) =>
      SourceManager.instance.previewFromUrl(
        entry.url,
        expectedSha256: entry.sha256,
      );

  static Future<String> _installOfficial(InstallPreview preview) =>
      SourceManager.instance.install(preview, official: true);

  static Future<void> _saveAttempt(int timestamp) async {
    final settings = AppSettings.instance;
    settings.lastSourceUpdate = timestamp;
    await settings.flush();
  }

  static bool _isOfficial(InstalledSource source) =>
      source.origin == 'builtin' || source.origin == 'official';

  InstalledSource? _find(String key) {
    for (final source in _sources()) {
      if (source.key == key) return source;
    }
    return null;
  }

  /// Explicit checks bypass the interval and join any check already in progress.
  Future<SourceUpdateResult> updateNow() {
    if (_flight != null) return _flight!;
    final completion = Completer<SourceUpdateResult>();
    _flight = completion.future;
    notifyListeners();
    unawaited(_run(completion));
    return completion.future;
  }

  /// Called at launch and resume. Record failed attempts too, to avoid retry loops.
  Future<void> autoUpdateIfDue() async {
    if (!_autoEnabled()) return;
    if (_flight != null) {
      await _flight;
      return;
    }
    final now = _now().millisecondsSinceEpoch;
    final last = _attemptedAt ?? _lastAttempt();
    // A corrected system clock must not leave checks suspended indefinitely.
    if (last > 0 && now >= last && now - last < interval.inMilliseconds) return;
    await updateNow();
  }

  Future<void> _run(Completer<SourceUpdateResult> completion) async {
    final updated = <String>[];
    final failures = <String, String>{};
    var checked = 0;
    try {
      _attemptedAt = _now().millisecondsSinceEpoch;
      await _recordAttempt(_attemptedAt!);
      await _ready();
      final index = await _repository.fetch();
      failures.addAll(
        index.failures.map((name, message) => MapEntry(name, tr(message))),
      );
      for (final entry in index.entries) {
        final source = _find(entry.key);
        if (source == null || !_isOfficial(source)) continue;
        checked++;
        try {
          if (entry.apiVersion != SourceRepository.supportedApiVersion) {
            throw SourceError('UNSUPPORTED', '此源需要更新应用后才能自动更新');
          }
          if (!SourceManager.isNewer(entry.version, source.version)) continue;
          final version = source.version;
          final origin = source.origin;
          final preview = await _preview(entry);
          _validatePreview(entry, preview);
          final current = _find(entry.key);
          if (!identical(source, current) ||
              current == null ||
              current.origin != origin ||
              current.version != version ||
              !_isOfficial(current)) {
            throw SourceError('CONFIG', '源状态已改变，本次更新已跳过');
          }
          await _install(preview);
          updated.add(entry.name);
        } catch (error) {
          failures[entry.name] = _describe(error);
        }
      }
    } catch (error) {
      failures[tr('官方源仓库')] = _describe(error);
    } finally {
      final result = SourceUpdateResult(
        updated: List.unmodifiable(updated),
        failures: Map.unmodifiable(failures),
        checked: checked,
      );
      lastResult = result;
      _flight = null;
      completion.complete(result);
      notifyListeners();
    }
  }

  static String _describe(Object error) =>
      error is SourceError ? error.friendly : error.toString();

  static void _validatePreview(
    SourceRepositoryEntry entry,
    InstallPreview preview,
  ) {
    if (preview.key != entry.key || preview.manifest.key != entry.key) {
      throw SourceError('CONFIG', '下载的源标识与官方索引不一致');
    }
    if (preview.manifest.version != entry.version) {
      throw SourceError('CONFIG', '下载的源版本与官方索引不一致');
    }
    final api = preview.manifest.json['apiVersion'];
    if (api is! int || api != SourceRepository.supportedApiVersion) {
      throw SourceError('UNSUPPORTED', '下载的源 API 与当前应用不兼容');
    }
    if (preview.sha256 != entry.sha256) {
      throw SourceError('CONFIG', '脚本校验失败：内容与源仓库公布的 SHA-256 不一致，可能被篡改');
    }
  }
}
