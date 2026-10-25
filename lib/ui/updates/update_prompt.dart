import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/versions.dart';
import '../../engine/app_installer.dart';
import '../../engine/app_updater.dart';
import '../../engine/source_updater.dart';
import '../kit/reminder_prompt.dart';
import '../kit/tokens.dart';
import '../theme.dart';

class _UpdateSection extends StatelessWidget {
  const _UpdateSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: context.text.titleSmall),
      if (children.isNotEmpty) ...[
        const SizedBox(height: Gap.s),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: Gap.l),
          children[i],
        ],
      ],
    ],
  );
}

class _UpdateItem extends StatelessWidget {
  const _UpdateItem({
    required this.name,
    required this.currentVersion,
    required this.latestVersion,
  });
  final String name;
  final String currentVersion;
  final String latestVersion;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: context.text.bodyLarge),
      const SizedBox(height: Gap.xs),
      Wrap(
        spacing: Gap.s,
        runSpacing: Gap.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'v$currentVersion',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          ExcludeSemantics(
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: context.colors.onSurfaceVariant,
            ),
          ),
          Text(
            'v$latestVersion',
            style: context.text.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ],
  );
}

/// 只展示可确认的操作；检查本身不会触发下载或安装。
Future<void> showAppUpdatePrompt(
  BuildContext context,
  AppUpdateResult result, {
  Future<bool> Function(Uri)? openRelease,
  AppInstaller? installer,
}) async {
  final release = result.release;
  if (release == null || !context.mounted) return;
  final service = installer ?? AppInstaller();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => ReminderPromptDialog(
      icon: Icons.system_update_alt_rounded,
      title: tr('发现软件新版本'),
      primaryLabel: tr(service.supported ? '下载并安装' : '前往下载'),
      onIgnore: () async {
        final settings = AppSettings.instance;
        settings.ignoredAppUpdate = release.version;
        await settings.flush();
      },
      children: [
        _UpdateItem(
          name: 'HentaiPark',
          currentVersion: result.currentVersion ?? '',
          latestVersion: release.version,
        ),
        const SizedBox(height: Gap.l),
        Text(
          tr(
            service.supported
                ? '确认后在应用内下载安装包，再由系统提示你确认安装。'
                : '此平台请前往官方发布页下载并手动安装。',
          ),
          style: ctx.text.bodyMedium?.copyWith(
            color: ctx.colors.onSurfaceVariant,
          ),
        ),
        for (final line in release.notesFor(
          chinese: AppLocalizations.of(ctx).locale.languageCode == 'zh',
        ))
          _ReleaseNote(line),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  if (service.supported) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AppDownloadDialog(
        release: release,
        installer: service,
        openRelease: openRelease ?? _openRelease,
      ),
    );
    return;
  }
  var opened = false;
  try {
    opened = await (openRelease ?? _openRelease)(release.url);
  } catch (_) {}
  if (!opened && context.mounted) {
    _message(context, tr('无法打开下载页面，请稍后重试'));
  }
}

/// One line of the release notes: section headings, list items and plain text.
class _ReleaseNote extends StatelessWidget {
  const _ReleaseNote(this.line);
  final ReleaseNoteLine line;

  @override
  Widget build(BuildContext context) => switch (line.kind) {
    ReleaseNoteKind.heading => Padding(
      padding: const EdgeInsets.only(top: Gap.l, bottom: Gap.xs),
      child: Text(line.text, style: context.text.titleSmall),
    ),
    ReleaseNoteKind.item => Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(line.text)),
        ],
      ),
    ),
    ReleaseNoteKind.text => Padding(
      padding: const EdgeInsets.only(top: Gap.s),
      child: Text(line.text),
    ),
  };
}

class _AppDownloadDialog extends StatefulWidget {
  const _AppDownloadDialog({
    required this.release,
    required this.installer,
    required this.openRelease,
  });
  final AppRelease release;
  final AppInstaller installer;
  final Future<bool> Function(Uri) openRelease;
  @override
  State<_AppDownloadDialog> createState() => _AppDownloadDialogState();
}

class _AppDownloadDialogState extends State<_AppDownloadDialog> {
  CancelToken? _token;
  File? _file;
  double? _progress;
  String? _failure;
  bool _busy = false;
  bool _permission = false;
  bool _handedToInstaller = false;

  Future<void> _discard() async {
    final file = _file;
    _file = null;
    if (file == null) return;
    try {
      await widget.installer.discard(file);
    } catch (_) {
      // 缓存清理失败不替代原始安装错误。
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
      _permission = false;
    });
    final token = CancelToken();
    _token = token;
    try {
      _file ??= await widget.installer.prepare(widget.release, token, (
        received,
        total,
      ) {
        if (mounted && !token.isCancelled) {
          setState(
            () => _progress = total > 0 ? (received / total).clamp(0, 1) : null,
          );
        }
      });
      if (!mounted || token.isCancelled) return;
      final launched = await widget.installer.install(
        _file!,
        widget.release.version,
      );
      _handedToInstaller = launched;
      if (!mounted || token.isCancelled) return;
      if (launched) {
        Navigator.pop(context);
        return;
      }
      setState(() => _permission = true);
    } catch (error) {
      // 系统拒绝或缓存文件失效时，重试重新下载并校验。
      await _discard();
      if (mounted && !token.isCancelled) {
        setState(
          () => _failure = error is AppInstallFailure
              ? error.message
              : '无法下载或安装更新，请重试或前往官方发布页',
        );
      }
    } finally {
      if ((!mounted || token.isCancelled) && !_handedToInstaller) {
        await _discard();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _authorize() async {
    try {
      await widget.installer.openPermission();
    } catch (_) {
      if (mounted) setState(() => _failure = '无法打开安装权限设置，请重试');
    }
  }

  Future<void> _fallback() async {
    var opened = false;
    try {
      opened = await widget.openRelease(widget.release.url);
    } catch (_) {}
    if (mounted && !opened) setState(() => _failure = '无法打开下载页面，请稍后重试');
  }

  @override
  void dispose() {
    _token?.cancel();
    if (!_busy && !_handedToInstaller) unawaited(_discard());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(tr(_permission ? '需要安装权限' : '软件更新')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_busy) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text(tr('正在下载并校验安装包…')),
          ],
          if (_permission) Text(tr('请在系统设置中允许安装此应用提供的更新，返回后点击“继续安装”。')),
          if (_failure != null) Text(tr(_failure!)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _token?.cancel();
            Navigator.pop(context);
          },
          child: SelectionContainer.disabled(
            child: Text(tr(_busy ? '取消' : '关闭')),
          ),
        ),
        if (_permission) ...[
          TextButton(
            onPressed: _busy ? null : _authorize,
            child: SelectionContainer.disabled(child: Text(tr('打开安装权限设置'))),
          ),
          FilledButton(
            onPressed: _busy ? null : _run,
            child: SelectionContainer.disabled(child: Text(tr('继续安装'))),
          ),
        ],
        if (_failure != null && !_busy) ...[
          TextButton(
            onPressed: _fallback,
            child: SelectionContainer.disabled(child: Text(tr('官方发布页'))),
          ),
          FilledButton(
            onPressed: () {
              _progress = null;
              unawaited(_run());
            },
            child: SelectionContainer.disabled(child: Text(tr('重试'))),
          ),
        ],
      ],
    ),
  );
}

Future<bool> _openRelease(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

Future<void> showAppUpdateResult(
  BuildContext context,
  AppUpdateResult result,
) async {
  if (!context.mounted) return;
  if (result.release != null) {
    await showAppUpdatePrompt(context, result);
  } else {
    _message(context, tr(result.failure ?? '软件已是最新版本'));
  }
}

Future<void> showSourceUpdatePrompt(
  BuildContext context,
  SourceUpdateResult result,
  SourceUpdater updater,
) async {
  if (!context.mounted || !result.hasUpdates) return;
  final requirements = <String, List<SourceUpdateCandidate>>{};
  for (final candidate in result.requiresAppUpdate) {
    (requirements[candidate.entry.minAppVersion] ??= []).add(candidate);
  }
  final versions = requirements.keys.toList()..sort(compareReleaseVersions);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => ReminderPromptDialog(
      icon: Icons.extension_outlined,
      title: tr('发现 {count} 个插件更新', {'count': result.allUpdates.length}),
      primaryLabel: result.available.isEmpty
          ? null
          : tr('更新 {count} 个插件', {'count': result.available.length}),
      onIgnore: () => AppSettings.instance.ignoreSourceUpdates({
        for (final candidate in result.allUpdates)
          candidate.entry.key: candidate.entry.version,
      }),
      children: [
        _UpdateSection(
          title: tr('可直接更新 {count} 个插件', {'count': result.available.length}),
          children: [
            for (final candidate in result.available)
              _UpdateItem(
                name: candidate.entry.name,
                currentVersion: candidate.version,
                latestVersion: candidate.entry.version,
              ),
          ],
        ),
        for (final version in versions) ...[
          const SizedBox(height: Gap.l),
          _UpdateSection(
            title: tr('{count} 个插件需要先将本体升级至 {version} 或更高版本', {
              'count': requirements[version]!.length,
              'version': version,
            }),
            children: [
              for (final candidate in requirements[version]!)
                _UpdateItem(
                  name: candidate.entry.name,
                  currentVersion: candidate.version,
                  latestVersion: candidate.entry.version,
                ),
            ],
          ),
        ],
        if (result.available.isNotEmpty) ...[
          const SizedBox(height: Gap.l),
          Text(
            tr('确认后下载并安装以下官方插件，保留登录状态与设置。'),
            style: ctx.text.bodyMedium?.copyWith(
              color: ctx.colors.onSurfaceVariant,
            ),
          ),
        ],
        if (result.failures.isNotEmpty) ...[
          const SizedBox(height: Gap.l),
          ..._failures(result),
        ],
      ],
    ),
  );
  if (confirmed != true) return;
  final applied = await updater.applyUpdates(result.available);
  if (context.mounted) await showSourceUpdateResult(context, applied);
}

Iterable<Widget> _failures(SourceUpdateResult result) sync* {
  for (final failure in result.failures.entries) {
    yield Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('${failure.key}\n${tr(failure.value)}'),
    );
  }
}

Future<void> showSourceUpdateResult(
  BuildContext context,
  SourceUpdateResult result,
) async {
  if (!context.mounted) return;
  if (result.failures.isNotEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(tr('官方站点更新失败')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.updated.isNotEmpty) ...[
                Text(tr('已更新 {count} 个官方站点', {'count': result.updated.length})),
                const SizedBox(height: 12),
              ],
              ..._failures(result),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: SelectionContainer.disabled(child: Text(tr('关闭'))),
          ),
        ],
      ),
    );
    return;
  }
  _message(
    context,
    result.updated.isNotEmpty
        ? tr('已更新 {count} 个官方站点', {'count': result.updated.length})
        : tr(result.checked == 0 ? '没有可检查的官方站点' : '官方站点已是最新版本'),
  );
}

void _message(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text)));
}
