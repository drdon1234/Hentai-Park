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
        !visible ||
        _suspended ||
        !scrollEpisodes ||
        !VideoSession.supported ||
        _preloaded != null ||
        episodeIndex >= episodes.length - 1) {
      return;
    }
    final next = preloadedEpisode = episodes[episodeIndex + 1];
    final token = _preloadCancel = CancelToken();
    final pending = _preloaded = prepareVideo(
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

  Future<void> _releaseRetainedEpisodes() {
    final retained = _retainedEpisodes.values.toList();
    _retainedEpisodes.clear();
    return _preloadClosing = Future.wait([
      _preloadClosing,
      for (final entry in retained)
        entry.paused.whenComplete(entry.video.close),
    ]).then((_) {});
  }

  void _updateDramaRetention() {
    if (_retainedEpisodes.isEmpty) return;
    final value = controller?.value;
    if (!_active ||
        !foreground ||
        !visible ||
        AppLock.instance.locked ||
        value == null ||
        !value.isPlaying ||
        value.isBuffering) {
      _retentionTimer?.cancel();
      _retentionTimer = null;
      return;
    }
    final request = _request;
    _retentionTimer ??= Timer(const Duration(seconds: 2), () {
      _retentionTimer = null;
      if (!_active || request != _request) return;
      PendingDisposals.instance.add(
        _releaseRetainedEpisodes().then((_) {
          if (_active && request == _request) _preloadNext();
        }),
      );
    });
  }

  Future<void> _selectDramaEpisode(
    Chapter next, {
    Duration? at,
    bool? wantsPlayback,
  }) {
    return PendingDisposals.instance.watch(() async {
      if (!_active) return;
      final existing = controller;
      if (next.id == episode.id && existing != null && error == null) {
        final request = _request;
        if (at != null) await existing.seekTo(at);
        if (!_active || request != _request) return;
        if (wantsPlayback != null) {
          _wantsPlayback = wantsPlayback;
          await syncPlayback();
          _update();
        }
        return;
      }
      savePosition();
      _retentionTimer?.cancel();
      _retentionTimer = null;
      _sourceRequest?.cancel('episode changed');
      final token = _sourceRequest = CancelToken();
      final request = ++_request;
      final retained = _retainedEpisodes.remove(next.id);
      Future<PreparedVideo>? pending;
      if (retained == null && preloadedEpisode?.id == next.id) {
        pending = _preloaded;
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
      Future<void> paused = Future.value();
      if (old != null) {
        old.removeListener(_onTick);
        paused = old.pause();
        paused.ignore();
        _retainedEpisodes[episode.id] = (
          video: PreparedVideo(old, _media, sources, current, offline),
          paused: paused,
        );
      }
      // 只保留最近两集；快速连续切集也不能无限占用解码器与媒体连接。
      while (_retainedEpisodes.length > 2) {
        final oldest = _retainedEpisodes.remove(_retainedEpisodes.keys.first)!;
        _preloadClosing = Future.wait([
          _preloadClosing,
          oldest.paused.whenComplete(oldest.video.close),
        ]).then((_) {});
      }
      _resetFor(next);
      if (wantsPlayback != null) _wantsPlayback = wantsPlayback;
      _update();
      PreparedVideo? prepared = retained?.video;
      var adopted = false;
      try {
        await paused;
        await retained?.paused;
        if (!_active || token.isCancelled || request != _request) {
          await prepared?.close();
          // 已取走的预加载仍由当前请求负责收尾。
          if (pending != null) {
            try {
              await (await pending).close();
            } catch (_) {}
          }
          return;
        }
        if (prepared == null && pending == null) {
          await _preloadClosing;
          if (!_active || token.isCancelled || request != _request) return;
        }
        prepared ??=
            await (pending ??
                prepareVideo(
                  work,
                  next,
                  token,
                  localFile: localFile,
                  initialSources: initialSources,
                ));
        if (!_active || token.isCancelled || request != _request) {
          await prepared.close();
          return;
        }
        final c = prepared.controller;
        // 滑回保留集时直接沿用其位置，包括不足五秒的片段。
        final resume = at != null
            ? (at > c.value.duration ? c.value.duration : at)
            : retained == null
            ? _resumePoint(c.value.duration)
            : c.value.isCompleted
            ? Duration.zero
            : null;
        if (resume != null) await c.seekTo(resume);
        await c.setPlaybackSpeed(speed);
        await c.setVolume(_volume);
        if (!_active || token.isCancelled || request != _request) {
          await prepared.close();
          return;
        }
        c.addListener(_onTick);
        _requestedPosition = null;
        controller = c;
        _media = prepared.media;
        sources = prepared.sources;
        current = prepared.source;
        offline = prepared.offline;
        _completed = c.value.isCompleted;
        adopted = true;
        _update();
        await syncPlayback();
        if (!_active || request != _request) return;
        _startSaving();
        onStarted?.call();
        _updateDramaRetention();
        if (_retainedEpisodes.isEmpty) _preloadNext();
      } catch (e, stack) {
        if (!adopted) {
          await prepared?.close();
          if (pending != null) {
            try {
              await (await pending).close();
            } catch (_) {}
          }
        }
        if (_active && !token.isCancelled && request == _request) {
          _logPlayback(e, 'episode', stack);
          error = e;
          _update();
        }
      } finally {
        if (identical(_sourceRequest, token)) _sourceRequest = null;
      }
    }());
  }
}
