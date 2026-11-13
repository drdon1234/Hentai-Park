import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/platform_capabilities.dart';
import '../kit/tokens.dart';
import '../theme.dart';
import '../widgets/content_translation.dart';

/// 解析出的链接仅在弹窗期间使用，不进入书库或配置。
class GameResourceLinks extends StatefulWidget {
  const GameResourceLinks({
    super.key,
    required this.title,
    required this.result,
    this.allowDownload = false,
  });

  final String title;
  final GameResourceLink result;
  final bool allowDownload;

  @override
  State<GameResourceLinks> createState() => _GameResourceLinksState();
}

class _GameResourceLinksState extends State<GameResourceLinks> {
  String? _copied;
  bool _copyFailed = false;
  bool _openFailed = false;

  String _code(int index) {
    final codes = widget.result.extractionCodes;
    return codes.isNotEmpty && codes[index].isNotEmpty
        ? codes[index]
        : widget.result.extractionCode;
  }

  String get _all => [
    widget.title,
    for (var i = 0; i < widget.result.urls.length; i++) ...[
      '',
      '${tr('链接 {number}', {'number': i + 1})}: ${widget.result.urls[i]}',
      if (_code(i).isNotEmpty) '${tr('提取码')}: ${_code(i)}',
    ],
    if (widget.result.archivePassword.isNotEmpty) ...[
      '',
      '${tr('解压密码')}: ${widget.result.archivePassword}',
    ],
  ].join('\n');

  Future<void> _copy(String id, String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) {
        setState(() {
          _copied = id;
          _copyFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _copyFailed = true);
    }
  }

  Widget _field(String label, String value, String id) => Padding(
    padding: const EdgeInsets.only(top: Gap.m),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.text.labelLarge),
              const SizedBox(height: Gap.xs),
              SelectableText(value, style: context.text.bodyMedium),
            ],
          ),
        ),
        const SizedBox(width: Gap.s),
        IconButton(
          tooltip: _copied == id ? tr('已复制') : tr('复制'),
          onPressed: () => _copy(id, value),
          icon: Icon(_copied == id ? Icons.check_rounded : Icons.copy_rounded),
        ),
      ],
    ),
  );

  Future<void> _open(String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _openFailed = true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(tr('游戏资源')),
    content: SizedBox(
      width: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TranslatedText(widget.title, style: context.text.titleMedium),
          if (!PlatformCapabilities.desktop) ...[
            const SizedBox(height: Gap.s),
            Text(tr('复制链接和密码后，可在电脑上下载。'), style: context.text.bodySmall),
          ],
          for (var i = 0; i < widget.result.urls.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.only(top: Gap.m),
                child: Divider(),
              ),
            _field(
              tr('链接 {number}', {'number': i + 1}),
              widget.result.urls[i],
              'url$i',
            ),
            if (_code(i).isNotEmpty) _field(tr('提取码'), _code(i), 'code$i'),
            if (widget.result.kind == GameChannelKind.external)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _open(widget.result.urls[i]),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(tr('打开链接')),
                ),
              ),
          ],
          if (widget.result.archivePassword.isNotEmpty)
            _field(tr('解压密码'), widget.result.archivePassword, 'password'),
          if (_copyFailed)
            Padding(
              padding: const EdgeInsets.only(top: Gap.m),
              child: Text(
                tr('复制失败，请重试'),
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ),
          if (_openFailed)
            Padding(
              padding: const EdgeInsets.only(top: Gap.m),
              child: Text(
                tr('无法打开链接，请复制后手动打开'),
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('关闭')),
      ),
      if (widget.allowDownload)
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(tr('直链下载')),
        ),
      FilledButton.icon(
        onPressed: () => _copy('all', _all),
        icon: Icon(
          _copied == 'all' ? Icons.check_rounded : Icons.copy_all_rounded,
        ),
        label: Text(tr(_copied == 'all' ? '已复制' : '复制全部')),
      ),
    ],
  );
}
