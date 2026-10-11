import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/credential_paste.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';
import '../theme.dart';
import '../web/web_verify_page.dart';
import '../widgets/common.dart';

/// Signed-out account card. Sites with a web login offer two clearly separated methods (web login,
/// recommended; or filling cookies / a password), each with exactly one primary action. Pasting
/// fills the fields first so the user can see what was recognised, then signs in.
class LoginPanel extends StatefulWidget {
  const LoginPanel({super.key, required this.source, required this.account});
  final String source;
  final AccountDef account;

  @override
  State<LoginPanel> createState() => _LoginPanelState();
}

class _LoginPanelState extends State<LoginPanel> {
  late final Map<String, TextEditingController> _fields = {for (final f in widget.account.fields) f['key'].toString(): TextEditingController()};
  final Set<String> _revealed = {};
  bool _busy = false;
  late bool _web = widget.account.loginUrl.isNotEmpty;

  AccountDef get a => widget.account;
  bool get _cookies => a.type == 'cookies';

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _missing => [
    for (final f in a.fields)
      if (f['optional'] != true && _fields[f['key']]!.text.trim().isEmpty) f['label'].toString(),
  ];

  Future<void> _submit() async {
    final missing = _missing;
    if (missing.isNotEmpty) {
      context.toast('请填写：${missing.join('、')}');
      return;
    }
    setState(() => _busy = true);
    try {
      final name = await SourceManager.instance.login(widget.source, {for (final e in _fields.entries) e.key: e.value.text.trim()});
      if (mounted) context.toast(name.isEmpty ? '登录成功' : '登录成功：$name');
    } catch (e) {
      if (mounted) context.toast('登录失败：${e.asSourceError.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      context.toast(_cookies ? '剪贴板是空的，请先复制 Cookie' : '剪贴板是空的，请先复制账号和密码');
      return;
    }
    final values = parsePastedCredentials(text, _fields.keys.toList(), cookies: _cookies);
    if (values.isEmpty) {
      context.toast(_cookies ? '没有在剪贴板里识别到 Cookie' : '没有在剪贴板里识别到账号和密码');
      return;
    }
    setState(() {
      for (final e in values.entries) {
        _fields[e.key]?.text = e.value;
      }
    });
    if (_missing.isEmpty) {
      await _submit();
    } else {
      context.toast('已识别部分内容，还缺少：${_missing.join('、')}');
    }
  }

  Future<void> _webLogin() async {
    final ok = await Nav.push<bool>(context, WebVerifyPage.login(source: widget.source, url: a.loginUrl));
    if (ok == true && mounted) context.toast('登录成功');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasWeb = a.loginUrl.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (a.hint.isNotEmpty) Text(a.hint, style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant, height: 1.45)),
            if (hasWeb) ...[
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: true, icon: Icon(Icons.public_rounded, size: 18), label: Text('网页登录')),
                  ButtonSegment(
                    value: false,
                    icon: Icon(_cookies ? Icons.cookie_outlined : Icons.password_rounded, size: 18),
                    label: Text(_cookies ? '填写 Cookie' : '账号密码'),
                  ),
                ],
                selected: {_web},
                onSelectionChanged: (v) => setState(() => _web = v.first),
              ),
            ],
            const SizedBox(height: 14),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: _web && hasWeb ? _webPane(context) : _formPane(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _webPane(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Step(icon: Icons.login_rounded, text: '在打开的页面中正常登录'),
        const _Step(icon: Icons.auto_awesome_rounded, text: '登录成功后自动返回，不需要复制任何内容'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _webLogin, icon: const Icon(Icons.open_in_browser_rounded), label: const Text('打开登录页')),
      ],
    );
  }

  Widget _formPane(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_cookies)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              '在浏览器登录后，从 Cookie 中复制下面几项。也可以复制整段 Cookie，点「从剪贴板识别」自动填好并登录。',
              style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant, height: 1.45),
            ),
          ),
        for (final f in a.fields) ...[_field(context, f), const SizedBox(height: 12)],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _paste,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('从剪贴板识别'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('登录'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(BuildContext context, Map<String, dynamic> f) {
    final key = f['key'].toString();
    final optional = f['optional'] == true;
    // Cookies stay visible (they are pasted, not typed, and need checking); passwords are masked.
    final secret = !_cookies && f['secret'] == true;
    final hint = (f['hint'] ?? '').toString();
    return TextField(
      controller: _fields[key],
      obscureText: secret && !_revealed.contains(key),
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: _cookies ? null : (secret ? const [AutofillHints.password] : const [AutofillHints.username]),
      style: _cookies ? const TextStyle(fontFamily: 'monospace', fontSize: 14) : null,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: optional ? '${f['label']}（可选）' : f['label']?.toString(),
        helperText: hint.isEmpty ? null : hint,
        suffixIcon: secret
            ? IconButton(
                icon: Icon(_revealed.contains(key) ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _revealed.contains(key) ? _revealed.remove(key) : _revealed.add(key)),
              )
            : null,
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 16, color: context.colors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: context.text.bodyMedium)),
      ],
    ),
  );
}
