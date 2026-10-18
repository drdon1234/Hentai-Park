import 'dart:convert';

import 'localization.dart';
import 'models.dart';

/// 自动诊断仅采集白名单字段与 package:/dart: 代码位置。
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
    'PRIVATE_ADDRESS',
    'CONNECTION',
    'CONNECT_TIMEOUT',
    'RECEIVE_TIMEOUT',
    'SEND_TIMEOUT',
    'RESPONSE_STREAM',
    'NETWORK',
    'CANCELLED',
    'UNKNOWN',
    'JAVA_CRASH',
    'NATIVE_CRASH',
    'ANR',
    'LOW_MEMORY',
    'SIGNALED',
    'EXIT_SELF',
    'EXCESSIVE_RESOURCE',
    'USER_REQUESTED',
    'USER_STOPPED',
    'DEPENDENCY_DIED',
    'INITIALIZATION_FAILURE',
    'PERMISSION_CHANGE',
    'PACKAGE_STATE_CHANGE',
    'PACKAGE_UPDATED',
    'FREEZER',
    'OTHER',
  };

  static final _event = RegExp(r'^[a-z][a-z_]{0,31}$');
  static final _name = RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,63}$');
  static final _host = RegExp(r'^(?:[a-zA-Z0-9-]+\.)*[a-zA-Z0-9-]+$');

  /// Fields describing [error]. A message is kept only as its fixed template;
  /// placeholder values never enter the log.
  static Map<String, String> error(Object error) {
    if (error is! SourceError) return {'type': '${error.runtimeType}'};
    return {
      'code': error.code,
      if (error.status != null) 'status': '${error.status}',
      ...error.diagnostics,
      'message': error.rawMessage,
    };
  }

  /// Keeps whitelisted fields only. Messages must be application or plugin
  /// copy keys, which are static text written by developers.
  static Map<String, String> fields(Map input, {PluginCopy? copy}) {
    String? value(String key) {
      final v = input[key];
      return v is String || v is num ? '$v' : null;
    }

    final event = value('event');
    final site = value('site');
    final action = value('action');
    final code = value('code');
    final status = int.tryParse(value('status') ?? '');
    final reason = value('reason');
    final transport = value('transport');
    final host = value('host');
    final type = value('type')?.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    final library = value('library')?.replaceAll(' ', '_');
    final message = value('message');
    final exitStatus = int.tryParse(value('exitStatus') ?? '');
    return {
      'event': event != null && _event.hasMatch(event) ? event : 'source',
      if (site != null && _name.hasMatch(site)) 'site': site,
      if (action != null && _name.hasMatch(action)) 'action': action,
      if (codes.contains(code)) 'code': code!,
      if (status != null && status >= 100 && status <= 599) 'status': '$status',
      if (reasons.contains(reason)) 'reason': reason!,
      if (transport == 'native' || transport == 'browser')
        'transport': transport!,
      if (host != null && host.length <= 253 && _host.hasMatch(host))
        'host': host,
      if (type != null && type.isNotEmpty && type.length <= 64) 'type': type,
      if (library != null && _name.hasMatch(library)) 'library': library,
      if (exitStatus != null && exitStatus >= 0 && exitStatus <= 255)
        'exitStatus': '$exitStatus',
      if (message != null &&
          message.length <= 200 &&
          (AppLocalizations.instance.hasMessage(message) ||
              (copy?.has(message) ?? false)))
        'message': message,
    };
  }

  static String format(Map<String, String> fields) => fields.entries
      .map(
        (e) => e.key == 'message'
            ? 'message=${jsonEncode(e.value)}'
            : '${e.key}=${e.value}',
      )
      .join(' ');

  static final _frame = RegExp(
    r'^#\d+\s+[A-Za-z0-9_.$<> ]+ \((?:package|dart):[A-Za-z0-9_./-]+\.dart:\d+(?::\d+)?\)$',
  );

  /// Code locations only. Release builds omit columns, so they are optional.
  static List<String> stack(StackTrace? stack) => (stack?.toString() ?? '')
      .split('\n')
      .map((line) => line.trim())
      .where(_frame.hasMatch)
      .map((line) => line.replaceFirst(RegExp(r'\s+'), ' '))
      .take(100)
      .toList();
}
