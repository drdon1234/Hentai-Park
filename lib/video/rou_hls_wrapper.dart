import 'dart:io';
import 'dart:typed_data';

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
const _roUd = <int>[0x72, 0x6f, 0x55, 0x64];
const _maxChunkBytes = 64 * 1024 * 1024;

bool isRouHlsWrapped(Uint8List bytes) {
  if (bytes.length < _pngSignature.length) return false;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return false;
  }
  return true;
}

Uint8List unwrapRouHlsIfWrapped(
  Uint8List bytes, {
  int maxBytes = 32 * 1024 * 1024,
}) => isRouHlsWrapped(bytes) ? unwrapRouHls(bytes, maxBytes: maxBytes) : bytes;

Uint8List unwrapRouHls(Uint8List bytes, {int maxBytes = 32 * 1024 * 1024}) {
  if (!isRouHlsWrapped(bytes)) {
    throw const FormatException('rou.video 媒体不是 PNG 封装');
  }
  var offset = _pngSignature.length;
  while (offset + 12 <= bytes.length) {
    final length = _uint32(bytes, offset);
    if (length > _maxChunkBytes || offset + 12 + length > bytes.length) {
      throw const FormatException('rou.video PNG chunk 越界');
    }
    final typeOffset = offset + 4;
    final dataOffset = offset + 8;
    if (_matches(bytes, typeOffset, _roUd)) {
      if (length < 1) throw const FormatException('rou.video roUd chunk 为空');
      final flag = bytes[dataOffset];
      if (flag & ~1 != 0) throw const FormatException('不支持的 PNG 媒体封装标志');
      final payload = Uint8List.sublistView(
        bytes,
        dataOffset + 1,
        dataOffset + length,
      );
      try {
        if (flag & 1 == 0) {
          if (payload.length > maxBytes) throw const FormatException('媒体响应过大');
          return payload;
        }
        final output = _LimitedOutput(maxBytes);
        final input = ZLibDecoder().startChunkedConversion(output);
        input.add(payload);
        input.close();
        return output.bytes.takeBytes();
      } catch (_) {
        throw const FormatException('rou.video roUd 数据解压失败');
      }
    }
    offset += 12 + length;
  }
  throw const FormatException('rou.video PNG 缺少 roUd chunk');
}

class _LimitedOutput implements Sink<List<int>> {
  _LimitedOutput(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw const FormatException('媒体响应过大');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}

int _uint32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

bool _matches(Uint8List bytes, int offset, List<int> expected) {
  if (offset + expected.length > bytes.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (bytes[offset + i] != expected[i]) return false;
  }
  return true;
}
