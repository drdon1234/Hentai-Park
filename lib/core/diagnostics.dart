import 'models.dart';

/// 自动日志仅接受白名单，不尝试从任意异常全文猜测哪些部分是秘密。
class Diagnostics {
  static const codes = {
    'NETWORK',
    'TIMEOUT',
    'AUTH',
    'PARSE',
    'CONFIG',
    'UNSUPPORTED',
    'HTTP',
    'CANCELLED',
    'UNKNOWN',
    'CLOUDFLARE',
    'CONFIRM_REQUIRED',
    'LOGIN_REQUIRED',
    'NOT_FOUND',
    'BLOCKED',
  };
  static const reasons = {
    'TLS_CERTIFICATE',
    'TLS_HANDSHAKE_TERMINATED',
    'TLS_HANDSHAKE',
    'DNS',
    'CONNECTION',
    'CONNECT_TIMEOUT',
    'RECEIVE_TIMEOUT',
    'SEND_TIMEOUT',
    'RESPONSE_STREAM',
    'NETWORK',
    'CANCELLED',
    'UNKNOWN',
  };
  static String error(Object error) {
    if (error is! SourceError) {
      return 'event=error type=${error.runtimeType.toString().replaceAll(RegExp(r"[^A-Za-z0-9_]"), '')}';
    }
    return event({'code': error.code, ...error.diagnostics});
  }

  static String event(Map fields) {
    final result = <String>['event=source'];
    if (codes.contains(fields['code'])) result.add('code=${fields['code']}');
    if ({'native', 'browser'}.contains(fields['transport'])) {
      result.add('transport=${fields['transport']}');
    }
    if (reasons.contains(fields['reason'])) {
      result.add('reason=${fields['reason']}');
    }
    final host = fields['host'];
    if (host is String &&
        host.length <= 253 &&
        RegExp(r'^(?:[a-zA-Z0-9-]+\.)*[a-zA-Z0-9-]+$').hasMatch(host)) {
      result.add('host=$host');
    }
    return result.join(' ');
  }

  static String message(Object? value) {
    if (value is Map) return event(value);
    final text = value?.toString() ?? '';
    // 重复净化时保留本模块生成的结构化字段；不保留任意自由文本。
    if (RegExp(r'^event=error type=[A-Za-z0-9_]+$').hasMatch(text)) return text;
    if (text.startsWith('event=source')) {
      final fields = <String, String>{};
      for (final token in text.split(' ').skip(1)) {
        final parts = token.split('=');
        if (parts.length == 2) fields[parts[0]] = parts[1];
      }
      return event(fields);
    }
    return 'event=message';
  }

  static String stack(StackTrace? stack) => (stack?.toString() ?? '')
      .split('\n')
      .where(
        (line) => RegExp(
          r'^#\d+\s+[A-Za-z0-9_.$<> ]+ \(package:[A-Za-z0-9_./-]+\.dart:\d+:\d+\)$',
        ).hasMatch(line),
      )
      .take(30)
      .join('\n');
}
