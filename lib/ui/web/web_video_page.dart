import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/app_lock.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/http_service.dart';
import '../../engine/platform_bridge.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../widgets/error_view.dart';
import 'web_playback_policy.dart';

/// 独立临时浏览器会话；没有源 HTTP、Cookie 或下载桥接。
class WebVideoPage extends StatefulWidget {
  const WebVideoPage({super.key, required this.work, this.episodeId});
  final WorkDetail work;
  final String? episodeId;

  @override
  State<WebVideoPage> createState() => _WebVideoPageState();
}

class _WebVideoPageState extends State<WebVideoPage>
    with WidgetsBindingObserver {
  static const _platform = MethodChannel('hentai_park/platform');
  WebPlaybackPolicy? _policy;
  InAppWebViewController? _controller;
  InAppWebViewKeepAlive? _keepAlive;
  Object? _error;
  double _progress = 0;
  bool _ready = false;
  bool _fullscreen = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLock.instance.addListener(_lockChanged);
    unawaited(_load());
  }

  Future<void> _release(InAppWebViewKeepAlive? session, dynamic id) async {
    if (session == null) return;
    try {
      if (Platform.isAndroid && id is String) {
        await _platform.invokeMethod('releaseWebVideo', id);
      } else {
        await InAppWebViewController.disposeKeepAlive(session);
      }
    } catch (_) {
      // 页面销毁时不得清除共享 Cookie 或默认 WebView 数据。
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final old = _keepAlive;
    final id = _controller?.getViewId();
    _controller = null;
    _keepAlive = null;
    setState(() {
      _policy = null;
      _error = null;
      _ready = false;
      _progress = 0;
    });
    await _release(old, id);
    try {
      final target = await SourceManager.instance.webVideo(
        widget.work.source,
        widget.work.id,
        episodeId: widget.episodeId,
      );
      final policy = WebPlaybackPolicy.fromJson(target);
      if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
        throw SourceError('UNSUPPORTED', '当前设备暂不支持应用内网页播放');
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _policy = policy;
        _keepAlive = InAppWebViewKeepAlive();
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _error = error is FormatException
            ? SourceError('PARSE', '播放器地址无效')
            : error,
      );
    }
  }

  Future<void> _created(
    InAppWebViewController controller,
    WebPlaybackPolicy policy,
    InAppWebViewKeepAlive session,
  ) async {
    if (!mounted || !identical(session, _keepAlive)) {
      await _release(session, controller.getViewId());
      return;
    }
    _controller = controller;
    try {
      if (Platform.isAndroid &&
          await _platform.invokeMethod<bool>(
                'isolateWebVideo',
                controller.getViewId(),
              ) !=
              true) {
        throw SourceError('UNSUPPORTED', '请更新 Android System WebView 后重试网页播放');
      }
      if (!mounted || !identical(session, _keepAlive)) return;
      _ready = true;
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(policy.url.toString())),
      );
      Library.instance.recordVisit(widget.work.toItem());
      _syncLifecycle();
    } catch (error) {
      if (mounted && identical(session, _keepAlive)) {
        setState(
          () => _error = error is SourceError
              ? error
              : SourceError('NETWORK', '浏览器请求失败'),
        );
      }
    }
  }

  void _lockChanged() => _syncLifecycle();

  void _syncLifecycle() {
    final state = WidgetsBinding.instance.lifecycleState;
    final paused =
        _error != null ||
        AppLock.instance.locked ||
        (state != null && state != AppLifecycleState.resumed);
    final controller = _controller;
    if (controller == null || !_ready) return;
    unawaited(_setPaused(controller, paused));
  }

  Future<void> _setPaused(
    InAppWebViewController controller,
    bool paused,
  ) async {
    try {
      if (paused) {
        await controller.evaluateJavascript(
          source: '''
          (() => { function pause(w) {
            try { w.document.querySelectorAll('video,audio').forEach(v => v.pause());
              for (let i=0; i<w.frames.length; i++) pause(w.frames[i]); } catch (_) {}
          } pause(window); })();
        ''',
        );
        if (Platform.isAndroid) await controller.pause();
        await controller.pauseAllMediaPlayback();
      } else {
        if (Platform.isAndroid) await controller.resume();
        await controller.setAllMediaPlaybackSuspended(suspended: false);
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncLifecycle();

  void _failed() {
    if (!mounted) return;
    final controller = _controller;
    if (controller != null && _ready) unawaited(_setPaused(controller, true));
    setState(() => _error = SourceError('NETWORK', '浏览器请求失败'));
  }

  bool _active(
    InAppWebViewController controller,
    InAppWebViewKeepAlive session,
  ) =>
      mounted &&
      identical(_controller, controller) &&
      identical(_keepAlive, session);

  void _setFullscreen(bool value) {
    if (!mounted) return;
    setState(() => _fullscreen = value);
    unawaited(PlatformBridge.applyVideoFullscreen(value));
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    AppLock.instance.removeListener(_lockChanged);
    final session = _keepAlive;
    final id = _controller?.getViewId();
    unawaited(_release(session, id));
    unawaited(PlatformBridge.applyVideoFullscreen(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    final session = _keepAlive;
    return Scaffold(
      appBar: _fullscreen
          ? null
          : AppBar(
              title: Text(
                widget.work.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  tooltip: tr('刷新'),
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _load,
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: _error == null && _progress < 1
                    ? LinearProgressIndicator(
                        value: _progress == 0 ? null : _progress,
                        minHeight: 3,
                      )
                    : const SizedBox(height: 3),
              ),
            ),
      body: SafeArea(
        top: !_fullscreen,
        child: Stack(
          children: [
            if (policy != null && session != null)
              InAppWebView(
                key: ValueKey(session),
                keepAlive: session,
                // 不设置初始 URL；Android 切换独立 Profile 后才允许联网。
                initialSettings: InAppWebViewSettings(
                  userAgent: HttpService.instance.userAgent,
                  incognito: !Platform.isAndroid,
                  thirdPartyCookiesEnabled: false,
                  javaScriptBridgeEnabled: false,
                  useShouldOverrideUrlLoading: true,
                  regexToCancelSubFramesLoading: policy.blockedFramePattern,
                  supportMultipleWindows: true,
                  allowsInlineMediaPlayback: true,
                  allowsPictureInPictureMediaPlayback: false,
                  allowFileAccess: false,
                  allowContentAccess: false,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                  useOnDownloadStart: true,
                  disableDefaultErrorPage: true,
                ),
                onWebViewCreated: (c) => _created(c, policy, session),
                onCreateWindow: (_, action) async => false,
                onDownloadStarting: (_, request) async => DownloadStartResponse(
                  handled: true,
                  action: DownloadStartResponseAction.CANCEL,
                ),
                onPermissionRequest: (_, request) async => PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.DENY,
                ),
                shouldOverrideUrlLoading: (c, action) async {
                  final uri = Uri.tryParse(
                    action.request.url?.toString() ?? '',
                  );
                  final allowed =
                      _active(c, session) &&
                      _ready &&
                      uri != null &&
                      (action.isForMainFrame
                          ? policy.allowsMainFrame(uri)
                          : policy.allowsFrame(uri));
                  return allowed
                      ? NavigationActionPolicy.ALLOW
                      : NavigationActionPolicy.CANCEL;
                },
                onLoadStart: (c, url) async {
                  if (!_active(c, session)) return;
                  final uri = Uri.tryParse(url?.toString() ?? '');
                  if (!_ready || uri == null || !policy.allowsMainFrame(uri)) {
                    await c.stopLoading();
                    if (_ready && mounted) {
                      unawaited(_setPaused(c, true));
                      setState(
                        () => _error = SourceError('BLOCKED', '播放器跳转地址未获授权'),
                      );
                    }
                  }
                },
                onProgressChanged: (c, progress) {
                  if (_active(c, session)) {
                    setState(() => _progress = progress / 100);
                  }
                },
                onLoadStop: (c, url) {
                  if (_active(c, session)) _syncLifecycle();
                },
                onReceivedError: (c, request, error) {
                  if (_active(c, session) && request.isForMainFrame == true) {
                    _failed();
                  }
                },
                onReceivedHttpError: (c, request, response) {
                  if (_active(c, session) && request.isForMainFrame == true) {
                    _failed();
                  }
                },
                onRenderProcessGone: (c, detail) {
                  if (_active(c, session)) _failed();
                },
                onEnterFullscreen: (c) {
                  if (_active(c, session)) _setFullscreen(true);
                },
                onExitFullscreen: (c) {
                  if (_active(c, session)) _setFullscreen(false);
                },
              ),
            if (_error != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Center(
                    child: SourceErrorView(
                      source: widget.work.source,
                      error: _error!,
                      onRetry: _load,
                    ),
                  ),
                ),
              ),
            if (policy == null && _error == null)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
