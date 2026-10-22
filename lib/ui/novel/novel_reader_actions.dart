part of 'novel_reader_page.dart';

/// Reader actions from the menu and selection toolbar: auto scroll, directory, search,
/// notes, download and read aloud.
mixin _NovelActions on _NovelReaderBase {
  @override
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
        ),
      );
    });
  }

  Future<void> _directory() async {
    final selected = await showChapterDirectory(
      context,
      uid: widget.work.uid,
      chapters: _chapters,
      current: _chapterIndex,
    );
    if (selected != null && mounted) await _switchChapter(selected);
  }

  Future<void> _search() async {
    if (_body == null) return;
    final key = _loadedKey;
    final searched = _text;
    final document = _translationDocument;
    final result = await showChapterSearch(context, searched);
    if (mounted && result != null && key == _loadedKey) {
      _jump(_displayOffset(document?.originalOffset(result) ?? result));
    }
  }

  @override
  Future<void> _addNote({required bool bookmark}) async {
    if (_body == null || _loadedKey == null) return;
    final key = _loadedKey!;
    final generation = _generation;
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
    final sourceStart = _sourceOffset(offset);
    final sourceEnd = _sourceOffset(offset + quote.length);
    quote = _originalText.substring(sourceStart, sourceEnd);
    offset = sourceStart;
    final note = bookmark ? '' : await askNote(context, quote: quote);
    if (note == null || !mounted || generation != _generation) return;
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

  Future<void> _notes() async {
    final result = await showReadingNotes(
      context,
      uid: widget.work.uid,
      chapters: _chapters,
    );
    if (!mounted || result == null) return;
    final index = _chapters.indexWhere((c) => c.id == result.chapterId);
    if (index < 0) {
      context.toast(tr('章节已不在当前目录中'));
      return;
    }
    if (index == _chapterIndex) {
      _jump(_displayOffset(result.offset));
    } else {
      await _switchChapter(index, offset: result.offset);
    }
  }

  void _download() {
    if (DownloadManager.instance.hasRestoreFailure(widget.work.uid)) {
      context.toast(tr('下载记录恢复失败，请前往下载页处理'));
      return;
    }
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
        language: _translationDocument != null
            ? normalizeSearchLanguage(_translation!.locale)!
            : widget.work.language.isNotEmpty
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

  Widget _moreMenu(Color foreground) => PopupMenuButton<String>(
    tooltip: tr('更多'),
    iconColor: foreground,
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
        case 'translation':
          _toggleFullTranslation();
        case 'translationFull':
          _setTranslationMode(scroll: false, persist: true);
        case 'translationScroll':
          _setTranslationMode(scroll: true);
        case 'translationScrollSave':
          _setTranslationMode(scroll: true, persist: true);
      }
    },
    itemBuilder: (ctx) => [
      PopupMenuItem(
        value: 'translation',
        enabled: _body != null,
        child: SelectionContainer.disabled(
          child: Text(tr(_translateFullText ? '显示原文' : '显示译文')),
        ),
      ),
      PopupMenuItem(
        value: 'translationFull',
        enabled: _body != null,
        child: Text(tr('全文翻译并保存')),
      ),
      PopupMenuItem(
        value: 'translationScroll',
        enabled: _body != null,
        child: Text(tr('随滚动翻译')),
      ),
      PopupMenuItem(
        value: 'translationScrollSave',
        enabled: _body != null,
        child: Text(tr('随滚动翻译并保存')),
      ),
      PopupMenuItem(
        value: 'notes',
        child: SelectionContainer.disabled(child: Text(tr('书签与标注'))),
      ),
      PopupMenuItem(
        value: 'search',
        child: SelectionContainer.disabled(child: Text(tr('本章搜索'))),
      ),
      PopupMenuItem(
        value: 'download',
        child: SelectionContainer.disabled(child: Text(tr('下载本章'))),
      ),
      if (!_paged)
        PopupMenuItem(
          value: 'auto',
          child: SelectionContainer.disabled(
            child: Text(tr(_auto ? '停止自动滚动' : '自动滚动')),
          ),
        ),
      PopupMenuItem(
        value: 'speech',
        child: SelectionContainer.disabled(
          child: Text(tr(_speech.playing ? '停止朗读' : '朗读')),
        ),
      ),
    ],
  );
}
