part of 'reader_page.dart';

/// Page grouping into spreads, page turns, chapter changes and saved progress.
mixin _ReaderNavigation on _ReaderBase {
  void _preload() {
    final pages = _pages;
    if (pages == null) return;
    _preloader.update(
      page: _page,
      count: pages.length,
      window: _settings.preloadPages,
    );
  }

  bool get _dualActive {
    if (!_paged) return false;
    return switch (_settings.readerDual) {
      'always' => true,
      'landscape' =>
        MediaQuery.maybeSizeOf(context)?.let((s) => s.width > s.height) ??
            false,
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
      if (pager != null &&
          pager.hasClients &&
          (pager.page?.round() ?? target) != target) {
        pager.jumpToPage(target);
      }
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

  void _onScroll() {
    if (_paged) return;
    final visible = _positions.itemPositions.value.where(
      (p) => p.itemTrailingEdge > 0.1 && p.itemLeadingEdge < 0.9,
    );
    if (visible.isEmpty) return;
    final first = visible.reduce((a, b) => a.index < b.index ? a : b).index;
    if (_pages != null && first < _pages!.length && first != _page) {
      _setPage(first);
    }
  }

  void _setPage(int page) {
    setState(() => _page = page);
    _preload();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveProgress);
  }

  void _saveProgress() {
    final pages = _pages;
    if (pages == null || pages.isEmpty || _loadedChapterId != _chapterId) {
      return;
    }
    // The last page counts as reached when the spread showing it is on screen.
    var page = _page;
    if (_paged && _spreads.isNotEmpty) {
      page = _spreads[spreadIndexOf(_spreads, _page)].pages.last;
    }
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

  int get _spreadIndex => _pager?.hasClients == true
      ? (_pager!.page ?? 0).round()
      : spreadIndexOf(_spreads, _page);

  void _turn(int delta) {
    final pager = _pager;
    if (pager == null) return;
    final target = _spreadIndex + delta;
    if (_settings.readerAnimate && !MediaQuery.disableAnimationsOf(context)) {
      pager.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
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
      final atEnd = pos.any(
        (p) => p.index == pages.length && p.itemTrailingEdge <= 1.01,
      );
      if (atEnd) return _nextChapter();
      _offsets.animateScroll(
        offset: MediaQuery.sizeOf(context).height * 0.85,
        duration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context) ? 1 : 260,
        ),
        curve: Curves.easeOut,
      );
    }
  }

  void _prev() {
    if (_paged) {
      if (_spreadIndex > 0) _turn(-1);
    } else {
      _offsets.animateScroll(
        offset: -MediaQuery.sizeOf(context).height * 0.85,
        duration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context) ? 1 : 260,
        ),
        curve: Curves.easeOut,
      );
    }
  }

  bool get _hasNextChapter =>
      _chapterIndex >= 0 && _chapterIndex < _chapters.length - 1;
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
}
