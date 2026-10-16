import 'package:flutter/material.dart';

/// 宽窗口的操作与选择在中央完成，紧凑窗口保留底部弹层。
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool? showDragHandle,
  AnimationStyle? sheetAnimationStyle,
}) {
  if (MediaQuery.sizeOf(context).width < 720) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (context) => isScrollControlled
          ? builder(context)
          : SingleChildScrollView(child: builder(context)),
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      sheetAnimationStyle: sheetAnimationStyle,
      useSafeArea: true,
    );
  }
  return showDialog<T>(
    context: context,
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
