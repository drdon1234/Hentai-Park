import '../core/models.dart';
export 'access/challenge.dart';

/// 站点防火墙拒绝当前网络时的统一错误。
SourceError firewallBlocked(String host, {String? url}) => SourceError(
  'BLOCKED',
  '站点拒绝了当前网络的访问，请更换网络或代理后重试',
  url: url,
  diagnostics: {'host': host, 'reason': 'FIREWALL_BLOCKED'},
);
