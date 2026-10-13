import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';

class DomainOrderPage extends StatelessWidget {
  const DomainOrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final settings = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('域排序'))),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final domains = settings.domainOrder;
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            buildDefaultDragHandles: false,
            header: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('拖动调整域的顺序；首页、聚合搜索和域选择器会同步排列。')),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: () =>
                          settings.domainOrder = AppSettings.defaultDomainOrder,
                      child: Text(tr('恢复默认顺序')),
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
            itemBuilder: (context, index) => Card(
              key: ValueKey(domains[index]),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(domains[index].label),
                trailing: ReorderableDragStartListener(
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
          );
        },
      ),
    );
  }
}
