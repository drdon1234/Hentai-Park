import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../kit/kit.dart';

class DomainOrderPage extends StatelessWidget {
  const DomainOrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('分类顺序'))),
      body: ListenableBuilder(
        listenable: settings.domain(SettingsDomain.appearance),
        builder: (context, _) {
          final domains = settings.domainOrder;
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            buildDefaultDragHandles: false,
            header: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('拖动调整分类的顺序；发现页、搜索和分类栏都会按这个顺序排列。')),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: () =>
                          settings.domainOrder = AppSettings.defaultDomainOrder,
                      child: SelectionContainer.disabled(
                        child: Text(tr('恢复默认顺序')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            itemCount: domains.length,
            onReorderItem: (from, to) {
              domains.insert(to, domains.removeAt(from));
              settings.domainOrder = domains;
            },
            itemBuilder: (context, index) => HairlineItem(
              key: ValueKey(domains[index]),
              child: ListTile(
                title: SelectionContainer.disabled(
                  child: Text(domains[index].label),
                ),
                trailing: SelectionContainer.disabled(
                  child: ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        semanticLabel: tr('拖动排序'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
