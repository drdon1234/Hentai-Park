part of 'novel_reader_page.dart';

mixin _NovelTranslation on _NovelReaderBase {
  void _onTranslationPreferences() {
    if (mounted && _translateFullText && _body != null) _beginTranslation();
  }

  void _detachTranslation() {
    _translation?.removeListener(_translationChanged);
    _translation?.cancel();
    _translation = null;
  }

  @override
  void _toggleFullTranslation() {
    if (_body == null) return;
    _translateFullText = !_translateFullText;
    if (_translateFullText) {
      _beginTranslation();
    } else {
      _detachTranslation();
      _showDocument(null);
    }
  }

  void _beginTranslation() {
    if (_body == null || _loadedKey == null) return;
    _detachTranslation();
    // 新语言/引擎翻译完成前继续保留可读的原文。
    _showDocument(null);
    final key = _loadedKey!;
    final original = _originalText;
    final locale =
        _translationLocale ??
        AppLocalizations.localeKey(AppLocalizations.of(context).locale);
    final engine = _settings.translateEngine;
    var session = _translations.remove(key);
    if (session != null &&
        (session.original != original ||
            session.locale != locale ||
            session.engine != engine)) {
      session.dispose();
      session = null;
    }
    session ??= NovelTranslationSession(
      original: original,
      locale: locale,
      engine: engine,
      queue: widget.translationQueue,
    );
    _translations[key] = session;
    while (_translations.length > 3) {
      _translations.remove(_translations.keys.first)?.dispose();
    }
    _translation = session;
    session.addListener(_translationChanged);
    if (session.document != null) {
      _showDocument(session.document);
    } else {
      unawaited(session.start());
    }
  }

  void _translationChanged() {
    if (!mounted || !_translateFullText) return;
    final document = _translation?.document;
    if (document != null && !identical(document, _translationDocument)) {
      _showDocument(document);
    } else {
      setState(() {});
    }
  }

  void _showDocument(NovelTranslationDocument? document) {
    final sourceOffset = _sourceOffset(_offset);
    _saveTimer?.cancel();
    _setAuto(false);
    unawaited(_speech.stop().catchError((Object _) {}));
    setState(() {
      _translationDocument = document;
      _text = document?.text ?? _originalText;
      _textDirection = novelTextDirection(_text);
      _segments = novelSegments(_text);
      _offset = novelSafeOffset(_text, _displayOffset(sourceOffset));
      _selected = '';
      _layoutKey = null;
    });
  }

  Widget _translationStatus(Color background) {
    final session = _translation;
    if (session == null || (!session.busy && !session.failed)) {
      return const SizedBox.shrink();
    }
    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(Gap.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (session.busy)
              LinearProgressIndicator(
                value: session.total == 0
                    ? null
                    : session.completed / session.total,
              ),
            Wrap(
              spacing: Gap.s,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  session.failed
                      ? tr('全文翻译失败，已保留原文')
                      : tr('正在翻译全文（{done}/{total}）', {
                          'done': session.completed,
                          'total': session.total,
                        }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (session.failed)
                  OutlinedButton(
                    onPressed: () => unawaited(session.start()),
                    child: Text(tr('重试')),
                  ),
                OutlinedButton(
                  onPressed: _toggleFullTranslation,
                  child: Text(tr('显示原文')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
