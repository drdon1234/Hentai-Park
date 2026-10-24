import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/platform_capabilities.dart';
import '../../core/settings.dart';
import '../../core/storage.dart';
import '../../engine/platform_bridge.dart';
import '../../engine/source_manager.dart';
import '../../images/image_tasks.dart';
import '../../images/park_image.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../kit/kit.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import '../widgets/platform_share.dart';
import 'device_session.dart';
import 'page_preloader.dart';
import 'reader_image.dart';
import 'reader_layout.dart';
import 'reader_settings_sheet.dart';
import 'reader_views.dart';
import 'reader_zoom.dart';

part 'reader_input.dart';
part 'reader_navigation.dart';
part 'reader_page_views.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.work,
    this.chapter,
    this.startPage = 0,
  });
  final WorkDetail work;
  final Chapter? chapter;
  final int startPage;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

/// State shared by the page and its navigation, input and view mixins.
abstract class _ReaderBase extends State<ReaderPage> {
  final _settings = AppSettings.instance;
  final _watched = AppSettings.instance.watch(AppSettings.readerKeys);
  late Chapter? _chapter = widget.chapter;
  List<PageImage>? _pages;
  Object? _error;
  bool _offline = false;
  int _loadGeneration = 0;
  String? _loadedChapterId;
  int _page = 0;
  bool _overlay = false;
  bool _desktopFullscreen = false;
  late ReaderMode _mode = _settings.readerMode;
  bool _modeOverride = false;
  final Map<int, double> _aspects = {};

  final _itemScroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  final _offsets = ScrollOffsetController();
  PageController? _pager;
  List<Spread> _spreads = const [];
  final _zoom = TransformationController();
  bool _zoomed = false;
  final _focus = FocusNode();
  Timer? _saveTimer;
  CancelToken? _request;
  late final _preloader = PagePreloader((index, token) async {
    await _provider(index)
        .loadBytes(cancelToken: token, priority: ImagePriority.preload);
  });

  String get _source => widget.work.source;
  String? get _chapterId => _chapter?.id ?? widget.work.singleChapterId;
  List<Chapter> get _chapters => widget.work.chapters ?? const [];
  int get _chapterIndex =>
      _chapter == null ? -1 : _chapters.indexWhere((c) => c.id == _chapter!.id);
  bool get _paged => _mode != ReaderMode.vertical;
  bool get _rtl => _mode == ReaderMode.rightToLeft;

  ParkImage _provider(int i) => ParkImage.page(
    _source,
    widget.work.id,
    _chapterId,
    i,
    _pages![i],
    crop: _settings.readerCrop,
  );

  Future<void> _load({int startPage});
}

class _ReaderPageState extends _ReaderBase
    with WidgetsBindingObserver, _ReaderNavigation, _ReaderInput, _ReaderViews {
  late final _device = ReaderDeviceSession(
    onVolume: (d) => d > 0 ? _next() : _prev(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(startPage: widget.startPage);
    _positions.itemPositions.addListener(_onScroll);
    _zoom.addListener(() {
      final z = _zoom.value.getMaxScaleOnAxis() > 1.01;
      if (z != _zoomed) setState(() => _zoomed = z);
    });
    _configureDevice();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _watched.addListener(_onSettings);
    // Mihon remembers the reading mode per series.
    Library.instance.readerModeOf(widget.work.uid).then((m) {
      if (m == null || !mounted || m >= ReaderMode.values.length) return;
      _modeOverride = true;
      _applyMode(ReaderMode.values[m]);
    });
  }

  @override
  void dispose() {
    _loadGeneration++;
    _preloader.clear();
    _request?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress();
    _saveTimer?.cancel();
    _device.dispose();
    _watched.removeListener(_onSettings);
    if (_desktopFullscreen) {
      unawaited(PlatformBridge.applyVideoFullscreen(false));
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pager?.dispose();
    _zoom.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _saveTimer?.cancel();
    _saveProgress();
  }

  void _onSettings() {
    _configureDevice();
    if (mounted) {
      setState(() {});
      _preload();
    }
  }

  void _configureDevice() {
    _device.synchronize(
      keepScreenOn: _settings.keepScreenOn,
      volumeKeys: _settings.volumeKeyPaging,
      orientation: _settings.readerOrientation,
    );
  }

  @override
  Future<void> _load({int startPage = 0}) async {
    final generation = ++_loadGeneration;
    _preloader.clear();
    _request?.cancel();
    final request = _request = CancelToken();
    final chapterId = _chapterId;
    _saveTimer?.cancel();
    setState(() {
      _pages = null;
      _error = null;
      _aspects.clear();
    });
    try {
      var pages = await DownloadManager.instance.localChapter(
        _source,
        widget.work.id,
        chapterId ?? '_',
      );
      if (!mounted || generation != _loadGeneration) return;
      final offline = pages != null;
      pages ??= (await SourceManager.instance.chapter(
        _source,
        widget.work.id,
        chapterId,
        cancelToken: request,
      )).pages;
      if (!mounted || generation != _loadGeneration) return;
      _offline = offline;
      _loadedChapterId = chapterId;
      for (var i = 0; i < pages.length; i++) {
        final a = pages[i].aspect;
        if (a != null) _aspects[i] = a;
      }
      final start = startPage.clamp(0, pages.isEmpty ? 0 : pages.length - 1);
      _spreads = _layout(pages.length);
      _pager?.dispose();
      _pager = PageController(initialPage: spreadIndexOf(_spreads, start));
      setState(() {
        _pages = pages;
        _page = start;
      });
      _preload();
      _saveProgress();
    } catch (e) {
      if (mounted && generation == _loadGeneration) setState(() => _error = e);
    }
  }

  void _applyMode(ReaderMode mode) {
    final page = _page;
    setState(() {
      _mode = mode;
      if (_pages != null) _spreads = _layout(_pages!.length);
      _pager?.dispose();
      _pager = PageController(initialPage: spreadIndexOf(_spreads, page));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_paged && _itemScroll.isAttached) _itemScroll.jumpTo(index: page);
    });
  }

  /// A mode picked in the reader applies to this work (Mihon's per-series reading mode).
  void _setMode(ReaderMode mode) {
    _modeOverride = true;
    _applyMode(mode);
    Library.instance.setReaderMode(widget.work.toItem(), mode.index);
  }

  void _useDefaultMode() {
    _modeOverride = false;
    Library.instance.setReaderMode(widget.work.toItem(), null);
    _applyMode(_settings.readerMode);
  }

  @override
  Widget build(BuildContext context) =>
      ImmersiveRegion(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    if (_pages != null && _paged) _relayout();
    final s = _settings;
    final readingBrightness = _background.computeLuminance() > .5
        ? Brightness.light
        : Brightness.dark;
    return Theme(
      data: ParkTheme.of(Brightness.dark, Color(s.seedColor)),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: _background,
          body: ReaderChrome(
            visible: _overlay,
            title: widget.work.title,
            subtitle: [?_chapter?.title, if (_offline) tr('离线阅读')].join(' · '),
            actions: [
              PopupMenuButton<ReaderMode>(
                tooltip: tr('阅读模式（仅本作）'),
                icon: Icon(_mode.icon, color: Scrims.onScrim),
                initialValue: _mode,
                onSelected: _setMode,
                itemBuilder: (_) => [
                  for (final m in ReaderMode.values)
                    PopupMenuItem(
                      value: m,
                      child: SelectionContainer.disabled(
                        child: Row(
                          children: [
                            Icon(m.icon, size: 20),
                            const SizedBox(width: Gap.m),
                            Text(m.label),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                tooltip: tr('阅读设置'),
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => showReaderSettings(
                  context,
                  mode: _mode,
                  modeIsOverride: _modeOverride,
                  onMode: _setMode,
                  onUseDefault: _useDefaultMode,
                ),
              ),
            ],
            bottom: _pages != null && _pages!.isNotEmpty
                ? ReaderProgress(
                    value: _page.toDouble(),
                    max: (_pages!.length - 1).toDouble(),
                    label: (v) => '${v.round() + 1}',
                    trailingLabel: '${_pages!.length}',
                    onSeek: (v) => _jump(v.round()),
                    onPrevious: _hasPrevChapter ? _prevChapter : null,
                    onNext: _hasNextChapter ? _nextChapter : null,
                  )
                : null,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Theme(
                    data: ParkTheme.of(readingBrightness, Color(s.seedColor)),
                    child: ReaderFilters(
                      grayscale: s.readerGrayscale,
                      invert: s.readerInvert,
                      dim: s.readerDim,
                      warm: s.readerWarm,
                      child: _content(),
                    ),
                  ),
                ),
                if (!_overlay &&
                    s.readerShowPageNumber &&
                    _pages != null &&
                    _pages!.isNotEmpty)
                  Positioned(
                    right: Gap.s + 2,
                    bottom: Gap.s + MediaQuery.paddingOf(context).bottom,
                    child: ReaderBadge(_pageLabel()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
