import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/platform_capabilities.dart';
import '../../core/settings.dart';
import '../../engine/platform_bridge.dart';
import '../kit/adaptive_sheet.dart';
import '../kit/kit.dart';
import '../theme.dart';
import 'settings_rows.dart';

// 外观：主题、强调色、界面语言、发现页分类、每行封面数与刷新率。
List<Widget> appearanceSettings(BuildContext context, AppSettings s) {
  final accents = {
    ...ParkTheme.accents,
    if (!ParkTheme.accents.containsKey(s.seedColor)) s.seedColor: tr('当前'),
  };
  return [
    RowGroup(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.page,
            vertical: Gap.m,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('主题'), style: context.text.bodyLarge),
              const SizedBox(height: Gap.s),
              Wrap(
                spacing: Gap.s,
                runSpacing: Gap.s,
                children: [
                  for (final option in [
                    (ThemeMode.system, tr('跟随')),
                    (ThemeMode.light, tr('浅色')),
                    (ThemeMode.dark, tr('深色')),
                  ])
                    ChoiceChip(
                      label: Text(option.$2),
                      selected: s.themeMode == option.$1,
                      onSelected: (_) => s.themeMode = option.$1,
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.m, Gap.page, Gap.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('强调色'), style: context.text.bodyLarge),
              const SizedBox(height: Gap.xs),
              Text(
                tr('只用在主要操作、进度、未读和选中状态上'),
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Gap.m),
              Wrap(
                spacing: Gap.m,
                runSpacing: Gap.m,
                children: [
                  for (final e in accents.entries)
                    _AccentSwatch(
                      color: ParkTheme.scheme(
                        Theme.of(context).brightness,
                        Color(e.key),
                      ).primary,
                      label: e.value,
                      selected: s.seedColor == e.key,
                      onTap: () => s.seedColor = e.key,
                    ),
                ],
              ),
            ],
          ),
        ),
        ListRow(
          title: tr('界面语言'),
          subtitle: AppLocalizations.languageNames[s.language] ?? tr('跟随系统'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final language = await chooseSetting<String>(context, tr('界面语言'), {
              '': tr('跟随系统'),
              ...AppLocalizations.languageNames,
            }, s.language);
            if (language != null) s.language = language;
          },
        ),
        ListRow(
          title: tr('发现页的分类'),
          subtitle: s.homeCategories.isEmpty
              ? tr('全部分类')
              : s.homeCategories.map((c) => c.label).join('、'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _editHomeCategories(context, s),
        ),
        if (PlatformCapabilities.desktop)
          ListRow(
            title: tr('界面缩放'),
            subtitle:
                '${s.desktopScale}% · Ctrl + / − / 0 · Ctrl + ${tr('滚轮')}',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final value = await chooseSetting<int>(context, tr('界面缩放'), {
                for (final value in {
                  75,
                  90,
                  100,
                  110,
                  125,
                  150,
                  175,
                  200,
                  s.desktopScale,
                }.toList()..sort())
                  value: '$value%',
              }, s.desktopScale);
              if (value != null) s.desktopScale = value;
            },
          ),
        ListRow(
          title: tr('每行封面数'),
          subtitle: s.gridColumns == 0 ? tr('自动') : '${s.gridColumns}',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final v = await chooseSetting<int>(context, tr('每行封面数'), {
              0: tr('自动'),
              2: '2',
              3: '3',
              4: '4',
            }, s.gridColumns);
            if (v != null) s.gridColumns = v;
          },
        ),
      ],
    ),
    if (Platform.isAndroid)
      RowGroup(
        title: tr('高级'),
        children: [
          ListRow(
            title: tr('屏幕刷新率'),
            subtitle: s.refreshRate == 0
                ? tr('自动（跟随屏幕最高刷新率）')
                : '${s.refreshRate} Hz',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickRefreshRate(context, s),
          ),
        ],
      ),
  ];
}

Future<void> _editHomeCategories(BuildContext context, AppSettings s) =>
    showAdaptiveSheet<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: s.watch(const {'homeCategories'}),
        builder: (ctx, _) {
          final chosen = s.homeCategories.isEmpty
              ? AppSettings.defaultDomainOrder.toSet()
              : s.homeCategories.toSet();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.l),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('发现页的分类'), style: ctx.text.titleLarge),
                  const SizedBox(height: Gap.xs),
                  Text(
                    tr('发现页会为这些分类放上书架。所有分类仍可在发现页顶部切换。'),
                    style: ctx.text.bodyMedium?.copyWith(
                      color: ctx.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Gap.l),
                  Wrap(
                    spacing: Gap.s,
                    runSpacing: Gap.s,
                    children: [
                      for (final c in s.domainOrder)
                        FilterChip(
                          label: Text(c.label),
                          selected: chosen.contains(c),
                          onSelected: (on) {
                            final next = {...chosen};
                            on ? next.add(c) : next.remove(c);
                            if (next.isEmpty) return;
                            s.homeCategories =
                                next.length ==
                                    AppSettings.defaultDomainOrder.length
                                ? const []
                                : [
                                    for (final d in s.domainOrder)
                                      if (next.contains(d)) d,
                                  ];
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

Future<void> _pickRefreshRate(BuildContext context, AppSettings s) async {
  final rates = await PlatformBridge.refreshRates();
  if (!context.mounted) return;
  final v = await chooseSetting<int>(context, tr('屏幕刷新率'), {
    0: tr('自动（最高刷新率）'),
    for (final hz in rates) hz: '$hz Hz',
  }, s.refreshRate);
  if (v != null) s.refreshRate = v;
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: Tooltip(
      message: label,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? context.colors.onSurface : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: ParkTheme.scheme(
                    Theme.of(context).brightness,
                    color,
                  ).onPrimary,
                )
              : null,
        ),
      ),
    ),
  );
}
