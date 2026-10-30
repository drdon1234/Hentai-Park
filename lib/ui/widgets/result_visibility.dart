import 'package:flutter/material.dart';

import '../../core/localization.dart';

/// 页面级临时开关，不改变用户的屏蔽规则。
class ResultVisibility extends StatelessWidget {
  const ResultVisibility({
    super.key,
    this.showBlocked,
    this.onBlocked,
    required this.hidePreviews,
    required this.onPreviews,
  });
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
          onPressed: () => onBlocked?.call(!showBlocked!),
        ),
      IconButton(
        isSelected: hidePreviews,
        tooltip: tr(hidePreviews ? '显示预览内容' : '隐藏预览内容'),
        icon: const Icon(Icons.filter_alt_off_outlined),
        selectedIcon: const Icon(Icons.filter_alt_outlined),
        onPressed: () => onPreviews(!hidePreviews),
      ),
    ],
  );
}
