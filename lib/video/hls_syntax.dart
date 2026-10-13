import '../core/models.dart';

List<String> hlsLines(String text) {
  final lines = text
      .replaceFirst('\uFEFF', '')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty || lines.first != '#EXTM3U') {
    throw SourceError('NETWORK', 'HLS 分段不完整');
  }
  return lines;
}

Map<String, String> hlsAttributes(String text) {
  final result = <String, String>{};
  var end = 0;
  for (final match in RegExp(
    r'([A-Z0-9-]+)=("[^"]*"|[^,"\s]+)(?:,|$)',
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
  if (end != text.length || result.isEmpty || text.endsWith(',')) {
    throw SourceError('NETWORK', 'HLS 加密清单无效');
  }
  return result;
}
