import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';

import 'domains.dart';

/// 外部文件只能描述 Cookie，不能携带任意文件路径或扩大站点权限。
void validateCookieSnapshot(Object? snapshot, {List<String>? domains}) {
  Never invalid() => throw const FormatException('备份数据无效');
  if (snapshot is! Map) invalid();
  bool hostAllowed(Object? value) =>
      value is String &&
      publicDomainHost(value.replaceFirst(RegExp(r'^\.'), '')) &&
      (domains == null ||
          hostInDomains(value.replaceFirst(RegExp(r'^\.'), ''), domains));

  void paths(Object? data, String host, {required bool shared}) {
    if (data is! Map) invalid();
    for (final path in data.entries) {
      if (path.key is! String ||
          !(path.key as String).startsWith('/') ||
          path.value is! Map) {
        invalid();
      }
      for (final entry in (path.value as Map).entries) {
        if (entry.key is! String || entry.value is! String) invalid();
        try {
          final stored = SerializableCookie.fromJson(entry.value as String);
          final cookie = stored.cookie;
          final domain = cookie.domain?.replaceFirst(RegExp(r'^\.'), '');
          if (stored.createTimeStamp < 0 ||
              cookie.name != entry.key ||
              (cookie.path ?? '/') != path.key ||
              (shared
                  ? domain != host.replaceFirst(RegExp(r'^\.'), '')
                  : domain != null)) {
            invalid();
          }
        } catch (_) {
          invalid();
        }
      }
    }
  }

  for (final entry in snapshot.entries) {
    if (entry.key is! String || entry.value is! String) invalid();
    // FileStorage 的固定目录；统一分隔符以便跨平台恢复。
    final segments = (entry.key as String).split('/');
    if (segments.length != 2 || segments.first != 'ie0_ps1') invalid();
    final name = segments.last;
    Object? data;
    try {
      data = jsonDecode(entry.value as String);
    } catch (_) {
      invalid();
    }
    if (name == '.index') {
      if (data is! List || data.any((host) => !hostAllowed(host))) invalid();
      for (final host in data) {
        if (!snapshot.containsKey('ie0_ps1/$host')) invalid();
      }
    } else if (name == '.domains') {
      if (data is! Map) invalid();
      for (final domain in data.entries) {
        if (!hostAllowed(domain.key)) invalid();
        paths(domain.value, domain.key as String, shared: true);
      }
    } else {
      if (!hostAllowed(name)) invalid();
      paths(data, name, shared: false);
    }
  }
}
