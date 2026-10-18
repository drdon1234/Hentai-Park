import 'package:flutter/material.dart';

/// 设置表单统一居中，限制宽屏下文字与控件之间的距离。
class SettingsBody extends StatelessWidget {
  const SettingsBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: child,
    ),
  );
}
