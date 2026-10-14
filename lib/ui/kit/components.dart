import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../theme.dart';
import 'tokens.dart';

/// Top-level page bar: a serif title (or [HeaderTabs]) and its actions.
class PageHeader extends StatelessWidget implements PreferredSizeWidget {
  const PageHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.actions = const [],
    this.bottom,
  });
  final String? title;
  final Widget? titleWidget;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  static const double height = 64;

  @override
  Size get preferredSize =>
      Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: height,
    titleSpacing: Gap.page,
    title:
        titleWidget ??
        Text(
          title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ParkText.serif(context.text.headlineSmall),
        ),
    actions: [
      ...actions,
      const SizedBox(width: Gap.xs),
    ],
    bottom: bottom,
  );
}

/// One header tab: a label with an optional unread count.
class HeaderTab {
  const HeaderTab(this.label, {this.count = 0});
  final String label;
  final int count;
}

/// Serif text tabs used as a page title, such as 收藏 · 更新 · 下载 on the shelf.
class HeaderTabs extends StatelessWidget {
  const HeaderTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });
  final List<HeaderTab> tabs;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = ParkText.serif(context.text.headlineSmall);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Semantics(
              selected: i == selected,
              button: true,
              label: tabs[i].count > 0
                  ? tr('{label}，{count} 项未读', {
                      'label': tabs[i].label,
                      'count': tabs[i].count,
                    })
                  : tabs[i].label,
              onTap: () => onSelected(i),
              excludeSemantics: true,
              child: InkWell(
                borderRadius: Radii.small,
                onTap: () {
                  if (i != selected) HapticFeedback.selectionClick();
                  onSelected(i);
                },
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: i == 0 ? 0 : Gap.s,
                    end: Gap.m,
                    top: Gap.xs,
                    bottom: Gap.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: Motion.of(context, Motion.short),
                        style: style!.copyWith(
                          color: i == selected ? c.onSurface : c.outline,
                        ),
                        child: Text(tabs[i].label),
                      ),
                      if (tabs[i].count > 0)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 2),
                          child: Text(
                            '${tabs[i].count}',
                            style: context.text.labelSmall?.copyWith(
                              color: c.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Section title inside a page, with an optional trailing action such as 全部.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.leading,
    this.padding = const EdgeInsets.fromLTRB(Gap.page, Gap.xl, Gap.s, Gap.s),
  });
  final String title;
  final Widget? trailing;
  final Widget? leading;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: Gap.s)],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: context.text.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A row in a hairline-separated list: settings, sites, chapters, downloads.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 2,
    this.padding = const EdgeInsets.symmetric(
      horizontal: Gap.page,
      vertical: Gap.m,
    ),
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool enabled;
  final int titleMaxLines;
  final int subtitleMaxLines;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = enabled ? c.onSurface : c.onSurface.withValues(alpha: .38);
    return Material(
      color: selected ? c.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: padding,
            child: Row(
              children: [
                if (leading != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(color: c.onSurfaceVariant, size: 22),
                    child: leading!,
                  ),
                  const SizedBox(width: Gap.l),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: titleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyLarge?.copyWith(color: fg),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: subtitleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(
                            color: c.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: Gap.m),
                  IconTheme.merge(
                    data: IconThemeData(color: c.onSurfaceVariant),
                    child: DefaultTextStyle.merge(
                      style: context.text.bodyMedium?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                      child: trailing!,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows separated by hairlines, with an optional small heading.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Gap.page,
            Gap.xl,
            Gap.page,
            Gap.xs,
          ),
          child: Semantics(
            header: true,
            child: Text(
              title!,
              style: context.text.labelLarge?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const Divider(indent: Gap.page, endIndent: Gap.page),
        children[i],
      ],
    ],
  );
}

/// A row in a reorderable list: keyed, with a hairline below instead of a group divider.
class HairlineItem extends StatelessWidget {
  const HairlineItem({required super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surface,
      border: Border(
        bottom: BorderSide(color: context.colors.outlineVariant, width: .8),
      ),
    ),
    child: child,
  );
}

/// Empty and blocked states: a quiet icon, one sentence, and what to do next.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actions = const [],
    this.compact = false,
  });
  final IconData icon;
  final String title;
  final String? message;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? Gap.m : Gap.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 24 : 32, color: c.outline),
              SizedBox(height: compact ? Gap.s : Gap.m),
              Text(
                title,
                style: compact
                    ? context.text.titleSmall
                    : context.text.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (message != null && message!.isNotEmpty) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  message!,
                  style: context.text.bodyMedium?.copyWith(
                    color: c.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: compact ? 3 : 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (actions.isNotEmpty) ...[
                SizedBox(height: compact ? Gap.s : Gap.l),
                Wrap(
                  spacing: Gap.s,
                  runSpacing: Gap.s,
                  alignment: WrapAlignment.center,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small metadata label. On covers it sits on a scrim; elsewhere it is a hairline outline.
class Tag extends StatelessWidget {
  const Tag(
    this.label, {
    super.key,
    this.icon,
    this.onImage = false,
    this.accent = false,
  });
  final String label;
  final IconData? icon;

  /// Drawn on top of a cover.
  final bool onImage;

  /// Unread counts and similar signals use the accent.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color fg;
    final Color? bg;
    BoxBorder? border;
    if (accent) {
      fg = c.onPrimary;
      bg = c.primary;
    } else if (onImage) {
      fg = Scrims.onScrim;
      bg = Scrims.strong;
    } else {
      fg = c.onSurfaceVariant;
      bg = null;
      border = Border.all(color: c.outlineVariant);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        border: border,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            if (label.isNotEmpty) const SizedBox(width: 2),
          ],
          if (label.isNotEmpty)
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Asks before an action that cannot be undone or that acts on the user's behalf.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content:
          content ??
          (message == null ? null : Text(message, style: ctx.text.bodyMedium)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel ?? tr('取消')),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: ctx.colors.error,
                  foregroundColor: ctx.colors.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// A bottom sheet that picks one of [options]; the current one is checked. Returns null when
/// dismissed.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T? selected,
  required String Function(T option) label,
}) => showModalBottomSheet<T>(
  context: context,
  sheetAnimationStyle: Motion.menu(context),
  isScrollControlled: true,
  builder: (ctx) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * .7,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Gap.s),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Gap.page,
              Gap.s,
              Gap.page,
              Gap.xs,
            ),
            child: Text(title, style: ctx.text.titleMedium),
          ),
          for (final option in options)
            ListTile(
              title: Text(label(option)),
              selected: option == selected,
              trailing: option == selected
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(ctx, option),
            ),
        ],
      ),
    ),
  ),
);

/// The search field shared by the home page and search pages. Read-only fields act as an entry
/// point that opens the search page.
class ParkSearchField extends StatelessWidget {
  const ParkSearchField({
    super.key,
    this.controller,
    this.focusNode,
    required this.hint,
    this.onTap,
    this.onSubmitted,
    this.onChanged,
    this.trailing = const [],
    this.autofocus = false,
  });
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final VoidCallback? onTap;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final List<Widget> trailing;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final readOnly = onTap != null;
    return Semantics(
      button: readOnly,
      textField: !readOnly,
      label: hint,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        readOnly: readOnly,
        onTap: onTap,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: context.text.bodyLarge,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          prefixIcon: Icon(Icons.search_rounded, color: c.onSurfaceVariant),
          suffixIcon: trailing.isEmpty
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: trailing),
        ),
      ),
    );
  }
}

/// Pull to refresh, with a light tap when the refresh starts.
class ParkRefresh extends StatelessWidget {
  const ParkRefresh({super.key, required this.onRefresh, required this.child});
  final RefreshCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () {
      HapticFeedback.mediumImpact();
      return onRefresh();
    },
    child: child,
  );
}
