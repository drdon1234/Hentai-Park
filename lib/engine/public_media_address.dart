import 'dart:io';

import '../core/models.dart';

/// Reject non-public addresses, including IPv4-mapped IPv6; direct connections use checked IPs.
bool isPublicMediaAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length == 16) {
    if (bytes.take(10).every((b) => b == 0) &&
        bytes[10] == 255 &&
        bytes[11] == 255) {
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
      !(a == 198 && (b == 18 || b == 19 || (b == 51 && bytes[2] == 100))) &&
      !(a == 203 && b == 0 && bytes[2] == 113);
}

Future<List<InternetAddress>> publicMediaAddresses(String host) async {
  final addresses = await InternetAddress.lookup(host)
      .timeout(const Duration(seconds: 15));
  if (addresses.isEmpty ||
      addresses.any((address) => !isPublicMediaAddress(address))) {
    throw SourceError('CONFIG', '媒体地址不在站点声明的 HTTPS 域名内');
  }
  return addresses;
}
