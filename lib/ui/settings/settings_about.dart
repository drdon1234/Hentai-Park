import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../core/app_log.dart';
import '../../core/crash_log.dart';
import '../../core/diagnostic_entry.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/storage.dart';
import '../../engine/platform_bridge.dart';
import '../../engine/source_manager.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/platform_share.dart';
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
        subtitle: tr('查看应用错误、崩溃堆栈与系统退出信息'),
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
  late LogMode _mode = AppSettings.instance.logMode;
  late Future<String> _report = _build(_mode);

  /// The in-app view and the export are the same report.
  static Future<String> _build(LogMode mode, {bool export = false}) async {
    final info = await PackageInfo.fromPlatform();
    final nativeEntries = await PlatformBridge.readCrashDiagnostics();
    final sites = [
      for (final key in AppLog.sites.toList()..sort())
        '$key ${SourceManager.instance.manifest(key)?.version ?? '-'}',
    ];
    return CrashLog.report(
      export: export,
      mode: mode,
      nativeEntries: nativeEntries,
      context: [
        '应用：${info.version}+${info.buildNumber}',
        '应用代理：${AppSettings.instance.proxy.isEmpty ? '未设置' : '已设置'}',
        '日志涉及的站点插件：${sites.isEmpty ? '无' : sites.join('，')}',
      ],
    );
  }

  static String _label(LogMode mode) => switch (mode) {
    LogMode.full => tr('完整模式（默认）'),
    LogMode.redacted => tr('脱敏模式'),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('运行日志')),
      actions: [
        IconButton(
          tooltip: tr('刷新'),
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => setState(() {
            _report = _build(_mode);
          }),
        ),
        IconButton(
          tooltip: tr('导出诊断日志'),
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () async {
            try {
              final report = _build(_mode, export: true);
              final text = await report;
              final file = File(
                p.join(AppPaths.cache.path, 'hentaipark_log.txt'),
              );
              await file.writeAsString(text);
              if (!context.mounted) return;
              await shareContent(context, files: [XFile(file.path)]);
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(tr('日志导出失败'))));
            }
          },
        ),
      ],
    ),
    body: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: RowGroup(
            children: [
              ListRow(
                title: tr('debug 日志'),
                subtitle: tr(
                  AppLog.debugEnabled
                      ? '已开启，仅本次运行有效'
                      : AppLog.debugNextLaunch
                      ? '将在下次启动时开启'
                      : '记录请求耗时、重试、缓存与播放器状态，不记录私人内容',
                ),
                trailing: Switch(
                  value: AppLog.debugEnabled || AppLog.debugNextLaunch,
                  onChanged: _debugBusy ? null : _toggleDebug,
                ),
                onTap: _debugBusy
                    ? null
                    : () => _toggleDebug(
                        !(AppLog.debugEnabled || AppLog.debugNextLaunch),
                      ),
              ),
              SwitchListTile.adaptive(
                title: Text(tr('长效日志')),
                subtitle: Text(
                  tr('追加保存运行日志，达到 100 MiB 后淘汰最早记录；关闭后立即覆盖历史，仅保留本次运行的最近日志。'),
                ),
                value: AppLog.persistent,
                onChanged: _retentionBusy ? null : _toggleRetention,
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: ListRow(
            title: tr('日志模式'),
            subtitle: _label(_mode),
            trailing: const Icon(Icons.expand_more_rounded),
            onTap: () async {
              final mode = await showChoiceSheet<LogMode>(
                context,
                title: tr('日志模式'),
                options: LogMode.values,
                selected: _mode,
                label: _label,
              );
              if (mode == null || !mounted || mode == _mode) return;
              AppSettings.instance.logMode = mode;
              setState(() {
                _mode = mode;
                _report = _build(mode);
              });
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Gap.page,
              Gap.s,
              Gap.page,
              Gap.s,
            ),
            child: Text(
              tr(
                _mode == LogMode.full
                    ? '仅记录错误代码、网络原因、目标主机和安全代码位置，不记录异常正文、账号信息或本地路径。页面与导出使用相同模式。'
                    : '在安全诊断信息的基础上隐藏目标主机和系统详细版本。页面与导出使用相同模式。',
              ),
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: Divider()),
        SliverFillRemaining(
          child: FutureBuilder<String>(
            key: ValueKey(_report),
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

  bool _retentionBusy = false;
  bool _debugBusy = false;
  Future<void> _toggleRetention(bool value) async {
    setState(() => _retentionBusy = true);
    try {
      await AppLog.setPersistent(value);
      if (mounted) setState(() => _report = _build(_mode));
    } catch (error) {
      AppLog.error(error, event: 'log_settings');
      if (mounted) context.toast(tr('保存失败，请重试'));
    } finally {
      if (mounted) setState(() => _retentionBusy = false);
    }
  }

  Future<void> _toggleDebug(bool value) async {
    if (_debugBusy) return;
    setState(() => _debugBusy = true);
    try {
      if (!value) {
        AppLog.setDebug(false);
        await AppLog.setDebugNextLaunch(false);
      } else {
        final next = await showChoiceSheet<bool>(
          context,
          title: tr('开启 debug 日志'),
          options: const [false, true],
          selected: false,
          label: (next) => tr(next ? '仅下次开启' : '仅本次开启'),
        );
        if (next == null || !mounted) return;
        await AppLog.setDebugNextLaunch(next);
        if (!next) AppLog.setDebug(true);
      }
      if (mounted) setState(() => _report = _build(_mode));
    } catch (error) {
      AppLog.error(error, event: 'log_settings');
      if (mounted) context.toast(tr('保存失败，请重试'));
    } finally {
      if (mounted) setState(() => _debugBusy = false);
    }
  }
}
