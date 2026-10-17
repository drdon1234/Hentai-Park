part of 'video_session.dart';

/// AI dramas page vertically: the next episode is prepared while the current one plays
/// and handed over without a loading gap when the user swipes to it.
extension _DramaEpisodes on VideoSession {
  Future<void> _discardPreload() {
    final pending = _preloaded;
    _preloadCancel?.cancel('episode preload no longer needed');
    _preloaded = null;
    preloadedEpisode = null;
    _preloadCancel = null;
    nextPreview = null;
    if (pending != null) {
      final closing = pending
          .then((video) => video.close())
          .catchError((Object _) {});
      _preloadClosing = Future.wait([_preloadClosing, closing]).then((_) {});
    }
    return _preloadClosing;
  }

  void _preloadNext() {
    if (!_active ||
        !scrollEpisodes ||
        !VideoSession.supported ||
        _preloaded != null ||
        episodeIndex >= episodes.length - 1) {
      return;
    }
    final next = preloadedEpisode = episodes[episodeIndex + 1];
    final token = _preloadCancel = CancelToken();
    final pending = _preloaded = PreparedVideo.open(
      work,
      next,
      token,
      localFile: localFile,
      initialSources: initialSources,
    );
    // 预加载失败不影响当前播放，切到该集时才显示或重试。
    pending.ignore();
    unawaited(
      pending
          .then((video) {
            if (_active && identical(pending, _preloaded)) {
              nextPreview = video;
              _update();
            }
          })
          .catchError((Object _) {}),
    );
  }

  Future<void> _selectDramaEpisode(Chapter next) {
    return PendingDisposals.instance.watch(() async {
      final refreshSources = error != null && next.id == episode.id;
      savePosition();
      _sourceRequest?.cancel('episode changed');
      final token = _sourceRequest = CancelToken();
      final request = ++_request;
      Future<PreparedVideo>? pending;
      if (preloadedEpisode?.id == next.id) {
        pending = _preloaded;
        // 转移所有权，当前请求取消时也取消尚未完成的预加载。
        final preloadToken = _preloadCancel;
        unawaited(token.whenCancel.then((e) => preloadToken?.cancel(e)));
        _preloaded = null;
        preloadedEpisode = null;
        _preloadCancel = null;
        nextPreview = null;
      } else {
        unawaited(_discardPreload());
      }
      final old = controller;
      final oldMedia = _media;
      // 只在确认换集后停止旧声音；释放与新播放器接管并行。
      final retiring = () async {
        try {
          await old?.pause();
        } finally {
          await (old?.dispose() ?? Future<void>.value()).whenComplete(
            () async => oldMedia?.close(),
          );
        }
      }();
      retiring.ignore();
      _resetFor(next);
      _update();
      PreparedVideo? prepared;
      try {
        if (pending == null) {
          await Future.wait([retiring, _preloadClosing]);
          if (!_active || token.isCancelled || request != _request) return;
        }
        prepared =
            await (pending ??
                PreparedVideo.open(
                  work,
                  next,
                  token,
                  localFile: localFile,
                  initialSources: initialSources,
                  refresh: refreshSources,
                ));
        if (!_active || token.isCancelled || request != _request) {
          await prepared.close();
          return;
        }
        final c = prepared.controller;
        final resume = _resumePoint(c.value.duration);
        if (resume != null) await c.seekTo(resume);
        await c.setPlaybackSpeed(speed);
        if (!_active || token.isCancelled || request != _request) {
          await prepared.close();
          return;
        }
        c.addListener(_onTick);
        controller = c;
        _media = prepared.media;
        sources = prepared.sources;
        current = prepared.source;
        offline = prepared.offline;
        _update();
        await syncPlayback();
        if (!_active || request != _request) return;
        _startSaving();
        onStarted?.call();
        await retiring;
        if (_active && request == _request) _preloadNext();
      } catch (e) {
        if (prepared != null && !identical(prepared.controller, controller)) {
          await prepared.close();
        }
        if (_active && !token.isCancelled && request == _request) {
          error = e;
          _update();
        }
      } finally {
        if (identical(_sourceRequest, token)) _sourceRequest = null;
      }
    }());
  }
}
