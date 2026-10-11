import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/storage.dart';
import '../../engine/source_manager.dart';
import '../../images/park_image.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import 'reader_image.dart';
import 'reader_layout.dart';
import 'reader_settings_sheet.dart';
import '../../core/localization.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.work, this.chapter, this.startPage = 0});
  final WorkDetail work;
  final Chapter? chapter;
  final int startPage;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _settings = AppSettings.instance;
  late Chapter? _chapter = widget.chapter;
  List<PageImage>? _pages;
  Object? _error;
  bool _offline = false;
  int _page = 0;
  bool _overlay = false;
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
  StreamSubscription<int>? _volumeSub;
  final _focus = FocusNode();
  Timer? _saveTimer;
  String _orientation = '';

  String get _source => widget.work.source;
  String? get _chapterId => _chapter?.id ?? widget.work.singleChapterId;
  List<Chapter> get _chapters => widget.work.chapters ?? const [];
  int get _chapterIndex => _chapter == null ? -1 : _chapters.indexWhere((c) => c.id == _chapter!.id);
  bool get _paged => _mode != ReaderMode.vertical;
  bool get _rtl => _mode == ReaderMode.rightToLeft;

  @override
  void initState() {
    super.initState();
    _load(startPage: widget.startPage);
    _positions.itemPositions.addListener(_onScroll);
    _zoom.addListener(() {
      final z = _zoom.value.getMaxScaleOnAxis() > 1.01;
      if (z != _zoomed) setState(() => _zoomed = z);
    });
    if (_settings.keepScreenOn) WakelockPlus.enable();
    if (_settings.volumeKeyPaging) {
      PlatformBridge.interceptVolumeKeys(true);
      _volumeSub = PlatformBridge.volumeKeys.listen((d) => d > 0 ? _next() : _prev());
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _settings.addListener(_onSettings);
    _applyOrientation();
    // Mihon remembers the reading mode per series.
    Library.instance.readerModeOf(widget.work.uid).then((m) {
      if (m == null || !mounted || m >= ReaderMode.values.length) return;
      _modeOverride = true;
      _applyMode(ReaderMode.values[m]);
    });
  }

  @override
  void dispose() {
    _saveProgress();
    _saveTimer?.cancel();
    _volumeSub?.cancel();
    _settings.removeListener(_onSettings);
    PlatformBridge.interceptVolumeKeys(false);
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    _pager?.dispose();
    _zoom.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSettings() {
    _applyOrientation();
    if (mounted) setState(() {});
  }

  void _applyOrientation() {
    final o = _settings.readerOrientation;
    if (o == _orientation) return;
    _orientation = o;
    SystemChrome.setPreferredOrientations(switch (o) {
      'portrait' => const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
      'landscape' => const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      _ => const [],
    });
  }

  Future<void> _load({int startPage = 0}) async {
    setState(() {
      _pages = null;
      _error = null;
      _aspects.clear();
    });
    try {
      var pages = await DownloadManager.instance.localChapter(_source, widget.work.id, _chapterId ?? '_');
      _offline = pages != null;
      pages ??= (await SourceManager.instance.chapter(_source, widget.work.id, _chapterId)).pages;
      if (!mounted) return;
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
      if (mounted) setState(() => _error = e);
    }
  }

  ParkImage _provider(int i) => ParkImage.page(_source, widget.work.id, _chapterId, i, _pages![i], crop: _settings.readerCrop);

  void _preload() {
    final pages = _pages;
    if (pages == null) return;
    final n = _settings.preloadPages;
    for (var i = _page + 1; i <= _page + n && i < pages.length; i++) {
      precacheImage(_provider(i), context, onError: (_, _) {});
    }
  }

  // ── Paged layout ──

  bool get _dualActive {
    if (!_paged) return false;
    return switch (_settings.readerDual) {
      'always' => true,
      'landscape' => MediaQuery.maybeSizeOf(context)?.let((s) => s.width > s.height) ?? false,
      _ => false,
    };
  }

  List<Spread> _layout(int count) => buildSpreads(
    count: count,
    aspects: _aspects,
    dual: _dualActive,
    coverSingle: _settings.readerCoverSingle,
    splitWide: _paged && _settings.readerSplitWide,
    rtl: _rtl,
  );

  /// Re-groups pages when something that affects spreads changed (a page's size became known,
  /// rotation, settings) and keeps the current page on screen.
  void _relayout() {
    final pages = _pages;
    if (pages == null || !_paged) return;
    final next = _layout(pages.length);
    if (_listEquals(next, _spreads)) return;
    _spreads = next;
    final target = spreadIndexOf(next, _page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pager = _pager;
      if (pager != null && pager.hasClients && (pager.page?.round() ?? target) != target) pager.jumpToPage(target);
    });
  }

  static bool _listEquals(List<Spread> a, List<Spread> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _onAspect(int i, double a) {
    if (_aspects[i] == a) return;
    _aspects[i] = a;
    if (_paged && (a > 1) && (_settings.readerSplitWide || _dualActive)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_relayout);
      });
    }
  }

  // ── Navigation ──

  void _onScroll() {
    if (_paged) return;
    final visible = _positions.itemPositions.value.where((p) => p.itemTrailingEdge > 0.1 && p.itemLeadingEdge < 0.9);
    if (visible.isEmpty) return;
    final first = visible.reduce((a, b) => a.index < b.index ? a : b).index;
    if (_pages != null && first < _pages!.length && first != _page) _setPage(first);
  }

  void _setPage(int page) {
    setState(() => _page = page);
    _preload();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveProgress);
  }

  void _saveProgress() {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    // The last page counts as reached when the spread showing it is on screen.
    var page = _page;
    if (_paged && _spreads.isNotEmpty) page = _spreads[spreadIndexOf(_spreads, _page)].pages.last;
    Library.instance.recordProgress(
      widget.work.toItem(),
      chapterId: _chapter?.id,
      chapterKey: _chapterId,
      chapterTitle: _chapter?.title,
      page: page,
      pageCount: pages.length,
    );
  }

  void _jump(int page) {
    final pages = _pages;
    if (pages == null) return;
    final p = page.clamp(0, pages.length - 1);
    if (_paged) {
      _pager?.jumpToPage(spreadIndexOf(_spreads, p));
    } else {
      _itemScroll.jumpTo(index: p);
    }
    _setPage(p);
  }

  int get _spreadIndex => _pager?.hasClients == true ? (_pager!.page ?? 0).round() : spreadIndexOf(_spreads, _page);

  void _turn(int delta) {
    final pager = _pager;
    if (pager == null) return;
    final target = _spreadIndex + delta;
    if (_settings.readerAnimate) {
      pager.animateToPage(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      pager.jumpToPage(target);
    }
  }

  void _next() {
    final pages = _pages;
    if (pages == null) return;
    if (_paged) {
      if (_spreadIndex >= _spreads.length - 1) {
        _nextChapter();
      } else {
        _turn(1);
      }
    } else {
      final pos = _positions.itemPositions.value;
      if (pos.isEmpty) return;
      final atEnd = pos.any((p) => p.index == pages.length && p.itemTrailingEdge <= 1.01);
      if (atEnd) return _nextChapter();
      _offsets.animateScroll(offset: MediaQuery.sizeOf(context).height * 0.85, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    }
  }

  void _prev() {
    if (_paged) {
      if (_spreadIndex > 0) _turn(-1);
    } else {
      _offsets.animateScroll(offset: -MediaQuery.sizeOf(context).height * 0.85, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    }
  }

  bool get _hasNextChapter => _chapterIndex >= 0 && _chapterIndex < _chapters.length - 1;
  bool get _hasPrevChapter => _chapterIndex > 0;

  void _nextChapter() {
    if (!_hasNextChapter) {
      context.toast(tr('已经是最后一页了'));
      return;
    }
    _saveProgress();
    setState(() => _chapter = _chapters[_chapterIndex + 1]);
    _load();
  }

  void _prevChapter() {
    if (!_hasPrevChapter) return;
    _saveProgress();
    setState(() => _chapter = _chapters[_chapterIndex - 1]);
    _load();
  }

  // ── Mode ──

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

  void _toggleOverlay() {
    setState(() => _overlay = !_overlay);
    SystemChrome.setEnabledSystemUIMode(_overlay ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  void _onTap(TapUpDetails d, BoxConstraints c) {
    if (!_settings.tapToPage || _overlay) {
      _toggleOverlay();
      return;
    }
    final action = tapActionFor(
      d.localPosition.dx / c.maxWidth,
      d.localPosition.dy / c.maxHeight,
      layout: TapLayout.values[_settings.readerTapLayout.clamp(0, TapLayout.values.length - 1)],
      vertical: !_paged,
      rtl: _rtl,
      invertH: _settings.readerTapInvertH,
      invertV: _settings.readerTapInvertV,
    );
    switch (action) {
      case TapAction.next:
        _next();
      case TapAction.prev:
        _prev();
      case TapAction.menu:
        _toggleOverlay();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.pageDown ||
        (k == LogicalKeyboardKey.arrowRight && !_rtl) ||
        (k == LogicalKeyboardKey.arrowLeft && _rtl)) {
      _next();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.pageUp ||
        (k == LogicalKeyboardKey.arrowLeft && !_rtl) ||
        (k == LogicalKeyboardKey.arrowRight && _rtl)) {
      _prev();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Long press: share / save ──

  /// The page under the finger: in a dual spread, the half that was pressed; in vertical mode the
  /// list item under the point.
  int _pageAt(Offset local, Size size) {
    if (_paged) {
      final spread = _spreads.isEmpty ? null : _spreads[_spreadIndex.clamp(0, _spreads.length - 1)];
      if (spread == null) return _page;
      if (spread.pages.length == 2) {
        final leftHalf = local.dx < size.width / 2;
        return (leftHalf != _rtl) ? spread.pages[0] : spread.pages[1];
      }
      return spread.first;
    }
    final y = local.dy / size.height;
    for (final pos in _positions.itemPositions.value) {
      if (pos.itemLeadingEdge <= y && pos.itemTrailingEdge >= y && pos.index < (_pages?.length ?? 0)) return pos.index;
    }
    return _page;
  }

  Future<void> _pageMenu(int index) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(tr('第 {value0} 页', {'value0': index + 1}), style: const TextStyle(fontWeight: FontWeight.w700))),
            ListTile(leading: const Icon(Icons.share_rounded), title: Text(tr('分享图片')), onTap: () => Navigator.pop(ctx, 'share')),
            ListTile(leading: const Icon(Icons.save_alt_rounded), title: Text(tr('保存到相册')), onTap: () => Navigator.pop(ctx, 'save')),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      final bytes = await _provider(index).displayBytes();
      final name = 'hentaipark_${safeFileName(widget.work.id)}_${index + 1}';
      if (action == 'save') {
        if (!await Gal.hasAccess(toAlbum: true)) await Gal.requestAccess(toAlbum: true);
        await Gal.putImageBytes(bytes, album: 'HentaiPark', name: name);
        if (mounted) context.toast(tr('已保存到相册'));
      } else {
        final file = File(p.join(AppPaths.cache.path, '$name.png'));
        await file.writeAsBytes(bytes);
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      }
    } catch (e) {
      if (mounted) context.toast(tr('操作失败：{value0}', {'value0': e}));
    }
  }

  // ── Build ──

  Color get _background => switch (_settings.readerBackground) {
    'white' => Colors.white,
    'gray' => const Color(0xFF303030),
    _ => Colors.black,
  };

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    if (_pages != null && _paged) _relayout();
    final s = _settings;
    return Theme(
      data: ParkTheme.build(Brightness.dark, Color(s.seedColor)),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: _background,
          body: Stack(
            children: [
              Positioned.fill(child: _filtered(_content())),
              if (s.readerDim > 0)
                Positioned.fill(
                  child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: s.readerDim.clamp(0, 0.8)))),
                ),
              if (s.readerWarm > 0)
                Positioned.fill(
                  child: IgnorePointer(child: ColoredBox(color: const Color(0xFFFF9800).withValues(alpha: s.readerWarm.clamp(0, 0.5)))),
                ),
              _TopBar(
                visible: _overlay,
                title: widget.work.title,
                subtitle: _chapter?.title,
                offline: _offline,
                mode: _mode,
                onMode: _setMode,
                onSettings: () => showReaderSettings(context, mode: _mode, modeIsOverride: _modeOverride, onMode: _setMode, onUseDefault: _useDefaultMode),
              ),
              if (_pages != null && _pages!.isNotEmpty)
                _BottomBar(
                  visible: _overlay,
                  page: _page,
                  count: _pages!.length,
                  onSeek: _jump,
                  onPrevChapter: _hasPrevChapter ? _prevChapter : null,
                  onNextChapter: _hasNextChapter ? _nextChapter : null,
                ),
              if (!_overlay && s.readerShowPageNumber && _pages != null && _pages!.isNotEmpty)
                Positioned(
                  right: 10,
                  bottom: 8 + MediaQuery.paddingOf(context).bottom,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        _pageLabel(),
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _pageLabel() {
    final n = _pages!.length;
    if (_paged && _spreads.isNotEmpty) {
      final spread = _spreads[spreadIndexOf(_spreads, _page)];
      if (spread.pages.length == 2) return '${spread.pages[0] + 1}-${spread.pages[1] + 1} / $n';
    }
    return '${_page + 1} / $n';
  }

  static const _grayscale = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
  static const _invert = ColorFilter.matrix([
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ]);

  Widget _filtered(Widget child) {
    var out = child;
    if (_settings.readerGrayscale) out = ColorFiltered(colorFilter: _grayscale, child: out);
    if (_settings.readerInvert) out = ColorFiltered(colorFilter: _invert, child: out);
    return out;
  }

  Widget _content() {
    if (_error != null) {
      return SafeArea(
        child: SourceErrorView(error: _error!, source: _source, onRetry: () => _load(startPage: _page)),
      );
    }
    final pages = _pages;
    if (pages == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white54));
    }
    if (pages.isEmpty) {
      return Center(
        child: Text(tr('这一章没有图片'), style: TextStyle(color: Colors.white54)),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final view = _paged ? _pagedView(pages) : _verticalView(pages);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) => _onTap(d, c),
          onLongPressStart: (d) => _pageMenu(_pageAt(d.localPosition, c.biggest)),
          child: view,
        );
      },
    );
  }

  Widget _verticalView(List<PageImage> pages) {
    final gap = _settings.readerGap;
    return InteractiveViewer(
      transformationController: _zoom,
      minScale: 1,
      maxScale: 4,
      panEnabled: _zoomed,
      scaleEnabled: true,
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScroll,
        itemPositionsListener: _positions,
        scrollOffsetController: _offsets,
        initialScrollIndex: _page,
        minCacheExtent: MediaQuery.sizeOf(context).height * 2,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
        itemCount: pages.length + 1,
        itemBuilder: (context, i) {
          if (i == pages.length) return _ChapterEnd(hasNext: _hasNextChapter, onNext: _nextChapter);
          final image = ReaderImage(
            key: ValueKey('v-$_chapterId-$i-${_settings.readerCrop}'),
            provider: _provider(i),
            index: i,
            knownAspect: _aspects[i],
            onAspect: (a) => _aspects[i] = a,
          );
          return gap > 0 ? Padding(padding: EdgeInsets.only(bottom: gap), child: image) : image;
        },
      ),
    );
  }

  Widget _pageImage(int i, {Alignment alignment = Alignment.center}) => ReaderImage(
    key: ValueKey('p-$_chapterId-$i-${_settings.readerCrop}'),
    provider: _provider(i),
    index: i,
    knownAspect: _aspects[i],
    fit: BoxFit.contain,
    fillHeight: true,
    alignment: alignment,
    onAspect: (a) => _onAspect(i, a),
  );

  Widget _spreadView(Spread spread) {
    if (spread.pages.length == 2) {
      // Pages lean towards the spine so the spread reads as one sheet.
      final first = _pageImage(spread.pages[0], alignment: _rtl ? Alignment.centerLeft : Alignment.centerRight);
      final second = _pageImage(spread.pages[1], alignment: _rtl ? Alignment.centerRight : Alignment.centerLeft);
      return Row(
        textDirection: TextDirection.ltr,
        children: [
          Expanded(child: _rtl ? second : first),
          Expanded(child: _rtl ? first : second),
        ],
      );
    }
    final half = spread.half;
    if (half != null) return _HalfPage(left: half == Half.left, child: _pageImage(spread.first));
    return _pageImage(spread.first);
  }

  Widget _pagedView(List<PageImage> pages) {
    return Directionality(
      // The UI language must not invert the selected manga reading direction.
      textDirection: TextDirection.ltr,
      child: PageView.builder(
      controller: _pager,
      reverse: _rtl,
      itemCount: _spreads.length + (_hasNextChapter ? 1 : 0),
      onPageChanged: (i) {
        if (i < _spreads.length) _setPage(_spreads[i].first);
      },
      itemBuilder: (context, i) {
        if (i >= _spreads.length) return _ChapterEnd(hasNext: true, onNext: _nextChapter);
        return _ZoomablePage(child: _spreadView(_spreads[i]));
      },
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Shows the left or right half of a wide page, scaled to fill the screen height.
class _HalfPage extends StatelessWidget {
  const _HalfPage({required this.left, required this.child});
  final bool left;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, c) => ClipRect(
        child: OverflowBox(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          minWidth: c.maxWidth * 2,
          maxWidth: c.maxWidth * 2,
          child: child,
        ),
      ),
    );
  }
}

/// Double-tap to zoom in/out on a single page.
class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({required this.child});
  final Widget child;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> with SingleTickerProviderStateMixin {
  final _t = TransformationController();
  TapDownDetails? _down;
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  Animation<Matrix4>? _tween;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() => _t.value = _tween!.value);
  }

  @override
  void dispose() {
    _t.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _toggle() {
    final zoomed = _t.value.getMaxScaleOnAxis() > 1.01;
    final p = _down?.localPosition ?? Offset.zero;
    final target = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
            ..scaleByDouble(2.5, 2.5, 1, 1));
    _tween = Matrix4Tween(begin: _t.value, end: target).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    return GestureDetector(
      onDoubleTapDown: (d) => _down = d,
      onDoubleTap: _toggle,
      child: InteractiveViewer(
        transformationController: _t,
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(child: widget.child),
      ),
    );
  }
}

class _ChapterEnd extends StatelessWidget {
  const _ChapterEnd({required this.hasNext, required this.onNext});
  final bool hasNext;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    return SizedBox(
      height: 240,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasNext ? tr('本章完') : tr('全部读完啦'),
              style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            if (hasNext) FilledButton.icon(onPressed: onNext, icon: const Icon(Icons.skip_next_rounded), label: Text(tr('下一章'))),
            if (!hasNext) OutlinedButton(onPressed: () => Navigator.maybePop(context), child: Text(tr('返回详情'))),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.offline,
    required this.mode,
    required this.onMode,
    required this.onSettings,
  });
  final bool visible;
  final String title;
  final String? subtitle;
  final bool offline;
  final ReaderMode mode;
  final ValueChanged<ReaderMode> onMode;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      left: 0,
      right: 0,
      top: visible ? 0 : -120,
      child: Material(
        color: Colors.black.withValues(alpha: 0.82),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const BackButton(color: Colors.white),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      if (subtitle != null || offline)
                        Text([?subtitle, if (offline) tr('离线阅读')].join(' · '), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuButton<ReaderMode>(
                  tooltip: tr('阅读模式（仅本作）'),
                  icon: Icon(mode.icon, color: Colors.white),
                  initialValue: mode,
                  onSelected: onMode,
                  itemBuilder: (_) => [
                    for (final m in ReaderMode.values)
                      PopupMenuItem(
                        value: m,
                        child: Row(children: [Icon(m.icon, size: 20), const SizedBox(width: 12), Text(m.label)]),
                      ),
                  ],
                ),
                IconButton(tooltip: tr('阅读设置'), icon: const Icon(Icons.settings_outlined, color: Colors.white), onPressed: onSettings),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatefulWidget {
  const _BottomBar({required this.visible, required this.page, required this.count, required this.onSeek, this.onPrevChapter, this.onNextChapter});
  final bool visible;
  final int page;
  final int count;
  final ValueChanged<int> onSeek;
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final value = _drag ?? widget.page.toDouble();
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      left: 0,
      right: 0,
      bottom: widget.visible ? 0 : -160,
      child: Material(
        color: Colors.black.withValues(alpha: 0.82),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: tr('上一章'),
                  onPressed: widget.onPrevChapter,
                  icon: const Icon(Icons.skip_previous_rounded),
                  color: Colors.white,
                  disabledColor: Colors.white24,
                ),
                Text(
                  '${value.round() + 1}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                Expanded(
                  child: Slider(
                    value: value.clamp(0, (widget.count - 1).toDouble()),
                    min: 0,
                    max: (widget.count - 1).clamp(1, 1 << 20).toDouble(),
                    divisions: widget.count > 1 ? widget.count - 1 : null,
                    label: '${value.round() + 1}',
                    onChanged: (v) => setState(() => _drag = v),
                    onChangeEnd: (v) {
                      setState(() => _drag = null);
                      widget.onSeek(v.round());
                    },
                  ),
                ),
                Text('${widget.count}', style: const TextStyle(color: Colors.white60)),
                IconButton(
                  tooltip: tr('下一章'),
                  onPressed: widget.onNextChapter,
                  icon: const Icon(Icons.skip_next_rounded),
                  color: Colors.white,
                  disabledColor: Colors.white24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
