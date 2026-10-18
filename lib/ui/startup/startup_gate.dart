import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_log.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../kit/kit.dart';
import '../theme.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({super.key, required this.initialize, required this.child});
  final Future<void> Function() initialize;
  final Widget child;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _ready = false, _failed = false, _running = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_running) return;
    setState(() {
      _running = true;
      _failed = false;
    });
    try {
      await widget.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (error, stack) {
      AppLog.error(error, event: 'startup', stack: stack);
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ParkTheme.of(
        Brightness.dark,
        const Color(ParkTheme.defaultAccent),
      ),
      locale: AppLocalizations.instance.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.delegates,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: _failed
                  ? EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: tr('启动失败'),
                      message: tr('初始化未完成，请检查存储空间、访问权限和系统服务后重试。原有数据不会被清除。'),
                      actions: [
                        FilledButton(
                          onPressed: _start,
                          child: SelectionContainer.disabled(
                            child: Text(tr('重试')),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: AppLog.linesFor(
                                    AppSettings.instance.logMode,
                                  ).join('\n'),
                                ),
                              );
                              if (mounted) setState(() => _copied = true);
                            } catch (error) {
                              AppLog.error(error, event: 'diagnostics_copy');
                            }
                          },
                          child: SelectionContainer.disabled(
                            child: Text(tr(_copied ? '已复制' : '复制诊断信息')),
                          ),
                        ),
                      ],
                    )
                  : const Padding(
                      padding: EdgeInsets.all(Gap.xl),
                      child: CircularProgressIndicator(),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
