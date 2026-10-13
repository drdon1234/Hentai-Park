import 'package:flutter/material.dart';

import '../../core/app_lock.dart';
import '../theme.dart';
import '../../core/localization.dart';

/// Covers the whole app while [AppLock] is locked.
class LockGate extends StatelessWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final lock = AppLock.instance;
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => Stack(
        children: [
          // Keep the app mounted underneath so navigation state survives locking.
          ExcludeSemantics(
            excluding: lock.locked,
            child: TickerMode(enabled: !lock.locked, child: child),
          ),
          if (lock.locked) const Positioned.fill(child: _LockScreen()),
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
    AppLocalizations.of(context);
    final c = context.colors;
    return Material(
      color: c.surface,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 56, color: c.primary),
              const SizedBox(height: 16),
              Text(
                tr('HentaiPark 已锁定'),
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: AppLock.instance.unlock,
                icon: const Icon(Icons.fingerprint_rounded),
                label: Text(tr('解锁')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
