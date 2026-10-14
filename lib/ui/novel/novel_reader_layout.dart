part of 'novel_reader_page.dart';

/// Text layout: paragraphs with highlighted notes, the paged and scrolling views, and
/// the mapping between scroll position and character offset.
mixin _NovelLayout on _NovelReaderBase {
  TextPainter _segmentPainter(NovelPage segment) {
    final prefix =
        _settings.novelIndent && novelParagraphStart(_text, segment.start)
        ? '\u3000\u3000'
        : '';
    return TextPainter(
      text: TextSpan(
        text: prefix + _text.substring(segment.start, segment.end).trimRight(),
        style: _effectiveStyle,
      ),
      textDirection: TextDirection.ltr,
      textAlign: _align,
    )..layout(maxWidth: _textWidth);
  }

  double _scrollAlignment(int offset) {
    if (_segments.isEmpty || _viewport.height <= 0) return 0;
    final segment = _segments[novelPageAt(_segments, offset)];
    final painter = _segmentPainter(segment);
    try {
      final prefix =
          _settings.novelIndent && novelParagraphStart(_text, segment.start)
          ? 2
          : 0;
      final position = (offset - segment.start + prefix).clamp(
        0,
        painter.text!.toPlainText().length,
      );
      return -painter
              .getOffsetForCaret(TextPosition(offset: position), Rect.zero)
              .dy /
          _viewport.height;
    } finally {
      painter.dispose();
    }
  }

  void _onScroll() {
    if (_paged || _body == null) return;
    final visible =
        _positions.itemPositions.value
            .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    if (visible.isEmpty) return;
    final first = visible.first;
    final end = visible.any(
      (p) => p.index == _segments.length && p.itemTrailingEdge <= 1,
    );
    if (end) {
      _changedOffset(_text.length);
      return;
    }
    if (first.index >= _segments.length) return;
    final segment = _segments[first.index];
    final painter = _segmentPainter(segment);
    try {
      final prefix =
          _settings.novelIndent && novelParagraphStart(_text, segment.start)
          ? 2
          : 0;
      final local =
          painter
              .getPositionForOffset(
                Offset(
                  0,
                  math.max(0, -first.itemLeadingEdge * _viewport.height),
                ),
              )
              .offset -
          prefix;
      _changedOffset(
        segment.start + local.clamp(0, segment.end - segment.start),
      );
    } finally {
      painter.dispose();
    }
  }

  (Color, Color) _colors(BuildContext context) =>
      _settings.novelTheme == 'system'
      ? (
          Theme.of(context).colorScheme.surface,
          Theme.of(context).colorScheme.onSurface,
        )
      : ReaderPalette.novel[_settings.novelTheme] ??
            ReaderPalette.novel['paper']!;
  TextStyle _style(Color color, {double? size}) => ParkText.novel(
    size: size ?? _settings.novelFontSize,
    height: _settings.novelLineHeight,
    letterSpacing: _settings.novelLetterSpacing,
    color: color,
    bold: _settings.novelBold,
    font: _settings.novelFont,
  );
  TextAlign get _align =>
      _settings.novelJustify ? TextAlign.justify : TextAlign.start;

  Widget _paragraph(String value, int offset, TextStyle style) {
    final notes = ReadingNotes.instance
        .forWork(widget.work.uid)
        .where((n) => n.chapterId == _loadedKey && n.quote.isNotEmpty);
    final ranges = <(int, int)>[];
    for (final note in notes) {
      final start = math.max(0, note.offset - offset),
          end = math.min(
            value.length,
            note.offset + note.quote.length - offset,
          );
      if (end > start && start < value.length) ranges.add((start, end));
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final (start, end) in ranges) {
      if (end <= cursor) continue;
      final begin = math.max(cursor, start);
      if (begin > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, begin)));
      }
      spans.add(
        TextSpan(
          text: value.substring(begin, end),
          style: TextStyle(
            backgroundColor: Theme.of(context).colorScheme.primary
                .withValues(alpha: .3),
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    if (_settings.novelIndent && novelParagraphStart(_text, offset)) {
      spans.insert(0, const TextSpan(text: '\u3000\u3000'));
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: _align,
      textDirection: TextDirection.ltr,
    );
  }

  Widget _content(Color foreground) => LayoutBuilder(
    builder: (context, c) {
      _viewport = Size(c.maxWidth, c.maxHeight);
      final margin = _settings.novelMargin;
      final scale = MediaQuery.textScalerOf(context);
      final style = _style(
        foreground,
        size: scale.scale(_settings.novelFontSize),
      );
      _effectiveStyle = style;
      _textWidth = math.max(1, c.maxWidth - margin * 2);
      final layoutKey = (
        _text,
        c.maxWidth,
        c.maxHeight,
        style,
        margin,
        _align,
        _settings.novelMode,
        _settings.novelIndent,
        _settings.novelParagraphGap,
      );
      if (_paged && _layoutKey != layoutKey) {
        _pages = paginateNovel(
          _text,
          width: math.max(1, c.maxWidth - margin * 2),
          height: math.max(1, c.maxHeight - 32),
          style: style,
          direction: TextDirection.ltr,
          align: _align,
          indent: _settings.novelIndent,
          paragraphGap: _settings.novelParagraphGap,
        );
        _page = novelPageAt(_pages, _offset);
        _pager?.dispose();
        _pager = PageController(initialPage: _page);
        _layoutKey = layoutKey;
      }
      final content = _paged
          ? PageView.builder(
              key: ValueKey(layoutKey),
              controller: _pager,
              itemCount: _pages.length,
              onPageChanged: (i) {
                _page = i;
                _changedOffset(_pages[i].start);
              },
              itemBuilder: (ctx, i) {
                final p = _pages[i];
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: margin,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final part in novelPageSegments(_text, p))
                        Padding(
                          padding: EdgeInsets.only(
                            top:
                                part.start > p.start &&
                                    novelParagraphStart(_text, part.start)
                                ? _settings.novelParagraphGap
                                : 0,
                          ),
                          child: _paragraph(
                            _text.substring(part.start, part.end).trimRight(),
                            part.start,
                            style,
                          ),
                        ),
                      if (i == _pages.length - 1)
                        TextButton(
                          onPressed: () => _changedOffset(_text.length),
                          child: Text(tr('标记本章已读')),
                        ),
                    ],
                  ),
                );
              },
            )
          : ScrollablePositionedList.builder(
              key: ValueKey(layoutKey),
              itemScrollController: _items,
              itemPositionsListener: _positions,
              scrollOffsetController: _scrollOffset,
              initialScrollIndex: novelPageAt(_segments, _offset),
              initialAlignment: _scrollAlignment(_offset),
              padding: EdgeInsets.symmetric(horizontal: margin, vertical: 16),
              itemCount: _segments.length + 1,
              itemBuilder: (ctx, i) {
                if (i == _segments.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      tr('本章结束'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: foreground),
                    ),
                  );
                }
                final p = _segments[i];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom:
                        p.end == _text.length ||
                            (p.end >= 2 &&
                                _text.substring(p.end - 2, p.end) == '\n\n')
                        ? _settings.novelParagraphGap
                        : 0,
                  ),
                  child: _paragraph(
                    _text.substring(p.start, p.end).trimRight(),
                    p.start,
                    style,
                  ),
                );
              },
            );
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: SelectionArea(
          onSelectionChanged: (content) {
            _selected = (content?.plainText ?? '')
                .replaceAll(RegExp(r'(^|\n)\u3000\u3000'), '\n')
                .trimLeft();
            if (_selected.isNotEmpty && _auto) _setAuto(false);
          },
          contextMenuBuilder: (ctx, state) =>
              AdaptiveTextSelectionToolbar.buttonItems(
                anchors: state.contextMenuAnchors,
                buttonItems: [
                  ...state.contextMenuButtonItems,
                  ContextMenuButtonItem(
                    label: tr('翻译'),
                    onPressed: () {
                      final selected = _selected;
                      ContextMenuController.removeAny();
                      unawaited(showTextTranslation(context, selected));
                    },
                  ),
                  ContextMenuButtonItem(
                    label: tr('标注'),
                    onPressed: () {
                      ContextMenuController.removeAny();
                      unawaited(_addNote(bookmark: false));
                    },
                  ),
                ],
              ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) {
              final fraction = details.localPosition.dx / c.maxWidth;
              if (_settings.novelTapToPage && fraction < .25) {
                _move(-1);
              } else if (_settings.novelTapToPage && fraction > .75) {
                _move(1);
              } else {
                _toggleControls();
              }
            },
            child: content,
          ),
        ),
      );
    },
  );
}
