import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../kit/tokens.dart';
import '../theme.dart';
import 'content_translation.dart';

class ExpandableDescription extends StatefulWidget {
  const ExpandableDescription({super.key, required this.text});
  final String text;

  @override
  State<ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<ExpandableDescription> {
  bool _open = false;

  @override
  void didUpdateWidget(ExpandableDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _open = false;
  }

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodyMedium?.copyWith(
      color: context.colors.onSurfaceVariant,
      height: 1.5,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(
              text: widget.text,
              style: DefaultTextStyle.of(context).style.merge(style),
            ),
            maxLines: 3,
            ellipsis: '\u2026',
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.localeOf(context),
          )..layout(maxWidth: constraints.maxWidth);
          final canExpand = painter.didExceedMaxLines;
          painter.dispose();
          return InkWell(
            borderRadius: Radii.medium,
            onTap: canExpand ? _toggle : null,
            child: AnimatedSize(
              duration: Motion.of(context, Motion.medium),
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_open)
                    for (final chunk in translationChunks(widget.text))
                      ContentTranslation(
                        text: chunk,
                        builder: (value) => Text(value, style: style),
                      )
                  else
                    ContentTranslation(
                      text: translationChunks(widget.text).firstOrNull ?? '',
                      builder: (value) => Text(
                        value,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  if (canExpand)
                    Semantics(
                      expanded: _open,
                      child: TextButton.icon(
                        onPressed: _toggle,
                        icon: Icon(
                          _open
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                        label: Text(tr(_open ? '收起简介' : '展开简介')),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
