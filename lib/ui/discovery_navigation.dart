import 'package:flutter/material.dart';

import '../core/localization.dart';
import '../core/models.dart';
import '../core/platform_capabilities.dart';
import '../core/settings.dart';
import 'kit/components.dart';
import 'kit/tokens.dart';
import 'theme.dart';

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
    if (AppSettings.instance.homeIncludes(domain))
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

/// 主页与全部站点共用的分类域入口。
class DomainEntryButton extends StatelessWidget {
  const DomainEntryButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.primary,
      minimumSize: const Size(48, 40),
      padding: EdgeInsets.zero,
      textStyle: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontWeight: FontWeight.w400),
    ),
    onPressed: onPressed,
    child: SelectionContainer.disabled(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('进入域')),
          const SizedBox(width: Gap.xs),
          const SizedBox(
            width: 24,
            height: 40,
            child: Center(child: Icon(Icons.chevron_right_rounded, size: 18)),
          ),
        ],
      ),
    ),
  );
}

/// 总览中的横向域卡片；订阅始终位于首位，不受内容筛选影响。
class DiscoveryDomainCards extends StatelessWidget {
  const DiscoveryDomainCards({super.key, required this.onSelected});

  final ValueChanged<DiscoveryDestination> onSelected;

  static IconData _icon(SourceCategory? category) => switch (category) {
    SourceCategory.doujin => Icons.menu_book_outlined,
    SourceCategory.anime => Icons.movie_outlined,
    SourceCategory.aiDrama => Icons.auto_awesome_outlined,
    SourceCategory.jav => Icons.video_library_outlined,
    SourceCategory.adult => Icons.smart_display_outlined,
    SourceCategory.shortvideo => Icons.video_collection_outlined,
    SourceCategory.recording => Icons.videocam_outlined,
    SourceCategory.gallery => Icons.photo_camera_outlined,
    SourceCategory.illustration => Icons.palette_outlined,
    SourceCategory.game => Icons.sports_esports_outlined,
    SourceCategory.other => Icons.forum_outlined,
    SourceCategory.live => Icons.sensors_outlined,
    SourceCategory.novel => Icons.auto_stories_outlined,
    null => Icons.subscriptions_outlined,
  };

  @override
  Widget build(BuildContext context) {
    if (PlatformCapabilities.desktop) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.page),
        child: Wrap(
          spacing: Gap.s,
          runSpacing: Gap.s,
          children: [
            for (final destination in [
              const DiscoveryDestination.subscriptions(),
              ...discoveryDestinations.where((entry) => entry.category != null),
            ])
              OutlinedButton.icon(
                onPressed: () => onSelected(destination),
                icon: Icon(_icon(destination.category), size: 18),
                label: Text(destination.label),
              ),
          ],
        ),
      );
    }
    return PageGutter(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: Gap.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final destination in [
              const DiscoveryDestination.subscriptions(),
              ...discoveryDestinations.where((entry) => entry.category != null),
            ])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Gap.s),
                child: Semantics(
                  button: true,
                  child: Material(
                    color: Theme.of(context).cardColor,
                    borderRadius: Radii.medium,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onSelected(destination),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gap.l,
                          vertical: Gap.m,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _icon(destination.category),
                              color: destination.subscription
                                  ? context.colors.primary
                                  : context.colors.onSurfaceVariant,
                            ),
                            const SizedBox(height: Gap.s),
                            SelectionContainer.disabled(
                              child: Text(
                                destination.label,
                                style: context.text.labelLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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

  @override
  // Start-aligned so a row that fits on a wide screen lines up with the page content.
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: PageGutter(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: Gap.s),
        child: Row(
          children: [
            for (final destination in discoveryDestinations) ...[
              if (destination.subscription)
                const SizedBox(
                  height: Gap.xl,
                  child: VerticalDivider(width: Gap.l),
                ),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Gap.s),
                child: _DomainChip(
                  destination: destination,
                  selected: selected == destination,
                  onSelected: onSelected,
                ),
              ),
            ],
          ],
        ),
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
  void initState() {
    super.initState();
    if (widget.selected) _reveal();
  }

  @override
  void didUpdateWidget(_DomainChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _reveal();
  }

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      Scrollable.ensureVisible(
        context,
        alignment: .5,
        duration: Motion.of(context, Motion.medium),
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    if (widget.destination.subscription) {
      final colors = Theme.of(context).colorScheme;
      return Semantics(
        selected: widget.selected,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.selected
                ? colors.onSecondaryContainer
                : colors.onSurface,
            backgroundColor: widget.selected ? colors.secondaryContainer : null,
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.padded,
            padding: const EdgeInsets.symmetric(horizontal: Gap.m),
          ),
          onPressed: () => widget.onSelected(widget.destination),
          icon: const Icon(Icons.subscriptions_outlined),
          label: SelectionContainer.disabled(
            child: Text(widget.destination.label),
          ),
        ),
      );
    }
    return ChoiceChip(
      label: SelectionContainer.disabled(child: Text(widget.destination.label)),
      selected: widget.selected,
      showCheckmark: false,
      onSelected: (_) => widget.onSelected(widget.destination),
    );
  }
}
