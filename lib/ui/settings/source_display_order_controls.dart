import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../engine/source_display_order.dart';
import '../widgets/common.dart';

String sourceProbeLabel(SourceProbeResult result) => switch (result.state) {
  SourceProbeState.available => tr('列表加载：{milliseconds} ms', {
    'milliseconds': result.elapsed!.inMilliseconds,
  }),
  SourceProbeState.loginRequired => tr('需要登录'),
  SourceProbeState.verificationRequired => tr('站点验证暂未完成'),
  SourceProbeState.unsupported => tr('无列表入口或需配置，未测速'),
  SourceProbeState.unavailable => tr('未能加载列表'),
  SourceProbeState.timedOut => tr('探测超时'),
};

/// 一次手动操作的入口；不保存排序偏好或启动后台调度。
class SourceDisplayOrderControls extends StatelessWidget {
  const SourceDisplayOrderControls({
    super.key,
    required this.sorter,
    required this.loaded,
  });

  final SourceDisplayOrder sorter;
  final bool loaded;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sorter,
    builder: (context, _) {
      final results = sorter.results.values;
      final available = results
          .where((r) => r.state == SourceProbeState.available)
          .length;
      final unavailable = results
          .where(
            (r) =>
                r.state == SourceProbeState.unavailable ||
                r.state == SourceProbeState.timedOut,
          )
          .length;
      return RowGroup(
        children: [
          ListTile(
            leading: const Icon(Icons.speed_rounded),
            title: SelectionContainer.disabled(child: Text(tr('站点测速排序'))),
            subtitle: SelectionContainer.disabled(
              child: Text(
                tr(
                  '仅手动探测一次，按列表可用性和加载耗时调整资源站点的显示顺序；不改变默认或手动顺序，不含排行榜与反搜。结果仅本次运行有效。',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Gap.s,
                  runSpacing: Gap.s,
                  children: [
                    OutlinedButton.icon(
                      onPressed: loaded && !sorter.running
                          ? sorter.checkNow
                          : null,
                      icon: const Icon(Icons.network_check_rounded),
                      label: SelectionContainer.disabled(
                        child: Text(tr('测速并自动排序')),
                      ),
                    ),
                    if (sorter.running)
                      OutlinedButton(
                        onPressed: sorter.cancel,
                        child: SelectionContainer.disabled(
                          child: Text(tr('取消探测')),
                        ),
                      )
                    else if (results.isNotEmpty)
                      OutlinedButton(
                        onPressed: sorter.invalidate,
                        child: SelectionContainer.disabled(
                          child: Text(tr('恢复原显示顺序')),
                        ),
                      ),
                  ],
                ),
                if (sorter.running) ...[
                  const SizedBox(height: Gap.s),
                  LinearProgressIndicator(
                    value: sorter.total == 0
                        ? null
                        : sorter.done / sorter.total,
                  ),
                  const SizedBox(height: Gap.s),
                  Text(
                    tr('正在探测：{done}/{total}', {
                      'done': sorter.done,
                      'total': sorter.total,
                    }),
                  ),
                ] else if (sorter.failed) ...[
                  const SizedBox(height: Gap.s),
                  Text(tr('站点加载失败，请重试')),
                ] else if (results.isNotEmpty) ...[
                  const SizedBox(height: Gap.s),
                  Text(
                    tr(
                      '探测完成：可用 {available}，未测速或需处理 {other}，加载失败 {unavailable}',
                      {
                        'available': available,
                        'other': results.length - available - unavailable,
                        'unavailable': unavailable,
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );
}
