import 'package:flutter/material.dart';

import '../../core/app_lock.dart';
import '../../core/localization.dart';
import '../kit/kit.dart';
import '../theme.dart';

/// Covers the whole app while [AppLock] is locked.
class LockGate extends StatelessWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.instance;
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => Stack(
        children: [
          // Keep the app mounted underneath so navigation state survives locking.
          ExcludeSemantics(
            excluding: lock.locked,
            child: ExcludeFocus(
              excluding: lock.locked,
              child: TickerMode(enabled: !lock.locked, child: child),
            ),
          ),
          if (lock.locked)
            const Positioned.fill(
              child: FocusScope(autofocus: true, child: _LockScreen()),
            ),
        ],
      ),
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen();

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => AppLock.instance.unlock(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.page),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 40,
                  color: c.onSurfaceVariant,
                ),
                const SizedBox(height: Gap.l),
                Text(
                  tr('HentaiPark 已锁定'),
                  style: ParkText.serif(context.text.headlineSmall),
                ),
                const SizedBox(height: Gap.xl),
                FilledButton.icon(
                  onPressed: AppLock.instance.unlock,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: SelectionContainer.disabled(child: Text(tr('解锁'))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
