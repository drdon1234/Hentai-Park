import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../tavern/store.dart';
import '../../tavern/transfer.dart';
import '../kit/adaptive_sheet.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../source/source_page.dart';
import '../theme.dart';
import '../widgets/content_translation.dart';

/// 关联只在确认后写入会话；导入和在线保存的资源独立留在本地库。
class TavernBooksPage extends StatefulWidget {
  const TavernBooksPage({super.key, required this.selected});
  final Set<String> selected;

  @override
  State<TavernBooksPage> createState() => _TavernBooksPageState();
}

class _TavernBooksPageState extends State<TavernBooksPage> {
  late final _selected = Set<String>.of(widget.selected);
  List<WorkItem>? _books;
  bool _working = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final books = await TavernStore.instance.resources(kind: 'lorebook');
      if (!mounted) return;
      setState(() {
        _books = books;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _import() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      if (await file.xFile.length() > 12 * 1024 * 1024) {
        throw const FormatException();
      }
      final item = await TavernTransfer.importBytes(
        await file.xFile.readAsBytes(),
        file.xFile.name,
        expectedKind: 'lorebook',
      );
      if (!mounted) return;
      if (item != null) _selected.add(item.uid);
      await _reload();
      if (mounted) context.toast(tr('已导入并选中，保存后关联到本会话。'));
    } catch (_) {
      if (mounted) context.toast(tr('导入失败，请检查文件格式'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _browse() async {
    final sources = SourceManager.instance.displayEnabled
        .where(
          (s) =>
              s.manifest!.kind == MediaKind.tavern &&
              s.manifest!.feeds.any((f) => f.key == 'lorebooks'),
        )
        .toList();
    final key = await showAdaptiveSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Gap.page),
              child: Text(tr('在线保存世界书后，返回此页确认关联。')),
            ),
            if (sources.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Gap.page),
                child: Text(tr('没有可用站点，请先启用或添加。')),
              ),
            for (final source in sources)
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: Text(source.manifest!.name),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, source.key),
              ),
          ],
        ),
      ),
    );
    if (key == null || !mounted) return;
    final manifest = SourceManager.instance.manifest(key);
    final feed = manifest?.feeds.indexWhere((f) => f.key == 'lorebooks') ?? -1;
    final existing = (_books ?? const <WorkItem>[]).map((b) => b.uid).toSet();
    await Nav.push(
      context,
      SourcePage(sourceKey: key, initialFeed: feed < 0 ? null : feed),
    );
    if (!mounted) return;
    await _reload();
    if (mounted && !_failed) {
      setState(() {
        _selected.addAll(
          _books!.where((b) => !existing.contains(b.uid)).map((b) => b.uid),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: Scaffold(
      appBar: AppBar(title: Text(tr('关联世界书'))),
      body: ReadableWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Gap.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('选择要用于本会话的世界书。角色卡内嵌世界书会自动使用。')),
                  const SizedBox(height: Gap.m),
                  Wrap(
                    spacing: Gap.s,
                    runSpacing: Gap.s,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _working ? null : _import,
                        icon: const Icon(Icons.file_open_outlined),
                        label: Text('${tr('导入')} JSON'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _browse,
                        icon: const Icon(Icons.public_rounded),
                        label: Text(tr('在线浏览')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_working) const LinearProgressIndicator(),
            Expanded(
              child: _failed
                  ? Center(
                      child: OutlinedButton(
                        onPressed: _reload,
                        child: Text(tr('重试')),
                      ),
                    )
                  : _books == null
                  ? const Center(child: CircularProgressIndicator())
                  : _books!.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Gap.page),
                      child: Text(
                        tr('还没有保存世界书。可导入 JSON，或在线浏览后保存到本地。'),
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _books!.length,
                      itemBuilder: (context, index) {
                        final book = _books![index];
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: Gap.page,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  value: _selected.contains(book.uid),
                                  title: TranslatedText(
                                    book.title,
                                    source: book.source,
                                  ),
                                  onChanged: _working
                                      ? null
                                      : (value) => setState(() {
                                          if (value == true) {
                                            _selected.add(book.uid);
                                          } else {
                                            _selected.remove(book.uid);
                                          }
                                        }),
                                ),
                              ),
                              IconButton(
                                tooltip: tr('查看世界书'),
                                onPressed: _working
                                    ? null
                                    : () async {
                                        await Nav.openWork(context, book);
                                        if (mounted) await _reload();
                                      },
                                icon: const Icon(Icons.menu_book_outlined),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Gap.page),
                child: FilledButton(
                  onPressed: _working || _books == null || _failed
                      ? null
                      : () {
                          final available = _books!.map((b) => b.uid).toSet();
                          Navigator.pop(
                            context,
                            _selected.intersection(available),
                          );
                        },
                  child: Text(tr('保存')),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
