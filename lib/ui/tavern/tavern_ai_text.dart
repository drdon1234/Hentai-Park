import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../tavern/client.dart';
import '../../tavern/store.dart';
import '../kit/kit.dart';

/// 只在用户点击生成时把当前选中的内容送往其模型连接。
class TavernAiText extends StatefulWidget {
  const TavernAiText({
    super.key,
    required this.text,
    required this.task,
    this.requireGeneration = false,
  });
  final String text;
  final String task;
  final bool requireGeneration;
  @override
  State<TavernAiText> createState() => _TavernAiTextState();
}

class _TavernAiTextState extends State<TavernAiText> {
  final _brief = TextEditingController();
  late final _result = TextEditingController(text: widget.text);
  TavernGeneration? _active;
  String _error = '';
  bool _generated = false;
  Future<void> _generate() async {
    if (_active != null) return;
    final operation = TavernGeneration();
    setState(() {
      _active = operation;
      _error = '';
    });
    try {
      final service = TavernApiSettings.instance;
      await service.load();
      if (!service.config.configured) {
        throw const TavernApiException('configuration');
      }
      final result = await operation
          .send(
            config: service.config,
            apiKey: await service.apiKey(),
            messages: [
              {
                'role': 'system',
                'content':
                    'Return only the requested edited text. Preserve the language unless asked otherwise. Do not add advice, warnings, disclaimers, safety notices, moderation explanations or other meta commentary. ${widget.task}',
              },
              {'role': 'user', 'content': '${_result.text}\n\n${_brief.text}'},
            ],
          )
          .join();
      if (operation.finishReason == 'length') {
        throw const TavernApiException('length');
      }
      if (mounted) {
        setState(() {
          _generated = true;
          _result.text = result;
          _brief.clear();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error is TavernApiException && error.code == 'configuration'
              ? tr('请先在酒馆设置中配置 AI 服务')
              : tr('生成失败，请检查模型连接后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _active = null);
    }
  }

  @override
  void dispose() {
    _active?.cancel();
    _brief.dispose();
    _result.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageHeader(
      title: tr('AI 创作'),
      actions: [
        TextButton(
          onPressed:
              _active == null && (!widget.requireGeneration || _generated)
              ? () => Navigator.pop(context, _result.text)
              : null,
          child: Text(tr('应用')),
        ),
      ],
    ),
    body: ReadableWidth(
      child: ListView(
        padding: const EdgeInsets.all(Gap.page),
        children: [
          TextField(
            controller: _result,
            enabled: _active == null,
            minLines: 6,
            maxLines: 16,
            decoration: InputDecoration(labelText: tr('内容')),
          ),
          const SizedBox(height: Gap.l),
          TextField(
            controller: _brief,
            enabled: _active == null,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: tr('描述你想创作的内容')),
          ),
          const SizedBox(height: Gap.m),
          FilledButton(
            onPressed: _active == null ? _generate : _active!.cancel,
            child: Text(_active == null ? tr('生成草稿') : tr('停止生成')),
          ),
          if (_error.isNotEmpty) Text(_error),
        ],
      ),
    ),
  );
}
