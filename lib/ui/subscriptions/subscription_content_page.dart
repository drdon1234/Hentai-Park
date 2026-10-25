import 'package:flutter/material.dart';

import '../../engine/source_manager.dart';
import '../../subscriptions/subscription_store.dart';
import '../search/source_search_page.dart';
import '../widgets/error_view.dart';

/// 浏览与周期检查从插件取得同一查询，不把历史更新列表当成订阅内容。
class SubscriptionContentPage extends StatefulWidget {
  const SubscriptionContentPage({
    super.key,
    required this.entry,
    this.sourceManager,
  });
  final SubscriptionEntry entry;
  final SourceManager? sourceManager;

  @override
  State<SubscriptionContentPage> createState() =>
      _SubscriptionContentPageState();
}

class _SubscriptionContentPageState extends State<SubscriptionContentPage> {
  SourceManager get manager => widget.sourceManager ?? SourceManager.instance;
  late Future<Map<String, dynamic>> query = _query();
  Future<Map<String, dynamic>> _query() => manager.subscriptionQuery(
    widget.entry.source,
    widget.entry.dimension,
    widget.entry.target,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: query,
    builder: (context, snapshot) {
      if (snapshot.data case final data?) {
        return SourceSearchPage(
          sourceKey: widget.entry.source,
          sourceManager: manager,
          initialKeyword: data['keyword'] as String,
          initialFilters: (data['filters'] as Map).cast<String, Object?>(),
        );
      }
      return Scaffold(
        appBar: AppBar(title: Text(widget.entry.label)),
        body: snapshot.hasError
            ? SourceErrorView(
                error: snapshot.error!,
                source: widget.entry.source,
                onRetry: () => setState(() => query = _query()),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    },
  );
}
