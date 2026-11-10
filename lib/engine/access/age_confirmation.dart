import 'dart:convert';

/// 源声明的年龄门操作及完成条件；只有应用已确认成年时才能执行。
class AgeConfirmationConfig {
  const AgeConfirmationConfig({
    required this.gateSelector,
    required this.readySelector,
    required this.requiredCookies,
    required this.clickSelector,
    this.checkSelector = '',
    this.questionnaire,
    this.birthDate,
  });

  final String gateSelector;
  final String readySelector;
  final List<String> requiredCookies;
  final String clickSelector;
  final String checkSelector;
  final Map<String, Object?>? questionnaire;
  final Map<String, String>? birthDate;

  String get signature => jsonEncode([
    gateSelector,
    readySelector,
    requiredCookies,
    clickSelector,
    checkSelector,
    questionnaire,
    birthDate,
  ]);

  static AgeConfirmationConfig? fromNetwork(Map<String, dynamic> network) {
    final raw = network['confirmation'];
    if (raw is! Map) return null;
    String text(Object? value) => value is String ? value.trim() : '';
    final gate = text(raw['selector']);
    final ready = text(raw['readySelector']);
    final auto = raw['auto'];
    final click = auto is Map ? text(auto['clickSelector']) : '';
    final check = auto is Map ? text(auto['checkSelector']) : '';
    Map<String, Object?>? questionnaire;
    Map<String, String>? birthDate;
    if (auto is Map && auto['questionnaire'] != null) {
      final rawQuestions = auto['questionnaire'];
      if (rawQuestions is! Map) return null;
      final rows = text(rawQuestions['rowSelector']);
      final submit = text(rawQuestions['submitSelector']);
      final answers = rawQuestions['answers'];
      if (rows.isEmpty ||
          rows.length > 1024 ||
          submit.isEmpty ||
          submit.length > 1024 ||
          answers is! List ||
          answers.isEmpty ||
          answers.length > 256) {
        return null;
      }
      final questions = <String>{};
      final clean = <Map<String, String>>[];
      for (final entry in answers) {
        if (entry is! Map) return null;
        final question = text(entry['question'])
            .replaceAll(RegExp(r'\s+'), ' ');
        final answer = text(entry['answer']).replaceAll(RegExp(r'\s+'), ' ');
        if (question.isEmpty ||
            question.length > 2048 ||
            answer.isEmpty ||
            answer.length > 1024 ||
            !questions.add(question)) {
          return null;
        }
        clean.add({'question': question, 'answer': answer});
      }
      questionnaire = {
        'rowSelector': rows,
        'submitSelector': submit,
        'answers': clean,
      };
    }
    if (auto is Map && auto['birthDate'] != null) {
      final rawDate = auto['birthDate'];
      if (rawDate is! Map || questionnaire != null) return null;
      final single = text(rawDate['dateSelector']);
      final year = text(rawDate['yearSelector']);
      final month = text(rawDate['monthSelector']);
      final day = text(rawDate['daySelector']);
      final separate = [year, month, day];
      if (single.isNotEmpty) {
        if (single.length > 1024 || separate.any((value) => value.isNotEmpty)) {
          return null;
        }
        birthDate = {'dateSelector': single};
      } else {
        if (separate.any((value) => value.isEmpty || value.length > 1024) ||
            separate.toSet().length != 3) {
          return null;
        }
        birthDate = {
          'yearSelector': year,
          'monthSelector': month,
          'daySelector': day,
        };
      }
    }
    if (auto is Map &&
        auto['checkSelector'] != null &&
        (auto['checkSelector'] is! String || check.isEmpty)) {
      return null;
    }
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
        [gate, ready, click, check].any((value) => value.length > 1024)) {
      return null;
    }
    return AgeConfirmationConfig(
      gateSelector: gate,
      readySelector: ready,
      requiredCookies: cookies,
      clickSelector: click,
      checkSelector: check,
      questionnaire: questionnaire,
      birthDate: birthDate,
    );
  }
}
