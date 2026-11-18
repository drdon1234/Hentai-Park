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
    unawaited(PlatformBridge.setSystemBarsHidden(!_overlay));
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

  static String _imageExtension(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return 'gif';
    }
    return 'png';
  }

  Future<void> _pageMenu(int index) async {
    final action = await showPageActions(context, index);
    if (action == null || !mounted) return;
    try {
      final bytes = await _provider(index).displayBytes();
      final ext = _imageExtension(bytes);
      final name = 'hentaipark_${safeFileName(widget.work.id)}_${index + 1}';
      if (action == PageAction.save) {
        if (!PlatformCapabilities.photoLibrary) {
          await FilePicker.saveFile(fileName: '$name.$ext', bytes: bytes);
          return;
        }
        var granted = await Gal.hasAccess(toAlbum: true);
        if (!granted) {
          granted = await Gal.requestAccess(toAlbum: true);
        }
        if (!granted) {
          if (mounted) context.toast(tr('需要相册权限才能保存图片'));
          return;
        }
        await Gal.putImageBytes(bytes, album: 'HentaiPark', name: name);
        if (mounted) context.toast(tr('已保存到相册'));
      } else {
        final file = File(p.join(AppPaths.cache.path, '$name.$ext'));
        await file.writeAsBytes(bytes);
        if (!mounted) return;
        await shareContent(context, files: [XFile(file.path)]);
      }
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
    }
  }
}
