import 'package:flutter/material.dart';

import '../core/localization.dart';
import '../core/models.dart';
import '../core/settings.dart';
import 'kit/tokens.dart';

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

/// 从任意页面回到根发现页的某个分类；页面状态由 Shell 持有，不重复堆叠首页。
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

class DiscoveryDomainBar extends StatelessWidget {
  const DiscoveryDomainBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final DiscoveryDestination selected;
  final ValueChanged<DiscoveryDestination> onSelected;

  @override
  // Start-aligned so a row that fits on a wide screen lines up with the page content.
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.s),
      child: Row(
        children: [
          for (final destination in discoveryDestinations)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Gap.s),
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
            duration: Motion.of(context, Motion.medium),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(widget.destination.label),
    selected: widget.selected,
    showCheckmark: false,
    onSelected: (_) => widget.onSelected(widget.destination),
  );
}
