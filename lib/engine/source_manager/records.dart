part of '../source_manager.dart';

/// Installed source plugin and its runtime state.
class InstalledSource {
  InstalledSource({
    required this.key,
    required this.origin,
    required this.version,
    this.url = '',
    this.enabled = true,
    this.order = 0,
    this.sha256 = '',
  });

  final String key;
  String origin; // builtin | official | url
  String version;
  String url;
  bool enabled;
  int order;

  /// SHA-256 of the installed script (shown to the user; empty for sources installed by older versions).
  String sha256;
  SourceManifest? manifest;

  /// Why the source could not be read, if it could not.
  SourceError? loadFailure;
  String? get loadError => loadFailure?.message;

  /// Last known account state; it changes only when the account is checked, never on every call.
  final accountListenable = ValueNotifier<AccountStatus?>(null);
  AccountStatus? get account => accountListenable.value;

  Map<String, dynamic> toJson() => {
    'key': key,
    'origin': origin,
    'version': version,
    'url': url,
    'enabled': enabled,
    'order': order,
    'sha256': sha256,
  };

  factory InstalledSource.fromJson(Map<String, dynamic> j) => InstalledSource(
    key: j['key'].toString(),
    origin: (j['origin'] ?? 'builtin').toString(),
    version: (j['version'] ?? '0.0.0').toString(),
    url: (j['url'] ?? '').toString(),
    enabled: j['enabled'] != false,
    order: (j['order'] as num?)?.toInt() ?? 0,
    sha256: (j['sha256'] ?? '').toString(),
  );

  String get name => manifest?.name ?? key;
  bool get ready => manifest != null && loadError == null;
}

class RepoEntry {
  RepoEntry(this.json, this.baseUrl);
  final Map<String, dynamic> json;
  final String baseUrl;
  String get key => json['key'].toString();
  String get name => (json['name'] ?? key).toString();
  String get version => (json['version'] ?? '0.0.0').toString();
  String get description => (json['description'] ?? '').toString();

  /// Optional checksum published by the repository; when present the download must match it.
  String? get sha256 => (json['sha256'] as String?)?.toLowerCase();
  String get url {
    final u = (json['url'] ?? json['file'] ?? '').toString();
    return u.startsWith('http') ? u : Uri.parse(baseUrl).resolve(u).toString();
  }
}

String sha256Hex(String text) =>
    crypto.sha256.convert(utf8.encode(text)).toString();

/// UTF-8 decoding normally drops a BOM; scripts must round-trip to their published bytes.
String decodeSourceScript(List<int> bytes) {
  final text = utf8.decode(bytes);
  final hasBom =
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  return hasBom ? '\uFEFF$text' : text;
}

/// What installing a script would do, shown to the user before anything is written.
class InstallPreview {
  InstallPreview({
    required this.code,
    required this.url,
    required this.key,
    required this.manifest,
    required this.sha256,
    required this.domains,
    required this.warnings,
    this.existing,
  });
  final String code;
  final String url;
  final String key;
  final SourceManifest manifest;
  final String sha256;
  final List<String> domains;
  final List<String> warnings;
  final InstalledSource? existing;
}
