import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/ui/reader/reader_layout.dart';

void main() {
  group('tapActionFor', () {
    TapAction at(double x, double y, TapLayout l, {bool vertical = false, bool rtl = false, bool invertH = false}) =>
        tapActionFor(x, y, layout: l, vertical: vertical, rtl: rtl, invertH: invertH);

    test('left/right zones, mirrored for RTL and by inversion', () {
      expect(at(0.1, 0.5, TapLayout.leftRight), TapAction.prev);
      expect(at(0.9, 0.5, TapLayout.leftRight), TapAction.next);
      expect(at(0.5, 0.5, TapLayout.leftRight), TapAction.menu);
      expect(at(0.1, 0.5, TapLayout.leftRight, rtl: true), TapAction.next);
      expect(at(0.1, 0.5, TapLayout.leftRight, rtl: true, invertH: true), TapAction.prev);
    });

    test('auto picks L-shape for vertical reading', () {
      expect(at(0.5, 0.1, TapLayout.auto, vertical: true), TapAction.prev);
      expect(at(0.1, 0.5, TapLayout.auto, vertical: true), TapAction.prev);
      expect(at(0.5, 0.5, TapLayout.auto, vertical: true), TapAction.menu);
      expect(at(0.9, 0.5, TapLayout.auto, vertical: true), TapAction.next);
      expect(at(0.5, 0.9, TapLayout.auto, vertical: true), TapAction.next);
    });

    test('kindle, edge and off', () {
      expect(at(0.5, 0.1, TapLayout.kindle), TapAction.menu);
      expect(at(0.1, 0.6, TapLayout.kindle), TapAction.prev);
      expect(at(0.6, 0.6, TapLayout.kindle), TapAction.next);
      expect(at(0.1, 0.5, TapLayout.edge), TapAction.next);
      expect(at(0.5, 0.9, TapLayout.edge), TapAction.prev);
      expect(at(0.1, 0.1, TapLayout.off), TapAction.menu);
    });
  });

  group('buildSpreads', () {
    test('single pages by default', () {
      expect(buildSpreads(count: 3, aspects: {}), [const Spread([0]), const Spread([1]), const Spread([2])]);
    });

    test('dual pages keep the cover and wide pages alone', () {
      final s = buildSpreads(count: 6, aspects: {3: 1.4}, dual: true);
      expect(s, [const Spread([0]), const Spread([1, 2]), const Spread([3]), const Spread([4, 5])]);
      expect(buildSpreads(count: 3, aspects: {}, dual: true, coverSingle: false), [const Spread([0, 1]), const Spread([2])]);
    });

    test('split wide pages in reading order', () {
      expect(buildSpreads(count: 2, aspects: {1: 1.5}, splitWide: true), [const Spread([0]), const Spread([1], half: Half.left), const Spread([1], half: Half.right)]);
      expect(buildSpreads(count: 1, aspects: {0: 1.5}, splitWide: true, rtl: true), [const Spread([0], half: Half.right), const Spread([0], half: Half.left)]);
    });

    test('spreadIndexOf', () {
      final s = buildSpreads(count: 5, aspects: {}, dual: true);
      expect(spreadIndexOf(s, 0), 0);
      expect(spreadIndexOf(s, 2), 1);
      expect(spreadIndexOf(s, 4), 2);
    });
  });
}
