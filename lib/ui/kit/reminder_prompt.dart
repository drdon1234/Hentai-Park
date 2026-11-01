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
    this.ignoreLabel,
    this.onIgnoreAll,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final String? primaryLabel;
  final String? ignoreLabel;
  final Future<void> Function()? onIgnoreAll;
  final Future<void> Function() onIgnore;

  @override
  State<ReminderPromptDialog> createState() => _ReminderPromptDialogState();
}

class _ReminderPromptDialogState extends State<ReminderPromptDialog> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _ignore({bool all = false}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await (all ? widget.onIgnoreAll! : widget.onIgnore)();
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
            _ignoreActions(),
            if (widget.onIgnoreAll != null) ...[
              const SizedBox(height: Gap.s),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _secondaryAction(
                        icon: Icons.schedule_outlined,
                        label: tr('稍后'),
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context, false),
                      ),
                    ),
                    if (widget.primaryLabel != null) ...[
                      const SizedBox(width: Gap.s),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gap.s,
                              vertical: Gap.s,
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: Radii.medium,
                            ),
                          ),
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context, true),
                          child: SelectionContainer.disabled(
                            child: Text(
                              widget.primaryLabel!,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ] else if (widget.primaryLabel != null) ...[
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

  Widget _ignoreActions() {
    // AlertDialog 使用固有尺寸布局，不能在操作区嵌入 LayoutBuilder。
    final availableWidth =
        (MediaQuery.sizeOf(context).width -
                MediaQuery.viewInsetsOf(context).horizontal -
                Gap.page * 2 -
                Gap.xl * 2)
            .clamp(1.0, 480.0);
    final ignore = _secondaryAction(
      icon: widget.onIgnoreAll == null
          ? Icons.notifications_off_outlined
          : null,
      label: widget.ignoreLabel ?? tr('不再提醒'),
      onPressed: _saving ? null : () => _ignore(),
    );
    final otherLabel = tr(widget.onIgnoreAll == null ? '稍后' : '所有站点不再提醒');
    final other = _secondaryAction(
      icon: widget.onIgnoreAll == null ? Icons.schedule_outlined : null,
      label: otherLabel,
      onPressed: _saving
          ? null
          : widget.onIgnoreAll == null
          ? () => Navigator.pop(context, false)
          : () => _ignore(all: true),
    );
    final labelWidth =
        (availableWidth - Gap.s) / 2 -
        Gap.s * 2 -
        (widget.onIgnoreAll == null ? 19 + Gap.s : 0);
    bool exceedsOneLine(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: context.text.labelLarge),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout(maxWidth: labelWidth.clamp(1, double.infinity));
      final exceeds = painter.didExceedMaxLines;
      painter.dispose();
      return exceeds;
    }

    if (exceedsOneLine(widget.ignoreLabel ?? tr('不再提醒')) ||
        exceedsOneLine(otherLabel)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ignore,
          const SizedBox(height: Gap.s),
          other,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: ignore),
          const SizedBox(width: Gap.s),
          Expanded(child: other),
        ],
      ),
    );
  }

  Widget _secondaryAction({
    IconData? icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final c = context.colors;
    return TextButton.icon(
      onPressed: onPressed,
      icon: icon == null ? null : Icon(icon, size: 19),
      label: SelectionContainer.disabled(child: Text(label)),
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: Gap.s),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? c.surfaceContainerHighest
            : c.surfaceContainerHigh,
        foregroundColor: c.onSurface,
        disabledBackgroundColor: c.surfaceContainerHigh.withValues(alpha: .38),
        disabledForegroundColor: c.onSurfaceVariant.withValues(alpha: .55),
        shape: const RoundedRectangleBorder(borderRadius: Radii.medium),
      ),
    );
  }
}
