import 'package:flutter/material.dart';

import '../../library/library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'favorite_actions.dart';
import '../../core/localization.dart';

class CategoryManagePage extends StatelessWidget {
  const CategoryManagePage({super.key});

  Future<void> _create(BuildContext context) async {
    final name = await promptText(context, tr('新建分类'), '');
    if (name == null) return;
    if (await Library.instance.createCategory(name) == null && context.mounted) context.toast(tr('分类名称为空或已存在'));
  }

  Future<void> _rename(BuildContext context, Category c) async {
    final name = await promptText(context, tr('重命名分类'), c.name);
    if (name != null && !Library.instance.renameCategory(c.id, name) && context.mounted) context.toast(tr('分类名称为空或已存在'));
  }

  Future<void> _delete(BuildContext context, Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('删除分类「{value0}」？', {'value0': c.name})),
        content: Text(tr('分类中的作品不会被取消收藏；不再属于任何分类的作品会出现在"默认"中。')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('取消'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('删除'))),
        ],
      ),
    );
    if (ok == true) Library.instance.deleteCategory(c.id);
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final lib = Library.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('分类'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _create(context), icon: const Icon(Icons.add_rounded), label: Text(tr('新建分类'))),
      body: ListenableBuilder(
        listenable: lib,
        builder: (context, _) {
          final cats = lib.categories;
          if (cats.isEmpty) {
            return MessageView(icon: Icons.label_outline_rounded, title: tr('还没有分类'), message: tr('分类用于整理书架；一部作品可以同时属于多个分类'));
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: cats.length,
            onReorderItem: (from, to) {
              final ids = cats.map((c) => c.id).toList();
              final id = ids.removeAt(from);
              ids.insert(to, id);
              lib.reorderCategories(ids);
            },
            itemBuilder: (context, i) {
              final c = cats[i];
              return Card(
                key: ValueKey(c.id),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.label_outline_rounded),
                  title: Text(c.name),
                  subtitle: Text(tr('{value0} 部作品', {'value0': lib.favorites(category: c.id).length})),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(tooltip: tr('重命名'), icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(context, c)),
                      IconButton(tooltip: tr('删除'), icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(context, c)),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded)),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
