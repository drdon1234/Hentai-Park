import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard and pointer focus stay local to the player and its active route.
class VideoPlayerInput extends StatefulWidget {
  const VideoPlayerInput({
    super.key,
    required this.child,
    required this.onPlayPause,
    required this.onSeek,
    required this.onVolume,
    required this.onMute,
    required this.onFullscreen,
    required this.onExitFullscreen,
    required this.onTemporarySpeedStart,
    required this.onTemporarySpeedEnd,
  });

  final Widget child;
  final VoidCallback onPlayPause;
  final ValueChanged<int> onSeek;
  final ValueChanged<double> onVolume;
  final VoidCallback onMute;
  final VoidCallback onFullscreen;
  final VoidCallback onExitFullscreen;
  final VoidCallback onTemporarySpeedStart;
  final VoidCallback onTemporarySpeedEnd;

  @override
  State<VideoPlayerInput> createState() => _VideoPlayerInputState();
}

class _VideoPlayerInputState extends State<VideoPlayerInput> {
  final _focus = FocusNode();
  Timer? _rightHoldTimer;
  bool _rightDown = false;
  bool _temporarySpeed = false;

  static const _rightHoldDelay = Duration(milliseconds: 300);

  @override
  void dispose() {
    _rightHoldTimer?.cancel();
    if (_temporarySpeed) widget.onTemporarySpeedEnd();
    _focus.dispose();
    super.dispose();
  }

  void _startRightHold() {
    if (_rightDown) return;
    _rightDown = true;
    _rightHoldTimer?.cancel();
    _rightHoldTimer = Timer(_rightHoldDelay, () {
      if (!_rightDown || _temporarySpeed) return;
      _temporarySpeed = true;
      widget.onTemporarySpeedStart();
    });
  }

  void _endRightHold() {
    if (!_rightDown) return;
    _rightDown = false;
    _rightHoldTimer?.cancel();
    _rightHoldTimer = null;
    if (_temporarySpeed) {
      _temporarySpeed = false;
      widget.onTemporarySpeedEnd();
    } else {
      widget.onSeek(10);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent == false) {
      if (_rightDown) _endRightHold();
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _endRightHold();
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext != null &&
        (focusedContext.widget is EditableText ||
            focusedContext.findAncestorWidgetOfExactType<EditableText>() !=
                null)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      if (!repeat) widget.onPlayPause();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onSeek(-10);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _startRightHold();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      widget.onVolume(.05);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      widget.onVolume(-.05);
    } else if (key == LogicalKeyboardKey.keyM) {
      if (!repeat) widget.onMute();
    } else if (key == LogicalKeyboardKey.keyF) {
      if (!repeat) widget.onFullscreen();
    } else if (key == LogicalKeyboardKey.escape) {
      if (!repeat) widget.onExitFullscreen();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: _onKey,
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _focus.requestFocus(),
      child: widget.child,
    ),
  );
}
