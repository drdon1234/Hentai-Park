import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../widgets/common.dart';

/// 手势坐标只在图像实际显示区域内计算，输出相对原图的矩形。
class SearchCropPage extends StatefulWidget {
  const SearchCropPage({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
  });
  final Uint8List bytes;
  final int width, height;
  @override
  State<SearchCropPage> createState() => _SearchCropPageState();
}

class _SearchCropPageState extends State<SearchCropPage> {
  Offset? _start;
  Rect _crop = const Rect.fromLTWH(0, 0, 1, 1);

  Offset _point(Offset point, Size size) => Offset(
    (point.dx / size.width).clamp(0, 1),
    (point.dy / size.height).clamp(0, 1),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('裁剪图片'))),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Gap.page),
            child: Text(tr('在图片上拖动选择区域；保留需要识别的画面')),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = applyBoxFit(
                  BoxFit.contain,
                  Size(widget.width.toDouble(), widget.height.toDouble()),
                  constraints.biggest,
                ).destination;
                return Center(
                  child: SizedBox.fromSize(
                    size: size,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.memory(widget.bytes, fit: BoxFit.fill),
                        ),
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, box) => GestureDetector(
                              key: const ValueKey('crop-image'),
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) {
                                _start = _point(
                                  details.localPosition,
                                  box.biggest,
                                );
                              },
                              onPanUpdate: (details) {
                                if (_start == null) return;
                                final end = _point(
                                  details.localPosition,
                                  box.biggest,
                                );
                                setState(
                                  () => _crop = Rect.fromPoints(_start!, end),
                                );
                              },
                              child: CustomPaint(
                                painter: _CropPainter(
                                  _crop,
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Gap.page),
            child: Wrap(
              spacing: Gap.m,
              runSpacing: Gap.s,
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => _crop = const Rect.fromLTWH(0, 0, 1, 1)),
                  child: SelectionContainer.disabled(child: Text(tr('重置'))),
                ),
                FilledButton(
                  key: const ValueKey('apply-crop'),
                  onPressed: _crop.width < .02 || _crop.height < .02
                      ? null
                      : () => Navigator.pop(context, _crop),
                  child: SelectionContainer.disabled(child: Text(tr('应用裁剪'))),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.crop, this.color);
  final Rect crop;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(shade, Paint()..color = Scrims.medium);
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.crop != crop || old.color != color;
}
