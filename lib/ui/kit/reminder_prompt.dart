import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../theme.dart';
import 'tokens.dart';

/// 更新与资源下载共用同一提示布局，内容滚动而操作区保持可见。
class ReminderPromptDialog extends StatefulWidget {
  const ReminderPromptDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    required this.onIgnore,
    this.primaryLabel,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final String? primaryLabel;
  final Future<void> Function() onIgnore;

  @override
  State<ReminderPromptDialog> createState() => _ReminderPromptDialogState();
}

class _ReminderPromptDialogState extends State<ReminderPromptDialog> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _ignore() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onIgnore();
      if (mounted) Navigator.pop(context, false);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(
      horizontal: Gap.page,
      vertical: Gap.xl,
    ),
    titlePadding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.l),
    contentPadding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.l),
    actionsPadding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.l),
    title: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Icon(widget.icon, color: context.colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: Gap.m),
        Expanded(child: Text(widget.title, style: context.text.titleLarge)),
      ],
    ),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...widget.children,
          if (_failed) ...[
            const SizedBox(height: Gap.m),
            Text(
              tr('无法保存提醒设置，请重试'),
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.error,
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: Gap.l),
            Row(
              children: [
                Expanded(
                  child: _secondaryAction(
                    icon: Icons.notifications_off_outlined,
                    label: tr('不再提醒'),
                    onPressed: _saving ? null : _ignore,
                  ),
                ),
                const SizedBox(width: Gap.s),
                Expanded(
                  child: _secondaryAction(
                    icon: Icons.schedule_outlined,
                    label: tr('稍后'),
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                  ),
                ),
              ],
            ),
            if (widget.primaryLabel != null) ...[
              const SizedBox(height: Gap.s),
              FilledButton(
                onPressed: _saving ? null : () => Navigator.pop(context, true),
                child: SelectionContainer.disabled(
                  child: Text(
                    widget.primaryLabel!,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _secondaryAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final c = context.colors;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: SelectionContainer.disabled(child: Text(label)),
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: Gap.s),
        backgroundColor: c.surfaceContainerHigh,
        foregroundColor: c.onSurface,
        disabledBackgroundColor: c.surfaceContainerHigh.withValues(alpha: .38),
        disabledForegroundColor: c.onSurfaceVariant.withValues(alpha: .55),
        shape: const RoundedRectangleBorder(borderRadius: Radii.medium),
      ),
    );
  }
}
