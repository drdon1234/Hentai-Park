import 'package:flutter/cupertino.dart';
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
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        start: BorderSide(
                          width: 3,
                          color: i == selectedIndex
                              ? context.colors.primary
                              : context.colors.surface,
                        ),
                      ),
                    ),
                    child: ListTile(
                      selected: i == selectedIndex,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: wide ? Gap.l : Gap.m,
                      ),
                      minLeadingWidth: 24,
                      horizontalTitleGap: wide ? Gap.m : 0,
                      leading: i == selectedIndex
                          ? destinations[i].selectedIcon ?? destinations[i].icon
                          : destinations[i].icon,
                      title: wide
                          ? SelectionContainer.disabled(
                              child: Text(destinations[i].label),
                            )
                          : null,
                      onTap: () => onSelected(i),
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
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return CupertinoTabBar(
        currentIndex: selectedIndex,
        onTap: onSelected,
        backgroundColor: context.colors.surface,
        activeColor: context.colors.primary,
        inactiveColor: context.colors.onSurfaceVariant,
        items: [
          for (final destination in destinations)
            BottomNavigationBarItem(
              icon: destination.icon,
              activeIcon: destination.selectedIcon,
              label: destination.label,
              tooltip: destination.tooltip ?? destination.label,
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
