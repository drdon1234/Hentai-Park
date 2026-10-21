import 'package:flutter/material.dart';

import '../../core/platform_capabilities.dart';
import 'tokens.dart';

/// 桌面始终使用居中面板，触屏设备的紧凑窗口使用底部弹层。
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool? showDragHandle,
  AnimationStyle? sheetAnimationStyle,
}) {
  if (!PlatformCapabilities.desktop && MediaQuery.sizeOf(context).width < 720) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (context) => isScrollControlled
          ? builder(context)
          : SingleChildScrollView(child: builder(context)),
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      sheetAnimationStyle: sheetAnimationStyle ?? Motion.menu(context),
      useSafeArea: true,
    );
  }
  return showDialog<T>(
    context: context,
    animationStyle: sheetAnimationStyle ?? Motion.menu(context),
    useRootNavigator: false,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: LayoutBuilder(
          builder: (context, constraints) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(size: Size(constraints.maxWidth, constraints.maxHeight)),
            child: isScrollControlled
                ? Builder(builder: builder)
                : SingleChildScrollView(child: Builder(builder: builder)),
          ),
        ),
      ),
    ),
  );
}
