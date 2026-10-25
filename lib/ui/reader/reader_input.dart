part of 'reader_page.dart';

/// Taps, keys and the long-press page menu (save or share a page).
mixin _ReaderInput on _ReaderBase, _ReaderNavigation {
  Future<void> _setDesktopFullscreen(bool enabled) async {
    final previous = _desktopFullscreen;
    _desktopFullscreen = enabled;
    try {
      await PlatformBridge.applyVideoFullscreen(enabled);
    } catch (_) {
      if (mounted && _desktopFullscreen == enabled) {
        _desktopFullscreen = previous;
      }
    }
  }

  void _toggleOverlay() {
    setState(() => _overlay = !_overlay);
    SystemChrome.setEnabledSystemUIMode(
      _overlay ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void _onTap(TapUpDetails d, BoxConstraints c) {
    if (!_settings.tapToPage || _overlay) {
      _toggleOverlay();
      return;
    }
    final action = tapActionFor(
      d.localPosition.dx / c.maxWidth,
      d.localPosition.dy / c.maxHeight,
      layout:
          TapLayout.values[_settings.readerTapLayout.clamp(
            0,
            TapLayout.values.length - 1,
          )],
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
    if (!readerHandlesKey(context, e)) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (PlatformCapabilities.desktop && k == LogicalKeyboardKey.keyF) {
      unawaited(_setDesktopFullscreen(!_desktopFullscreen));
      return KeyEventResult.handled;
    }
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
      if (_desktopFullscreen) {
        unawaited(_setDesktopFullscreen(false));
        return KeyEventResult.handled;
      }
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The page under the finger: in a dual spread, the half that was pressed; in vertical mode the
  /// list item under the point.
  int _pageAt(Offset local, Size size) {
    if (_paged) {
      final spread = _spreads.isEmpty
          ? null
          : _spreads[_spreadIndex.clamp(0, _spreads.length - 1)];
      if (spread == null) return _page;
      if (spread.pages.length == 2) {
        final leftHalf = local.dx < size.width / 2;
        return (leftHalf != _rtl) ? spread.pages[0] : spread.pages[1];
      }
      return spread.first;
    }
    final y = local.dy / size.height;
    for (final pos in _positions.itemPositions.value) {
      if (pos.itemLeadingEdge <= y &&
          pos.itemTrailingEdge >= y &&
          pos.index < (_pages?.length ?? 0)) {
        return pos.index;
      }
    }
    return _page;
  }

  Future<void> _pageMenu(int index) async {
    final action = await showPageActions(context, index);
    if (action == null || !mounted) return;
    try {
      final bytes = await _provider(index).displayBytes();
      final name = 'hentaipark_${safeFileName(widget.work.id)}_${index + 1}';
      if (action == PageAction.save) {
        if (!PlatformCapabilities.photoLibrary) {
          await FilePicker.saveFile(fileName: '$name.png', bytes: bytes);
          return;
        }
        if (!await Gal.hasAccess(toAlbum: true)) {
          await Gal.requestAccess(toAlbum: true);
        }
        await Gal.putImageBytes(bytes, album: 'HentaiPark', name: name);
        if (mounted) context.toast(tr('已保存到相册'));
      } else {
        final file = File(p.join(AppPaths.cache.path, '$name.png'));
        await file.writeAsBytes(bytes);
        if (!mounted) return;
        await shareContent(context, files: [XFile(file.path)]);
      }
    } catch (e) {
      if (mounted) context.toast(tr('操作失败：{value0}', {'value0': e}));
    }
  }
}
