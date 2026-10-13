import 'package:flutter/material.dart';

/// 输入框与操作分行，操作可换行；布局不受标题栏剩余宽度影响。
class SearchToolbar extends StatelessWidget {
  const SearchToolbar({super.key, required this.field, required this.actions});
  final Widget field;
  final List<Widget> actions;
  static const inputPadding = EdgeInsetsDirectional.fromSTEB(18, 14, 14, 14);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        ),
      ],
    ),
  );
}

/// 键盘和横屏缩小可用高度时，工具栏自身可滚动，结果区域仍保留空间。
class SearchLayout extends StatelessWidget {
  const SearchLayout({super.key, required this.toolbar, required this.results});
  final Widget toolbar;
  final Widget results;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .75),
          child: SingleChildScrollView(child: toolbar),
        ),
        Expanded(child: results),
      ],
    ),
  );
}
