/// 原生 WebView 与服务端浏览器共同实现的最小能力边界。
abstract interface class BrowserInteractionHost {
  bool get supportsCdp;
  bool get supportsNativeInput;
  Future<dynamic> javascript({
    required String body,
    required Map<String, dynamic> arguments,
  });
  Future<dynamic> evaluate(String source);
  Future<dynamic> cdp(String method, Map<String, dynamic> parameters);
  Future<bool> nativeClick({required String url, required String token});
}
