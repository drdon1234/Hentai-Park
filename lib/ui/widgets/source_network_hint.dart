import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';

class SourceNetworkHint extends StatelessWidget {
  const SourceNetworkHint({super.key, required this.source});
  final String source;

  @override
  Widget build(BuildContext context) => DelayedNetworkHint(
    key: ValueKey(source),
    enabled:
        SourceManager.instance.manifest(source)?.network['vpnHint'] == true,
  );
}

class DelayedNetworkHint extends StatefulWidget {
  const DelayedNetworkHint({super.key, required this.enabled});
  final bool enabled;

  @override
  State<DelayedNetworkHint> createState() => _DelayedNetworkHintState();
}

class _DelayedNetworkHintState extends State<DelayedNetworkHint> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _visible = false;
    if (widget.enabled) {
      _timer = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void didUpdateWidget(DelayedNetworkHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return const NetworkAccessHint();
  }
}

class NetworkAccessHint extends StatelessWidget {
  const NetworkAccessHint({super.key, this.showSettings = true});
  final bool showSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('该站点在中国大陆可能需要开启 VPN 或配置代理，请检查网络，或请再等待一段时间'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (showSettings)
            TextButton(
              onPressed: () => Nav.openNetworkSettings(context),
              child: SelectionContainer.disabled(child: Text(tr('网络设置'))),
            ),
        ],
      ),
    );
  }
}
