import 'dart:typed_data';

import '../core/models.dart';

class HlsFragmentTiming {
  const HlsFragmentTiming({
    required this.videoStartUs,
    required this.audioStartUs,
  });
  final int videoStartUs;
  final int audioStartUs;
}

Never _invalid() => throw SourceError('NETWORK', 'HLS 分段不完整');

class _Box {
  _Box(this.bytes, this.type);
  final Uint8List bytes;
  final String type;
  ByteData get data => ByteData.sublistView(bytes);
}

List<_Box> _boxes(Uint8List bytes, [int start = 0]) {
  final result = <_Box>[];
  final data = ByteData.sublistView(bytes);
  while (start < bytes.length) {
    if (bytes.length - start < 8) _invalid();
    final size = data.getUint32(start);
    // 窗口输出不超过 32 位 box；不接受长度不明确或截断的 box。
    if (size < 8 || size > bytes.length - start) _invalid();
    result.add(
      _Box(
        Uint8List.sublistView(bytes, start, start + size),
        String.fromCharCodes(bytes.sublist(start + 4, start + 8)),
      ),
    );
    start += size;
  }
  return result;
}

Uint8List _container(String type, Iterable<Uint8List> children) {
  final payload = BytesBuilder(copy: false);
  for (final child in children) {
    payload.add(child);
  }
  final header = Uint8List(8);
  ByteData.sublistView(header).setUint32(0, payload.length + 8);
  header.setRange(4, 8, type.codeUnits);
  return (BytesBuilder(copy: false)
        ..add(header)
        ..add(payload.takeBytes()))
      .takeBytes();
}

/// Media3 muxer 写的是完整文件：tfhd 使用绝对地址且没有 tfdt。
/// 转为独立 HLS 媒体段时，改用 moof 相对地址，并为每条轨道写入累积解码时间。
(Uint8List, Uint8List) splitHlsFragment(
  Uint8List bytes, {
  HlsFragmentTiming? timing,
}) {
  final boxes = _boxes(bytes);
  final split = boxes.indexWhere((box) => box.type == 'moof');
  if (split < 1 ||
      !boxes.take(split).any((box) => box.type == 'moov') ||
      !boxes
          .skip(split)
          .any((box) => box.type == 'mdat' && box.bytes.length > 8)) {
    _invalid();
  }
  final defaults = <int, int>{};
  final decodeTimes = <int, int>{};
  for (final moov in boxes.take(split).where((b) => b.type == 'moov')) {
    if (timing != null) {
      for (final trak in _boxes(moov.bytes, 8).where((b) => b.type == 'trak')) {
        final children = _boxes(trak.bytes, 8);
        final tkhd = children.singleWhere((b) => b.type == 'tkhd');
        final trackOffset = tkhd.bytes[8] == 1 ? 28 : 20;
        if (tkhd.bytes.length < trackOffset + 4) _invalid();
        final track = tkhd.data.getUint32(trackOffset);
        final mdia = children.singleWhere((b) => b.type == 'mdia');
        final metadata = _boxes(mdia.bytes, 8);
        final mdhd = metadata.singleWhere((b) => b.type == 'mdhd');
        final timescaleOffset = mdhd.bytes[8] == 1 ? 28 : 20;
        if (mdhd.bytes.length < timescaleOffset + 4) _invalid();
        final timescale = mdhd.data.getUint32(timescaleOffset);
        final handler = metadata.singleWhere((b) => b.type == 'hdlr');
        if (handler.bytes.length < 20 || timescale == 0) _invalid();
        final type = String.fromCharCodes(handler.bytes.sublist(16, 20));
        final startUs = type == 'vide'
            ? timing.videoStartUs
            : timing.audioStartUs;
        if (startUs < 0) _invalid();
        decodeTimes[track] =
            startUs * timescale ~/ Duration.microsecondsPerSecond;
      }
    }
    for (final mvex in _boxes(moov.bytes, 8).where((b) => b.type == 'mvex')) {
      for (final trex in _boxes(mvex.bytes, 8).where((b) => b.type == 'trex')) {
        if (trex.bytes.length < 32) _invalid();
        defaults[trex.data.getUint32(12)] = trex.data.getUint32(20);
      }
    }
  }
  final init = BytesBuilder(copy: false);
  final media = BytesBuilder(copy: false);
  for (var i = 0; i < boxes.length; i++) {
    final box = boxes[i];
    if (i < split) {
      init.add(box.bytes);
    } else {
      media.add(
        box.type == 'moof' ? _fragment(box, defaults, decodeTimes) : box.bytes,
      );
    }
  }
  return (init.takeBytes(), media.takeBytes());
}

Uint8List _fragment(_Box moof, Map<int, int> defaults, Map<int, int> times) {
  final children = _boxes(moof.bytes, 8);
  final rewritten = <Uint8List>[];
  for (final child in children) {
    if (child.type != 'traf') {
      rewritten.add(child.bytes);
      continue;
    }
    final parts = _boxes(child.bytes, 8);
    final headers = parts.where((b) => b.type == 'tfhd').toList();
    if (headers.length != 1) _invalid();
    final tfhd = headers.single;
    if (tfhd.bytes.length < 16) _invalid();
    final flags = tfhd.data.getUint32(8);
    final track = tfhd.data.getUint32(12);
    final hasBase = flags & 1 != 0;
    if (hasBase && tfhd.bytes.length < 24) _invalid();
    var cursor = hasBase ? 24 : 16;
    if (flags & 2 != 0) cursor += 4;
    var duration = defaults[track] ?? 0;
    if (flags & 8 != 0) {
      if (cursor + 4 > tfhd.bytes.length) _invalid();
      duration = tfhd.data.getUint32(cursor);
    }
    final header = Uint8List.fromList([
      ...tfhd.bytes.take(16),
      ...tfhd.bytes.skip(hasBase ? 24 : 16),
    ]);
    final data = ByteData.sublistView(header);
    data.setUint32(0, header.length);
    data.setUint32(8, (flags & ~1) | 0x020000);
    final tfdt = Uint8List(20);
    final time = ByteData.sublistView(tfdt);
    time.setUint32(0, 20);
    tfdt.setRange(4, 8, 'tfdt'.codeUnits);
    time.setUint32(8, 0x01000000);
    time.setUint64(12, times[track] ?? 0);
    var total = 0;
    for (final run in parts.where((b) => b.type == 'trun')) {
      total += _runDuration(run, duration);
    }
    times[track] = (times[track] ?? 0) + total;
    rewritten.add(
      _container('traf', [
        header,
        tfdt,
        for (final part in parts)
          if (part.type != 'tfhd' && part.type != 'tfdt') part.bytes,
      ]),
    );
  }
  final result = _container('moof', rewritten);
  final delta = result.length - moof.bytes.length;
  // tfhd/tfdt 改变 moof 大小；所有 trun 的样本地址必须一并调整。
  for (final traf in _boxes(result, 8).where((b) => b.type == 'traf')) {
    for (final run in _boxes(traf.bytes, 8).where((b) => b.type == 'trun')) {
      if (run.data.getUint32(8) & 1 == 0 || run.bytes.length < 20) _invalid();
      run.data.setInt32(16, run.data.getInt32(16) + delta);
    }
  }
  return result;
}

int _runDuration(_Box run, int defaultDuration) {
  if (run.bytes.length < 16) _invalid();
  final data = run.data;
  final flags = data.getUint32(8);
  final count = data.getUint32(12);
  var cursor = 16;
  if (flags & 1 != 0) cursor += 4;
  if (flags & 4 != 0) cursor += 4;
  final fields = [
    0x100,
    0x200,
    0x400,
    0x800,
  ].where((f) => flags & f != 0).length;
  if (cursor > run.bytes.length ||
      count * fields * 4 > run.bytes.length - cursor) {
    _invalid();
  }
  if (flags & 0x100 == 0) {
    if (defaultDuration <= 0 && count > 0) _invalid();
    return count * defaultDuration;
  }
  var duration = 0;
  for (var i = 0; i < count; i++) {
    duration += data.getUint32(cursor);
    cursor += fields * 4;
  }
  return duration;
}
