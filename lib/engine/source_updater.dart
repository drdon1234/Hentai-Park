import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/async_tasks.dart';
import '../core/localization.dart';
import '../core/models.dart';
import '../core/settings.dart';
import 'background_downloads.dart';
import 'source_compatibility.dart';
import 'source_manager.dart';
import 'source_repository.dart';

/// An update offered for a specific installed source, with its state captured at check time.
class SourceUpdateCandidate {
  SourceUpdateCandidate({required this.entry, required this.source})
    : version = source.version,
      origin = source.origin;

  final SourceRepositoryEntry entry;
  final InstalledSource source;
  final String version;
  final String origin;
}

class SourceUpdateResult {
  const SourceUpdateResult({
    this.available = const [],
    this.requiresAppUpdate = const [],
    this.updated = const [],
    this.failures = const {},
    this.checked = 0,
  });

  final List<SourceUpdateCandidate> available;
  final List<SourceUpdateCandidate> requiresAppUpdate;
  bool get hasUpdates => available.isNotEmpty || requiresAppUpdate.isNotEmpty;
  Iterable<SourceUpdateCandidate> get allUpdates => [
    ...available,
    ...requiresAppUpdate,
  ];
  final List<String> updated;
  final Map<String, String> failures;
  final int checked;
}

/// Checks official sources, and installs offered updates only after confirmation.
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
    Future<String> Function()? currentVersion,
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
       _now = now ?? DateTime.now,
       _currentVersion = currentVersion ?? SourceCompatibility.currentVersion;

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
  final Future<String> Function() _currentVersion;
  Future<SourceUpdateResult>? _flight;
  List<SourceUpdateCandidate>? _applying;
  int? _attemptedAt;
  bool _disposed = false;

  bool get running => _flight != null;
  SourceUpdateResult? lastResult;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

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
  Future<SourceUpdateResult> checkNow() {
    if (_flight != null) return _flight!;
    return _start(_check);
  }

  /// This method is called only after the user confirms the selected candidates.
  /// A confirmation waits for an active check rather than accidentally returning it.
  Future<SourceUpdateResult> applyUpdates(
    List<SourceUpdateCandidate> candidates,
  ) {
    final selected = List<SourceUpdateCandidate>.unmodifiable(
      {for (final candidate in candidates) candidate.entry.key: candidate}
          .values,
    );
    final active = _flight;
    if (active != null) {
      if (_applying != null && _sameCandidates(_applying!, selected)) {
        return active;
      }
      return active.then((_) => applyUpdates(selected));
    }
    if (selected.isEmpty) {
      return Future.value(lastResult ?? const SourceUpdateResult());
    }
    return _start(() async {
      try {
        return await BackgroundDownloads.instance.run(
          (token) => _apply(
            selected,
            check: () {
              if (token.cancelError case final error?) throw error;
            },
          ),
        );
      } catch (error) {
        return SourceUpdateResult(
          available: selected,
          failures: {tr('官方站点仓库'): _describe(error)},
        );
      }
    }, applying: selected);
  }

  static bool _sameCandidates(
    List<SourceUpdateCandidate> a,
    List<SourceUpdateCandidate> b,
  ) =>
      a.length == b.length &&
      a.every((candidate) => b.any((other) => identical(candidate, other)));

  Future<SourceUpdateResult> _start(
    Future<SourceUpdateResult> Function() action, {
    List<SourceUpdateCandidate>? applying,
  }) {
    if (_disposed) {
      return Future.value(
        SourceUpdateResult(failures: {tr('官方站点仓库'): tr('官方站点更新失败')}),
      );
    }
    final completion = Completer<SourceUpdateResult>();
    _flight = completion.future;
    _applying = applying;
    if (!_disposed) notifyListeners();
    unawaited(_run(action, completion));
    return completion.future;
  }

  /// Called at launch and resume. Record failed attempts too, to avoid retry loops.
  Future<void> autoCheckIfDue({bool force = false}) async {
    if (!_autoEnabled()) return;
    if (_flight != null) {
      await _flight;
      return;
    }
    final now = _now().millisecondsSinceEpoch;
    final last = _attemptedAt ?? _lastAttempt();
    // A corrected system clock must not leave checks suspended indefinitely.
    if (!force &&
        last > 0 &&
        now >= last &&
        now - last < interval.inMilliseconds) {
      return;
    }
    await checkNow();
  }

  Future<void> _run(
    Future<SourceUpdateResult> Function() action,
    Completer<SourceUpdateResult> completion,
  ) async {
    final result = await action();
    lastResult = result;
    _flight = null;
    _applying = null;
    completion.complete(result);
    if (!_disposed) notifyListeners();
  }

  Future<SourceUpdateResult> _check() async {
    final available = <SourceUpdateCandidate>[];
    final requiresAppUpdate = <SourceUpdateCandidate>[];
    final failures = <String, String>{};
    var checked = 0;
    try {
      _attemptedAt = _now().millisecondsSinceEpoch;
      await _recordAttempt(_attemptedAt!);
      await _ready();
      final index = await _repository.fetch();
      final current = await _currentVersion();
      failures.addAll(index.failures);
      for (final entry in index.entries) {
        final source = _find(entry.key);
        if (source == null || !_isOfficial(source)) continue;
        checked++;
        try {
          if (entry.apiVersion != SourceRepository.supportedApiVersion) {
            throw SourceError('UNSUPPORTED', '此站点需要更新应用后才能更新');
          }
          if (!SourceManager.isNewer(entry.version, source.version)) continue;
          final candidate = SourceUpdateCandidate(entry: entry, source: source);
          if (SourceCompatibility.supports(current, entry.minAppVersion)) {
            available.add(candidate);
          } else {
            requiresAppUpdate.add(candidate);
          }
        } catch (error) {
          failures[entry.name] = _describe(error);
        }
      }
    } catch (error) {
      failures[tr('官方站点仓库')] = _describe(error);
    }
    return SourceUpdateResult(
      available: List.unmodifiable(available),
      requiresAppUpdate: List.unmodifiable(requiresAppUpdate),
      failures: Map.unmodifiable(failures),
      checked: checked,
    );
  }

  Future<SourceUpdateResult> _apply(
    List<SourceUpdateCandidate> candidates, {
    required void Function() check,
  }) async {
    final updated = <String>[];
    final failures = <String, String>{};
    final remaining = <String, SourceUpdateCandidate>{
      for (final candidate in lastResult?.available ?? const [])
        candidate.entry.key: candidate,
      for (final candidate in candidates) candidate.entry.key: candidate,
    };
    try {
      check();
      await _ready();
      final current = await _currentVersion();
      await forEachConcurrent(candidates, 3, (candidate) async {
        final entry = candidate.entry;
        try {
          check();
          _validateCandidate(candidate);
          SourceCompatibility.validate({
            'apiVersion': entry.apiVersion,
            'minAppVersion': entry.minAppVersion,
          }, current);
          final preview = await _preview(entry);
          _validatePreview(entry, preview);
          check();
          _validateCandidate(candidate);
          await _install(preview);
          updated.add(entry.name);
          remaining.remove(entry.key);
        } catch (error) {
          failures[entry.name] = _describe(error);
        }
      });
    } catch (error) {
      failures[tr('官方站点仓库')] = _describe(error);
    }
    return SourceUpdateResult(
      updated: List.unmodifiable(updated),
      available: List.unmodifiable(remaining.values),
      requiresAppUpdate: lastResult?.requiresAppUpdate ?? const [],
      failures: Map.unmodifiable(failures),
      checked: candidates.length,
    );
  }

  void _validateCandidate(SourceUpdateCandidate candidate) {
    final entry = candidate.entry;
    final current = _find(entry.key);
    if (!identical(current, candidate.source) ||
        current == null ||
        current.origin != candidate.origin ||
        current.version != candidate.version ||
        !_isOfficial(current) ||
        !SourceManager.isNewer(entry.version, current.version)) {
      throw SourceError('CONFIG', '站点状态已改变，本次更新已跳过');
    }
    if (entry.apiVersion != SourceRepository.supportedApiVersion) {
      throw SourceError('UNSUPPORTED', '此站点需要更新应用后才能更新');
    }
  }

  static String _describe(Object error) =>
      error is SourceError ? error.friendly : tr('官方站点更新失败');

  static void _validatePreview(
    SourceRepositoryEntry entry,
    InstallPreview preview,
  ) {
    if (preview.key != entry.key || preview.manifest.key != entry.key) {
      throw SourceError('CONFIG', '下载的站点标识与官方索引不一致');
    }
    if (preview.manifest.version != entry.version) {
      throw SourceError('CONFIG', '下载的站点版本与官方索引不一致');
    }
    if (preview.manifest.rankingOnly != entry.rankingOnly ||
        preview.manifest.reverseSearchOnly != entry.reverseSearchOnly) {
      throw SourceError('CONFIG', '插件分发频道不匹配');
    }
    final api = preview.manifest.json['apiVersion'];
    if (api is! int || api != SourceRepository.supportedApiVersion) {
      throw SourceError('UNSUPPORTED', '下载的站点 API 与当前应用不兼容');
    }
    if (preview.manifest.json['minAppVersion'] != entry.minAppVersion) {
      throw SourceError('CONFIG', '下载的插件最低应用版本与官方索引不一致');
    }
    if (preview.sha256 != entry.sha256) {
      throw SourceError('CONFIG', '脚本校验失败：内容与站点仓库公布的 SHA-256 不一致，可能被篡改');
    }
  }
}
