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

/// 历史、下载等长列表在宽窗口中保持易读的行宽，不把一行拉到整个屏幕。
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960),
      child: child,
    ),
  );
}
