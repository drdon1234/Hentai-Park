import 'package:flutter/material.dart';

import '../../core/platform_capabilities.dart';
import '../theme.dart';
import 'tokens.dart';

/// 导航先遵循设备平台，再根据窗口空间调整密度。
class PlatformNavigation extends StatelessWidget {
  const PlatformNavigation({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.wide,
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool wide;

  static bool expandedSidebar(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= 840 &&
        (PlatformCapabilities.desktop || size.shortestSide >= 600);
  }

  static bool usesSidebar(BuildContext context) =>
      PlatformCapabilities.desktop || expandedSidebar(context);

  @override
  Widget build(BuildContext context) {
    if (PlatformCapabilities.desktop) {
      return SizedBox(
        width: wide ? 200 : 64,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: Gap.l),
          children: [
            for (var i = 0; i < destinations.length; i++)
              Tooltip(
                message: destinations[i].tooltip ?? destinations[i].label,
                child: Semantics(
                  selected: i == selectedIndex,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.xs,
                      vertical: Gap.xs,
                    ),
                    child: Material(
                      color: i == selectedIndex
                          ? context.colors.secondaryContainer
                          : Colors.transparent,
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => onSelected(i),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: wide ? Gap.l : Gap.s,
                            ),
                            child: Row(
                              mainAxisAlignment: wide
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.center,
                              children: [
                                IconTheme.merge(
                                  data: IconThemeData(
                                    color: i == selectedIndex
                                        ? context.colors.onSecondaryContainer
                                        : context.colors.onSurfaceVariant,
                                  ),
                                  child: i == selectedIndex
                                      ? destinations[i].selectedIcon ??
                                            destinations[i].icon
                                      : destinations[i].icon,
                                ),
                                if (wide) ...[
                                  const SizedBox(width: Gap.m),
                                  Expanded(
                                    child: SelectionContainer.disabled(
                                      child: Text(destinations[i].label),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (wide) {
      return NavigationRail(
        scrollable: true,
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        labelType: NavigationRailLabelType.all,
        groupAlignment: -.9,
        destinations: [
          for (final destination in destinations)
            NavigationRailDestination(
              icon: destination.icon,
              selectedIcon: destination.selectedIcon,
              label: SelectionContainer.disabled(
                child: Text(destination.label),
              ),
            ),
        ],
      );
    }
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: destinations,
    );
  }
}
