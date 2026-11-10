import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import '../../core/app_lock.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/storage.dart';
import '../../engine/browser_interaction.dart';
import '../../engine/desktop_shutdown.dart';
import '../../engine/http_service.dart';
import '../../engine/platform_bridge.dart';
import '../../engine/source_manager.dart';
import '../kit/immersive.dart';
import '../kit/tokens.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import 'online_game_target.dart';

class OnlineGamePage extends StatefulWidget {
  const OnlineGamePage({super.key, required this.work, required this.manager});
  final WorkDetail work;
  final SourceManager manager;

  @override
  State<OnlineGamePage> createState() => _OnlineGamePageState();
}

class _OnlineGamePageState extends State<OnlineGamePage>
    with WidgetsBindingObserver, RouteAware {
  static const _platform = MethodChannel('hentai_park/platform');
  OnlineGameTarget? _target;
  InAppWebViewKeepAlive? _session;
  InAppWebViewController? _controller;
  WebViewEnvironment? _environment;
  CancelToken? _request;
  Object? _error;
  bool _attached = false;
  bool _ready = false;
  bool _navigationEnabled = false;
  bool _routeVisible = true;
  ModalRoute<dynamic>? _route;
  Future<void> _playbackUpdates = Future.value();
  bool _fullscreen = false;
  bool _landscape = false;
  bool _keysVisible = false;
  bool _saving = false;
  int _documentGeneration = 0;
  int? _httpError;
  Timer? _accessPoll;
  Timer? _loadWatchdog;
  bool _accessChecking = false;
  BrowserAccessDocument _accessDocument = BrowserAccessDocument();
  int _generation = 0;
  Future<void> _closing = Future.value();
  Future<void> _screenUpdates = Future.value();
  final Set<String> _pressed = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLock.instance.addListener(_lifecycleChanged);
    unawaited(_load());
  }

  Future<void> _disposeSession(
    InAppWebViewKeepAlive? session,
    dynamic id,
    bool attached,
    WebViewEnvironment? environment,
  ) async {
    try {
      if (session != null) {
        if (Platform.isAndroid && attached && id is String) {
          await _platform.invokeMethod<void>('releaseWebGame', id);
        } else {
          await InAppWebViewController.disposeKeepAlive(session);
        }
      }
    } finally {
      await environment?.dispose();
    }
  }

  Future<void> _close() {
    _resetAccess();
    _releaseKeys();
    final session = _session;
    final id = _controller?.getViewId();
    final attached = _attached;
    final environment = _environment;
    _session = null;
    _controller = null;
    _environment = null;
    _target = null;
    _attached = false;
    _ready = false;
    _navigationEnabled = false;
    final previous = _closing;
    return _closing = () async {
      await previous;
      await _disposeSession(session, id, attached, environment);
    }();
  }

  void _resetAccess() {
    _documentGeneration++;
    _accessPoll?.cancel();
    _accessPoll = null;
    _loadWatchdog?.cancel();
    _loadWatchdog = null;
    _accessDocument = BrowserAccessDocument();
    _httpError = null;
  }

  void _checkAccess(
    InAppWebViewController controller,
    InAppWebViewKeepAlive session,
    OnlineGameTarget target,
  ) {
    _accessPoll?.cancel();
    final generation = _documentGeneration;
    bool current() =>
        mounted &&
        identical(session, _session) &&
        // 插件在创建回调与加载回调中可能包装同一原生控制器为不同 Dart 对象。
        identical(controller.platform, _controller?.platform) &&
        generation == _documentGeneration &&
        _error == null &&
        _routeVisible &&
        !AppLock.instance.locked &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed);
    Future<void> inspect() async {
      if (!current() || _accessChecking) return;
      _accessChecking = true;
      try {
        final url = (await controller.getUrl())?.toString();
        if (!current() || !target.allowsDocument(Uri.tryParse(url ?? ''))) {
          return;
        }
        final state = await _accessDocument.inspect(
          controller,
          url: url!,
          current: current,
          confirmation: null,
          confirmAdult: false,
          httpError: _httpError,
        );
        if (!current()) return;
        if (state != BrowserAccessState.waiting) {
          _accessPoll?.cancel();
          if (state == BrowserAccessState.ready) {
            _loadWatchdog?.cancel();
            setState(() => _ready = true);
          }
          if (state == BrowserAccessState.failed) {
            setState(
              () => _error = SourceError('HTTP', '游戏加载失败', status: _httpError),
            );
          }
        }
      } catch (_) {
        // 保留可见页面，无法自动完成时由用户继续验证。
      } finally {
        _accessChecking = false;
      }
    }

    _accessPoll = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => unawaited(inspect()),
    );
    unawaited(inspect());
  }

  void _watchLoading(InAppWebViewKeepAlive session) {
    var elapsed = Duration.zero;
    var previous = DateTime.now();
    _loadWatchdog = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final interval = now.difference(previous);
      previous = now;
      if (!mounted ||
          !identical(session, _session) ||
          _error != null ||
          _ready) {
        timer.cancel();
        return;
      }
      if (!_routeVisible ||
          AppLock.instance.locked ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed)) {
        return;
      }
      // 后台系统可能冻结计时器；恢复后的第一跳不能计入后台停留时间。
      elapsed += interval > const Duration(seconds: 2)
          ? const Duration(seconds: 1)
          : interval;
      if (elapsed >= const Duration(seconds: 60)) {
        timer.cancel();
        _accessPoll?.cancel();
        setState(() => _error = SourceError('TIMEOUT', '请求超时'));
      }
    });
  }

  Future<void> _load() => PendingDisposals.instance.watch(() async {
    _request?.cancel('online game reloaded');
    final request = _request = CancelToken();
    final generation = ++_generation;
    final closing = _close();
    if (mounted) setState(() => _error = null);
    WebViewEnvironment? environment;
    try {
      await closing;
      if (!Platform.isAndroid && !Platform.isWindows) {
        throw SourceError('UNSUPPORTED', '当前设备暂不支持在线游戏');
      }
      final raw = await widget.manager.onlineGame(
        widget.work.source,
        widget.work.id,
        cancelToken: request,
      );
      final target = OnlineGameTarget.fromJson(raw, widget.work.id);
      final key = onlineGameProfileKey(widget.work.source, target.storageId);
      if (Platform.isWindows) {
        final directory = Directory(
          p.join(AppPaths.data.path, 'online_games', key),
        );
        await directory.create(recursive: true);
        environment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: directory.path),
        );
      }
      if (!mounted || generation != _generation || request.isCancelled) {
        await environment?.dispose();
        return;
      }
      setState(() {
        _target = target;
        _environment = environment;
        _session = InAppWebViewKeepAlive();
      });
    } catch (error) {
      await environment?.dispose();
      if (mounted && generation == _generation && !request.isCancelled) {
        setState(
          () => _error = error is FormatException
              ? SourceError('PARSE', '游戏地址无效')
              : error,
        );
      }
    }
  }());

  Future<void> _created(
    InAppWebViewController controller,
    InAppWebViewKeepAlive session,
    OnlineGameTarget target,
  ) async {
    if (!mounted || !identical(session, _session)) {
      await _disposeSession(session, controller.getViewId(), false, null);
      return;
    }
    _controller = controller;
    try {
      if (Platform.isAndroid) {
        final key = onlineGameProfileKey(widget.work.source, target.storageId);
        final attached = await _platform.invokeMethod<bool>('attachWebGame', {
          'id': controller.getViewId(),
          'key': key,
        });
        if (attached != true) {
          throw SourceError(
            'UNSUPPORTED',
            '请更新 Android System WebView 后重试在线游戏',
          );
        }
        if (!mounted || !identical(session, _session)) {
          await _disposeSession(session, controller.getViewId(), true, null);
          return;
        }
        _attached = true;
      }
      if (!mounted || !identical(session, _session)) return;
      _navigationEnabled = true;
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(target.launchUrl.toString())),
      );
      _lifecycleChanged();
    } catch (error) {
      if (mounted && identical(session, _session)) {
        setState(
          () => _error = error is SourceError
              ? error
              : SourceError('NETWORK', '游戏加载失败'),
        );
      }
    }
  }

  String _ruffleDocument(OnlineGameTarget target) {
    String scriptValue(String value) =>
        jsonEncode(value).replaceAll('<', r'\u003c');
    final player = scriptValue(target.player.toString());
    final movie = scriptValue(target.url.toString());
    return '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body,#game{margin:0;width:100%;height:100%;overflow:hidden;background:#000}ruffle-player{width:100%;height:100%}</style></head>
<body><div id="game"></div><script>
window.RufflePlayer=window.RufflePlayer||{};window.RufflePlayer.config={polyfills:false};
const script=document.createElement('script');script.src=$player;
script.onload=()=>{const p=window.RufflePlayer.newest().createPlayer();
document.getElementById('game').appendChild(p);p.load($movie);};
document.head.appendChild(script);
</script></body></html>''';
  }

  void _lifecycleChanged() {
    final controller = _controller;
    if (controller == null) return;
    final active =
        _routeVisible &&
        !AppLock.instance.locked &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed);
    if (!active) _releaseKeys();
    _playbackUpdates = _playbackUpdates
        .then((_) async {
          if (!mounted || !identical(controller, _controller)) return;
          if (active) {
            await controller.resume();
          } else {
            await controller.pause();
          }
        })
        .catchError((Object _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    Nav.routeObserver.unsubscribe(this);
    _route = route;
    _routeVisible = route?.isCurrent ?? true;
    if (route is PageRoute<dynamic>) Nav.routeObserver.subscribe(this, route);
    _lifecycleChanged();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _lifecycleChanged();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _lifecycleChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _lifecycleChanged();

  Future<void> _setScreen(bool fullscreen, {bool landscape = false}) {
    setState(() {
      _fullscreen = fullscreen;
      _landscape = fullscreen && landscape;
    });
    return _screenUpdates = _screenUpdates
        .then((_) async {
          await SystemChrome.setPreferredOrientations(
            fullscreen && landscape
                ? [
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ]
                : [],
          );
          await PlatformBridge.applyVideoFullscreen(
            fullscreen,
            landscape: landscape,
            keepNavigationBar: fullscreen && !landscape,
          );
        })
        .catchError((Object _) {});
  }

  void _key(_GameKey key, bool down) {
    if (down ? !_pressed.add(key.code) : !_pressed.remove(key.code)) return;
    final controller = _controller;
    if (controller == null || !_ready) return;
    final ctrl = _pressed.contains('ControlLeft');
    if (Platform.isAndroid) {
      unawaited(
        _platform
            .invokeMethod<bool>('sendWebGameKey', {
              'id': controller.getViewId(),
              'code': key.code,
              'down': down,
              'ctrl': ctrl,
            })
            .catchError((Object _) => false),
      );
    } else if (Platform.isWindows) {
      unawaited(
        controller
            .callDevToolsProtocolMethod(
              methodName: 'Input.dispatchKeyEvent',
              parameters: {
                'type': down ? 'keyDown' : 'keyUp',
                'key': key.key,
                'code': key.code,
                'windowsVirtualKeyCode': key.number,
                'nativeVirtualKeyCode': key.number,
                'modifiers': ctrl ? 2 : 0,
                if (down &&
                    !ctrl &&
                    (key.key.length == 1 || key.key == 'Enter'))
                  'text': key.key == 'Enter' ? '\r' : key.key,
              },
            )
            .catchError((Object _) => null),
      );
    }
  }

  void _releaseKeys() {
    for (final key in _gameKeys) {
      if (_pressed.contains(key.code)) _key(key, false);
    }
    _pressed.clear();
  }

  Future<Map<String, dynamic>> _localStorageSnapshot() async {
    final controller = _controller;
    final target = _target;
    if (controller == null || target == null || !_ready) {
      throw const FormatException();
    }
    final raw = await controller.evaluateJavascript(
      source: '''(() => {
const entries=Object.create(null);for(let i=0;i<localStorage.length;i++){const key=localStorage.key(i);entries[key]=localStorage.getItem(key);}
return JSON.stringify({origin:location.origin,entries});})()''',
    );
    if (raw is! String || raw.length > 8 * 1024 * 1024) {
      throw const FormatException();
    }
    final value = jsonDecode(raw);
    if (value is! Map ||
        !target.allowsDocument(Uri.tryParse('${value['origin']}')) ||
        value['entries'] is! Map) {
      throw const FormatException();
    }
    final entries = (value['entries'] as Map).cast<String, dynamic>();
    if (entries.values.any((value) => value is! String)) {
      throw const FormatException();
    }
    return {
      'source': widget.work.source,
      'game': target.storageId,
      'origin': value['origin'],
      'localStorage': entries,
    };
  }

  Future<void> _exportSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final snapshot = await _localStorageSnapshot();
      final saved = await FilePicker.saveFile(
        fileName: 'hentaipark-game-save.json',
        bytes: utf8.encode(jsonEncode(snapshot)),
      );
      if (saved != null && mounted) context.toast(tr('已导出游戏存档'));
    } catch (_) {
      if (mounted) context.toast(tr('游戏存档操作失败'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _importSave() async {
    if (_saving) return;
    final file = await FilePicker.pickFile(dialogTitle: tr('选择备份文件'));
    if (file == null || !mounted) return;
    setState(() => _saving = true);
    try {
      if (await file.xFile.length() > 8 * 1024 * 1024) {
        throw const FormatException();
      }
      final value = jsonDecode(await file.xFile.readAsString());
      final target = _target;
      final controller = _controller;
      if (value is! Map ||
          target == null ||
          controller == null ||
          value['source'] != widget.work.source ||
          value['game'] != target.storageId ||
          value['localStorage'] is! Map) {
        throw const FormatException();
      }
      final entries = (value['localStorage'] as Map).cast<String, dynamic>();
      if (entries.values.any((v) => v is! String)) {
        throw const FormatException();
      }
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('导入游戏存档')),
          content: Text(
            tr('将替换此游戏的 localStorage；IndexedDB 存档不包含在内。导入前会保留当前数据。'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('导入')),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted || !identical(controller, _controller)) {
        return;
      }
      final current = await _localStorageSnapshot();
      final directory = Directory(
        p.join(AppPaths.data.path, 'online_game_saves'),
      );
      await directory.create(recursive: true);
      final hash = onlineGameProfileKey(widget.work.source, target.storageId);
      final backup = File(
        p.join(
          directory.path,
          '${hash}_${DateTime.now().microsecondsSinceEpoch}.json',
        ),
      );
      if (!await writeFileAtomic(backup, utf8.encode(jsonEncode(current)))) {
        throw const FileSystemException();
      }
      if (!mounted || !identical(controller, _controller)) return;
      final payload = jsonEncode(
        base64Encode(utf8.encode(jsonEncode(entries))),
      );
      final result = await controller.evaluateJavascript(
        source:
            '''(() => {
const incoming=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob($payload),c=>c.charCodeAt(0))));
const old=Object.create(null);for(let i=0;i<localStorage.length;i++){const k=localStorage.key(i);old[k]=localStorage.getItem(k);}
try{localStorage.clear();for(const [k,v] of Object.entries(incoming))localStorage.setItem(k,v);return 'ok';}
catch(_){try{localStorage.clear();for(const [k,v] of Object.entries(old))localStorage.setItem(k,v);}catch(_){}return 'failed';}
})()''',
      );
      if (result != 'ok') throw const FormatException();
      await controller.reload();
      if (mounted) context.toast(tr('已导入游戏存档'));
    } catch (_) {
      if (mounted) context.toast(tr('游戏存档操作失败'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    Nav.routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    AppLock.instance.removeListener(_lifecycleChanged);
    _request?.cancel('online game closed');
    _generation++;
    PendingDisposals.instance.add(_close());
    PendingDisposals.instance.add(
      _screenUpdates.then((_) async {
        await SystemChrome.setPreferredOrientations([]);
        if (_fullscreen) await PlatformBridge.applyVideoFullscreen(false);
      }),
    );
    super.dispose();
  }

  Widget _actions() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PopupMenuButton<String>(
        tooltip: tr('游戏存档'),
        enabled: _ready && !_saving,
        onSelected: (value) =>
            value == 'export' ? _exportSave() : _importSave(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'export',
            child: Text(tr('导出游戏存档（仅 localStorage）')),
          ),
          PopupMenuItem(
            value: 'import',
            child: Text(tr('导入游戏存档（仅 localStorage）')),
          ),
        ],
      ),
      IconButton(
        tooltip: tr(_keysVisible ? '隐藏虚拟按键' : '显示虚拟按键'),
        onPressed: () {
          if (_keysVisible) _releaseKeys();
          setState(() => _keysVisible = !_keysVisible);
        },
        icon: Icon(
          _keysVisible
              ? Icons.keyboard_hide_outlined
              : Icons.keyboard_alt_outlined,
        ),
      ),
      IconButton(
        tooltip: tr(_landscape ? '竖屏' : '横屏'),
        onPressed: () => _setScreen(true, landscape: !_landscape),
        icon: const Icon(Icons.screen_rotation_rounded),
      ),
      IconButton(
        tooltip: tr(_fullscreen ? '退出全屏' : '全屏'),
        onPressed: () => _setScreen(!_fullscreen),
        icon: Icon(
          _fullscreen
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final session = _session;
    return ImmersiveRegion(
      enabled: _fullscreen,
      child: PopScope(
        canPop: !_fullscreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _fullscreen) unawaited(_setScreen(false));
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: _fullscreen
              ? null
              : AppBar(title: Text(widget.work.title), actions: [_actions()]),
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (target != null && session != null)
                  InAppWebView(
                    key: ValueKey(session),
                    keepAlive: session,
                    webViewEnvironment: _environment,
                    initialUserScripts: Platform.isAndroid
                        ? UnmodifiableListView([
                            UserScript(
                              groupName:
                                  'park_game_${onlineGameProfileKey(widget.work.source, target.storageId)}',
                              source: challengeDocumentScript,
                              injectionTime:
                                  UserScriptInjectionTime.AT_DOCUMENT_START,
                            ),
                          ])
                        : null,
                    initialSettings: InAppWebViewSettings(
                      userAgent: HttpService.instance.userAgent,
                      javaScriptBridgeEnabled: false,
                      // Defaults keep the HTTP cache and web storage persistent.
                      supportMultipleWindows: true,
                      useShouldOverrideUrlLoading: true,
                      useShouldInterceptRequest: target.isFlash,
                      regexToCancelSubFramesLoading: target.blockedFramePattern,
                      thirdPartyCookiesEnabled: false,
                      allowFileAccess: false,
                      allowContentAccess: false,
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                      useOnDownloadStart: true,
                      disableDefaultErrorPage: true,
                      mediaPlaybackRequiresUserGesture: false,
                    ),
                    onWebViewCreated: (c) => _created(c, session, target),
                    shouldInterceptRequest: (c, request) async {
                      if (target.isFlash &&
                          request.url.toString() ==
                              target.launchUrl.toString()) {
                        return WebResourceResponse(
                          contentType: 'text/html',
                          statusCode: 200,
                          reasonPhrase: 'OK',
                          headers: {'Cache-Control': 'no-store'},
                          data: Uint8List.fromList(
                            utf8.encode(_ruffleDocument(target)),
                          ),
                        );
                      }
                      return null;
                    },
                    shouldOverrideUrlLoading: (c, action) async {
                      final uri = Uri.tryParse(
                        action.request.url?.toString() ?? '',
                      );
                      return _navigationEnabled &&
                              (action.isForMainFrame
                                  ? target.allowsDocument(uri)
                                  : target.allowsFrame(uri))
                          ? NavigationActionPolicy.ALLOW
                          : NavigationActionPolicy.CANCEL;
                    },
                    onLoadStart: (c, url) async {
                      if (!identical(session, _session)) return;
                      _resetAccess();
                      _watchLoading(session);
                      setState(() => _ready = false);
                      if (_navigationEnabled &&
                          !target.allowsDocument(
                            Uri.tryParse(url?.toString() ?? ''),
                          )) {
                        await c.stopLoading();
                      }
                    },
                    onLoadStop: (c, url) {
                      if (identical(session, _session)) {
                        _checkAccess(c, session, target);
                      }
                    },
                    onCreateWindow: (_, _) async => false,
                    onDownloadStarting: (_, _) async => DownloadStartResponse(
                      handled: true,
                      action: DownloadStartResponseAction.CANCEL,
                    ),
                    onPermissionRequest: (_, request) async =>
                        PermissionResponse(
                          resources: request.resources,
                          action: PermissionResponseAction.DENY,
                        ),
                    onReceivedError: (c, request, error) {
                      if (mounted &&
                          identical(session, _session) &&
                          request.isForMainFrame == true) {
                        setState(
                          () => _error = SourceError('NETWORK', '游戏加载失败'),
                        );
                      }
                    },
                    onReceivedHttpError: (c, request, response) {
                      if (mounted &&
                          identical(session, _session) &&
                          request.isForMainFrame == true &&
                          (response.statusCode ?? 0) >= 400) {
                        _httpError = response.statusCode;
                      }
                    },
                  ),
                if (target == null && _error == null)
                  const Center(child: CircularProgressIndicator()),
                if (target != null && !_ready && _error == null)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Center(
                      child: SourceErrorView(
                        source: widget.work.source,
                        error: _error!,
                        onRetry: _load,
                      ),
                    ),
                  ),
                if (_fullscreen)
                  Align(
                    alignment: Alignment.topRight,
                    child: Material(
                      color: Colors.black87,
                      child: IconTheme(
                        data: const IconThemeData(color: Colors.white),
                        child: _actions(),
                      ),
                    ),
                  ),
                if (_keysVisible && target != null && _error == null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _GameKeyboard(onKey: _key),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GameKey {
  const _GameKey(this.key, this.code, this.number, this.label, [this.icon]);
  final String key;
  final String code;
  final int number;
  final String label;
  final IconData? icon;
}

const _gameKeys = [
  _GameKey('ArrowUp', 'ArrowUp', 38, '上', Icons.arrow_upward_rounded),
  _GameKey('ArrowLeft', 'ArrowLeft', 37, '左', Icons.arrow_back_rounded),
  _GameKey('ArrowDown', 'ArrowDown', 40, '下', Icons.arrow_downward_rounded),
  _GameKey('ArrowRight', 'ArrowRight', 39, '右', Icons.arrow_forward_rounded),
  _GameKey('z', 'KeyZ', 90, 'Z'),
  _GameKey('Enter', 'Enter', 13, 'Enter'),
  _GameKey(' ', 'Space', 32, 'Space'),
  _GameKey('x', 'KeyX', 88, 'X'),
  _GameKey('Escape', 'Escape', 27, 'Esc'),
  _GameKey('Control', 'ControlLeft', 17, 'Ctrl'),
];

class _GameKeyboard extends StatelessWidget {
  const _GameKeyboard({required this.onKey});
  final void Function(_GameKey, bool) onKey;

  Widget _button(_GameKey key) => _GameKeyButton(keyData: key, onKey: onKey);
  Widget _spacer() => const SizedBox(width: 48, height: 48);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [_spacer(), _button(_gameKeys[0]), _spacer()],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _button(_gameKeys[1]),
                _button(_gameKeys[2]),
                _button(_gameKeys[3]),
              ],
            ),
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _button(_gameKeys[4]),
                _button(_gameKeys[5]),
                _button(_gameKeys[6]),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _button(_gameKeys[7]),
                _button(_gameKeys[8]),
                _button(_gameKeys[9]),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class _GameKeyButton extends StatelessWidget {
  const _GameKeyButton({required this.keyData, required this.onKey});
  final _GameKey keyData;
  final void Function(_GameKey, bool) onKey;

  @override
  Widget build(BuildContext context) => Semantics(
    label: tr(keyData.label),
    button: true,
    onTap: () {
      onKey(keyData, true);
      onKey(keyData, false);
    },
    child: Listener(
      onPointerDown: (_) => onKey(keyData, true),
      onPointerUp: (_) => onKey(keyData, false),
      onPointerCancel: (_) => onKey(keyData, false),
      child: Container(
        width: 48,
        height: 48,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .72),
          border: Border.all(color: Colors.white70),
          borderRadius: Radii.tiny,
        ),
        alignment: Alignment.center,
        child: keyData.icon == null
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  keyData.label,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: Colors.white),
                ),
              )
            : Icon(keyData.icon, color: Colors.white),
      ),
    ),
  );
}
