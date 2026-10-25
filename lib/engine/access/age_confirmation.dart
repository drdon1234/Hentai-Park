import 'dart:convert';

/// 源声明的年龄门操作及完成条件；只有应用已确认成年时才能执行。
class AgeConfirmationConfig {
  const AgeConfirmationConfig({
    required this.gateSelector,
    required this.readySelector,
    required this.requiredCookies,
    required this.clickSelector,
  });

  final String gateSelector;
  final String readySelector;
  final List<String> requiredCookies;
  final String clickSelector;

  String get signature =>
      jsonEncode([gateSelector, readySelector, requiredCookies, clickSelector]);

  static AgeConfirmationConfig? fromNetwork(Map<String, dynamic> network) {
    final raw = network['confirmation'];
    if (raw is! Map) return null;
    String text(Object? value) => value is String ? value.trim() : '';
    final gate = text(raw['selector']);
    final ready = text(raw['readySelector']);
    final auto = raw['auto'];
    final click = auto is Map ? text(auto['clickSelector']) : '';
    final names = raw['requiredCookies'];
    if (names is! List ||
        names.isEmpty ||
        names.any(
          (value) =>
              value is! String ||
              !RegExp(r'^[!#$%&\x27*+.^_`|~0-9a-zA-Z-]+$').hasMatch(value),
        )) {
      return null;
    }
    final cookies = names.cast<String>().toSet().toList(growable: false);
    if (gate.isEmpty ||
        ready.isEmpty ||
        click.isEmpty ||
        [gate, ready, click].any((value) => value.length > 1024)) {
      return null;
    }
    return AgeConfirmationConfig(
      gateSelector: gate,
      readySelector: ready,
      requiredCookies: cookies,
      clickSelector: click,
    );
  }
}
