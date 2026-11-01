import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../theme.dart';

/// 页面级临时开关，不改变用户的屏蔽规则。
class ResultVisibility extends StatelessWidget {
  const ResultVisibility({
    super.key,
    this.supportsPreviews = false,
    this.showBlocked,
    this.onBlocked,
    required this.hidePreviews,
    required this.onPreviews,
  });
  final bool supportsPreviews;
  final bool? showBlocked;
  final ValueChanged<bool>? onBlocked;
  final bool hidePreviews;
  final ValueChanged<bool> onPreviews;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (showBlocked != null)
        IconButton(
          isSelected: showBlocked,
          tooltip: tr(showBlocked! ? '隐藏已屏蔽内容' : '显示已屏蔽内容'),
          icon: const Icon(Icons.visibility_off_outlined),
          selectedIcon: const Icon(Icons.visibility_outlined),
          onPressed: () {
            onBlocked?.call(!showBlocked!);
            context.toast(tr(showBlocked! ? '已隐藏屏蔽内容' : '已显示屏蔽内容'));
          },
        ),
      if (supportsPreviews)
        IconButton(
          isSelected: hidePreviews,
          tooltip: tr(hidePreviews ? '显示仅供预览的作品' : '隐藏仅供预览的作品'),
          icon: const Icon(Icons.preview_outlined),
          selectedIcon: const Icon(Icons.preview_rounded),
          onPressed: () {
            onPreviews(!hidePreviews);
            context.toast(tr(hidePreviews ? '已显示仅供预览的作品' : '已隐藏仅供预览的作品'));
          },
        ),
    ],
  );
}
