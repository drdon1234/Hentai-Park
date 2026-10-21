import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

import '../core/models.dart';
import '../core/versions.dart';

/// 插件与宿主之间的安装契约，版本取自当前安装包。
abstract final class SourceCompatibility {
  static const apiVersion = 2;

  static Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  static bool supports(String current, String minimum) =>
      Version.parse(current).compareTo(parseReleaseVersion(minimum)) >= 0;

  static void validate(Map<String, dynamic> manifest, String current) {
    if (manifest['apiVersion'] != apiVersion) {
      throw SourceError('UNSUPPORTED', '此站点需要更新应用后才能更新');
    }
    final minimum = manifest['minAppVersion'];
    if (!isReleaseVersion(minimum)) {
      throw SourceError('CONFIG', '插件缺少有效的最低应用版本声明');
    }
    if (!supports(current, minimum as String)) {
      throw SourceError(
        'UNSUPPORTED',
        '此插件需要 HentaiPark {version} 或更高版本',
        params: {'version': minimum},
      );
    }
  }
}
