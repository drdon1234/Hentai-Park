import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/content_translation.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/tag_translations.dart';
import '../kit/adaptive_sheet.dart';

Future<void> showTextTranslation(
  BuildContext context,
  String text, {
  String source = '',
  String namespace = '',
  bool tag = false,
  ContentTranslationQueue? queue,
}) async {
  if (text.trim().isEmpty) return;
  final locale = AppLocalizations.localeKey(
    AppLocalizations.of(context).locale,
  );
  if (tag) {
    try {
      await TagTranslations.instance.ensureLoaded(source, locale);
    } catch (_) {}
    if (!context.mounted) return;
  }
  return showAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TextTranslationSheet(
      text: text,
      locale: locale,
      queue: queue ?? ContentTranslationQueue.instance,
      dictionary: tag
          ? TagTranslations.instance.lookup(
              source,
              locale,
              text,
              namespace: namespace,
            )
          : null,
    ),
  );
}

/// 一个选择区允许跨行选择；服务翻译只由显式的工具栏操作触发。
class TranslationSelectionArea extends StatefulWidget {
  const TranslationSelectionArea({super.key, required this.child, this.queue});
  final Widget child;
  final ContentTranslationQueue? queue;
  @override
  State<TranslationSelectionArea> createState() =>
      _TranslationSelectionAreaState();
}

class _TranslationSelectionAreaState extends State<TranslationSelectionArea> {
  String selected = '';

  @override
  Widget build(BuildContext context) => SelectionArea(
    onSelectionChanged: (value) => selected = value?.plainText ?? '',
    contextMenuBuilder: (context, state) =>
        AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: [
            ...state.contextMenuButtonItems,
            ContextMenuButtonItem(
              label: tr('翻译'),
              onPressed: () {
                final text = selected;
                ContextMenuController.removeAny();
                unawaited(
                  showTextTranslation(context, text, queue: widget.queue),
                );
              },
            ),
          ],
        ),
    child: TextSelectionGuard(child: widget.child),
  );
}

/// 放在选择区域内部，只允许从可选文字的实际行框开始选择。
class TextSelectionGuard extends StatefulWidget {
  const TextSelectionGuard({super.key, required this.child});
  final Widget child;

  @override
  State<TextSelectionGuard> createState() => _TextSelectionGuardState();
}

class _TextSelectionGuardState extends State<TextSelectionGuard> {
  bool _startsOnText = false;
  late final _delegate = _TextHitSelectionDelegate(() => _startsOnText);

  void _pointerDown(PointerDownEvent event) {
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(
      result,
      event.position,
      event.viewId,
    );
    _startsOnText = result.path.any((entry) {
      final target = entry.target;
      if (target is! RenderParagraph || target.registrar == null) return false;
      final point = target.globalToLocal(event.position);
      if (!target.paintBounds.contains(point)) return false;
      return target
          .getBoxesForSelection(
            TextSelection(
              baseOffset: 0,
              extentOffset: target.text.toPlainText().length,
            ),
          )
          .any((box) => box.toRect().contains(point));
    });
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _pointerDown,
    child: SelectionContainer(delegate: _delegate, child: widget.child),
  );
}

/// Flutter 默认会选中距长按位置最近的文字；仅允许从实际文字范围起选。
/// 起选后仍由框架处理跨段拖选、滚动、选择手柄与键盘操作。
class _TextHitSelectionDelegate extends StaticSelectionContainerDelegate {
  _TextHitSelectionDelegate(this.startsOnText);
  final bool Function() startsOnText;

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final starting =
        event is SelectWordSelectionEvent ||
        event is SelectParagraphSelectionEvent ||
        (event is SelectionEdgeUpdateEvent &&
            value.status == SelectionStatus.none);
    if (starting && !startsOnText()) {
      super.dispatchSelectionEvent(const ClearSelectionEvent());
      return SelectionResult.none;
    }
    return super.dispatchSelectionEvent(event);
  }
}

class _TextTranslationSheet extends StatefulWidget {
  const _TextTranslationSheet({
    required this.text,
    required this.locale,
    required this.queue,
    this.dictionary,
  });
  final String text, locale;
  final String? dictionary;
  final ContentTranslationQueue queue;
  @override
  State<_TextTranslationSheet> createState() => _TextTranslationSheetState();
}

class _TextTranslationSheetState extends State<_TextTranslationSheet> {
  String? result;
  bool busy = false, failed = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_translate());
  }

  Future<void> _translate() async {
    if (busy) return;
    final current = ++generation;
    final engine = AppSettings.instance.translateEngine;
    setState(() {
      busy = true;
      failed = false;
    });
    final pieces = <String>[];
    final runes = widget.text.runes.toList();
    for (var start = 0; start < runes.length; start += 400) {
      if (!mounted || current != generation) return;
      final text = String.fromCharCodes(
        runes.sublist(start, (start + 400).clamp(0, runes.length)),
      );
      final value = await widget.queue.request(
        text,
        widget.locale,
        engine,
        isActive: () => mounted && current == generation,
      );
      if (value == null) {
        if (mounted) {
          setState(() {
            busy = false;
            failed = true;
          });
        }
        return;
      }
      pieces.add(value);
    }
    if (mounted && current == generation) {
      setState(() {
        result = pieces.join();
        busy = false;
      });
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('划词翻译'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(widget.text),
                    if (widget.dictionary != null) ...[
                      const Divider(),
                      Text(tr('词库译文')),
                      SelectableText(widget.dictionary!),
                    ],
                    const Divider(),
                    if (busy) const LinearProgressIndicator(),
                    if (result != null) SelectableText(result!),
                    if (failed) Text(tr('翻译失败，请重试')),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : _translate,
                  child: SelectionContainer.disabled(child: Text(tr('重试'))),
                ),
                TextButton(
                  onPressed: result == null
                      ? null
                      : () => Clipboard.setData(ClipboardData(text: result!)),
                  child: SelectionContainer.disabled(child: Text(tr('复制译文'))),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: SelectionContainer.disabled(child: Text(tr('关闭'))),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
