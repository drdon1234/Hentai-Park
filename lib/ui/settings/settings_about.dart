import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/app_log.dart';
import '../../core/crash_log.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/storage.dart';
import '../../engine/source_manager.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/selectable_log_view.dart';
import 'update_settings.dart';

// 关于：版本、许可、运行日志。
List<Widget> aboutSettings(BuildContext context) => [
  Padding(
    padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, Gap.s),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HentaiPark', style: ParkText.serif(context.text.headlineSmall)),
        const SizedBox(height: Gap.xs),
        Text(
          tr('可插拔的多站点漫画、图集、视频、小说与游戏客户端。内容来自第三方站点，仅限成年人在合法地区使用。'),
          style: context.text.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  ),
  RowGroup(title: tr('更新'), children: const [UpdateSettings()]),
  RowGroup(
    title: tr('诊断'),
    children: [
      ListRow(
        title: tr('运行日志'),
        subtitle: tr('诊断日志只记录错误代码、网络原因、目标主机和代码位置'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Nav.push(context, const _LogsPage()),
      ),
    ],
  ),
  RowGroup(
    children: [
      ListRow(
        title: tr('开源许可证'),
        subtitle: 'AGPL-3.0-only',
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () =>
            showLicensePage(context: context, applicationName: 'HentaiPark'),
      ),
    ],
  ),
];

class _LogsPage extends StatefulWidget {
  const _LogsPage();

  @override
  State<_LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<_LogsPage> {
  late final Future<String> _report = _build();

  /// The in-app view and the export are the same report.
  static Future<String> _build() async {
    final info = await PackageInfo.fromPlatform();
    final sites = [
      for (final key in AppLog.sites.toList()..sort())
        '$key ${SourceManager.instance.manifest(key)?.version ?? '-'}',
    ];
    return CrashLog.report(
      context: [
        '应用：${info.version}+${info.buildNumber}',
        '应用代理：${AppSettings.instance.proxy.isEmpty ? '未设置' : '已设置'}',
        '日志涉及的站点插件：${sites.isEmpty ? '无' : sites.join('，')}',
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('运行日志')),
      actions: [
        IconButton(
          tooltip: tr('导出诊断日志'),
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () async {
            final file = File(
              p.join(AppPaths.cache.path, 'hentaipark_log.txt'),
            );
            await file.writeAsString(await _report);
            await SharePlus.instance.share(
              ShareParams(files: [XFile(file.path)]),
            );
          },
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, Gap.s),
          child: Text(
            tr(
              '自动记录时间、站点与操作、错误代码、HTTP 状态、网络原因、目标主机、内置错误文案和代码位置。不记录账号、密码、Cookie、Token、请求内容、完整链接或错误中的动态内容。',
            ),
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        const Divider(),
        Expanded(
          child: FutureBuilder<String>(
            future: _report,
            builder: (context, snapshot) => switch (snapshot) {
              AsyncSnapshot(hasData: true, :final data?) => SelectableLogView(
                text: data,
              ),
              AsyncSnapshot(hasError: true) => EmptyState(
                icon: Icons.notes_rounded,
                title: tr('日志读取失败'),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ],
    ),
  );
}
