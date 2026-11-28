import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// 一侧安全区明显宽于另一侧时（如可折叠 iPhone 外屏右侧的状态区），导航移入该侧；
  /// 返回导航所在一侧的宽度，另一侧为零。两侧对称（横屏刘海）或已用侧边栏时返回零。
  static EdgeInsets insetRail(BuildContext context) {
    if (usesSidebar(context)) return EdgeInsets.zero;
    final padding = MediaQuery.paddingOf(context);
    const minimum = 64.0, asymmetry = 40.0;
    if (padding.right >= minimum && padding.right - padding.left >= asymmetry) {
      return EdgeInsets.only(right: padding.right);
    }
    if (padding.left >= minimum && padding.left - padding.right >= asymmetry) {
      return EdgeInsets.only(left: padding.left);
    }
    return EdgeInsets.zero;
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformCapabilities.desktop) {
      return SizedBox(
        width: wide ? 224 : 56,
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
                      shape: const RoundedRectangleBorder(
                        borderRadius: Radii.tiny,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        borderRadius: Radii.tiny,
                        onTap: () => onSelected(i),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 40),
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

/// 放在侧边安全区里的悬浮胶囊导航，尺寸对齐 iPhone Duo 外屏系统侧边标签栏：
/// 仅图标、48pt 宽、每项 52pt 高，外侧与底边各距屏幕 24pt。
/// 胶囊之外的区域保持透明且不拦截触摸，从其下方滑过的横向内容清晰可见。
class InsetNavigationRail extends StatelessWidget {
  const InsetNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.trailing,
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 导航位于右侧安全区；否则位于左侧。
  final bool trailing;

  static const _inset = 2.0;
  static const _edge = 24.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: trailing ? Alignment.bottomRight : Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: trailing ? 0 : _edge,
          right: trailing ? _edge : 0,
          bottom: _edge,
        ),
        child: Material(
          color: ParkTheme.navigationColor(c),
          elevation: 3,
          shadowColor: c.shadow,
          shape: StadiumBorder(
            side: BorderSide(color: c.outlineVariant, width: .5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(_inset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < destinations.length; i++)
                  _InsetRailItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    onTap: () {
                      if (i != selectedIndex) HapticFeedback.selectionClick();
                      onSelected(i);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InsetRailItem extends StatelessWidget {
  const _InsetRailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = destination.tooltip ?? destination.label;
    // 外屏不显示文字，长按提示与读屏仍给出名称。
    return Tooltip(
      message: label,
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.short),
            width: 44,
            height: 52,
            decoration: ShapeDecoration(
              color: selected ? c.secondaryContainer : Colors.transparent,
              shape: const StadiumBorder(),
            ),
            child: IconTheme.merge(
              data: IconThemeData(
                size: 24,
                color: selected ? c.onSecondaryContainer : c.onSurfaceVariant,
              ),
              child: Center(
                child: selected
                    ? destination.selectedIcon ?? destination.icon
                    : destination.icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
