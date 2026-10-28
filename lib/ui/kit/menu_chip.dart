import 'package:flutter/material.dart';

import '../../core/platform_capabilities.dart';

import '../theme.dart';
import 'selection_menu.dart';
import 'tokens.dart';

/// A capsule that opens a menu of [options] (value → label). Used for scope filters above lists:
/// an active filter takes the accent tint so a narrowed list is visible at a glance.
class MenuChip<T> extends StatelessWidget {
  const MenuChip({
    super.key,
    required this.label,
    required this.options,
    required this.onSelected,
    this.active = false,
    this.selected,
    this.maxWidth = 240,
  });
  final String label;
  final Map<T, String> options;
  final ValueChanged<T> onSelected;
  final bool active;

  /// The option selected in the menu, when one is.
  final T? selected;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = active ? c.onSecondaryContainer : c.onSurface;
    // Indexes rather than values: a null value would read as a cancelled menu.
    final entries = options.entries.toList();
    return PopupMenuButton<int>(
      popUpAnimationStyle: Motion.menu(context),
      tooltip: label,
      position: PopupMenuPosition.under,
      onSelected: (i) => onSelected(entries[i].key),
      itemBuilder: (_) => [
        for (var i = 0; i < entries.length; i++)
          SelectionPopupMenuItem(
            value: i,
            selected: entries[i].key == selected,
            child: SelectionContainer.disabled(child: Text(entries[i].value)),
          ),
      ],
      child: SelectionContainer.disabled(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 48, maxWidth: maxWidth),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.short),
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsetsDirectional.only(
                start: Gap.m + 2,
                end: Gap.s,
              ),
              decoration: ShapeDecoration(
                color: active
                    ? c.secondaryContainer
                    : Theme.of(context).chipTheme.backgroundColor,
                shape: PlatformCapabilities.desktop
                    ? const RoundedRectangleBorder(borderRadius: Radii.tiny)
                    : const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelLarge?.copyWith(
                        color: fg,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down_rounded, size: 22, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
