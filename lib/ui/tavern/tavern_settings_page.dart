import 'package:flutter/material.dart';

import '../../core/localization.dart';
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
  final _temperature = TextEditingController();
  final _tokens = TextEditingController();
  final _context = TextEditingController();
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _clear = false;
  bool _hasKey = false;

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
      _temperature.text = config.temperature.toString();
      _tokens.text = config.maxTokens.toString();
      _context.text = config.contextTokens.toString();
      _hasKey = config.secretRef.isNotEmpty;
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
        clearKey: _clear,
      );
      _key.clear();
      _clear = false;
      _hasKey = TavernApiSettings.instance.config.secretRef.isNotEmpty;
      if (mounted) context.toast(tr('已保存'));
    } on FormatException catch (error) {
      if (mounted) context.toast(tr(error.message));
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _url,
      _model,
      _key,
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
                            controller: _model,
                            decoration: InputDecoration(labelText: tr('模型名称')),
                          ),
                          const SizedBox(height: Gap.l),
                          TextField(
                            controller: _key,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: 'API Key',
                              helperMaxLines: 4,
                              helperText: _hasKey
                                  ? tr('留空保留已保存的密钥；更换服务地址时需重新填写。')
                                  : tr('可留空，适用于不需要密钥的服务。'),
                            ),
                          ),
                          if (_hasKey)
                            CheckboxListTile(
                              value: _clear,
                              contentPadding: EdgeInsets.zero,
                              title: Text(tr('清除已保存的密钥')),
                              onChanged: (value) =>
                                  setState(() => _clear = value == true),
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
