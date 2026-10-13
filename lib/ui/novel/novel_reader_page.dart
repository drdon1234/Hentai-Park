import 'dart:async';

import '../widgets/text_translation.dart';

import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../reader/device_session.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../../novel/reading_notes.dart';
import '../../novel/novel_speech.dart';
import '../../novel/text_layout.dart';
import '../../engine/platform_bridge.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import 'novel_settings_sheet.dart';

class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({
    super.key,
    required this.work,
    this.chapter,
    this.startOffset = 0,
  });
  final WorkDetail work;
  final Chapter? chapter;
  final int startOffset;
  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage>
    with WidgetsBindingObserver {
  final _settings = AppSettings.instance;
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
  CancelToken? _request;
  List<Chapter> get _chapters => widget.work.chapters?.isNotEmpty == true
      ? widget.work.chapters!
      : [Chapter(chapterKeyOf(widget.work.singleChapterId), tr('全本'))];
  Chapter get _chapter => _chapters[_chapterIndex];
  bool get _paged => _settings.novelMode == 'paged';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chapterIndex = math.max(
      0,
      _chapters.indexWhere((c) => c.id == widget.chapter?.id),
    );
    _positions.itemPositions.addListener(_onScroll);
    _settings.addListener(_onSettings);
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
    _saveTimer?.cancel();
    _autoTimer?.cancel();
    _device.dispose();
    _positions.itemPositions.removeListener(_onScroll);
    _settings.removeListener(_onSettings);
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

  void _save() {
    if (_body == null || _loadedKey == null) return;
    Library.instance.recordProgress(
      widget.work.toItem(),
      chapterId: _loadedKey,
      chapterKey: _loadedKey,
      chapterTitle: _chapter.title,
      page: _offset,
      pageCount: _text.length + 1,
    );
  }

  void _changedOffset(int offset) {
    _offset = novelSafeOffset(_text, offset);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
    if (mounted) setState(() {});
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

  Future<void> _switchChapter(int index, {int? offset}) async {
    if (index < 0 || index >= _chapters.length) return;
    _save();
    setState(() => _chapterIndex = index);
    final state = Library.instance.chapterState(widget.work.uid, _chapter.id);
    await _load(offset ?? (state?.read == true ? 0 : state?.lastPage ?? 0));
  }

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
      if (_settings.novelAnimate) {
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
          duration: Duration(milliseconds: _settings.novelAnimate ? 220 : 1),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    unawaited(PlatformBridge.applyVideoFullscreen(!_controls));
  }

  void _setAuto(bool value) {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (mounted) setState(() => _auto = value && !_paged && _body != null);
    if (!_auto) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_items.isAttached) return;
      if (_offset >= _text.length) {
        _setAuto(false);
        return;
      }
      unawaited(
        _scrollOffset.animateScroll(
          offset: _settings.novelAutoScroll,
          duration: const Duration(milliseconds: 950),
          curve: Curves.linear,
        ),
      );
    });
  }

  Future<void> _directory() async {
    final controller = TextEditingController();
    var query = '', reversed = false;
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          final indices = [
            for (var i = 0; i < _chapters.length; i++)
              if (_chapters[i].title.toLowerCase().contains(
                query.toLowerCase(),
              ))
                i,
          ];
          if (reversed) indices.sort((a, b) => b.compareTo(a));
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * .8,
              child: Column(
                children: [
                  ListTile(
                    title: Text(tr('目录')),
                    trailing: IconButton(
                      tooltip: tr('倒序'),
                      icon: const Icon(Icons.swap_vert),
                      onPressed: () => update(() => reversed = !reversed),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(hintText: tr('搜索章节')),
                      onChanged: (v) => update(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: indices.length,
                      itemBuilder: (ctx, i) {
                        final index = indices[i], chapter = _chapters[index];
                        return ListTile(
                          selected: index == _chapterIndex,
                          title: Text(chapter.title),
                          subtitle:
                              Library.instance
                                      .chapterState(widget.work.uid, chapter.id)
                                      ?.read ==
                                  true
                              ? Text(tr('已读'))
                              : null,
                          trailing:
                              DownloadManager.instance.isChapterDownloaded(
                                widget.work.uid,
                                chapter.id,
                              )
                              ? const Icon(Icons.download_done)
                              : null,
                          onTap: () => Navigator.pop(ctx, index),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
    if (selected != null && mounted) await _switchChapter(selected);
  }

  Future<void> _search() async {
    if (_body == null) return;
    final text = _text, key = _loadedKey;
    final controller = TextEditingController();
    var query = '';
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          final matches = <int>[];
          if (query.trim().isNotEmpty) {
            final haystack = text.toLowerCase(), needle = query.toLowerCase();
            var start = 0;
            while (matches.length < 500) {
              final offset = haystack.indexOf(needle, start);
              if (offset < 0) break;
              matches.add(offset);
              start = offset + needle.length;
            }
          }
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * .75,
              child: Column(
                children: [
                  ListTile(title: Text(tr('本章搜索'))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(hintText: tr('搜索正文')),
                      onChanged: (v) => update(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (ctx, i) {
                        final offset = matches[i];
                        return ListTile(
                          title: Text(
                            text.substring(
                              math.max(0, offset - 24),
                              math.min(text.length, offset + query.length + 70),
                            ),
                          ),
                          onTap: () => Navigator.pop(ctx, offset),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
    if (mounted && result != null && key == _loadedKey) _jump(result);
  }

  Future<void> _addNote({bool bookmark = false}) async {
    if (_body == null || _loadedKey == null) return;
    final key = _loadedKey!;
    var quote = bookmark
        ? _text.substring(_offset, novelSafeOffset(_text, _offset + 100))
        : _selected;
    var offset = _offset;
    if (!bookmark && quote.isNotEmpty) {
      final visibleStart = _paged && _pages.isNotEmpty
          ? _pages[_page].start
          : _segments[novelPageAt(_segments, _offset)].start;
      final found = novelSelectionRange(_text, quote, visibleStart);
      if (found == null) return;
      offset = found.start;
      quote = _text.substring(found.start, found.end);
    }
    final controller = TextEditingController();
    final note = bookmark
        ? ''
        : await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr('添加标注')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(quote, maxLines: 5, overflow: TextOverflow.ellipsis),
                    TextField(
                      controller: controller,
                      maxLines: 4,
                      decoration: InputDecoration(hintText: tr('备注')),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('取消')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, controller.text),
                  child: Text(tr('保存')),
                ),
              ],
            ),
          );
    controller.dispose();
    if (note == null) return;
    try {
      await ReadingNotes.instance.add(
        uid: widget.work.uid,
        chapterId: key,
        offset: offset,
        quote: quote,
        note: note,
      );
      if (mounted) context.toast(tr('已保存'));
    } catch (e) {
      if (mounted) context.toast(tr('操作失败：{value0}', {'value0': e}));
    }
  }

  Future<void> _editNote(ReadingNote entry) async {
    final controller = TextEditingController(text: entry.note);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('编辑标注')),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(hintText: tr('备注')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(tr('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await ReadingNotes.instance.update(entry.id, note: value);
    } catch (e) {
      if (mounted) context.toast(tr('操作失败：{value0}', {'value0': e}));
    }
  }

  Future<void> _notes() async {
    final result = await showModalBottomSheet<ReadingNote>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .75,
          child: ListenableBuilder(
            listenable: ReadingNotes.instance,
            builder: (ctx, _) {
              final notes = ReadingNotes.instance.forWork(widget.work.uid);
              return Column(
                children: [
                  ListTile(title: Text(tr('书签与标注'))),
                  Expanded(
                    child: notes.isEmpty
                        ? Center(child: Text(tr('暂无书签与标注')))
                        : ListView.builder(
                            itemCount: notes.length,
                            itemBuilder: (ctx, i) {
                              final n = notes[i];
                              return ListTile(
                                title: Text(
                                  n.note.isEmpty ? n.quote : n.note,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  _chapters
                                          .where((c) => c.id == n.chapterId)
                                          .firstOrNull
                                          ?.title ??
                                      n.chapterId,
                                ),
                                onTap: () => Navigator.pop(ctx, n),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: tr('编辑标注'),
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _editNote(n),
                                    ),
                                    IconButton(
                                      tooltip: tr('删除'),
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        try {
                                          await ReadingNotes.instance.remove(
                                            n.id,
                                          );
                                        } catch (e) {
                                          if (ctx.mounted) {
                                            ctx.toast(
                                              tr('操作失败：{value0}', {
                                                'value0': e,
                                              }),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    final index = _chapters.indexWhere((c) => c.id == result.chapterId);
    if (index < 0) {
      context.toast(tr('章节已不在当前目录中'));
      return;
    }
    if (index == _chapterIndex) {
      _jump(result.offset);
    } else {
      await _switchChapter(index, offset: result.offset);
    }
  }

  void _download() {
    DownloadManager.instance.enqueue(widget.work.toItem(), [_chapter]);
    context.toast(tr('已加入下载队列'));
  }

  Future<void> _readAloud() async {
    if (_speech.playing) {
      await _speech.stop();
      return;
    }
    if (_body == null) return;
    final generation = _generation;
    _setAuto(false);
    try {
      await _speech.read(
        _text,
        offset: _offset,
        language: widget.work.language.isNotEmpty
            ? widget.work.language
            : SourceManager.instance.manifest(widget.work.source)?.language ??
                  'en',
        rate: _settings.novelSpeechRate,
        onPosition: (offset) {
          if (mounted && generation == _generation) _jump(offset);
        },
      );
    } catch (_) {
      if (mounted) context.toast(tr('朗读不可用，请检查系统语音引擎与语言包'));
    }
  }

  (Color, Color) _colors(BuildContext context) =>
      switch (_settings.novelTheme) {
        'white' => (Colors.white, const Color(0xFF252525)),
        'green' => (const Color(0xFFCCE2CB), const Color(0xFF243429)),
        'dark' => (const Color(0xFF191919), const Color(0xFFBCB7AD)),
        'system' => (
          Theme.of(context).colorScheme.surface,
          Theme.of(context).colorScheme.onSurface,
        ),
        _ => (const Color(0xFFF2E8D3), const Color(0xFF3E352B)),
      };
  TextStyle _style(Color color) => TextStyle(
    fontSize: _settings.novelFontSize,
    height: _settings.novelLineHeight,
    letterSpacing: _settings.novelLetterSpacing,
    color: color,
    fontWeight: _settings.novelBold ? FontWeight.w600 : FontWeight.w400,
    fontFamily: _settings.novelFont == 'system' ? null : _settings.novelFont,
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
          style: TextStyle(backgroundColor: Colors.amber.withValues(alpha: .3)),
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
      final style = _style(foreground)
          .copyWith(fontSize: scale.scale(_settings.novelFontSize));
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
                      unawaited(_addNote());
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
  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
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
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    if (_controls)
                      AppBar(
                        backgroundColor: background,
                        foregroundColor: foreground,
                        title: Text(
                          _chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        actions: [
                          IconButton(
                            tooltip: tr('目录'),
                            icon: const Icon(Icons.list),
                            onPressed: _directory,
                          ),
                          IconButton(
                            tooltip: tr('添加书签'),
                            icon: const Icon(Icons.bookmark_add_outlined),
                            onPressed: _body == null
                                ? null
                                : () => _addNote(bookmark: true),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              switch (value) {
                                case 'notes':
                                  _notes();
                                case 'search':
                                  _search();
                                case 'download':
                                  _download();
                                case 'auto':
                                  _setAuto(!_auto);
                                case 'speech':
                                  _readAloud();
                              }
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'notes',
                                child: Text(tr('书签与标注')),
                              ),
                              PopupMenuItem(
                                value: 'search',
                                child: Text(tr('本章搜索')),
                              ),
                              PopupMenuItem(
                                value: 'download',
                                child: Text(tr('下载本章')),
                              ),
                              if (!_paged)
                                PopupMenuItem(
                                  value: 'auto',
                                  child: Text(tr(_auto ? '停止自动滚动' : '自动滚动')),
                                ),
                              PopupMenuItem(
                                value: 'speech',
                                child: Text(
                                  tr(_speech.playing ? '停止朗读' : '朗读'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    Expanded(
                      child: _error != null
                          ? SourceErrorView(
                              error: _error!,
                              source: widget.work.source,
                              onRetry: () => _load(_offset),
                            )
                          : _body == null
                          ? const Center(child: CircularProgressIndicator())
                          : _content(foreground),
                    ),
                    if (_body != null &&
                        (_controls || _settings.novelShowStatus))
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            if (_offline)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.offline_pin_outlined,
                                  size: 16,
                                  color: foreground,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                widget.work.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: foreground,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              _paged
                                  ? '${_page + 1}/${_pages.length} · ${(progress * 100).round()}%'
                                  : '${(progress * 100).round()}%',
                              style: TextStyle(color: foreground, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    if (_controls && _body != null)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Slider(
                            value: progress,
                            onChanged: (v) => _jump((v * _text.length).round()),
                          ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              IconButton(
                                tooltip: tr('上一章'),
                                onPressed: _chapterIndex > 0
                                    ? () => _switchChapter(_chapterIndex - 1)
                                    : null,
                                icon: const Icon(Icons.skip_previous),
                              ),
                              TextButton.icon(
                                onPressed: _directory,
                                icon: const Icon(Icons.list),
                                label: Text(tr('目录')),
                              ),
                              TextButton.icon(
                                onPressed: () => showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => const NovelSettingsSheet(),
                                ),
                                icon: const Icon(Icons.text_fields),
                                label: Text(tr('设置')),
                              ),
                              IconButton(
                                tooltip: tr('下一章'),
                                onPressed: _chapterIndex < _chapters.length - 1
                                    ? () => _switchChapter(_chapterIndex + 1)
                                    : null,
                                icon: const Icon(Icons.skip_next),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
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
    );
  }
}
