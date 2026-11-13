import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../tavern/store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 头像与封面共用图片路径；没有图片时以人格首字和形状区分身份。
class TavernAvatar extends StatelessWidget {
  const TavernAvatar({
    super.key,
    required this.name,
    this.user = false,
    this.saved,
    this.item,
  });
  final String name;
  final bool user;
  final SavedTavernResource? saved;
  final WorkItem? item;
  @override
  Widget build(BuildContext context) {
    final resource = saved;
    final preview = item ?? resource?.item;
    final fallback = Center(
      child: user && name.trim().isNotEmpty
          ? Text(
              name.trim().characters.first,
              style: context.text.titleMedium?.copyWith(
                color: context.colors.onSecondaryContainer,
              ),
            )
          : Icon(
              Icons.person_outline_rounded,
              color: context.colors.onSurfaceVariant,
            ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 40,
        child: ClipRRect(
          borderRadius: user ? Radii.large : Radii.small,
          child: ColoredBox(
            color: user
                ? context.colors.secondaryContainer
                : context.colors.surfaceContainerHighest,
            child: !user && resource?.format == 'png'
                ? ListenableBuilder(
                    listenable: AppSettings.instance.watch({'blurCovers'}),
                    builder: (context, _) => ImageFiltered(
                      enabled: AppSettings.instance.blurCovers,
                      imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Image.memory(
                        resource!.bytes,
                        cacheWidth: 160,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => fallback,
                      ),
                    ),
                  )
                : !user && preview != null && preview.cover.isNotEmpty
                ? CoverImage(
                    source: preview.source,
                    url: preview.cover,
                    mediaKind: MediaKind.tavern,
                  )
                : fallback,
          ),
        ),
      ),
    );
  }
}
