/// Pure reader geometry: tap zones and how pages are grouped into screens (spreads).
library;

import '../../core/localization.dart';

enum TapAction { prev, next, menu }

/// Tap zone layouts (Mihon's navigation layouts).
enum TapLayout { auto, leftRight, lShaped, kindle, edge, off }

extension TapLayoutLabel on TapLayout {
  String get label => switch (this) {
    TapLayout.auto => tr('自动（随阅读模式）'),
    TapLayout.leftRight => tr('左右分区'),
    TapLayout.lShaped => tr('L 形'),
    TapLayout.kindle => tr('Kindle 式'),
    TapLayout.edge => tr('边缘'),
    TapLayout.off => tr('关闭'),
  };
}

/// Maps a tap at normalized coordinates (0..1) to an action.
/// "next" zones are on the right / bottom; [rtl] mirrors them horizontally for right-to-left reading,
/// and [invertH] / [invertV] mirror them again on request.
TapAction tapActionFor(double x, double y, {required TapLayout layout, required bool vertical, bool rtl = false, bool invertH = false, bool invertV = false}) {
  var l = layout;
  if (l == TapLayout.auto) l = vertical ? TapLayout.lShaped : TapLayout.leftRight;
  if (rtl != invertH) x = 1 - x;
  if (invertV) y = 1 - y;
  const a = 1 / 3, b = 2 / 3;
  final midX = x >= a && x <= b;
  final midY = y >= a && y <= b;
  switch (l) {
    case TapLayout.off:
      return TapAction.menu;
    case TapLayout.leftRight:
      if (x < a) return TapAction.prev;
      if (x > b) return TapAction.next;
      return TapAction.menu;
    case TapLayout.lShaped:
      if (midX && midY) return TapAction.menu;
      if (y < a || (x < a && y <= b)) return TapAction.prev;
      return TapAction.next;
    case TapLayout.kindle:
      if (y < a) return TapAction.menu;
      if (x < a) return TapAction.prev;
      return TapAction.next;
    case TapLayout.edge:
      if (!midX) return TapAction.next;
      if (y > b) return TapAction.prev;
      return TapAction.menu;
    case TapLayout.auto:
      return TapAction.menu;
  }
}

enum Half { left, right }

/// One screen in paged mode: one page, two pages side by side, or one half of a wide page.
class Spread {
  const Spread(this.pages, {this.half});
  final List<int> pages;
  final Half? half;

  int get first => pages.first;

  @override
  bool operator ==(Object other) => other is Spread && other.half == half && other.pages.length == pages.length && other.pages.indexed.every((e) => pages[e.$1] == e.$2);

  @override
  int get hashCode => Object.hash(Object.hashAll(pages), half);

  @override
  String toString() => 'Spread($pages${half == null ? '' : ', $half'})';
}

/// Groups [count] pages into spreads. [aspects] holds known width/height ratios; pages wider than
/// tall are never paired (dual) and are cut in two (split) — in reading order, so right-to-left
/// reading shows the right half first.
List<Spread> buildSpreads({
  required int count,
  required Map<int, double> aspects,
  bool dual = false,
  bool coverSingle = true,
  bool splitWide = false,
  bool rtl = false,
}) {
  bool wide(int i) => (aspects[i] ?? 0) > 1.0;
  final out = <Spread>[];
  var i = 0;
  while (i < count) {
    if (dual) {
      if (wide(i) || (coverSingle && i == 0) || i + 1 >= count || wide(i + 1)) {
        out.add(Spread([i]));
        i++;
      } else {
        out.add(Spread([i, i + 1]));
        i += 2;
      }
    } else if (splitWide && wide(i)) {
      out
        ..add(Spread([i], half: rtl ? Half.right : Half.left))
        ..add(Spread([i], half: rtl ? Half.left : Half.right));
      i++;
    } else {
      out.add(Spread([i]));
      i++;
    }
  }
  return out;
}

/// Index of the spread that shows [page] (the first one when a page is split).
int spreadIndexOf(List<Spread> spreads, int page) {
  for (var i = 0; i < spreads.length; i++) {
    if (spreads[i].pages.contains(page)) return i;
  }
  return spreads.isEmpty ? 0 : spreads.length - 1;
}
