import 'package:flutter/painting.dart';

/// 正文方向取首个有方向的字符，不跟随应用界面语言。
TextDirection novelTextDirection(String text) {
  final first = RegExp(r'\p{L}', unicode: true).firstMatch(text)?.group(0);
  if (first == null) return TextDirection.ltr;
  return RegExp(r'[\u0590-\u08ff\ufb1d-\ufdff\ufe70-\ufeff]').hasMatch(first)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

class NovelPage {
  const NovelPage(this.start, this.end);
  final int start;
  final int end;
}

/// UTF-16 文字位置不随窗口尺寸、字号、字体和阅读模式改变。
List<NovelPage> paginateNovel(
  String text, {
  required double width,
  required double height,
  required TextStyle style,
  required TextDirection direction,
  TextAlign align = TextAlign.start,
  bool indent = false,
  double paragraphGap = 0,
}) {
  if (text.isEmpty) return const [];
  final out = <NovelPage>[];
  var pageStart = 0;
  var used = 0.0;
  for (final segment in novelSegments(text)) {
    final prefix = indent && novelParagraphStart(text, segment.start)
        ? '\u3000\u3000'
        : '';
    final value = text.substring(segment.start, segment.end).trimRight();
    final painter = TextPainter(
      text: TextSpan(text: prefix + value, style: style),
      textDirection: direction,
      textAlign: align,
    )..layout(maxWidth: width.clamp(1, double.infinity));
    try {
      final lines = painter.computeLineMetrics();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final local = i == 0
            ? 0
            : (painter
                          .getLineBoundary(
                            painter.getPositionForOffset(
                              Offset(
                                direction == TextDirection.rtl
                                    ? painter.width
                                    : 0,
                                line.baseline - line.ascent + line.height / 2,
                              ),
                            ),
                          )
                          .start -
                      prefix.length)
                  .clamp(0, value.length);
        final start = segment.start + local;
        var gap = i == 0 && used > 0 && novelParagraphStart(text, segment.start)
            ? paragraphGap
            : 0.0;
        if (used + gap + line.height > height && start > pageStart) {
          out.add(NovelPage(pageStart, start));
          pageStart = start;
          used = 0;
          gap = 0;
        }
        used += gap + line.height;
      }
    } finally {
      painter.dispose();
    }
  }
  if (pageStart < text.length) out.add(NovelPage(pageStart, text.length));
  return out;
}

bool novelParagraphStart(String text, int offset) =>
    offset == 0 ||
    (offset >= 2 && text.substring(offset - 2, offset) == '\n\n');

int novelSafeOffset(String text, int offset) {
  var result = offset.clamp(0, text.length);
  if (result > 0 &&
      result < text.length &&
      text.codeUnitAt(result) >= 0xDC00 &&
      text.codeUnitAt(result) <= 0xDFFF) {
    result--;
  }
  return result;
}

/// SelectionArea 在不同段落间插入的空白可能不同；返回原文范围，
/// 将显示缩进与段落分隔的差异排除在用户保存的引用之外。
NovelPage? novelSelectionRange(String text, String selected, int from) {
  final whitespace = RegExp(r'\s');
  final needle = selected.replaceAll(whitespace, '');
  if (needle.isEmpty) return null;
  final offsets = <int>[];
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (whitespace.hasMatch(text[i])) continue;
    offsets.add(i);
    buffer.write(text[i]);
  }
  final normalized = buffer.toString();
  final startIndex = offsets.indexWhere((i) => i >= from);
  if (startIndex < 0) return null;
  final index = normalized.indexOf(needle, startIndex);
  if (index < 0) return null;
  return NovelPage(offsets[index], offsets[index + needle.length - 1] + 1);
}

/// 与分页测量共用段落边界，跨页续段不重复缩进和段间距。
List<NovelPage> novelPageSegments(String text, NovelPage page) => [
  for (final segment in novelSegments(text))
    if (segment.end > page.start && segment.start < page.end)
      NovelPage(
        segment.start < page.start ? page.start : segment.start,
        segment.end > page.end ? page.end : segment.end,
      ),
];

int novelPageAt(List<NovelPage> pages, int offset) {
  var low = 0, high = pages.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (pages[mid].end <= offset) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low.clamp(0, pages.isEmpty ? 0 : pages.length - 1);
}

/// 滚动模式把超长段落拆成可定位片段，保留所有原文与字符位置。
List<NovelPage> novelSegments(String text) {
  final out = <NovelPage>[];
  var start = 0;
  while (start < text.length) {
    final boundary = text.indexOf('\n\n', start);
    var end = boundary < 0 ? text.length : boundary + 2;
    if (end - start > 1200) {
      end = start + 1200;
      final last = text.codeUnitAt(end - 1);
      if (last >= 0xD800 && last <= 0xDBFF) end--;
    }
    out.add(NovelPage(start, end));
    start = end;
  }
  return out;
}
