import '../core/models.dart';
import 'domains.dart';

/// 插件只声明上传与结果条件，不能向远端浏览器注入任意脚本。
class BrowserImageSearchRequest {
  BrowserImageSearchRequest._(
    this.url,
    this.domains,
    this.uploadUrl,
    this.fileField,
    this.resultPath,
    this.resultQuery,
    this.resultParams,
    this.resultSelector,
    this.emptySelector,
    this.emptyText,
  );

  factory BrowserImageSearchRequest.fromJson(
    Map<String, dynamic> json, {
    required List<String> domains,
  }) {
    String text(String key, {int max = 1024}) {
      final value = json[key];
      if (value is! String || value.isEmpty || value.length > max) {
        throw SourceError('CONFIG', '浏览器反搜参数无效');
      }
      return value;
    }

    final url = Uri.tryParse(text('url', max: 8192));
    final uploadUrl = Uri.tryParse(text('uploadUrl', max: 8192));
    final fileField = text('fileField', max: 100);
    final path = text('resultPath');
    final query = text('resultQuery', max: 100);
    final params = json['resultParams'];
    if (url == null ||
        uploadUrl == null ||
        !loginNavigationAllowed(uploadUrl, domains) ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(fileField) ||
        !loginNavigationAllowed(url, domains) ||
        !path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains(RegExp(r'[?#\s]')) ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(query) ||
        params is! Map ||
        params.length > 8 ||
        params.entries.any(
          (entry) =>
              entry.key is! String ||
              !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(entry.key) ||
              entry.value is! String ||
              (entry.value as String).length > 256,
        )) {
      throw SourceError('CONFIG', '浏览器反搜参数无效');
    }
    return BrowserImageSearchRequest._(
      url,
      List.unmodifiable(domains),
      uploadUrl,
      fileField,
      path,
      query,
      Map<String, String>.unmodifiable(params.cast<String, String>()),
      text('resultSelector'),
      text('emptySelector'),
      text('emptyText', max: 256),
    );
  }

  final Uri url;
  final Uri uploadUrl;
  final List<String> domains;
  final String fileField, resultPath, resultQuery;
  final Map<String, String> resultParams;
  final String resultSelector, emptySelector, emptyText;

  bool allows(Uri uri) => loginNavigationAllowed(uri, domains);

  bool isResult(Uri uri) =>
      allows(uri) &&
      uri.path == resultPath &&
      (uri.queryParameters[resultQuery]?.isNotEmpty ?? false);

  Uri resultUrl(Uri uri) {
    if (!isResult(uri)) {
      throw SourceError('CONFIG', '浏览器反搜参数无效');
    }
    return uri.replace(
      queryParameters: {...uri.queryParameters, ...resultParams},
    );
  }
}

class BrowserImageSearchResult {
  const BrowserImageSearchResult(this.url, this.html);
  final String url, html;
  Map<String, dynamic> toJson() => {'url': url, 'html': html};
}

typedef BrowserImageSearch = Future<BrowserImageSearchResult?> Function(
  BrowserImageSearchRequest request,
);
