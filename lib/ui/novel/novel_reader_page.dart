import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/content_translation.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/translator.dart';
import '../../engine/platform_bridge.dart';
import '../../engine/source_manager.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../../novel/novel_speech.dart';
import '../../novel/novel_translation.dart';
import '../../novel/reading_notes.dart';
import '../../novel/text_layout.dart';
import '../kit/kit.dart';
import '../reader/device_session.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import '../widgets/text_translation.dart';
import 'novel_reader_bars.dart';
import 'novel_sheets.dart';

part 'novel_reader_actions.dart';
part 'novel_reader_layout.dart';
part 'novel_reader_translation.dart';

class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({
    super.key,
    required this.work,
    this.chapter,
    this.startOffset = 0,
    this.translationQueue,
  });
  final WorkDetail work;
  final Chapter? chapter;
  final int startOffset;
  final ContentTranslationQueue? translationQueue;
  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

/// State shared by the page, its layout and its actions.
abstract class _NovelReaderBase extends State<NovelReaderPage> {
  final _settings = AppSettings.instance;
  final _watched = AppSettings.instance.watch(AppSettings.novelKeys);
  final _translationPreferences = AppSettings.instance.watch(const {
    'translateEngine',
    'language',
  });
  final _items = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  final _scrollOffset = ScrollOffsetController();
  final _focus = FocusNode();
  final _speech = NovelSpeech();
  PageController? _pager;
  late final _device = ReaderDeviceSession(
    onVolume: (value) => _move(value > 0 ? 1 : -1),
  );
  Timer? _saveTimer, _autoTimer;
  TextChapter? _body;
  Object? _error;
  String _text = '', _selected = '';
  List<NovelPage> _segments = [], _pages = [];
  int _chapterIndex = 0, _offset = 0, _generation = 0, _page = 0;
  String? _loadedKey;
  bool _controls = true, _offline = false, _auto = false;
  final Map<String, TextChapter> _cache = {};
  Object? _layoutKey;
  Size _viewport = Size.zero;
  TextStyle _effectiveStyle = const TextStyle();
  double _textWidth = 1;
  TextDirection _textDirection = TextDirection.ltr;
  CancelToken? _request;
  bool _translateFullText = false;
  bool _scrollTranslation = false, _persistScrollTranslation = false;
  String? _translationLocale;
  NovelTranslationSession? _translation;
  NovelTranslationDocument? _translationDocument;
  final _translations = <String, NovelTranslationSession>{};
  String get _originalText => _body?.paragraphs.join('\n\n') ?? '';
  int _sourceOffset(int offset) =>
      _translationDocument?.originalOffset(offset) ?? offset;
  int _displayOffset(int offset) =>
      _translationDocument?.translatedOffset(offset) ?? offset;
  List<Chapter> get _chapters => widget.work.chapters?.isNotEmpty == true
      ? widget.work.chapters!
      : [Chapter(chapterKeyOf(widget.work.singleChapterId), tr('全本'))];
  Chapter get _chapter => _chapters[_chapterIndex];
  bool get _paged => _settings.novelMode == 'paged';

  void _changedOffset(int offset);
  void _jump(int offset);
  void _move(int delta);
  void _toggleControls();
  Future<void> _switchChapter(int index, {int? offset});
  void _setAuto(bool value);
  Future<void> _addNote({required bool bookmark});
  void _toggleFullTranslation();
  void _setTranslationMode({required bool scroll, bool persist = false});
}

class _NovelReaderPageState extends _NovelReaderBase
    with
        WidgetsBindingObserver,
        _NovelLayout,
        _NovelActions,
        _NovelTranslation {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chapterIndex = math.max(
      0,
      _chapters.indexWhere((c) => c.id == widget.chapter?.id),
    );
    _positions.itemPositions.addListener(_onScroll);
    _watched.addListener(_onSettings);
    _translationPreferences.addListener(_onTranslationPreferences);
    ReadingNotes.instance.addListener(_onNotes);
    _speech.addListener(_onNotes);
    _configureDevice();
    unawaited(_load(widget.startOffset));
  }

  @override
  void dispose() {
    _generation++;
    _request?.cancel();
    _save();
    _detachTranslation();
    for (final session in _translations.values) {
      session.dispose();
    }
    _saveTimer?.cancel();
    _autoTimer?.cancel();
    _device.dispose();
    _positions.itemPositions.removeListener(_onScroll);
    _watched.removeListener(_onSettings);
    _translationPreferences.removeListener(_onTranslationPreferences);
    ReadingNotes.instance.removeListener(_onNotes);
    _speech.removeListener(_onNotes);
    _speech.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(PlatformBridge.applyVideoFullscreen(false));
    unawaited(PlatformBridge.resetVideoBrightness());
    _pager?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = AppLocalizations.localeKey(
      AppLocalizations.of(context).locale,
    );
    if (_translationLocale != locale) {
      _translationLocale = locale;
      if (_translateFullText && _body != null) _beginTranslation();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _save();
      _setAuto(false);
      unawaited(_speech.stop().catchError((Object _) {}));
    }
  }

  void _onNotes() {
    if (mounted) setState(() {});
  }

  void _onSettings() {
    _configureDevice();
    if (_paged && _auto) _setAuto(false);
    if (mounted) setState(() {});
  }

  void _configureDevice() {
    unawaited(
      _settings.novelBrightness < 0
          ? PlatformBridge.resetVideoBrightness()
          : PlatformBridge.setVideoBrightness(_settings.novelBrightness),
    );
    _device.synchronize(
      keepScreenOn: _settings.novelKeepScreenOn,
      volumeKeys: _settings.novelVolumeKeys,
      orientation: _settings.novelOrientation,
    );
  }

  Future<void> _load(int offset) async {
    final generation = ++_generation;
    _detachTranslation();
    _translationDocument = null;
    _request?.cancel();
    final request = _request = CancelToken();
    final key = _chapter.id;
    unawaited(_speech.stop().catchError((Object _) {}));
    _saveTimer?.cancel();
    _setAuto(false);
    setState(() {
      _body = null;
      _loadedKey = null;
      _error = null;
      _selected = '';
      _offset = offset;
    });
    try {
      var body = await DownloadManager.instance.localTextChapter(
        widget.work.source,
        widget.work.id,
        key,
      );
      final offline = body != null;
      body ??= _cache[key];
      body ??= await SourceManager.instance.textChapter(
        widget.work.source,
        widget.work.id,
        key == '_' ? null : key,
        cancelToken: request,
      );
      if (!mounted || generation != _generation) return;
      _text = body.paragraphs.join('\n\n');
      _textDirection = novelTextDirection(_text);
      _cache[key] = body;
      while (_cache.length > 3) {
        _cache.remove(_cache.keys.first);
      }
      _segments = novelSegments(_text);
      _offset = novelSafeOffset(_text, offset);
      _layoutKey = null;
      setState(() {
        _body = body;
        _offline = offline;
        _loadedKey = key;
      });
      if (_translateFullText) _beginTranslation();
      unawaited(_prefetch(generation, request));
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    }
  }

  Future<void> _prefetch(int generation, CancelToken request) async {
    if (_chapterIndex + 1 >= _chapters.length) return;
    final next = _chapters[_chapterIndex + 1].id;
    if (_cache.containsKey(next)) return;
    try {
      var body = await DownloadManager.instance.localTextChapter(
        widget.work.source,
        widget.work.id,
        next,
      );
      body ??= await SourceManager.instance.textChapter(
        widget.work.source,
        widget.work.id,
        next == '_' ? null : next,
        cancelToken: request,
      );
      if (!mounted || generation != _generation) return;
      _cache[next] = body;
      while (_cache.length > 3) {
        _cache.remove(_cache.keys.first);
      }
    } catch (_) {
      /* 预取失败由用户打开章节时的正常重试界面处理。 */
    }
  }

  void _save() {
    if (_body == null || _loadedKey == null) return;
    Library.instance.recordProgress(
      widget.work.toItem(),
      chapterId: _loadedKey,
      chapterKey: _loadedKey,
      chapterTitle: _chapter.title,
      page: _sourceOffset(_offset),
      pageCount: _originalText.length + 1,
    );
  }

  @override
  void _changedOffset(int offset) {
    final next = novelSafeOffset(_text, offset);
    if (_offset == next) return;
    _offset = next;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
    _translateVisible();
    if (mounted) setState(() {});
  }

  @override
  Future<void> _switchChapter(int index, {int? offset}) async {
    if (index < 0 || index >= _chapters.length) return;
    _save();
    setState(() => _chapterIndex = index);
    final state = Library.instance.chapterState(widget.work.uid, _chapter.id);
    await _load(offset ?? (state?.read == true ? 0 : state?.lastPage ?? 0));
  }

  @override
  void _jump(int offset) {
    if (_body == null) return;
    _changedOffset(offset);
    if (_paged && _pager?.hasClients == true) {
      _page = novelPageAt(_pages, _offset);
      _pager!.jumpToPage(_page);
    } else if (_items.isAttached) {
      _items.jumpTo(
        index: novelPageAt(_segments, _offset),
        alignment: _scrollAlignment(_offset),
      );
    }
  }

  @override
  void _move(int delta) {
    if (_body == null) return;
    if (_paged) {
      final target = _page + delta;
      if (target < 0 || target >= _pages.length) {
        if (target >= _pages.length) _changedOffset(_text.length);
        unawaited(_switchChapter(_chapterIndex + delta, offset: 0));
        return;
      }
      if (_pager?.hasClients != true) return;
      if (_settings.novelAnimate && !MediaQuery.disableAnimationsOf(context)) {
        unawaited(
          _pager!.animateToPage(
            target,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          ),
        );
      } else {
        _pager!.jumpToPage(target);
      }
    } else if (_items.isAttached) {
      unawaited(
        _scrollOffset.animateScroll(
          offset: delta * _viewport.height * .85,
          duration: Duration(
            milliseconds:
                _settings.novelAnimate &&
                    !MediaQuery.disableAnimationsOf(context)
                ? 220
                : 1,
          ),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  void _toggleControls() {
    setState(() => _controls = !_controls);
    unawaited(PlatformBridge.applyVideoFullscreen(!_controls));
  }

  @override
  Widget build(BuildContext context) =>
      ImmersiveRegion(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    final (background, foreground) = _colors(context);
    final progress = _text.isEmpty
        ? 0.0
        : (_offset / _text.length).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          surface: background,
          onSurface: foreground,
          brightness: background.computeLuminance() < .2
              ? Brightness.dark
              : Brightness.light,
        ),
        iconTheme: theme.iconTheme.copyWith(color: foreground),
        textTheme: theme.textTheme.apply(
          bodyColor: foreground,
          displayColor: foreground,
        ),
      ),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if ([
            LogicalKeyboardKey.arrowRight,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.pageDown,
            LogicalKeyboardKey.space,
          ].contains(event.logicalKey)) {
            _move(1);
            return KeyEventResult.handled;
          }
          if ([
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.pageUp,
          ].contains(event.logicalKey)) {
            _move(-1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: background,
          body: ReaderChrome(
            visible: _controls,
            barColor: Color.alphaBlend(
              foreground.withValues(alpha: .06),
              background,
            ),
            foreground: foreground,
            title: _chapter.title,
            subtitle: [widget.work.title, if (_offline) tr('离线阅读')].join(' · '),
            actions: [
              IconButton(
                tooltip: tr('目录'),
                icon: const Icon(Icons.list_rounded),
                onPressed: _directory,
              ),
              IconButton(
                tooltip: tr('添加书签'),
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: _body == null
                    ? null
                    : () => _addNote(bookmark: true),
              ),
              _moreMenu(foreground),
            ],
            bottom: _body == null
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_translateFullText) _translationStatus(background),
                      NovelReaderBottomBar(
                        foreground: foreground,
                        progress: progress,
                        onSeek: (v) => _jump((v * _text.length).round()),
                        onPrevious: _chapterIndex > 0
                            ? () => _switchChapter(_chapterIndex - 1)
                            : null,
                        onNext: _chapterIndex < _chapters.length - 1
                            ? () => _switchChapter(_chapterIndex + 1)
                            : null,
                        onDirectory: _directory,
                      ),
                    ],
                  ),
            child: SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: _error != null
                            ? SourceErrorView(
                                error: _error!,
                                source: widget.work.source,
                                onRetry: () => _load(_sourceOffset(_offset)),
                              )
                            : _body == null
                            ? const Center(child: CircularProgressIndicator())
                            : Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 900,
                                  ),
                                  child: _content(foreground),
                                ),
                              ),
                      ),
                      if (_body != null && _settings.novelShowStatus)
                        NovelStatusLine(
                          foreground: foreground,
                          offline: _offline,
                          title: _chapter.title,
                          progress: _paged
                              ? '${_page + 1}/${_pages.length} · ${(progress * 100).round()}%'
                              : '${(progress * 100).round()}%',
                        ),
                    ],
                  ),
                  if (_translateFullText && _body != null && !_controls)
                    Positioned(
                      left: Gap.page,
                      right: Gap.page,
                      bottom: 0,
                      child: _translationStatus(background),
                    ),
                  if (_settings.novelDim > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black.withValues(
                            alpha: _settings.novelDim,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
