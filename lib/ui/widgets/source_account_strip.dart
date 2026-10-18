import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../kit/tokens.dart';
import '../nav.dart';
import '../theme.dart';

/// Account access stays visible below the source toolbar, including optional sign-in.
class SourceAccountStrip extends StatelessWidget {
  const SourceAccountStrip({
    super.key,
    required this.source,
    this.sourceManager,
  });
  final String source;
  final SourceManager? sourceManager;

  static double height(BuildContext context) =>
      60 * (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1, 3);

  @override
  Widget build(BuildContext context) {
    final manager = sourceManager ?? SourceManager.instance;
    final status = manager.accountListenable(source);
    Widget content(AccountStatus? account) {
      final loggedIn = account?.loggedIn == true;
      return SizedBox(
        height: height(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.page,
            vertical: Gap.s,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Text(
                    loggedIn
                        ? (account!.name.isEmpty ? tr('已登录') : account.name)
                        : tr(
                            manager.manifest(source)?.account?.required == true
                                ? '这个站点需要登录后才能浏览'
                                : '登录后可使用原站账号功能',
                          ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.m),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * .65,
                  ),
                  child: loggedIn
                      ? OutlinedButton.icon(
                          onPressed: () =>
                              Nav.openSourceSettings(context, source),
                          icon: const Icon(Icons.account_circle_outlined),
                          label: Text(
                            tr('账号管理'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: () => Nav.login(context, source),
                          icon: const Icon(Icons.login_rounded),
                          label: Text(
                            tr('登录'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return status == null
        ? content(null)
        : ValueListenableBuilder(
            valueListenable: status,
            builder: (context, value, _) => content(value),
          );
  }
}
