import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_lock.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../kit/kit.dart';
import '../theme.dart';

/// First run: confirm age (required), then privacy preferences and interests (both skippable).
/// Existing users who upgrade see only the age step.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

enum _Step { age, privacy, interests }

class _OnboardingPageState extends State<OnboardingPage> {
  final _settings = AppSettings.instance;
  _Step _step = _Step.age;
  late final Set<SourceCategory> _interests = {
    ...(_settings.homeCategories.isEmpty
        ? AppSettings.defaultDomainOrder
        : _settings.homeCategories),
  };

  bool get _fullFlow => !_settings.onboarded && _settings.freshInstall;

  void _confirmAge() {
    HapticFeedback.lightImpact();
    if (!_fullFlow) {
      _settings.onboarded = true;
      _settings.adultConfirmed = true;
      return;
    }
    setState(() => _step = _Step.privacy);
  }

  void _finish() {
    final all = _interests.length == AppSettings.defaultDomainOrder.length;
    _settings.homeCategories = all || _interests.isEmpty
        ? const []
        : [
            for (final c in _settings.domainOrder)
              if (_interests.contains(c)) c,
          ];
    _settings.onboarded = true;
    // Confirming last keeps this page up until every step is done.
    _settings.adultConfirmed = true;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.medium),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: switch (_step) {
                  _Step.age => _age(context),
                  _Step.privacy => _privacy(context),
                  _Step.interests => _interestsStep(context),
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _frame(
    BuildContext context, {
    required String title,
    required String message,
    required List<Widget> body,
    required List<Widget> actions,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xxl, Gap.xl, Gap.l),
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: ParkText.serif(context.text.headlineMedium),
              ),
            ),
            const SizedBox(height: Gap.m),
            Text(
              message,
              style: context.text.bodyLarge?.copyWith(
                color: context.colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: Gap.xl),
            ...body,
          ],
        ),
      ),
      const Divider(),
      Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.m, Gap.xl, Gap.l),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: Gap.s),
              actions[i],
            ],
          ],
        ),
      ),
    ],
  );

  Widget _age(BuildContext context) => _frame(
    context,
    title: 'HentaiPark',
    message: tr(
      '这里的内容来自第三方站点，可能包含成人内容。继续前请确认：你已年满 18 周岁（或所在地区的法定成年年龄），并且在你所在的地区浏览此类内容是合法的。',
    ),
    body: [
      _Point(icon: Icons.public_rounded, text: tr('应用本身不存放内容，作品都来自你启用的站点。')),
      _Point(
        icon: Icons.lock_outline_rounded,
        text: tr('书架、历史和账号只保存在这台设备上，可以随时备份或删除。'),
      ),
    ],
    actions: [
      TextButton(onPressed: () => SystemNavigator.pop(), child: Text(tr('退出'))),
      FilledButton(onPressed: _confirmAge, child: Text(tr('我已成年，继续'))),
    ],
  );

  Widget _privacy(BuildContext context) => ListenableBuilder(
    listenable: _settings.watch(const {
      'blurCovers',
      'secureScreen',
      'appLock',
    }),
    builder: (context, _) => _frame(
      context,
      title: tr('隐私偏好'),
      message: tr('都可以稍后在“我的 → 隐私与安全”中修改。'),
      body: [
        RowGroup(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('模糊封面')),
              subtitle: Text(tr('在列表与预览中模糊所有封面')),
              value: _settings.blurCovers,
              onChanged: (v) => _settings.blurCovers = v,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('防截屏与多任务预览')),
              subtitle: Text(tr('最近任务中隐藏内容，并禁止截屏（Android）')),
              value: _settings.secureScreen,
              onChanged: (v) => _settings.secureScreen = v,
            ),
            if (AppLock.platformSupported)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('应用锁')),
                subtitle: Text(tr('打开应用时需要指纹 / 面部 / 锁屏密码验证')),
                value: _settings.appLock,
                onChanged: (v) async {
                  if (!v) {
                    AppLock.instance.disable();
                    return;
                  }
                  if (!await AppLock.instance.available()) {
                    if (context.mounted) {
                      context.toast(tr('设备没有设置锁屏或生物识别，无法开启'));
                    }
                    return;
                  }
                  await AppLock.instance.enable();
                },
              ),
          ],
        ),
      ],
      actions: [
        TextButton(
          onPressed: () => setState(() => _step = _Step.interests),
          child: Text(tr('跳过')),
        ),
        FilledButton(
          onPressed: () => setState(() => _step = _Step.interests),
          child: Text(tr('下一步')),
        ),
      ],
    ),
  );

  Widget _interestsStep(BuildContext context) => _frame(
    context,
    title: tr('感兴趣的分类'),
    message: tr('发现页会为这些分类放上书架。所有分类仍可在发现页顶部切换。'),
    body: [
      Wrap(
        spacing: Gap.s,
        runSpacing: Gap.s,
        children: [
          for (final c in _settings.domainOrder)
            FilterChip(
              label: Text(c.label),
              selected: _interests.contains(c),
              onSelected: (on) =>
                  setState(() => on ? _interests.add(c) : _interests.remove(c)),
            ),
        ],
      ),
    ],
    actions: [
      TextButton(
        onPressed: () {
          _interests.addAll(AppSettings.defaultDomainOrder);
          _finish();
        },
        child: Text(tr('跳过')),
      ),
      FilledButton(
        onPressed: _interests.isEmpty ? null : _finish,
        child: Text(tr('开始使用')),
      ),
    ],
  );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.m),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: context.colors.onSurfaceVariant),
        const SizedBox(width: Gap.m),
        Expanded(child: Text(text, style: context.text.bodyMedium)),
      ],
    ),
  );
}
