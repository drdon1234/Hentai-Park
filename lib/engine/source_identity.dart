import 'dart:convert';

const appPartition = '_app';
final _sourceKey = RegExp(r'^[A-Za-z0-9_-]+$');

bool isSourceKey(Object? key) =>
    key is String &&
    key != appPartition &&
    key.length <= 100 &&
    _sourceKey.stringMatch(key) == key;

/// 可逆的源身份编码：大小写、下划线和短横线均保留区别。
String sourceIdentity(String key) => utf8
    .encode(key)
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

/// 每段不超过 DNS 的 63 字符限制；完整 origin 的长度由安装边界约束。
String sourceHost(String key) {
  final identity = sourceIdentity(key);
  if (identity.isEmpty) return 'probe';
  return [
    for (var offset = 0; offset < identity.length; offset += 60)
      'k${identity.substring(offset, (offset + 60).clamp(0, identity.length))}',
  ].join('.');
}
