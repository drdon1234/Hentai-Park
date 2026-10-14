import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../../novel/reading_notes.dart';
import '../kit/kit.dart';
import '../theme.dart';

/// A tall sheet with a title row, an optional field and a list below.
class _ListSheet extends StatelessWidget {
  const _ListSheet({
    required this.title,
    required this.list,
    this.field,
    this.action,
    this.height = .75,
  });
  final String title;
  final Widget list;
  final Widget? field;
  final Widget? action;
  final double height;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * height,
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: context.text.titleMedium),
            trailing: action,
          ),
          if (field != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.page),
              child: field,
            ),
          Expanded(child: list),
        ],
      ),
    ),
  );
}

/// The chapter list with a filter and reverse order; returns the picked index.
Future<int?> showChapterDirectory(
  BuildContext context, {
  required String uid,
  required List<Chapter> chapters,
  required int current,
}) async {
  final controller = TextEditingController();
  var query = '', reversed = false;
  final selected = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) {
        final indices = [
          for (var i = 0; i < chapters.length; i++)
            if (chapters[i].title.toLowerCase().contains(query.toLowerCase()))
              i,
        ];
        if (reversed) indices.sort((a, b) => b.compareTo(a));
        return _ListSheet(
          title: tr('目录'),
          height: .8,
          action: TextButton(
            onPressed: () => update(() => reversed = !reversed),
            child: Text(tr('倒序')),
          ),
          field: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: tr('搜索章节')),
            onChanged: (v) => update(() => query = v),
          ),
          list: ListView.builder(
            itemCount: indices.length,
            itemBuilder: (ctx, i) {
              final index = indices[i], chapter = chapters[index];
              return ListTile(
                selected: index == current,
                title: Text(chapter.title),
                subtitle:
                    Library.instance.chapterState(uid, chapter.id)?.read == true
                    ? Text(tr('已读'))
                    : null,
                trailing:
                    DownloadManager.instance.isChapterDownloaded(
                      uid,
                      chapter.id,
                    )
                    ? Icon(Icons.download_done, semanticLabel: tr('已下载'))
                    : null,
                onTap: () => Navigator.pop(ctx, index),
              );
            },
          ),
        );
      },
    ),
  );
  controller.dispose();
  return selected;
}

/// Searches [text] (the open chapter); returns the offset of the picked match.
Future<int?> showChapterSearch(BuildContext context, String text) async {
  final controller = TextEditingController();
  var query = '';
  final result = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) {
        final matches = <int>[];
        if (query.trim().isNotEmpty) {
          final haystack = text.toLowerCase(), needle = query.toLowerCase();
          var start = 0;
          while (matches.length < 500) {
            final offset = haystack.indexOf(needle, start);
            if (offset < 0) break;
            matches.add(offset);
            start = offset + needle.length;
          }
        }
        return _ListSheet(
          title: tr('本章搜索'),
          field: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: tr('搜索正文')),
            onChanged: (v) => update(() => query = v),
          ),
          list: ListView.builder(
            itemCount: matches.length,
            itemBuilder: (ctx, i) {
              final offset = matches[i];
              return ListTile(
                title: Text(
                  text.substring(
                    math.max(0, offset - 24),
                    math.min(text.length, offset + query.length + 70),
                  ),
                ),
                onTap: () => Navigator.pop(ctx, offset),
              );
            },
          ),
        );
      },
    ),
  );
  controller.dispose();
  return result;
}

/// Asks for a note: a new one on [quote], or an edit of [initial]. Null when cancelled.
Future<String?> askNote(
  BuildContext context, {
  String? quote,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final note = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(quote == null ? '编辑标注' : '添加标注')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (quote != null)
              Text(
                quote,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: ParkText.serif(ctx.text.bodyMedium),
              ),
            TextField(
              controller: controller,
              maxLines: quote == null ? 5 : 4,
              decoration: InputDecoration(hintText: tr('备注')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('取消'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(tr('保存')),
        ),
      ],
    ),
  );
  controller.dispose();
  return note;
}

/// Bookmarks and notes of a work, editable in place; returns the one to open.
Future<ReadingNote?> showReadingNotes(
  BuildContext context, {
  required String uid,
  required List<Chapter> chapters,
}) => showModalBottomSheet<ReadingNote>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => ListenableBuilder(
    listenable: ReadingNotes.instance,
    builder: (ctx, _) {
      final notes = ReadingNotes.instance.forWork(uid);
      Future<void> guarded(Future<void> Function() action) async {
        try {
          await action();
        } catch (e) {
          if (ctx.mounted) ctx.toast(tr('操作失败：{value0}', {'value0': e}));
        }
      }

      return _ListSheet(
        title: tr('书签与标注'),
        list: notes.isEmpty
            ? EmptyState(
                icon: Icons.bookmark_border_rounded,
                title: tr('暂无书签与标注'),
              )
            : ListView.builder(
                itemCount: notes.length,
                itemBuilder: (ctx, i) {
                  final n = notes[i];
                  return ListTile(
                    title: Text(
                      n.note.isEmpty ? n.quote : n.note,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      chapters
                              .where((c) => c.id == n.chapterId)
                              .firstOrNull
                              ?.title ??
                          n.chapterId,
                    ),
                    onTap: () => Navigator.pop(ctx, n),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: tr('编辑标注'),
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => guarded(() async {
                            final value = await askNote(ctx, initial: n.note);
                            if (value != null) {
                              await ReadingNotes.instance.update(
                                n.id,
                                note: value,
                              );
                            }
                          }),
                        ),
                        IconButton(
                          tooltip: tr('删除'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              guarded(() => ReadingNotes.instance.remove(n.id)),
                        ),
                      ],
                    ),
                  );
                },
              ),
      );
    },
  ),
);
