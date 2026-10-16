import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/titles.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../kit/adaptive_sheet.dart';
import '../nav.dart';
import '../theme.dart';

/// Adds or removes a favorite the same way from every entry point (detail page, long-press menus).
Future<void> toggleFavorite(BuildContext context, WorkItem item) async {
  unawaited(HapticFeedback.lightImpact());
  final lib = Library.instance;
  if (lib.isFavorite(item.uid)) {
    lib.removeFavorite(item.uid);
    return;
  }
  // Mihon's duplicate check: the same work may already be in the library from another source.
  final key = normalizeTitle(item.title);
  final dupes = lib
      .favorites()
      .where(
        (f) => f.item.uid != item.uid && normalizeTitle(f.item.title) == key,
      )
      .toList();
  if (dupes.isNotEmpty) {
    final existing = dupes.first.item;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('书库中已有相似作品')),
        content: Text(
          '「${existing.title}」（${SourceManager.instance.manifest(existing.source)?.name ?? existing.source}）',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: SelectionContainer.disabled(child: Text(tr('取消'))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'open'),
            child: SelectionContainer.disabled(child: Text(tr('打开已有'))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'add'),
            child: SelectionContainer.disabled(child: Text(tr('仍然收藏'))),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'open') {
      await Nav.openWork(context, existing);
      return;
    }
    if (choice != 'add') return;
  }
  var categories = <int>{};
  if (AppSettings.instance.askCategoryOnFavorite && lib.categories.isNotEmpty) {
    final picked = await pickCategories(context, title: tr('收藏到'));
    if (picked == null) return;
    categories = picked;
  }
  lib.addFavorite(item, categories: categories);
}

/// Changes the categories of an existing favorite.
Future<void> editFavoriteCategories(BuildContext context, String uid) async {
  final picked = await pickCategories(
    context,
    selected: Library.instance.categoriesOf(uid),
  );
  if (picked != null) Library.instance.setCategories(uid, picked);
}

/// Multi-select category sheet (Mihon style). An empty selection means the default category.
Future<Set<int>?> pickCategories(
  BuildContext context, {
  Set<int> selected = const {},
  String title = '设置分类',
}) {
  return showAdaptiveSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CategoryPicker(selected: selected, title: title),
  );
}

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({required this.selected, required this.title});
  final Set<int> selected;
  final String title;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  late final Set<int> _selected = {...widget.selected};

  Future<void> _create() async {
    final name = await promptText(context, tr('新建分类'), '');
    if (name == null) return;
    final c = await Library.instance.createCategory(name);
    if (c == null) {
      if (mounted) context.toast(tr('分类名称为空或已存在'));
      return;
    }
    setState(() => _selected.add(c.id));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        Library.instance.collection(LibraryCollection.categories),
        Library.instance.collection(LibraryCollection.favorites),
      ]),
      builder: (context, _) {
        final cats = Library.instance.categories;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: SelectionContainer.disabled(
                    child: Text(
                      tr(widget.title),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  trailing: SelectionContainer.disabled(
                    child: TextButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(tr('新建')),
                    ),
                  ),
                ),
                if (cats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: Text(tr('还没有分类。不选择任何分类时作品会放在"默认"里。')),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in cats)
                        CheckboxListTile(
                          value: _selected.contains(c.id),
                          title: SelectionContainer.disabled(
                            child: Text(c.name),
                          ),
                          onChanged: (v) => setState(
                            () => v == true
                                ? _selected.add(c.id)
                                : _selected.remove(c.id),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: SelectionContainer.disabled(
                            child: Text(tr('取消')),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, _selected),
                          child: SelectionContainer.disabled(
                            child: Text(tr('确定')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<String?> promptText(
  BuildContext context,
  String title,
  String initial, {
  String? hint,
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) =>
            Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: SelectionContainer.disabled(child: Text(tr('取消'))),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text.trim()),
          child: SelectionContainer.disabled(child: Text(tr('确定'))),
        ),
      ],
    ),
  );
}
