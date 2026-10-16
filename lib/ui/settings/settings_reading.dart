import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/platform_capabilities.dart';
import '../../core/settings.dart';
import '../../core/storage.dart';
import '../../engine/platform_bridge.dart';
import '../kit/adaptive_sheet.dart';
import '../kit/kit.dart';
import '../library/category_manage_page.dart';
import '../nav.dart';
import '../theme.dart';
import 'settings_rows.dart';

// 阅读，以及书架与下载（更新策略、下载并发与分类管理）。
List<Widget> readingSettings(BuildContext context, AppSettings s) => [
  RowGroup(
    children: [
      ListRow(
        title: tr('默认阅读模式'),
        subtitle: s.readerMode.label,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          final m = await chooseSetting<ReaderMode>(context, tr('默认阅读模式'), {
            for (final m in ReaderMode.values) m: m.label,
          }, s.readerMode);
          if (m != null) s.readerMode = m;
        },
      ),
      SwitchListTile(
        title: SelectionContainer.disabled(child: Text(tr('点击屏幕边缘翻页'))),
        value: s.tapToPage,
        onChanged: (v) => s.tapToPage = v,
      ),
      SwitchListTile(
        title: SelectionContainer.disabled(child: Text(tr('音量键翻页'))),
        value: s.volumeKeyPaging,
        onChanged: (v) => s.volumeKeyPaging = v,
      ),
      SwitchListTile(
        title: SelectionContainer.disabled(child: Text(tr('阅读时保持屏幕常亮'))),
        value: s.keepScreenOn,
        onChanged: (v) => s.keepScreenOn = v,
      ),
    ],
  ),
  RowGroup(
    title: tr('高级'),
    children: [
      SettingsSlider(
        title: tr('预加载页数'),
        value: s.preloadPages,
        min: 0,
        max: 10,
        onChanged: (v) => s.preloadPages = v,
      ),
    ],
  ),
];

List<Widget> shelfSettings(BuildContext context, AppSettings s) => [
  RowGroup(
    title: tr('书架'),
    children: [
      ListRow(
        title: tr('更新策略'),
        subtitle: _updatePolicySummary(s),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _editUpdatePolicy(context),
      ),
      SwitchListTile(
        title: SelectionContainer.disabled(child: Text(tr('收藏时选择分类'))),
        value: s.askCategoryOnFavorite,
        onChanged: (v) => s.askCategoryOnFavorite = v,
      ),
      ListRow(
        title: tr('管理分类'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Nav.push(context, const CategoryManagePage()),
      ),
    ],
  ),
  RowGroup(
    title: tr('下载'),
    children: [
      SwitchListTile(
        title: SelectionContainer.disabled(child: Text(tr('仅在 Wi-Fi 下下载'))),
        subtitle: SelectionContainer.disabled(
          child: Text(tr('使用移动数据时暂停，连上 Wi-Fi 后自动继续')),
        ),
        value: s.downloadWifiOnly,
        onChanged: (v) => s.downloadWifiOnly = v,
      ),
      SwitchListTile(
        title: SelectionContainer.disabled(child: Text(tr('自动下载新章节'))),
        subtitle: SelectionContainer.disabled(
          child: Text(tr('书库更新发现新章节后自动加入下载队列')),
        ),
        value: s.autoDownloadNew,
        onChanged: (v) => s.autoDownloadNew = v,
      ),
      SwitchListTile(
        title: SelectionContainer.disabled(child: Text(tr('读完后删除'))),
        subtitle: SelectionContainer.disabled(
          child: Text(tr('章节被标记为已读后删除它的下载（本地导入的作品除外）')),
        ),
        value: s.deleteAfterRead,
        onChanged: (v) => s.deleteAfterRead = v,
      ),
      ListRow(
        title: tr('下载位置'),
        subtitle: AppPaths.downloadRoot.path,
        subtitleMaxLines: 3,
        trailing: PlatformCapabilities.desktop
            ? const Icon(Icons.folder_open_rounded)
            : null,
        onTap: !PlatformCapabilities.desktop
            ? null
            : () async {
                try {
                  final path = await FilePicker.getDirectoryPath();
                  if (path == null) return;
                  await AppPaths.selectDownloadDirectory(path);
                  s.downloadDirectory = path;
                } catch (_) {
                  if (context.mounted) context.toast(tr('无法保存到所选目录'));
                }
              },
      ),
    ],
  ),
];

String _updatePolicySummary(AppSettings s) {
  if (s.libraryUpdateHours == 0) return tr('不自动检查');
  return [
    _intervals[s.libraryUpdateHours] ??
        tr('每 {hours} 小时', {'hours': s.libraryUpdateHours}),
    if (s.updateOnlyMultiChapter) tr('只查多章节'),
    if (s.updateSkipUnread) tr('跳过有未读'),
    if (s.updateSkipNotStarted) tr('跳过未开始'),
  ].join(' · ');
}

Map<int, String> get _intervals => {
  0: tr('关闭'),
  6: tr('6 小时'),
  12: tr('12 小时'),
  24: tr('每天'),
  48: tr('2 天'),
  168: tr('每周'),
};

/// The four update options in one place: how often, and which favorites to skip.
Future<void> _editUpdatePolicy(BuildContext context) => showAdaptiveSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => ListenableBuilder(
    listenable: AppSettings.instance.domain(SettingsDomain.library),
    builder: (ctx, _) {
      final s = AppSettings.instance;
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.page,
                  0,
                  Gap.page,
                  Gap.s,
                ),
                child: Text(tr('更新策略'), style: ctx.text.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                child: Text(
                  tr('打开应用或回到前台时，如果已到间隔就检查收藏的新章节'),
                  style: ctx.text.bodyMedium?.copyWith(
                    color: ctx.colors.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Gap.page),
                child: Wrap(
                  spacing: Gap.s,
                  runSpacing: Gap.s,
                  children: [
                    for (final e in _intervals.entries)
                      ChoiceChip(
                        label: SelectionContainer.disabled(
                          child: Text(e.value),
                        ),
                        selected: s.libraryUpdateHours == e.key,
                        showCheckmark: false,
                        onSelected: (_) {
                          s.libraryUpdateHours = e.key;
                          if (e.key > 0) {
                            PlatformBridge.requestNotificationPermission();
                          }
                        },
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                title: SelectionContainer.disabled(child: Text(tr('只检查多章节作品'))),
                subtitle: SelectionContainer.disabled(
                  child: Text(tr('单本画廊不会出新章节，跳过可以省去大部分请求')),
                ),
                value: s.updateOnlyMultiChapter,
                onChanged: s.libraryUpdateHours == 0
                    ? null
                    : (v) => s.updateOnlyMultiChapter = v,
              ),
              SwitchListTile(
                title: SelectionContainer.disabled(
                  child: Text(tr('跳过有未读章节的作品')),
                ),
                value: s.updateSkipUnread,
                onChanged: s.libraryUpdateHours == 0
                    ? null
                    : (v) => s.updateSkipUnread = v,
              ),
              SwitchListTile(
                title: SelectionContainer.disabled(
                  child: Text(tr('跳过还没开始读的作品')),
                ),
                value: s.updateSkipNotStarted,
                onChanged: s.libraryUpdateHours == 0
                    ? null
                    : (v) => s.updateSkipNotStarted = v,
              ),
              const SizedBox(height: Gap.s),
            ],
          ),
        ),
      );
    },
  ),
);

// ── 搜索与翻译 ──
