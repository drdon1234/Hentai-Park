import 'package:flutter/material.dart';

import '../../engine/source_manager.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../../core/localization.dart';

/// Downloads a script, shows what it is and what it would be allowed to touch, and installs it only
/// after the user confirms (Mihon's "untrusted extension" prompt). Returns the key, or null.
Future<String?> installSourceFromUrl(
  BuildContext context,
  String url, {
  String? expectedSha256,
  String? expectedKey,
}) async {
  final sm = SourceManager.instance;
  final InstallPreview preview;
  try {
    preview = await _withProgress(
      context,
      tr('正在下载并检查源脚本…'),
      () => sm.previewFromUrl(url, expectedSha256: expectedSha256),
    );
  } catch (e) {
    if (context.mounted) {
      context.toast(tr('无法安装：{value0}', {'value0': e.asSourceError.message}));
    }
    return null;
  }
  if (!context.mounted) return null;
  if (expectedKey != null && preview.key != expectedKey) {
    context.toast(tr('源脚本身份或校验值无效'));
    return null;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _TrustDialog(preview: preview),
  );
  if (ok != true || !context.mounted) return null;
  try {
    final key = await _withProgress(
      context,
      tr('正在安装…'),
      () => sm.install(preview),
    );
    if (context.mounted) {
      context.toast(
        '${tr(preview.existing != null ? '已更新' : '已安装')} ${preview.manifest.name}',
      );
    }
    return key;
  } catch (e) {
    if (context.mounted) {
      context.toast(tr('安装失败：{value0}', {'value0': e.asSourceError.message}));
    }
    return null;
  }
}

Future<T> _withProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function() body,
) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    return await body();
  } finally {
    nav.pop();
  }
}

class _TrustDialog extends StatelessWidget {
  const _TrustDialog({required this.preview});
  final InstallPreview preview;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final m = preview.manifest;
    final c = context.colors;
    Widget row(String label, String value, {bool mono = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: context.text.bodySmall?.copyWith(
                color: c.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: mono
                  ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                  : context.text.bodyMedium,
            ),
          ),
        ],
      ),
    );
    return AlertDialog(
      icon: Icon(Icons.verified_user_outlined, color: c.primary),
      title: Text(
        preview.existing != null
            ? tr('更新源「{value0}」？', {'value0': m.name})
            : tr('安装源「{value0}」？', {'value0': m.name}),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(tr('标识'), preview.key),
            row(tr('版本'), 'v${m.version} · ${m.kind.label}'),
            if (preview.url.isNotEmpty) row(tr('来源'), preview.url),
            row('SHA-256', preview.sha256.substring(0, 16), mono: true),
            row(
              tr('所属站点'),
              preview.domains.isEmpty
                  ? tr('（未声明）')
                  : preview.domains.join('\n'),
            ),
            if (preview.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final w in preview.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: c.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tr(w), style: TextStyle(color: c.error)),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              tr('源脚本会以你的身份访问上述站点。只安装你信任的来源。'),
              style: context.text.bodySmall?.copyWith(
                color: c.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('取消')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(preview.existing != null ? tr('信任并更新') : tr('信任并安装')),
        ),
      ],
    );
  }
}
