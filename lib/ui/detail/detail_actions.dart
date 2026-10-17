import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/titles.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../kit/adaptive_sheet.dart';
import '../kit/kit.dart';
import '../migration/migration_page.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/platform_share.dart';
import '../widgets/source_interaction.dart';

/// Favorite, download and more: outlined, quiet, and accent only when active.
class DetailSecondaryButton extends StatelessWidget {
  const DetailSecondaryButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.onLongPress,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        toggled: active,
        label: tooltip,
        // The label replaces the child's semantics, so the actions are restated here.
        onTap: onPressed,
        onLongPress: onLongPress,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.small,
            side: BorderSide(color: c.outline.withValues(alpha: .6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            onLongPress: onLongPress,
            child: SelectionContainer.disabled(
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  icon,
                  color: !enabled
                      ? c.onSurface.withValues(alpha: .3)
                      : active
                      ? c.primary
                      : c.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Open in browser, share, copy, search everywhere and migrate.
Future<void> showDetailMore(
  BuildContext context, {
  required WorkDetail detail,
  required WorkItem item,
  VoidCallback? onOpenOriginal,
}) async {
  final d = detail;
  await showAdaptiveSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (SourceManager.instance
                    .manifest(item.source)
                    ?.can('interaction') ==
                true)
              ListTile(
                leading: const Icon(Icons.thumb_up_outlined),
                title: Text(tr('原站喜好')),
                onTap: () {
                  Navigator.pop(ctx);
                  showSourceInteraction(context, item);
                },
              ),
            if (onOpenOriginal != null)
              ListTile(
                leading: const Icon(Icons.open_in_browser_rounded),
                title: SelectionContainer.disabled(child: Text(tr('在浏览器中打开'))),
                onTap: () {
                  Navigator.pop(ctx);
                  onOpenOriginal();
                },
              ),
            if (d.url.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: SelectionContainer.disabled(child: Text(tr('分享链接'))),
                onTap: () {
                  Navigator.pop(ctx);
                  shareContent(context, text: '${d.title}\n${d.url}');
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: SelectionContainer.disabled(child: Text(tr('复制标题'))),
              onTap: () {
                Clipboard.setData(ClipboardData(text: d.title));
                Navigator.pop(ctx);
                context.toast(tr('已复制'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.tag_rounded),
              title: SelectionContainer.disabled(
                child: Text(tr('复制编号  {id}', {'id': d.id})),
              ),
              onTap: () {
                Clipboard.setData(ClipboardData(text: d.id));
                Navigator.pop(ctx);
                context.toast(tr('已复制'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.travel_explore_rounded),
              title: SelectionContainer.disabled(child: Text(tr('在所有站点搜索标题'))),
              onTap: () {
                Navigator.pop(ctx);
                Nav.openAggregateSearch(
                  context,
                  keyword: searchableTitle(d.title),
                );
              },
            ),
            if (Library.instance.isFavorite(d.uid))
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: SelectionContainer.disabled(child: Text(tr('迁移到其他站点'))),
                subtitle: SelectionContainer.disabled(
                  child: Text(tr('保留分类与已读进度')),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Nav.push(context, MigrationPage(items: [item]));
                },
              ),
          ],
        ),
      ),
    ),
  );
}
