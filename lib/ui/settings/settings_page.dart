import 'package:flutter/material.dart';

import '../../core/app_lock.dart';
import '../../core/localization.dart';
import '../../core/platform_capabilities.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/source_manager.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import 'settings_sections.dart';

/// 我的: incognito at hand, then one entry per settings section. Each section is its own page
/// so no screen carries more than a handful of choices.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsSection _selected = SettingsSection.appearance;

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.desktop) return _index(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth < 780 * scale) return _index(context);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 240,
              child: Material(
                color: context.colors.surface,
                child: ListView(
                  padding: const EdgeInsets.all(Gap.m),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(Gap.s),
                      child: Text(tr('我的'), style: context.text.titleLarge),
                    ),
                    for (final group in _groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Gap.s,
                          Gap.l,
                          Gap.s,
                          Gap.s,
                        ),
                        child: Text(
                          group.$1,
                          style: context.text.labelMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      for (final section in group.$2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Gap.xs),
                          child: ListTile(
                            dense: true,
                            selected: _selected == section,
                            selectedTileColor:
                                context.colors.secondaryContainer,
                            selectedColor: context.colors.onSecondaryContainer,
                            shape: const RoundedRectangleBorder(
                              borderRadius: Radii.tiny,
                            ),
                            leading: Icon(section.icon),
                            title: Text(section.title),
                            onTap: () => setState(() => _selected = section),
                          ),
                        ),
                    ],
                    const Divider(),
                    ListenableBuilder(
                      listenable: AppSettings.instance.watch(const {
                        'incognito',
                      }),
                      builder: (context, _) => SwitchListTile.adaptive(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: Gap.s,
                        ),
                        title: Text(tr('无痕模式')),
                        value: AppSettings.instance.incognito,
                        onChanged: (value) =>
                            AppSettings.instance.incognito = value,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: RepaintBoundary(
                child: KeyedSubtree(
                  key: ValueKey(_selected),
                  child: SettingsSectionPage(_selected),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _index(BuildContext context) {
    final s = AppSettings.instance;
    return Scaffold(
      appBar: PageHeader(title: tr('我的')),
      body: ListenableBuilder(
        // Everything the index summarises; search history writes do not rebuild it.
        listenable: Listenable.merge([
          for (final domain in SettingsDomain.values)
            if (domain != SettingsDomain.search) s.domain(domain),
          SourceManager.instance,
        ]),
        builder: (context, _) => SettingsBody(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Gap.xxl),
            children: [
              RowGroup(
                children: [
                  SwitchListTile.adaptive(
                    secondary: const Icon(Icons.visibility_off_outlined),
                    title: SelectionContainer.disabled(child: Text(tr('无痕模式'))),
                    subtitle: SelectionContainer.disabled(
                      child: Text(tr('暂停记录历史、阅读进度与已读状态')),
                    ),
                    value: s.incognito,
                    onChanged: (v) => s.incognito = v,
                  ),
                ],
              ),
              for (final group in _groups)
                RowGroup(
                  title: group.$1,
                  children: [
                    for (final section in group.$2)
                      ListRow(
                        leading: _SectionIcon(section.icon),
                        title: section.title,
                        titleMaxLines: null,
                        subtitle: section.summary(),
                        subtitleMaxLines: 1,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () =>
                            Nav.push(context, SettingsSectionPage(section)),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static List<(String, List<SettingsSection>)> get _groups => [
    (
      tr('使用'),
      const [
        SettingsSection.appearance,
        SettingsSection.reading,
        SettingsSection.shortVideo,
        SettingsSection.shelf,
        SettingsSection.search,
      ],
    ),
    (
      tr('连接与隐私'),
      const [
        SettingsSection.network,
        SettingsSection.privacy,
        SettingsSection.subscriptions,
        SettingsSection.filter,
      ],
    ),
    (
      tr('数据'),
      const [
        SettingsSection.sites,
        SettingsSection.storage,
        SettingsSection.backup,
        SettingsSection.about,
      ],
    ),
  ];
}

extension SettingsSectionSummary on SettingsSection {
  /// One line telling what is set now, so most visits end at the index.
  String summary() {
    final s = AppSettings.instance;
    return switch (this) {
      SettingsSection.appearance => [
        switch (s.themeMode) {
          ThemeMode.system => tr('跟随系统'),
          ThemeMode.light => tr('浅色'),
          ThemeMode.dark => tr('深色'),
        },
        AppLocalizations.languageNames[s.language] ?? tr('跟随系统'),
      ].join(' · '),
      SettingsSection.reading => s.readerMode.label,
      SettingsSection.shortVideo => tr('预加载 {preload} 条，保留已看 {retained} 条', {
        'preload': s.shortVideoPreloadCount,
        'retained': s.shortVideoRetainedCount,
      }),
      SettingsSection.shelf =>
        s.libraryUpdateHours == 0
            ? tr('不自动检查更新')
            : tr('每 {hours} 小时检查更新', {'hours': s.libraryUpdateHours}),
      SettingsSection.search => tr('多语言搜索、内容翻译'),
      SettingsSection.network =>
        s.proxy.isEmpty ? tr('未设置代理') : tr('代理 {proxy}', {'proxy': s.proxy}),
      SettingsSection.privacy => [
        if (AppLock.platformSupported && s.appLock) tr('应用锁'),
        if (s.blurCovers) tr('模糊封面'),
        if (PlatformCapabilities.secureScreen && s.secureScreen) tr('防截屏'),
      ].join(' · '),
      SettingsSection.subscriptions =>
        s.subscriptionUpdateHours > 0 ? tr('自动检查') : tr('已关闭'),
      SettingsSection.filter => _filterSummary(s),
      SettingsSection.sites => tr('{count} 个站点已启用', {
        'count': SourceManager.instance.enabled.length,
      }),
      SettingsSection.storage => tr('缓存、下载、数据库占用与清理'),
      SettingsSection.backup =>
        s.autoBackupHours == 0 ? tr('自动备份已关闭') : tr('自动备份已开启'),
      SettingsSection.about => tr('版本、更新、许可证与日志'),
    };
  }
}

String _filterSummary(AppSettings settings) {
  final presets = BlockPresetConfig.current()
      .where((preset) => preset.on)
      .length;
  final custom =
      settings.blockedTags.length +
      settings.blockedWorks.length +
      settings.blockedAuthors.length;
  if (presets == 0 && custom == 0) return tr('未屏蔽标签');
  return [
    if (presets > 0) tr('已启用 {count} 组预设', {'count': presets}),
    if (custom > 0) tr('自定义屏蔽 {count} 项', {'count': custom}),
  ].join(' · ');
}

/// A settings section's icon on a small accent-tinted tile, so the index scans by shape first.
class _SectionIcon extends StatelessWidget {
  const _SectionIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: context.colors.secondaryContainer,
      borderRadius: Radii.small,
    ),
    child: Icon(icon, size: 20, color: context.colors.onSecondaryContainer),
  );
}
