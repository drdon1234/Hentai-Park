import 'package:flutter/material.dart';

import '../core/localization.dart';
import '../core/models.dart';
import '../core/settings.dart';

/// 发现入口与媒体分类分开，订阅不会改变源的媒体类型或分类。
class DiscoveryDestination {
  const DiscoveryDestination.all() : category = null, subscription = false;
  const DiscoveryDestination.domain(this.category) : subscription = false;
  const DiscoveryDestination.subscriptions()
    : category = null,
      subscription = true;

  final SourceCategory? category;
  final bool subscription;
  String get label => subscription ? tr('订阅') : category?.label ?? tr('全部');
  String get key => subscription ? 'subscriptions' : category?.name ?? 'all';

  @override
  bool operator ==(Object other) =>
      other is DiscoveryDestination && other.key == key;
  @override
  int get hashCode => key.hashCode;
}

List<DiscoveryDestination> get discoveryDestinations => [
  const DiscoveryDestination.all(),
  for (final domain in AppSettings.instance.domainOrder)
    DiscoveryDestination.domain(domain),
  const DiscoveryDestination.subscriptions(),
];

/// 全局域切换回到根发现页；页面状态由 Shell 持有，不重复堆叠首页。
class DiscoveryNavigation extends InheritedWidget {
  const DiscoveryNavigation({
    super.key,
    required this.onSelect,
    required super.child,
  });
  final ValueChanged<DiscoveryDestination> onSelect;
  static DiscoveryNavigation? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DiscoveryNavigation>();
  @override
  bool updateShouldNotify(DiscoveryNavigation oldWidget) =>
      oldWidget.onSelect != onSelect;
}

class DomainMenu extends StatelessWidget {
  const DomainMenu({super.key, this.onSelected});
  final ValueChanged<DiscoveryDestination>? onSelected;
  @override
  Widget build(BuildContext context) {
    final select = onSelected ?? DiscoveryNavigation.of(context)?.onSelect;
    if (select == null) return const SizedBox.shrink();
    return PopupMenuButton<DiscoveryDestination>(
      tooltip: tr('切换域'),
      icon: const Icon(Icons.dashboard_outlined),
      onSelected: select,
      itemBuilder: (_) => [
        for (final destination in discoveryDestinations)
          PopupMenuItem(value: destination, child: Text(destination.label)),
      ],
    );
  }
}

class DiscoveryDomainBar extends StatelessWidget {
  const DiscoveryDomainBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final DiscoveryDestination selected;
  final ValueChanged<DiscoveryDestination> onSelected;

  static double extent(BuildContext context) =>
      56 +
      (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
        0,
        double.infinity,
      );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: extent(context),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          for (final destination in discoveryDestinations)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _DomainChip(
                destination: destination,
                selected: selected == destination,
                onSelected: onSelected,
              ),
            ),
        ],
      ),
    ),
  );
}

class _DomainChip extends StatefulWidget {
  const _DomainChip({
    required this.destination,
    required this.selected,
    required this.onSelected,
  });
  final DiscoveryDestination destination;
  final bool selected;
  final ValueChanged<DiscoveryDestination> onSelected;
  @override
  State<_DomainChip> createState() => _DomainChipState();
}

class _DomainChipState extends State<_DomainChip> {
  @override
  void didUpdateWidget(_DomainChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: .5,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(widget.destination.label),
    avatar: widget.destination.subscription
        ? const Icon(Icons.subscriptions_outlined, size: 18)
        : null,
    selected: widget.selected,
    showCheckmark: false,
    onSelected: (_) => widget.onSelected(widget.destination),
  );
}
