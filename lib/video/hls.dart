import 'dart:typed_data';

import '../core/crypto.dart';
import '../core/models.dart';
import 'hls_syntax.dart';

enum HlsResourceKind { transportStream, initialization, fragment }

class HlsSegment {
  const HlsSegment(
    this.url,
    this.duration, {
    this.key,
    this.iv,
    this.kind = HlsResourceKind.transportStream,
    required this.sequence,
  });
  final Uri url;
  final double duration;
  final Uri? key;
  final Uint8List? iv;
  final BigInt sequence;
  final HlsResourceKind kind;
  String get extension =>
      kind == HlsResourceKind.transportStream ? 'ts' : 'mp4';
}

Uint8List _sequenceIv(BigInt sequence) {
  final iv = Uint8List(16);
  var value = sequence;
  for (var i = 15; i >= 0; i--) {
    iv[i] = (value & BigInt.from(0xff)).toInt();
    value >>= 8;
  }
  return iv;
}

/// Decrypts an HLS AES-128 segment. HLS uses CBC with PKCS#7 padding for the
/// complete segment payload; malformed ciphertext is rejected before playback
/// or the MP4 muxer sees it.
Uint8List decryptHlsAes128(Uint8List encrypted, Uint8List key, Uint8List iv) {
  if (key.length != 16 ||
      iv.length != 16 ||
      encrypted.isEmpty ||
      encrypted.length % 16 != 0) {
    throw SourceError('NETWORK', 'HLS 加密分段无效');
  }
  try {
    return aesCbcDecrypt(encrypted, key, iv);
  } catch (_) {
    throw SourceError('NETWORK', 'HLS 加密分段解密失败');
  }
}

/// 下载使用完整点播；播放会话可显式允许滚动的 MPEG-TS 直播清单。
class HlsPlaylist {
  HlsPlaylist._(this.lines, this.segments, this.initialization);
  final List<String> lines;
  final List<HlsSegment> segments;
  final HlsSegment? initialization;
  List<HlsSegment> get resources => [?initialization, ...segments];

  static HlsPlaylist parse(String text, Uri base, {bool live = false}) {
    final lines = hlsLines(text);
    if (!live && !lines.contains('#EXT-X-ENDLIST')) {
      throw SourceError('UNSUPPORTED', '只支持完整的 HLS 点播清单');
    }
    if (live) {
      final target = lines
          .where((line) => line.startsWith('#EXT-X-TARGETDURATION:'))
          .toList();
      final duration = target.length == 1
          ? int.tryParse(target.single.substring(22))
          : null;
      if (duration == null ||
          duration < 1 ||
          duration > 3600 ||
          !lines.any((line) => line.startsWith('#EXT-X-MEDIA-SEQUENCE:'))) {
        throw SourceError('NETWORK', 'HLS 直播清单无效');
      }
    }
    final segments = <HlsSegment>[];
    final clean = <String>[];
    double? duration;
    var ended = false;
    var sequence = BigInt.zero;
    final maximumSequence = (BigInt.one << 64) - BigInt.one;
    var hasSequence = false;
    Uri? key;
    Uint8List? iv;
    HlsSegment? initialization;
    for (final line in lines) {
      if (ended) {
        // 部分 CDN 在 ENDLIST 后附时长扩展；它不授权任何附加资源。
        if (RegExp(r'^#EXT-X-TOTAL_DURATION:\d+(?:\.\d+)?$').hasMatch(line)) {
          continue;
        }
        throw SourceError('UNSUPPORTED', 'HLS 结束标签后包含数据');
      }
      if (line.startsWith('#EXT-X-TOKEN:')) continue;
      if (line.startsWith('#EXT-X-KEY:')) {
        final attributes = hlsAttributes(line.substring('#EXT-X-KEY:'.length));
        if (attributes['METHOD'] == 'NONE') {
          if (attributes.length != 1) {
            throw SourceError('NETWORK', 'HLS 加密清单无效');
          }
          key = null;
          iv = null;
        } else {
          if (attributes['METHOD'] != 'AES-128' ||
              attributes.keys.any(
                (name) => !const {
                  'METHOD',
                  'URI',
                  'IV',
                  'KEYFORMAT',
                  'KEYFORMATVERSIONS',
                }.contains(name),
              ) ||
              (attributes['KEYFORMAT'] ?? 'identity') != 'identity' ||
              (attributes['KEYFORMATVERSIONS'] ?? '1') != '1') {
            throw SourceError('UNSUPPORTED', '暂不支持此 HLS 加密方式');
          }
          final address = attributes['URI'];
          if (address == null || address.isEmpty || address.contains(r'{$')) {
            throw SourceError('NETWORK', 'HLS 加密清单无效');
          }
          key = base.resolve(address);
          final explicitIv = attributes['IV'];
          iv = null;
          if (explicitIv != null) {
            if (!RegExp(r'^0[xX][0-9a-fA-F]{1,32}$').hasMatch(explicitIv)) {
              throw SourceError('NETWORK', 'HLS 加密初始化向量无效');
            }
            final hex = explicitIv.substring(2).padLeft(32, '0');
            iv = Uint8List.fromList([
              for (var i = 0; i < hex.length; i += 2)
                int.parse(hex.substring(i, i + 2), radix: 16),
            ]);
          }
        }
        continue;
      }
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        final value = line.substring('#EXT-X-MEDIA-SEQUENCE:'.length);
        if (hasSequence ||
            segments.isNotEmpty ||
            duration != null ||
            !RegExp(r'^\d+$').hasMatch(value)) {
          throw SourceError('NETWORK', 'HLS 分段序号无效');
        }
        final parsed = BigInt.tryParse(value);
        if (parsed == null || parsed > maximumSequence) {
          throw SourceError('NETWORK', 'HLS 分段序号无效');
        }
        sequence = parsed;
        hasSequence = true;
      }
      if (line.startsWith('#EXT-X-MAP:')) {
        final attributes = hlsAttributes(line.substring('#EXT-X-MAP:'.length));
        final address = attributes['URI'];
        // 仅支持完整点播的单个初始化段；范围、动态切换和直播另需独立实现。
        if (live ||
            initialization != null ||
            segments.isNotEmpty ||
            duration != null ||
            attributes.length != 1 ||
            address == null ||
            address.isEmpty ||
            address.contains(r'{$') ||
            (key != null && iv == null)) {
          throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
        }
        initialization = HlsSegment(
          base.resolve(address),
          0,
          sequence: BigInt.zero,
          key: key,
          iv: iv,
          kind: HlsResourceKind.initialization,
        );
        clean.add(line);
        continue;
      }
      // Tags with their own URI would bypass the local segment registry.
      if (line.startsWith('#EXT') &&
          RegExp(r'\bURI\s*=', caseSensitive: false).hasMatch(line)) {
        throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
      }
      if (live &&
          (line == '#EXT-X-DISCONTINUITY' ||
              RegExp(r'^#EXT-X-DISCONTINUITY-SEQUENCE:\d+$').hasMatch(line))) {
        clean.add(line);
        continue;
      }
      if (RegExp(
        r'^#EXT-X-(MAP:|BYTERANGE:|DISCONTINUITY(?:$|:|-)|GAP$|STREAM-INF:|I-FRAMES-ONLY$|PART:|PRELOAD-HINT:)',
      ).hasMatch(line)) {
        throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
      }
      if (line.startsWith('#EXTINF:')) {
        if (duration != null) throw SourceError('NETWORK', 'HLS 分段地址缺失');
        duration = double.tryParse(line.substring(8).split(',').first);
        if (duration == null || !duration.isFinite || duration <= 0) {
          throw SourceError('NETWORK', 'HLS 分段时长无效');
        }
      } else if (!line.startsWith('#')) {
        if (duration == null) throw SourceError('NETWORK', 'HLS 分段时长缺失');
        final url = base.resolve(line);
        if (sequence > maximumSequence) {
          throw SourceError('NETWORK', 'HLS 分段序号无效');
        }
        segments.add(
          HlsSegment(
            url,
            duration,
            key: key,
            iv: key == null
                ? null
                : Uint8List.fromList(iv ?? _sequenceIv(sequence)),
            sequence: sequence,
            kind: initialization == null
                ? HlsResourceKind.transportStream
                : HlsResourceKind.fragment,
          ),
        );
        sequence += BigInt.one;
        duration = null;
        if (segments.length > (live ? 1024 : 30000)) {
          throw SourceError('UNSUPPORTED', 'HLS 分段数量过多');
        }
      }
      if (line == '#EXT-X-ENDLIST') ended = true;
      clean.add(line);
    }
    if (duration != null || segments.isEmpty) {
      throw SourceError('NETWORK', 'HLS 分段不完整');
    }
    return HlsPlaylist._(
      List.unmodifiable(clean),
      List.unmodifiable(segments),
      initialization,
    );
  }

  String rewrite(String Function(HlsSegment) register) {
    var index = 0;
    final output = <String>[];
    for (final line in lines) {
      if (line.startsWith('#EXT-X-KEY:')) continue;
      if (line.startsWith('#EXT-X-MAP:')) {
        output.add('#EXT-X-MAP:URI="${register(initialization!)}"');
        continue;
      }
      output.add(line.startsWith('#') ? line : register(segments[index++]));
    }
    return '${output.join('\n')}\n';
  }
}

/// 检查完整 ISO BMFF 顶层盒，拒绝截断、错误长度和混用的 TS/MP4 资源。
void validateHlsResource(Uint8List bytes, HlsResourceKind kind) {
  if (kind == HlsResourceKind.transportStream) {
    validateTransportStream(bytes);
    return;
  }
  final types = <String>{};
  final data = ByteData.sublistView(bytes);
  var offset = 0;
  while (offset < bytes.length) {
    if (bytes.length - offset < 8) throw SourceError('NETWORK', '媒体分段已损坏');
    var size = data.getUint32(offset);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    var header = 8;
    if (size == 1) {
      if (bytes.length - offset < 16 || data.getUint32(offset + 8) != 0) {
        throw SourceError('NETWORK', '媒体分段已损坏');
      }
      size = data.getUint32(offset + 12);
      header = 16;
    } else if (size == 0) {
      size = bytes.length - offset;
    }
    if (size < header || size > bytes.length - offset) {
      throw SourceError('NETWORK', '媒体分段已损坏');
    }
    types.add(type);
    offset += size;
  }
  final valid = kind == HlsResourceKind.initialization
      ? types.containsAll({'ftyp', 'moov'}) &&
            !types.contains('moof') &&
            !types.contains('mdat')
      : types.containsAll({'moof', 'mdat'}) && !types.contains('moov');
  if (!valid) throw SourceError('NETWORK', '媒体分段已损坏');
}

void validateTransportStream(Uint8List bytes) {
  if (bytes.length < 188 * 2 || bytes.length % 188 != 0) {
    throw SourceError('NETWORK', '媒体分段不是完整的 MPEG-TS');
  }
  for (var i = 0; i < bytes.length; i += 188) {
    if (bytes[i] != 0x47) throw SourceError('NETWORK', '媒体分段已损坏');
  }
}
