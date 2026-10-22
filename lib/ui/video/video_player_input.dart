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
  });

  final Widget child;
  final VoidCallback onPlayPause;
  final ValueChanged<int> onSeek;
  final ValueChanged<double> onVolume;
  final VoidCallback onMute;
  final VoidCallback onFullscreen;
  final VoidCallback onExitFullscreen;

  @override
  State<VideoPlayerInput> createState() => _VideoPlayerInputState();
}

class _VideoPlayerInputState extends State<VideoPlayerInput> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
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
      widget.onSeek(10);
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
