import 'block_rule.dart';
import 'tag_translations.dart';
import 'translation_options.dart';
import 'translator.dart';

class BlockCandidate {
  const BlockCandidate(this.text, {this.source = '', this.namespace = ''});
  final String text;
  final String source;
  final String namespace;
}

class BlockSuggestions {
  const BlockSuggestions(this.candidates, this.failedLanguages);
  final List<BlockCandidate> candidates;
  final int failedLanguages;
}

/// 翻译和词包只产生候选，确认后才保存；匹配本身始终同步、离线。
class BlockSuggestionService {
  BlockSuggestionService({
    Future<KeywordTranslation> Function(String, Iterable<String>)? translate,
    Future<List<BlockCandidate>> Function(BlockRule)? dictionary,
  }) : _translate =
           translate ??
           ((text, targets) => Translator.instance.translateAll(text, targets)),
       _dictionary = dictionary ?? _dictionaryCandidates;

  final Future<KeywordTranslation> Function(String, Iterable<String>)
  _translate;
  final Future<List<BlockCandidate>> Function(BlockRule) _dictionary;

  Future<BlockSuggestions> suggest(String entry) async {
    final rule = BlockRule(entry);
    if (!rule.translatable) return const BlockSuggestions([], 0);
    final candidates = <BlockCandidate>[];
    try {
      candidates.addAll(await _dictionary(rule));
    } catch (_) {
      // 单个本地词包不可读时仍可使用原词与在线候选。
    }
    var failures = translateLanguages.length;
    try {
      final result = await _translate(rule.text, translateLanguages.keys);
      failures -= result.translations.keys
          .where(translateLanguages.containsKey)
          .length;
      candidates.addAll(
        result.translations.values.map((text) => BlockCandidate(text)),
      );
    } catch (_) {
      // 失败状态交给编辑器展示；不改变现有规则。
    }
    final seen = <String>{rule.text.toLowerCase()};
    return BlockSuggestions([
      for (final candidate in candidates)
        if (candidate.text.trim().isNotEmpty &&
            candidate.text.trim().toLowerCase() != rule.text.toLowerCase() &&
            BlockRule(candidate.text).translatable &&
            BlockRule(candidate.text).scope.isEmpty &&
            seen.add(
              '${candidate.source}/${candidate.namespace}/${candidate.text.trim().toLowerCase()}',
            ))
          candidate,
    ], failures);
  }

  static Future<List<BlockCandidate>> _dictionaryCandidates(
    BlockRule rule,
  ) async {
    final values = await TagTranslations.instance.blockCandidates(
      rule.text,
      namespace: rule.title ? '' : rule.scope,
    );
    return [
      for (final value in values)
        BlockCandidate(
          value.text,
          source: value.source,
          namespace: value.namespace,
        ),
    ];
  }
}
