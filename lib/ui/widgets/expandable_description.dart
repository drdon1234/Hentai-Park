import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../kit/tokens.dart';
import '../theme.dart';
import 'content_translation.dart';
import 'text_translation.dart';

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
    final chunks = translationChunks(widget.text);
    final style = context.text.bodyMedium?.copyWith(
      color: context.colors.onSurfaceVariant,
      height: 1.5,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.m, Gap.page, Gap.m),
      child: ContentTranslation(
        text: chunks.firstOrNull ?? '',
        builder: (value) => LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(
                text: value,
                style: DefaultTextStyle.of(context).style.merge(style),
              ),
              maxLines: 3,
              ellipsis: '\u2026',
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              locale: Localizations.localeOf(context),
            )..layout(maxWidth: constraints.maxWidth);
            final canExpand =
                _open || chunks.length > 1 || painter.didExceedMaxLines;
            painter.dispose();
            return AnimatedSize(
              duration: Motion.of(context, Motion.medium),
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TranslationSelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          value,
                          maxLines: _open ? null : 3,
                          overflow: _open ? null : TextOverflow.ellipsis,
                          style: style,
                        ),
                        if (_open)
                          for (final chunk in chunks.skip(1))
                            ContentTranslation(
                              text: chunk,
                              builder: (value) => Text(value, style: style),
                            ),
                      ],
                    ),
                  ),
                  if (canExpand) const SizedBox(height: Gap.m),
                  if (canExpand)
                    Semantics(
                      expanded: _open,
                      child: OutlinedButton.icon(
                        onPressed: _toggle,
                        icon: Icon(
                          _open
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                        label: SelectionContainer.disabled(
                          child: Text(tr(_open ? '收起简介' : '展开简介')),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
