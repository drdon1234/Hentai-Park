import 'package:pub_semver/pub_semver.dart';

final _releaseVersion = RegExp(
  r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
);

bool isReleaseVersion(Object? value) {
  if (value is! String || _releaseVersion.stringMatch(value) != value) {
    return false;
  }
  try {
    Version.parse(value);
    return true;
  } on FormatException {
    return false;
  }
}

Version parseReleaseVersion(String value) {
  if (!isReleaseVersion(value)) throw const FormatException('版本格式无效');
  return Version.parse(value);
}

int compareReleaseVersions(String a, String b) =>
    parseReleaseVersion(a).compareTo(parseReleaseVersion(b));
