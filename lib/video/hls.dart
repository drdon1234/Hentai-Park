import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../core/models.dart';

class HlsSegment {
  const HlsSegment(
    this.url,
    this.duration, {
    this.key,
    this.iv,
    required this.sequence,
  });
  final Uri url;
  final double duration;
  final Uri? key;
  final Uint8List? iv;
  final BigInt sequence;
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
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            false,
            PaddedBlockCipherParameters(
              ParametersWithIV(KeyParameter(key), iv),
              null,
            ),
          );
    return cipher.process(encrypted);
  } catch (_) {
    throw SourceError('NETWORK', 'HLS 加密分段解密失败');
  }
}

/// The supported download/playback format is a finite, continuous MPEG-TS VOD.
class HlsPlaylist {
  HlsPlaylist._(this.lines, this.segments);
  final List<String> lines;
  final List<HlsSegment> segments;
  double get duration => segments.fold(0, (sum, s) => sum + s.duration);

  static HlsPlaylist parse(String text, Uri base) {
    final lines = text
        .replaceFirst('\uFEFF', '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty ||
        lines.first != '#EXTM3U' ||
        !lines.contains('#EXT-X-ENDLIST')) {
      throw SourceError('UNSUPPORTED', '只支持完整的 HLS 点播清单');
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
    for (final line in lines) {
      if (ended) throw SourceError('UNSUPPORTED', 'HLS 结束标签后包含数据');
      if (line.startsWith('#EXT-X-TOKEN:')) continue;
      if (line.startsWith('#EXT-X-KEY:')) {
        final attributes = _attributes(line.substring('#EXT-X-KEY:'.length));
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
      // Tags with their own URI would bypass the local segment registry.
      if (line.startsWith('#EXT') &&
          RegExp(r'\bURI\s*=', caseSensitive: false).hasMatch(line)) {
        throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
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
          ),
        );
        sequence += BigInt.one;
        duration = null;
        if (segments.length > 30000) {
          throw SourceError('UNSUPPORTED', 'HLS 分段数量过多');
        }
      }
      if (line == '#EXT-X-ENDLIST') ended = true;
      clean.add(line);
    }
    if (duration != null || segments.isEmpty) {
      throw SourceError('NETWORK', 'HLS 分段不完整');
    }
    return HlsPlaylist._(List.unmodifiable(clean), List.unmodifiable(segments));
  }

  String rewrite(String Function(HlsSegment) register) {
    var index = 0;
    final output = <String>[];
    for (final line in lines) {
      if (line.startsWith('#EXT-X-KEY:')) continue;
      output.add(line.startsWith('#') ? line : register(segments[index++]));
    }
    return '${output.join('\n')}\n';
  }
}

Map<String, String> _attributes(String text) {
  final result = <String, String>{};
  var end = 0;
  for (final match in RegExp(
    r'([A-Z0-9-]+)=("[^"]*"|[^,]*)(?:,|$)',
  ).allMatches(text)) {
    if (match.start != end || result.containsKey(match[1])) {
      throw SourceError('NETWORK', 'HLS 加密清单无效');
    }
    final value = match[2]!;
    result[match[1]!] = value.startsWith('"')
        ? value.substring(1, value.length - 1)
        : value;
    end = match.end;
  }
  if (end != text.length || result.isEmpty) {
    throw SourceError('NETWORK', 'HLS 加密清单无效');
  }
  return result;
}

void validateTransportStream(Uint8List bytes) {
  if (bytes.length < 188 * 2 || bytes.length % 188 != 0) {
    throw SourceError('NETWORK', '媒体分段不是完整的 MPEG-TS');
  }
  for (var i = 0; i < bytes.length; i += 188) {
    if (bytes[i] != 0x47) throw SourceError('NETWORK', '媒体分段已损坏');
  }
}
