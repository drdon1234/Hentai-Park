import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_lock.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/platform_capabilities.dart';
import '../../core/settings.dart';
import '../kit/kit.dart';
import '../theme.dart';

/// 首次使用先确认年龄，再设置隐私与分类；后续步骤可返回调整。
/// Existing users who upgrade see only the age step.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

enum _Step { age, privacy, interests }

class _OnboardingPageState extends State<OnboardingPage> {
  final _settings = AppSettings.instance;
  bool _saving = false;
  late _Step _step = _settings.adultConfirmed && _fullFlow
      ? _Step.privacy
      : _Step.age;
  late final Set<SourceCategory> _interests = {
    ...(_settings.homeCategories.isEmpty
        ? AppSettings.defaultDomainOrder
        : _settings.homeCategories),
  };

  bool get _fullFlow =>
      !_settings.onboarded &&
      (_settings.freshInstall || _settings.adultConfirmed);

  void _back() {
    if (_saving) return;
    if (_step == _Step.age) return;
    if (_step == _Step.privacy && _settings.adultConfirmed) return;
    setState(() => _step = _Step.values[_step.index - 1]);
  }

  Future<void> _confirmAge() async {
    if (_saving) return;
    setState(() => _saving = true);
    final fullFlow = _fullFlow;
    try {
      unawaited(HapticFeedback.lightImpact());
      await _settings.confirmAdult(completeOnboarding: !fullFlow);
      if (mounted && fullFlow) setState(() => _step = _Step.privacy);
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.long),
              switchInCurve: Motion.emphasized,
              switchOutCurve: Motion.curve,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(.04, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
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
      if (_fullFlow || _step != _Step.age)
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.l, Gap.page, 0),
          child: _StepDots(count: _Step.values.length, current: _step.index),
        ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Gap.page,
            Gap.xxl,
            Gap.page,
            Gap.l,
          ),
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
                height: 1.55,
              ),
            ),
            const SizedBox(height: Gap.xl),
            ...body,
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, Gap.l),
        child: Row(
          children: [
            if (_step == _Step.interests)
              TextButton(
                onPressed: _back,
                child: SelectionContainer.disabled(child: Text(tr('返回'))),
              ),
            ...actions.take(actions.length - 1),
            const SizedBox(width: Gap.s),
            Expanded(child: actions.last),
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
        icon: Icons.info_outline_rounded,
        text: tr(
          '成年确认只保存在本机，后续启动无需重复确认。此声明仅用于本应用，不能替代第三方站点的独立验证；第三方内容及服务适用相应站点条款和当地法律。',
        ),
      ),
      _Point(
        icon: Icons.lock_outline_rounded,
        text: tr('书架、历史和账号只保存在这台设备上，可以随时备份或删除。'),
      ),
    ],
    actions: [
      TextButton(
        onPressed: () => SystemNavigator.pop(),
        child: SelectionContainer.disabled(child: Text(tr('退出'))),
      ),
      FilledButton(
        onPressed: _saving ? null : _confirmAge,
        child: SelectionContainer.disabled(child: Text(tr('我已成年，继续'))),
      ),
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
          margin: EdgeInsets.zero,
          children: [
            SwitchListTile.adaptive(
              title: SelectionContainer.disabled(child: Text(tr('模糊封面'))),
              subtitle: SelectionContainer.disabled(
                child: Text(tr('在列表与预览中模糊所有封面')),
              ),
              value: _settings.blurCovers,
              onChanged: (v) => _settings.blurCovers = v,
            ),
            if (PlatformCapabilities.secureScreen)
              SwitchListTile.adaptive(
                title: SelectionContainer.disabled(
                  child: Text(tr('防截屏与多任务预览')),
                ),
                subtitle: SelectionContainer.disabled(
                  child: Text(tr('最近任务中隐藏内容，并禁止截屏（Android）')),
                ),
                value: _settings.secureScreen,
                onChanged: (v) => _settings.secureScreen = v,
              ),
            if (AppLock.platformSupported)
              SwitchListTile.adaptive(
                title: SelectionContainer.disabled(child: Text(tr('应用锁'))),
                subtitle: SelectionContainer.disabled(
                  child: Text(tr('打开应用时需要指纹 / 面部 / 锁屏密码验证')),
                ),
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
        FilledButton(
          onPressed: () => setState(() => _step = _Step.interests),
          child: SelectionContainer.disabled(child: Text(tr('下一步'))),
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
            SelectionChip(
              label: c.label,
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
        child: SelectionContainer.disabled(child: Text(tr('跳过'))),
      ),
      FilledButton(
        onPressed: _interests.isEmpty ? null : _finish,
        child: SelectionContainer.disabled(child: Text(tr('开始使用'))),
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
    padding: const EdgeInsets.only(bottom: Gap.l),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.colors.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 18,
              color: context.colors.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(width: Gap.m),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: Gap.xs + 2),
            child: Text(
              text,
              style: context.text.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Where the first-run flow is: one capsule per step, the current and finished ones in accent.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) => Semantics(
    label: tr('第 {value0} 步，共 {value1} 步', {
      'value0': current + 1,
      'value1': count,
    }),
    excludeSemantics: true,
    child: Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: Gap.xs + 2),
          AnimatedContainer(
            duration: Motion.of(context, Motion.medium),
            curve: Motion.emphasized,
            width: i == current ? 28 : 12,
            height: 4,
            decoration: BoxDecoration(
              color: i <= current
                  ? context.colors.primary
                  : context.colors.surfaceContainerHighest,
              borderRadius: Radii.tiny,
            ),
          ),
        ],
      ],
    ),
  );
}
