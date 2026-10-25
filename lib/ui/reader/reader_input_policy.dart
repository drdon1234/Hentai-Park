import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_lock.dart';

/// 阅读按键只交给前台、未被弹层遮挡且未锁定的阅读页。
bool readerInputAvailable(BuildContext context) {
  final state = WidgetsBinding.instance.lifecycleState;
  return (state == null || state == AppLifecycleState.resumed) &&
      !AppLock.instance.locked &&
      (ModalRoute.isCurrentOf(context) ?? true);
}

bool readerHandlesKey(BuildContext context, KeyEvent event) {
  if (event is! KeyDownEvent || !readerInputAvailable(context)) return false;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isControlPressed ||
      keyboard.isAltPressed ||
      keyboard.isMetaPressed ||
      keyboard.isShiftPressed) {
    return false;
  }
  final focused = FocusManager.instance.primaryFocus?.context;
  return focused == null ||
      (focused.widget is! EditableText &&
          focused.findAncestorWidgetOfExactType<EditableText>() == null);
}
