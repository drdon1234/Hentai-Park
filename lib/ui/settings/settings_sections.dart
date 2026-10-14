import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../kit/kit.dart';
import 'backup_page.dart';
import 'blocklist_page.dart';
import 'settings_about.dart';
import 'settings_appearance.dart';
import 'settings_connection.dart';
import 'settings_reading.dart';
import 'source_manage_page.dart';
import 'storage_page.dart';

enum SettingsSection {
  appearance(Icons.palette_outlined),
  reading(Icons.auto_stories_outlined),
  shelf(Icons.collections_bookmark_outlined),
  search(Icons.translate_rounded),
  network(Icons.public_rounded),
  privacy(Icons.lock_outline_rounded),
  subscriptions(Icons.notifications_none_rounded),
  filter(Icons.block_rounded),
  sites(Icons.extension_outlined),
  storage(Icons.pie_chart_outline_rounded),
  backup(Icons.settings_backup_restore_rounded),
  about(Icons.info_outline_rounded);

  const SettingsSection(this.icon);
  final IconData icon;

  /// Settings shown in this section; the page rebuilds only when they change.
  List<SettingsDomain> get domains => switch (this) {
    SettingsSection.appearance => const [SettingsDomain.appearance],
    SettingsSection.reading => const [SettingsDomain.reader],
    SettingsSection.shelf => const [
      SettingsDomain.library,
      SettingsDomain.network,
    ],
    SettingsSection.search => const [SettingsDomain.search],
    SettingsSection.network => const [SettingsDomain.network],
    SettingsSection.privacy => const [SettingsDomain.privacy],
    SettingsSection.subscriptions => const [SettingsDomain.subscriptions],
    SettingsSection.filter => const [SettingsDomain.filter],
    SettingsSection.sites ||
    SettingsSection.storage ||
    SettingsSection.backup ||
    SettingsSection.about => const [],
  };

  String get title => switch (this) {
    SettingsSection.appearance => tr('外观'),
    SettingsSection.reading => tr('阅读'),
    SettingsSection.shelf => tr('书架与下载'),
    SettingsSection.search => tr('搜索与翻译'),
    SettingsSection.network => tr('网络'),
    SettingsSection.privacy => tr('隐私与安全'),
    SettingsSection.subscriptions => tr('订阅与通知'),
    SettingsSection.filter => tr('内容过滤'),
    SettingsSection.sites => tr('站点'),
    SettingsSection.storage => tr('存储'),
    SettingsSection.backup => tr('备份'),
    SettingsSection.about => tr('关于'),
  };
}

/// One settings section. Sections with a dedicated page (sites, filter, storage, backup) open
/// it directly; the others are short lists built here.
class SettingsSectionPage extends StatelessWidget {
  const SettingsSectionPage(this.section, {super.key});
  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    switch (section) {
      case SettingsSection.sites:
        return const SourceManagePage();
      case SettingsSection.filter:
        return const BlocklistPage();
      case SettingsSection.storage:
        return const StoragePage();
      case SettingsSection.backup:
        return const BackupPage();
      case SettingsSection.subscriptions:
      case SettingsSection.appearance:
      case SettingsSection.reading:
      case SettingsSection.shelf:
      case SettingsSection.search:
      case SettingsSection.network:
      case SettingsSection.privacy:
      case SettingsSection.about:
        break;
    }
    final s = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(title: Text(section.title)),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          for (final domain in section.domains) s.domain(domain),
        ]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: Gap.xxl),
          children: switch (section) {
            SettingsSection.appearance => appearanceSettings(context, s),
            SettingsSection.reading => readingSettings(context, s),
            SettingsSection.shelf => shelfSettings(context, s),
            SettingsSection.search => searchSettings(context, s),
            SettingsSection.network => networkSettings(context, s),
            SettingsSection.privacy => privacySettings(context, s),
            SettingsSection.subscriptions => subscriptionSettings(context, s),
            SettingsSection.about => aboutSettings(context),
            _ => const [],
          },
        ),
      ),
    );
  }
}
