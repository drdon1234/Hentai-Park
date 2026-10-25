import 'package:flutter/material.dart';

import '../theme.dart';
import 'tokens.dart';

/// The selected option in a choice menu is shown with the app's accent tint.
class SelectionMenuOption extends StatelessWidget {
  const SelectionMenuOption({
    super.key,
    required this.selected,
    required this.child,
  });

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurface;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsets.symmetric(horizontal: Gap.m),
      decoration: BoxDecoration(
        color: selected ? colors.secondaryContainer : null,
        borderRadius: Radii.small,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: IconTheme.merge(
          data: IconThemeData(color: foreground),
          child: Semantics(selected: selected, child: child),
        ),
      ),
    );
  }
}

/// A native dropdown option with the same selected foreground treatment.
class SelectionDropdownItem<T> extends DropdownMenuItem<T> {
  const SelectionDropdownItem({
    super.key,
    required super.value,
    required this.selected,
    required super.child,
    super.enabled = true,
  });

  final bool selected;
}

/// Popup-menu choice without a checkmark or a reserved leading icon slot.
class SelectionPopupMenuItem<T> extends PopupMenuItem<T> {
  const SelectionPopupMenuItem({
    super.key,
    super.value,
    required this.selected,
    required super.child,
    super.enabled,
    super.onTap,
  }) : super(height: 48, padding: EdgeInsets.zero);

  final bool selected;

  @override
  PopupMenuItemState<T, SelectionPopupMenuItem<T>> createState() =>
      _SelectionPopupMenuItemState<T>();
}

class _SelectionPopupMenuItemState<T>
    extends PopupMenuItemState<T, SelectionPopupMenuItem<T>> {
  @override
  Widget? buildChild() =>
      SelectionMenuOption(selected: widget.selected, child: widget.child!);
}

/// Gives Flutter's native dropdowns the same accent-colored selected row.
class SelectionDropdownTheme extends StatelessWidget {
  const SelectionDropdownTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        focusColor: theme.colorScheme.secondaryContainer,
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          focusColor: theme.inputDecorationTheme.focusColor ?? theme.focusColor,
        ),
      ),
      child: child,
    );
  }
}
