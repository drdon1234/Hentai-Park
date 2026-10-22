import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../game/downloads.dart';
import '../../library/downloads.dart' show DownloadStatus;
import '../kit/adaptive_sheet.dart';
import '../kit/kit.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import '../widgets/platform_share.dart';

class GameResources extends StatefulWidget {
  const GameResources({super.key, required this.work});
  final WorkDetail work;
  @override
  State<GameResources> createState() => _GameResourcesState();
}

class _GameResourcesState extends State<GameResources> {
  List<GameResource>? _resources;
  Object? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GameResources oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.work != widget.work) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _error = null;
      _resources = null;
    });
    try {
      final resources = await SourceManager.instance.gameResources(
        widget.work.source,
        widget.work.id,
      );
      if (mounted && generation == _generation) {
        setState(() => _resources = resources);
      }
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(tr('游戏资源'), style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              tooltip: tr('刷新'),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Text(tr('直链重试会从头下载；网盘账号与原站账号权限独立。')),
        if (_error != null)
          SourceErrorView(
            error: _error!,
            source: widget.work.source,
            onRetry: _load,
          )
        else if (_resources == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_resources!.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text(tr('暂无游戏资源')))
        else
          for (final resource in _resources!)
            GameResourceCard(
              key: ValueKey(resource.id),
              work: widget.work,
              resource: resource,
            ),
      ],
    ),
  );
}

class GameResourceCard extends StatefulWidget {
  const GameResourceCard({
    super.key,
    required this.work,
    required this.resource,
  });
  final WorkDetail work;
  final GameResource resource;
  @override
  State<GameResourceCard> createState() => GameResourceCardState();
}

class GameResourceCardState extends State<GameResourceCard> {
  bool _busy = false;
  Object? _error;
  String? _lastChannel;

  /// A reply is posted publicly with the user's account, so it is never sent without a clear yes.
  Future<bool> _confirmReply(GameChannel channel) async {
    final source = widget.work.source;
    final settings = AppSettings.instance;
    if (settings.replyWithoutAsking.contains(source)) return true;
    final site = SourceManager.instance.manifest(source)?.name ?? source;
    var remember = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr('以你的账号发帖？')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('{site}要求回复后才显示下载链接。继续会用你的账号在下面的帖子里公开回复。', {'site': site}),
              ),
              const SizedBox(height: Gap.m),
              Text(tr('帖子'), style: ctx.text.labelLarge),
              Text(widget.work.title, style: ctx.text.bodyMedium),
              const SizedBox(height: Gap.s),
              Text(tr('回复内容'), style: ctx.text.labelLarge),
              Text(channel.replyText, style: ctx.text.bodyMedium),
              const SizedBox(height: Gap.s),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: remember,
                onChanged: (v) => setState(() => remember = v ?? false),
                title: SelectionContainer.disabled(child: Text(tr('这个站点不再询问'))),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: SelectionContainer.disabled(child: Text(tr('取消'))),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: SelectionContainer.disabled(child: Text(tr('回复并获取链接'))),
            ),
          ],
        ),
      ),
    );
    if (ok == true && remember) settings.allowReplyWithoutAsking(source);
    return ok == true;
  }

  Future<void> _choose(GameChannel channel) async {
    if (_busy) return;
    if (channel.requiresReply && !await _confirmReply(channel)) return;
    if (!mounted) return;
    _lastChannel = channel.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (channel.kind == GameChannelKind.direct) {
        await GameDownloadManager.instance.enqueue(
          widget.work.toItem(),
          widget.resource,
          channel,
        );
      } else {
        final result = await SourceManager.instance.resolveGameResource(
          widget.work.source,
          widget.work.id,
          widget.resource.id,
          channel.id,
        );
        if (!mounted) return;
        if (result.kind != GameChannelKind.external) {
          throw SourceError('PARSE', '游戏下载地址无效');
        }
        await _showLinks(result);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) context.toast(tr('已复制'));
  }

  Future<void> _open(String url) async {
    try {
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw const FormatException();
      }
    } catch (_) {
      if (mounted) context.toast(tr('无法打开链接，请复制后手动打开'));
    }
  }

  Future<void> _showLinks(GameResourceLink result) => showAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        minChildSize: .3,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text(tr('网盘资源'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (result.extractionCode.isNotEmpty)
              ListTile(
                title: SelectionContainer.disabled(child: Text(tr('提取码'))),
                subtitle: SelectionContainer.disabled(
                  child: SelectableText(result.extractionCode),
                ),
                trailing: SelectionContainer.disabled(
                  child: IconButton(
                    tooltip: tr('复制'),
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copy(result.extractionCode),
                  ),
                ),
              ),
            if (result.archivePassword.isNotEmpty)
              ListTile(
                title: SelectionContainer.disabled(child: Text(tr('解压密码'))),
                subtitle: SelectionContainer.disabled(
                  child: SelectableText(result.archivePassword),
                ),
                trailing: SelectionContainer.disabled(
                  child: IconButton(
                    tooltip: tr('复制'),
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copy(result.archivePassword),
                  ),
                ),
              ),
            for (var i = 0; i < result.urls.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr('链接 {number}', {'number': i + 1})),
                      SelectableText(result.urls[i]),
                      if (result.extractionCodes.isNotEmpty &&
                          result.extractionCodes[i].isNotEmpty &&
                          result.extractionCodes[i] != result.extractionCode)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: SelectionContainer.disabled(
                            child: Text(tr('提取码')),
                          ),
                          subtitle: SelectionContainer.disabled(
                            child: SelectableText(result.extractionCodes[i]),
                          ),
                          trailing: SelectionContainer.disabled(
                            child: IconButton(
                              tooltip: tr('复制'),
                              icon: const Icon(Icons.copy),
                              onPressed: () => _copy(result.extractionCodes[i]),
                            ),
                          ),
                        ),
                      const SizedBox(height: Gap.m),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => _open(result.urls[i]),
                            icon: const Icon(Icons.open_in_new),
                            label: SelectionContainer.disabled(
                              child: Text(tr('打开链接')),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _copy(result.urls[i]),
                            icon: const Icon(Icons.copy),
                            label: SelectionContainer.disabled(
                              child: Text(tr('复制链接')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final resource = widget.resource;
    final manager = GameDownloadManager.instance;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [
                    resource.title,
                    resource.version,
                  ].where((s) => s.isNotEmpty).join(' · ').isEmpty
                  ? tr('资源 {id}', {'id': resource.id})
                  : [
                      resource.title,
                      resource.version,
                    ].where((s) => s.isNotEmpty).join(' · '),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in [
                  ...resource.platforms,
                  ...resource.languages,
                  if (resource.size.isNotEmpty) resource.size,
                ])
                  Tag(label),
                Tag(
                  tr(
                    resource.testStatus == 'tested'
                        ? '原站标记已测试'
                        : resource.testStatus == 'untested'
                        ? '未测试'
                        : '未提供测试状态',
                  ),
                ),
                if (resource.status == 'expired') Tag(tr('已失效')),
              ],
            ),
            if (resource.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(resource.notes),
              ),
            for (final channel in resource.channels.where(
              (c) => c.requiresReply,
            ))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tr('点击后将发送回复：{text}', {'text': channel.replyText})),
              ),
            if (_error != null)
              SourceErrorView(
                error: _error!,
                source: widget.work.source,
                onRetry: () => _choose(
                  widget.resource.channels.firstWhere(
                    (c) => c.id == _lastChannel,
                    orElse: () => widget.resource.channels.first,
                  ),
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            ListenableBuilder(
              listenable: manager,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final channel in resource.channels) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: _busy || resource.status == 'expired'
                            ? null
                            : () => _choose(channel),
                        icon: Icon(
                          channel.kind == GameChannelKind.direct
                              ? Icons.download
                              : Icons.open_in_new,
                        ),
                        label: SelectionContainer.disabled(
                          child: Text(
                            '${tr(channel.requiresReply
                                ? '回复解锁并获取链接'
                                : channel.kind == GameChannelKind.direct
                                ? '直链下载'
                                : '获取网盘链接')} · ${(SourceManager.instance.manifest(widget.work.source)?.copy ?? PluginCopy.none).text(channel.label)}${channel.size.isEmpty ? '' : ' · ${channel.size}'}',
                          ),
                        ),
                      ),
                    ),
                    if (manager.task(
                          '${widget.work.uid}:${resource.id}:${channel.id}',
                        )
                        case final task?)
                      GameDownloadTile(task: task),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameDownloadTile extends StatelessWidget {
  const GameDownloadTile({super.key, required this.task});
  final GameDownloadTask task;
  @override
  Widget build(BuildContext context) {
    final manager = GameDownloadManager.instance;
    final running = task.status == DownloadStatus.running;
    final queued = task.status == DownloadStatus.queued;
    final done = task.status == DownloadStatus.done;
    final label = tr(switch (task.status) {
      DownloadStatus.queued => '等待下载',
      DownloadStatus.running => '正在下载',
      DownloadStatus.paused => '已取消',
      DownloadStatus.done => '下载完成',
      DownloadStatus.failed => '下载失败',
    });
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.page,
        vertical: Gap.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(task.item.title, style: Theme.of(context).textTheme.titleSmall),
          SelectableText(task.filename),
          Text(
            '$label · ${(task.bytes / (1024 * 1024)).toStringAsFixed(1)} MB${task.total > 0 ? ' / ${(task.total / (1024 * 1024)).toStringAsFixed(1)} MB' : ''}',
          ),
          if (running || queued)
            LinearProgressIndicator(
              value: task.total > 0 ? task.bytes / task.total : null,
            ),
          if (task.error != null) Text(tr(task.error!)),
          if (task.extractionCode.isNotEmpty)
            SelectableText('${tr('提取码')}: ${task.extractionCode}'),
          if (task.archivePassword.isNotEmpty)
            SelectableText('${tr('解压密码')}: ${task.archivePassword}'),
          if (done) SelectableText(task.file.path),
          const SizedBox(height: Gap.m),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (running || queued)
                OutlinedButton(
                  onPressed: () => manager.cancel(task.key),
                  child: SelectionContainer.disabled(child: Text(tr('取消下载'))),
                )
              else if (!done)
                OutlinedButton(
                  onPressed: manager.isActive(task.key)
                      ? null
                      : () => manager.retry(task.key),
                  child: SelectionContainer.disabled(child: Text(tr('重新下载'))),
                ),
              if (done)
                OutlinedButton(
                  onPressed: () async {
                    try {
                      await shareContent(
                        context,
                        files: [XFile(task.file.path)],
                      );
                    } catch (_) {
                      if (context.mounted) context.toast(tr('无法导出游戏文件'));
                    }
                  },
                  child: SelectionContainer.disabled(child: Text(tr('导出游戏文件'))),
                ),
              if (done)
                OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: task.file.path),
                    );
                    if (context.mounted) context.toast(tr('已复制'));
                  },
                  child: SelectionContainer.disabled(child: Text(tr('复制文件路径'))),
                ),
              if (!running && !queued)
                OutlinedButton(
                  onPressed: () async {
                    try {
                      await manager.remove(task.key);
                    } catch (_) {
                      if (context.mounted) context.toast(tr('请先取消下载并等待结束'));
                    }
                  },
                  child: SelectionContainer.disabled(
                    child: Text(tr('移除任务（保留文件）')),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
