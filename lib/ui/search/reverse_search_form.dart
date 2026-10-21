import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/platform_capabilities.dart';
import '../../engine/source_manager.dart';
import '../../images/search_image.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 所有反搜服务共用的图片准备与服务选择区，不承载站点业务规则。
class ReverseSearchForm extends StatelessWidget {
  const ReverseSearchForm({
    super.key,
    required this.sources,
    required this.selectedSources,
    required this.image,
    required this.preparing,
    required this.busy,
    required this.onSelect,
    required this.onPick,
    required this.onCrop,
    required this.onRemove,
    required this.onSearch,
    required this.onCancel,
    required this.onManage,
    this.onPaste,
  });

  final List<InstalledSource> sources;
  final Set<String> selectedSources;
  final SearchImage? image;
  final bool preparing, busy;
  final ValueChanged<Set<String>> onSelect;
  final VoidCallback onPick, onCrop, onRemove, onSearch, onCancel, onManage;
  final VoidCallback? onPaste;

  Widget _selectAllButton(List<InstalledSource> entries) {
    final allSelected = entries.every(
      (entry) => selectedSources.contains(entry.key),
    );
    return OutlinedButton(
      onPressed: () => onSelect({
        for (final entry in entries)
          if (allSelected || !selectedSources.contains(entry.key)) entry.key,
      }),
      child: Text(tr(allSelected ? '取消全选' : '全选')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <ReverseSearchCategory, List<InstalledSource>>{};
    for (final entry in sources) {
      final category =
          entry.manifest?.reverseSearchCategory ??
          ReverseSearchCategory.general;
      (groups[category] ??= []).add(entry);
    }
    final colors = context.colors;
    final secondary = context.text.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            tr('寻找图片出处'),
            style: ParkText.serif(context.text.headlineSmall),
          ),
        ),
        const SizedBox(height: Gap.s),
        Text(
          tr('从截图或插画查找出处，再用作品名或番号搜索资源'),
          style: context.text.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Gap.xl),
        if (sources.isEmpty)
          EmptyState(
            icon: Icons.extension_outlined,
            title: tr('没有启用的反搜服务'),
            message: tr('在站点管理中启用或安装站点'),
            actions: [
              OutlinedButton(onPressed: onManage, child: Text(tr('管理站点'))),
            ],
          )
        else ...[
          Material(
            color: colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: Radii.medium,
              side: BorderSide(color: colors.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                if (image case final image?)
                  InkWell(
                    onTap: preparing ? null : onPick,
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.m),
                      child: Image.memory(
                        image.bytes,
                        width: double.infinity,
                        height: 220,
                        fit: BoxFit.contain,
                        semanticLabel: tr('待反搜图片'),
                      ),
                    ),
                  )
                else
                  InkWell(
                    onTap: preparing ? null : onPick,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.l,
                        vertical: Gap.xxl,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          children: [
                            ExcludeSemantics(
                              child: Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 40,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: Gap.l),
                            Text(tr('选择图片'), style: context.text.titleMedium),
                            const SizedBox(height: Gap.xs),
                            Text(
                              PlatformCapabilities.desktop
                                  ? tr('拖入图片或使用粘贴快捷键，也可点击选择')
                                  : tr('支持截图、插画和照片'),
                              style: secondary,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (preparing)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
          if (onPaste != null) ...[
            const SizedBox(height: Gap.s),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: preparing ? null : onPaste,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: Text(tr('粘贴图片')),
              ),
            ),
          ],
          if (image != null) ...[
            const SizedBox(height: Gap.s),
            SelectionContainer.disabled(
              child: Wrap(
                spacing: Gap.xs,
                runSpacing: Gap.xs,
                children: [
                  OutlinedButton.icon(
                    onPressed: preparing ? null : onPick,
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 18,
                    ),
                    label: Text(tr('选择图片')),
                  ),
                  OutlinedButton.icon(
                    onPressed: preparing ? null : onCrop,
                    icon: const Icon(Icons.crop, size: 18),
                    label: Text(tr('裁剪图片')),
                  ),
                  OutlinedButton(
                    onPressed: preparing ? null : onRemove,
                    child: Text(tr('移除图片')),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Gap.xl),
          OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            spacing: Gap.s,
            overflowSpacing: Gap.xs,
            children: [
              Semantics(
                header: true,
                child: Text(tr('选择服务（可多选）'), style: context.text.titleMedium),
              ),
              _selectAllButton(sources),
            ],
          ),
          const SizedBox(height: Gap.m),
          for (final category in ReverseSearchCategory.values)
            if (groups[category] case final entries?) ...[
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        category.label,
                        style: context.text.titleSmall,
                      ),
                    ),
                  ),
                  _selectAllButton(entries),
                ],
              ),
              const SizedBox(height: Gap.s),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: Gap.s,
                  runSpacing: Gap.xs,
                  children: [
                    for (final entry in entries)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth,
                        ),
                        child: Tooltip(
                          message: [
                            entry.name,
                            if (entry.manifest!.description.isNotEmpty)
                              entry.manifest!.description,
                            if (entry.manifest!.network['vpnHint'] == true)
                              tr('在中国大陆访问可能需要 VPN 或代理'),
                          ].join('\n'),
                          child: SelectionChip(
                            label: entry.name,
                            selected: selectedSources.contains(entry.key),
                            onSelected: (_) => onSelect({entry.key}),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.l),
            ],
          const SizedBox(height: Gap.xl),
          SelectionContainer.disabled(
            child: busy
                ? OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close, size: 20),
                    label: Text(tr('取消')),
                  )
                : FilledButton.icon(
                    onPressed:
                        image == null || selectedSources.isEmpty || preparing
                        ? null
                        : onSearch,
                    icon: const Icon(Icons.image_search_outlined, size: 20),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gap.m),
                      child: Text(tr('开始反搜'), textAlign: TextAlign.center),
                    ),
                  ),
          ),
          const SizedBox(height: Gap.m),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Gap.s),
              Expanded(
                child: Text(
                  tr('点击搜索后，图片会上传至所选服务；请勿上传私人或敏感图片'),
                  style: secondary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
