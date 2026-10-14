import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/crash_log.dart';
import '../../core/localization.dart';
import '../../core/storage.dart';
import '../../engine/js_engine.dart';
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
        subtitle: tr('诊断日志只记录错误类型、传输方式和目标主机'),
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

class _LogsPage extends StatelessWidget {
  const _LogsPage();

  @override
  Widget build(BuildContext context) {
    final logs = JsEngine.instance.logs.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('运行日志')),
        actions: [
          IconButton(
            tooltip: tr('导出诊断日志'),
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () async {
              final text = await CrashLog.report(JsEngine.instance.logs);
              final file = File(
                p.join(AppPaths.cache.path, 'hentaipark_log.txt'),
              );
              await file.writeAsString(text);
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
            padding: const EdgeInsets.fromLTRB(
              Gap.page,
              Gap.s,
              Gap.page,
              Gap.s,
            ),
            child: Text(
              tr(
                '自动记录的字段：错误类型、传输方式、网络原因和目标主机。不记录账号、密码、Cookie、Token、请求内容或完整链接。',
              ),
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: logs.isEmpty
                ? EmptyState(icon: Icons.notes_rounded, title: tr('暂无日志'))
                : SelectableLogView(logs: logs),
          ),
        ],
      ),
    );
  }
}
