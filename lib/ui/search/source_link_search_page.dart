import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../engine/source_manager.dart';
import '../widgets/paged_grid.dart';

/// 保留原站查询中的全部筛选语义，不把链接强行转换为应用的筛选表单。
class SourceLinkSearchPage extends StatefulWidget {
  const SourceLinkSearchPage({
    super.key,
    required this.source,
    required this.url,
    required this.manager,
  });
  final String source, url;
  final SourceManager manager;
  @override
  State<SourceLinkSearchPage> createState() => _SourceLinkSearchPageState();
}

class _SourceLinkSearchPageState extends State<SourceLinkSearchPage> {
  final token = CancelToken();
  late final controller = PagedController(
    (page, cursor) => widget.manager.searchLink(
      widget.source,
      widget.url,
      page: page,
      cursor: cursor,
      cancelToken: token,
    ),
    source: widget.source,
  );
  @override
  void initState() {
    super.initState();
    controller.loadMore();
  }

  @override
  void dispose() {
    token.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('原站链接搜索'))),
    body: RefreshIndicator(
      onRefresh: controller.refresh,
      child: CustomScrollView(
        slivers: [
          PagedSliverGrid(
            controller: controller,
            kind: widget.manager.manifest(widget.source)!.kind,
          ),
        ],
      ),
    ),
  );
}
