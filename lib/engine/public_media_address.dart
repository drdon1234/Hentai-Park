import 'dart:async';
import 'dart:io';

import '../core/app_log.dart';
import '../core/models.dart';

/// Reject non-public addresses, including IPv4-mapped IPv6; direct connections use checked IPs.
/// 198.18.0.0/15 and 2001:2::/48 are accepted: reserved for benchmarking, never assigned
/// to LAN hosts, and Clash, sing-box and Surge map domains into it in fake-ip
/// mode. The system VPN routes those connections by domain, and TLS still
/// verifies the original host name.
/// RFC 6052 (64:ff9b::/96) and RFC 8215 (64:ff9b:1::/48) NAT64 addresses are
/// accepted when their embedded 32-bit IPv4 suffix is itself public.
bool isPublicMediaAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length == 16) {
    if (bytes[0] == 0x20 &&
        bytes[1] == 1 &&
        bytes[2] == 0 &&
        bytes[3] == 2 &&
        bytes[4] == 0 &&
        bytes[5] == 0) {
      return true;
    }
    if (bytes.take(10).every((b) => b == 0) &&
        bytes[10] == 255 &&
        bytes[11] == 255) {
      return isPublicMediaAddress(
        InternetAddress.fromRawAddress(bytes.sublist(12)),
      );
    }
    // NAT64 well-known prefix 64:ff9b::/96 (RFC 6052) and 64:ff9b:1::/48 (RFC 8215).
    final isRfc6052 =
        bytes[0] == 0x00 &&
        bytes[1] == 0x64 &&
        bytes[2] == 0xff &&
        bytes[3] == 0x9b &&
        bytes.skip(4).take(8).every((b) => b == 0);
    final isRfc8215 =
        bytes[0] == 0x00 &&
        bytes[1] == 0x64 &&
        bytes[2] == 0xff &&
        bytes[3] == 0x9b &&
        bytes[4] == 0x00 &&
        bytes[5] == 0x01;
    if (isRfc6052 || isRfc8215) {
      return isPublicMediaAddress(
        InternetAddress.fromRawAddress(bytes.sublist(12)),
      );
    }
    // Only global unicast, excluding documentation and special-purpose prefixes.
    return (bytes[0] & 0xe0) == 0x20 &&
        !(bytes[0] == 0x20 && bytes[1] == 1 && bytes[2] < 2) &&
        !(bytes[0] == 0x20 &&
            bytes[1] == 1 &&
            bytes[2] == 0x0d &&
            bytes[3] == 0xb8) &&
        !(bytes[0] == 0x20 && bytes[1] == 2);
  }
  final a = bytes[0], b = bytes[1];
  return a != 0 &&
      a != 10 &&
      a != 127 &&
      a < 224 &&
      !(a == 100 && b >= 64 && b <= 127) &&
      !(a == 169 && b == 254) &&
      !(a == 172 && b >= 16 && b <= 31) &&
      !(a == 192 && (b == 168 || b == 0 || b == 2)) &&
      !(a == 198 && b == 51 && bytes[2] == 100) &&
      !(a == 203 && b == 0 && bytes[2] == 113);
}

/// 被拒绝地址所属的范围类别，只记录类别、不记录地址本身。
String _addressRange(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length == 16) {
    if (bytes.take(10).every((b) => b == 0) &&
        bytes[10] == 255 &&
        bytes[11] == 255) {
      return _addressRange(InternetAddress.fromRawAddress(bytes.sublist(12)));
    }
    if (bytes.every((b) => b == 0)) return 'unspecified';
    if (address.isLoopback) return 'loopback';
    if ((bytes[0] & 0xfe) == 0xfc) return 'unique_local';
    if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return 'link_local';
    if (bytes[0] == 0xff) return 'multicast';
    return 'reserved';
  }
  final a = bytes[0], b = bytes[1];
  if (a == 0) return 'unspecified';
  if (a == 127) return 'loopback';
  if (a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168)) {
    return 'private';
  }
  if (a == 100 && b >= 64 && b <= 127) return 'shared';
  if (a == 169 && b == 254) return 'link_local';
  if (a >= 224 && a < 240) return 'multicast';
  return 'reserved';
}

final _reportedRanges = <String>{};

/// 只连接公网地址。解析结果混有内网或保留地址时（如代理应用在虚拟地址之外
/// 另给出 IPv6 本地地址），丢弃这些记录并使用其余公网地址；全部不可用才拒绝。
Future<List<InternetAddress>> publicMediaAddresses(String host) async {
  final addresses = await InternetAddress.lookup(host)
      .timeout(const Duration(seconds: 15));
  return filterPublicMediaAddresses(host, addresses);
}

List<InternetAddress> filterPublicMediaAddresses(
  String host,
  Iterable<InternetAddress> addresses,
) {
  final public = <InternetAddress>[];
  final rejected = <String>{};
  for (final address in addresses) {
    if (isPublicMediaAddress(address)) {
      public.add(address);
    } else {
      rejected.add(_addressRange(address));
    }
  }
  final range = (rejected.toList()..sort()).join('+');
  if (public.isEmpty) {
    throw SourceError(
      'CONFIG',
      '媒体主机解析到了内网或保留地址，已拒绝连接',
      diagnostics: {
        'host': host,
        'transport': 'native',
        'reason': 'PRIVATE_ADDRESS',
        if (range.isNotEmpty) 'range': range,
      },
    );
  }
  if (range.isNotEmpty && _reportedRanges.add('$host $range')) {
    if (_reportedRanges.length > 128) {
      _reportedRanges.remove(_reportedRanges.first);
    }
    AppLog.record({
      'event': 'media',
      'action': 'resolve',
      'host': host,
      'transport': 'native',
      'reason': 'PRIVATE_ADDRESS',
      'range': range,
      'outcome': 'success',
    });
  }
  return public;
}

/// Connects to checked public media addresses with sequential fallback across
/// resolved records (e.g. broken IPv6 falling back to IPv4) while preserving
/// original host SNI and TLS verification.
Future<ConnectionTask<Socket>> connectPublicMediaSocket(Uri uri) async {
  final addresses = await publicMediaAddresses(uri.host);
  var cancelled = false;
  ConnectionTask<Socket>? activeTask;
  Socket? connected;

  Future<Socket> connectAny() async {
    Object? lastError;
    for (var i = 0; i < addresses.length; i++) {
      if (cancelled) {
        throw const SocketException('Media connection cancelled');
      }
      final isLast = i == addresses.length - 1;
      try {
        final task = await Socket.startConnect(addresses[i], uri.port);
        activeTask = task;
        if (cancelled) {
          task.cancel();
          throw const SocketException('Media connection cancelled');
        }
        final socket = isLast
            ? await task.socket
            : await task.socket.timeout(
                const Duration(seconds: 4),
                onTimeout: () {
                  task.cancel();
                  throw TimeoutException('Media address fallback timeout');
                },
              );
        connected = socket;
        if (cancelled) {
          socket.destroy();
          throw const SocketException('Media connection cancelled');
        }
        if (uri.scheme != 'https') return socket;
        try {
          final secure = await SecureSocket.secure(socket, host: uri.host);
          connected = secure;
          if (cancelled) {
            secure.destroy();
            throw const SocketException('Media connection cancelled');
          }
          return secure;
        } catch (_) {
          socket.destroy();
          connected = null;
          rethrow;
        }
      } catch (error) {
        lastError = error;
        if (cancelled || isLast) rethrow;
      }
    }
    throw lastError ?? const SocketException('No public media address');
  }

  return ConnectionTask.fromSocket(connectAny(), () {
    cancelled = true;
    activeTask?.cancel();
    connected?.destroy();
  });
}
