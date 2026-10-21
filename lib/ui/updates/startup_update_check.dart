import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import '../../core/app_lock.dart';
import '../../core/settings.dart';
import '../../engine/app_updater.dart';
import '../../engine/source_updater.dart';
import 'update_prompt.dart';

/// 启动检查只发现更新；提示按完成顺序等待用户逐项确认。
class StartupUpdateCheck extends StatefulWidget {
  const StartupUpdateCheck({
    super.key,
    required this.child,
    this.appUpdater,
    this.sourceUpdater,
    this.visibilityChanges,
    this.canPrompt,
  });

  final Widget child;
  final AppUpdater? appUpdater;
  final SourceUpdater? sourceUpdater;
  final Listenable? visibilityChanges;
  final bool Function()? canPrompt;

  @override
  State<StartupUpdateCheck> createState() => _StartupUpdateCheckState();
}

class _PendingPrompt {
  const _PendingPrompt.app(this.app) : sources = null;
  const _PendingPrompt.sources(this.sources) : app = null;

  final AppUpdateResult? app;
  final SourceUpdateResult? sources;
}

class _StartupUpdateCheckState extends State<StartupUpdateCheck>
    with WidgetsBindingObserver {
  final _pending = Queue<_PendingPrompt>();
  final _seenApps = <String>{};
  final _seenSources = <String>{};
  late Listenable _visibilityChanges;
  late bool _foreground;
  late bool _appEnabled;
  late bool _sourcesEnabled;
  ModalRoute<dynamic>? _route;
  bool _showing = false;
  bool _drainScheduled = false;
  bool _checkingSources = false;
  int _appGeneration = 0;
  int _sourceGeneration = 0;

  AppUpdater get _appUpdater => widget.appUpdater ?? AppUpdater.instance;
  SourceUpdater get _sourceUpdater =>
      widget.sourceUpdater ?? SourceUpdater.instance;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    final state = binding.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _appEnabled = AppSettings.instance.autoAppUpdates;
    _sourcesEnabled = AppSettings.instance.autoSourceUpdates;
    _visibilityChanges = widget.visibilityChanges ?? AppLock.instance;
    _visibilityChanges.addListener(_scheduleDrain);
    _settings.addListener(_settingsChanged);
    binding.addObserver(this);
    binding.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_checkApp());
      unawaited(_checkSources(force: true));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute.of 订阅 isCurrent 变化，其他页面或手动弹窗关闭后继续队列。
    _route = ModalRoute.of(context);
    _scheduleDrain();
  }

  @override
  void didUpdateWidget(StartupUpdateCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changes = widget.visibilityChanges ?? AppLock.instance;
    if (!identical(changes, _visibilityChanges)) {
      _visibilityChanges.removeListener(_scheduleDrain);
      _visibilityChanges = changes;
      _visibilityChanges.addListener(_scheduleDrain);
    }
    _scheduleDrain();
  }

  final _settings = AppSettings.instance.watch(const {
    'autoAppUpdates',
    'autoSourceUpdates',
  });

  void _settingsChanged() {
    final settings = AppSettings.instance;
    if (_appEnabled && !settings.autoAppUpdates) _appGeneration++;
    if (_sourcesEnabled && !settings.autoSourceUpdates) _sourceGeneration++;
    _appEnabled = settings.autoAppUpdates;
    _sourcesEnabled = settings.autoSourceUpdates;
    _pending.removeWhere(
      (item) => item.app != null ? !_appEnabled : !_sourcesEnabled,
    );
    _scheduleDrain();
  }

  Future<void> _checkApp() async {
    if (!_appEnabled || _appUpdater.running) return;
    final generation = _appGeneration;
    try {
      final result = await _appUpdater.checkOnLaunch();
      if (!mounted || !_appEnabled || generation != _appGeneration) return;
      if (result?.release == null || result?.failure != null) return;
      _pending.add(_PendingPrompt.app(result!));
      _scheduleDrain();
    } catch (_) {
      // 自动检查失败静默；用户可在设置中手动重试。
    }
  }

  Future<void> _checkSources({bool force = false}) async {
    if (!_sourcesEnabled || _checkingSources) return;
    final updater = _sourceUpdater;
    // 手动检查或用户确认后的安装已有自己的交互，不接管其结果。
    if (updater.running) return;
    final previousResult = updater.lastResult;
    final generation = _sourceGeneration;
    _checkingSources = true;
    try {
      await updater.autoCheckIfDue(force: force);
      if (!mounted || !_sourcesEnabled || generation != _sourceGeneration) {
        return;
      }
      final result = updater.lastResult;
      // 间隔内未实际检查时不消费旧结果或手动检查的历史结果。
      if (result == null || identical(previousResult, result)) return;
      if (!result.hasUpdates) return;
      _pending.add(_PendingPrompt.sources(result));
      _scheduleDrain();
    } catch (_) {
      // 自动检查失败静默；用户可在设置中手动重试。
    } finally {
      _checkingSources = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _scheduleDrain();
      unawaited(_checkSources());
    }
  }

  bool get _canShow =>
      mounted &&
      _foreground &&
      (widget.canPrompt?.call() ?? !AppLock.instance.locked) &&
      (_route?.isCurrent ?? true);

  void _scheduleDrain() {
    if (!mounted || _drainScheduled || _showing || _pending.isEmpty) return;
    _drainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainScheduled = false;
      if (mounted) unawaited(_drain());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  static String _sourceVersion(SourceUpdateCandidate candidate) =>
      '${candidate.entry.key}\u0000${candidate.entry.version}';

  Future<void> _drain() async {
    if (_showing || !_canShow) return;
    while (_pending.isNotEmpty && _canShow) {
      final pending = _pending.removeFirst();
      final app = pending.app;
      final sources = pending.sources;
      if (app != null) {
        final latest = _appUpdater.lastResult;
        if (latest != null && !identical(app, latest)) continue;
        final version = app.release!.version;
        if (!_appEnabled ||
            AppSettings.instance.ignoredAppUpdate == version ||
            !_seenApps.add(version)) {
          continue;
        }
      } else {
        if (!_sourcesEnabled ||
            sources == null ||
            !identical(sources, _sourceUpdater.lastResult)) {
          continue;
        }
        bool shouldPrompt(SourceUpdateCandidate candidate) =>
            candidate.source.version == candidate.version &&
            candidate.source.origin == candidate.origin &&
            AppSettings.instance.ignoredSourceUpdates[candidate.entry.key] !=
                candidate.entry.version &&
            !_seenSources.contains(_sourceVersion(candidate));
        final available = sources.available.where(shouldPrompt).toList();
        final requiresAppUpdate = sources.requiresAppUpdate
            .where(shouldPrompt)
            .toList();
        if (available.isEmpty && requiresAppUpdate.isEmpty) continue;
        _seenSources.addAll(
          [...available, ...requiresAppUpdate].map(_sourceVersion),
        );
        if (!mounted) return;
        _showing = true;
        try {
          await showSourceUpdatePrompt(
            context,
            SourceUpdateResult(
              available: available,
              requiresAppUpdate: requiresAppUpdate,
              checked: sources.checked,
              failures: sources.failures,
            ),
            _sourceUpdater,
          );
        } finally {
          _showing = false;
        }
        continue;
      }
      if (!mounted) return;
      _showing = true;
      try {
        await showAppUpdatePrompt(context, app);
      } finally {
        _showing = false;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_settingsChanged);
    _visibilityChanges.removeListener(_scheduleDrain);
    _pending.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
