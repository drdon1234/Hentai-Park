import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../tavern/client.dart';
import '../../tavern/store.dart';
import '../kit/kit.dart';
import '../theme.dart';

class TavernSettingsPage extends StatefulWidget {
  const TavernSettingsPage({super.key});
  @override
  State<TavernSettingsPage> createState() => _TavernSettingsPageState();
}

class _TavernSettingsPageState extends State<TavernSettingsPage> {
  final _url = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  final _systemPrompt = TextEditingController();
  final _temperature = TextEditingController();
  final _tokens = TextEditingController();
  final _context = TextEditingController();
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _fetchingModels = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      await TavernApiSettings.instance.load();
      final config = TavernApiSettings.instance.config;
      _url.text = config.baseUrl;
      _model.text = config.model;
      _systemPrompt.text = config.effectiveSystemPrompt;
      _temperature.text = config.temperature.toString();
      _tokens.text = config.maxTokens.toString();
      _context.text = config.contextTokens.toString();
    } catch (_) {
      _loadFailed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final temperature = double.tryParse(_temperature.text.trim());
    final tokens = int.tryParse(_tokens.text.trim());
    final contextTokens = int.tryParse(_context.text.trim());
    if (temperature == null || tokens == null || contextTokens == null) {
      context.toast(tr('模型配置无效'));
      return;
    }
    setState(() => _saving = true);
    try {
      await TavernApiSettings.instance.save(
        baseUrl: _url.text,
        model: _model.text,
        temperature: temperature,
        maxTokens: tokens,
        contextTokens: contextTokens,
        newKey: _key.text,
        systemPrompt: _systemPrompt.text,
      );
      _key.clear();
      if (mounted) context.toast(tr('已保存'));
    } on FormatException catch (error) {
      if (mounted) context.toast(tr(error.message));
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _fetchModels() async {
    if (_fetchingModels || _url.text.trim().isEmpty) return;
    setState(() => _fetchingModels = true);
    try {
      final typedKey = _key.text.trim();
      var key = typedKey;
      if (key.isEmpty) {
        final settings = TavernApiSettings.instance;
        await settings.load();
        final normalized = TavernApiSettings.validateBaseUrl(_url.text)
            .toString()
            .replaceFirst(RegExp(r'/+$'), '');
        if (normalized == settings.config.baseUrl) {
          key = await settings.apiKey();
        }
      }
      final models = await TavernModelCatalog().fetch(
        baseUrl: _url.text,
        apiKey: key,
      );
      if (!mounted) return;
      if (models.isEmpty) {
        context.toast(tr('未找到可用模型'));
        return;
      }
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(tr('选择模型')),
          children: [
            for (final model in models)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, model),
                child: Text(model),
              ),
          ],
        ),
      );
      if (selected != null && mounted) _model.text = selected;
    } on TavernApiException catch (error) {
      if (mounted) {
        context.toast(
          tr(
            error.code == 'insecure_key'
                ? 'HTTP 本机服务不能携带 API Key'
                : '获取模型失败，请检查接口地址和密钥',
          ),
        );
      }
    } on FormatException catch (error) {
      if (mounted) context.toast(tr(error.message));
    } catch (_) {
      if (mounted) context.toast(tr('获取模型失败，请检查接口地址和密钥'));
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _url,
      _model,
      _key,
      _systemPrompt,
      _temperature,
      _tokens,
      _context,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageHeader(title: tr('AI 服务设置')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _loadFailed
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('读取失败，请重试')),
                const SizedBox(height: Gap.s),
                OutlinedButton(onPressed: _load, child: Text(tr('重试'))),
              ],
            ),
          )
        : SettingsBody(
            child: ListView(
              padding: const EdgeInsets.all(Gap.page),
              children: [
                Text(
                  tr('酒馆需要自行配置兼容 OpenAI 的 AI 服务；对话内容会发送到所选服务。'),
                  style: context.text.bodyMedium,
                ),
                const SizedBox(height: Gap.xl),
                RowGroup(
                  margin: EdgeInsets.zero,
                  title: tr('AI 服务设置'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(Gap.page),
                      child: Column(
                        children: [
                          TextField(
                            controller: _url,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: tr('接口地址'),
                              hintText: 'https://example.com/v1',
                            ),
                          ),
                          const SizedBox(height: Gap.l),
                          TextField(
                            controller: _key,
                            decoration: const InputDecoration(
                              labelText: 'API Key',
                              hintText: 'sk-xxxx',
                            ),
                          ),
                          const SizedBox(height: Gap.l),
                          TextField(
                            controller: _model,
                            decoration: InputDecoration(
                              labelText: tr('模型名称'),
                              suffixIcon: IconButton(
                                tooltip: tr('获取模型'),
                                onPressed: _fetchingModels
                                    ? null
                                    : _fetchModels,
                                icon: _fetchingModels
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.list_alt_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(height: Gap.l),
                        ],
                      ),
                    ),
                  ],
                ),
                RowGroup(
                  margin: EdgeInsets.zero,
                  title: tr('生成设置'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(Gap.page),
                      child: Column(
                        children: [
                          TextField(
                            controller: _systemPrompt,
                            minLines: 3,
                            maxLines: 6,
                            decoration: InputDecoration(
                              labelText: tr('系统 Prompt'),
                            ),
                          ),
                          const SizedBox(height: Gap.l),
                          TextField(
                            controller: _temperature,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: tr('温度'),
                              helperText: '0–2',
                            ),
                          ),
                          const SizedBox(height: Gap.l),
                          TextField(
                            controller: _tokens,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: tr('最大输出 Token 数'),
                            ),
                          ),
                          const SizedBox(height: Gap.l),
                          TextField(
                            controller: _context,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: tr('上下文 Token 数'),
                              helperText: tr('包含输入和输出；历史按保守估算裁剪。'),
                              helperMaxLines: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.l),
                Text(
                  tr('使用 HTTPS；仅本机地址允许 HTTP，且不能携带密钥。'),
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: Gap.xl),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(tr('保存')),
                ),
              ],
            ),
          ),
  );
}
