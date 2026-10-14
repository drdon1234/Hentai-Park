part of 'reader_page.dart';

/// The vertical strip, paged spreads and the error, loading and empty states.
mixin _ReaderViews on _ReaderBase, _ReaderNavigation, _ReaderInput {
  Color get _background => switch (_settings.readerBackground) {
    'white' => Colors.white,
    'gray' => ReaderPalette.gray,
    _ => Colors.black,
  };

  String _pageLabel() {
    final n = _pages!.length;
    if (_paged && _spreads.isNotEmpty) {
      final spread = _spreads[spreadIndexOf(_spreads, _page)];
      if (spread.pages.length == 2) {
        return '${spread.pages[0] + 1}-${spread.pages[1] + 1} / $n';
      }
    }
    return '${_page + 1} / $n';
  }

  Widget _content() {
    if (_error != null) {
      return SafeArea(
        child: SourceErrorView(
          error: _error!,
          source: _source,
          onRetry: () => _load(startPage: _page),
        ),
      );
    }
    final pages = _pages;
    if (pages == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pages.isEmpty) {
      return Center(
        child: Text(
          tr('这一章没有图片'),
          style: context.text.bodyLarge?.copyWith(color: Colors.white54),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final view = _paged ? _pagedView(pages) : _verticalView(pages);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) => _onTap(d, c),
          onLongPressStart: (d) =>
              _pageMenu(_pageAt(d.localPosition, c.biggest)),
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
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScroll,
        itemPositionsListener: _positions,
        scrollOffsetController: _offsets,
        initialScrollIndex: _page,
        minCacheExtent: MediaQuery.sizeOf(context).height * 2,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
        itemCount: pages.length + 1,
        itemBuilder: (context, i) {
          if (i == pages.length) {
            return ReaderChapterEnd(
              hasNext: _hasNextChapter,
              onNext: _nextChapter,
            );
          }
          final image = ReaderImage(
            key: ValueKey('v-$_chapterId-$i-${_settings.readerCrop}'),
            provider: _provider(i),
            index: i,
            knownAspect: _aspects[i],
            onAspect: (a) => _aspects[i] = a,
          );
          return gap > 0
              ? Padding(
                  padding: EdgeInsets.only(bottom: gap),
                  child: image,
                )
              : image;
        },
      ),
    );
  }

  Widget _pageImage(int i, {Alignment alignment = Alignment.center}) =>
      ReaderImage(
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
      final first = _pageImage(
        spread.pages[0],
        alignment: _rtl ? Alignment.centerLeft : Alignment.centerRight,
      );
      final second = _pageImage(
        spread.pages[1],
        alignment: _rtl ? Alignment.centerRight : Alignment.centerLeft,
      );
      return Row(
        textDirection: TextDirection.ltr,
        children: [
          Expanded(child: _rtl ? second : first),
          Expanded(child: _rtl ? first : second),
        ],
      );
    }
    final half = spread.half;
    if (half != null) {
      return HalfPage(left: half == Half.left, child: _pageImage(spread.first));
    }
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
          if (i >= _spreads.length) {
            return ReaderChapterEnd(hasNext: true, onNext: _nextChapter);
          }
          return ZoomablePage(child: _spreadView(_spreads[i]));
        },
      ),
    );
  }
}
