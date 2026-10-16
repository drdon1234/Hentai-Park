import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/content_translation.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/tag_translations.dart';
import '../../engine/source_manager.dart';
import '../kit/adaptive_sheet.dart';
import 'on_visible.dart';
import 'text_translation.dart';

final _translationSettings = AppSettings.instance.watch(const {
  'autoTranslateContent',
  'translateEngine',
});

/// Per-route display state. Original values remain in models and actions.
class TranslationPage extends StatefulWidget {
  const TranslationPage({super.key, required this.child, this.active = true});
  final Widget child;
  final bool active;
  @override
  State<TranslationPage> createState() => _TranslationPageState();
}

class _TranslationPageState extends State<TranslationPage> {
  bool original = false;
  bool manual = false;
  int retry = 0;

  void change(VoidCallback action) => setState(action);

  @override
  Widget build(BuildContext context) {
    final active =
        widget.active && (_TranslationScope.of(context)?.active ?? true);
    return ListenableBuilder(
      listenable: Listenable.merge([
        _translationSettings,
        TagTranslations.instance,
      ]),
      builder: (context, _) => _TranslationScope(
        owner: this,
        original: original,
        enabled:
            active && (manual || AppSettings.instance.autoTranslateContent),
        active: active,
        locale: AppLocalizations.localeKey(AppLocalizations.of(context).locale),
        engine: AppSettings.instance.translateEngine,
        retry: retry,
        child: TranslationSelectionArea(child: widget.child),
      ),
    );
  }
}

class _TranslationScope extends InheritedTheme {
  const _TranslationScope({
    required this.owner,
    required this.original,
    required this.enabled,
    required this.active,
    required this.locale,
    required this.engine,
    required this.retry,
    required super.child,
  });
  final _TranslationPageState owner;
  final bool original, enabled, active;
  final String locale, engine;
  final int retry;
  static _TranslationScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TranslationScope>();
  @override
  Widget wrap(BuildContext context, Widget child) => _TranslationScope(
    owner: owner,
    original: original,
    enabled: enabled,
    active: active,
    locale: locale,
    engine: engine,
    retry: retry,
    child: child,
  );
  @override
  // Installed dictionaries refresh visible display without mutating source models.
  bool updateShouldNotify(_TranslationScope old) => true;
}

/// One short unit of visible remote text. Builder keeps the host's layout/style.
class ContentTranslation extends StatefulWidget {
  const ContentTranslation({
    super.key,
    required this.text,
    required this.builder,
    this.source = '',
    this.namespace = '',
    this.tag = false,
    this.queue,
  });
  final String text, source, namespace;
  final bool tag;
  final ContentTranslationQueue? queue;
  final Widget Function(String value) builder;
  @override
  State<ContentTranslation> createState() => _ContentTranslationState();
}

class _ContentTranslationState extends State<ContentTranslation> {
  bool _visible = false, _busy = false, _attempted = false;
  bool _waitingCapacity = false;
  ModalRoute<dynamic>? _route;
  bool get _routeCurrent => _route?.isCurrent ?? true;
  ContentTranslationQueue get _queue =>
      widget.queue ?? ContentTranslationQueue.instance;
  String? _translated;
  String _identity = '';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _queue.addListener(_capacityAvailable);
  }

  void _capacityAvailable() {
    if (_waitingCapacity && _queue.hasCapacity) {
      _waitingCapacity = false;
      unawaited(_request());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 显式订阅路由的可见状态；异步回调中的查询不能替代构建依赖。
    _route = ModalRoute.of(context);
    _reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _request();
    });
  }

  @override
  void didUpdateWidget(ContentTranslation old) {
    super.didUpdateWidget(old);
    if (old.queue != widget.queue) {
      (old.queue ?? ContentTranslationQueue.instance).removeListener(
        _capacityAvailable,
      );
      _queue.addListener(_capacityAvailable);
    }
    _reset();
  }

  void _reset() {
    final scope = _TranslationScope.of(context);
    final identity =
        '${widget.text}\u0000${widget.source}\u0000${widget.namespace}'
        '\u0000${scope?.locale}\u0000${scope?.engine}\u0000${scope?.enabled}'
        '\u0000${scope?.original}\u0000${scope?.retry}';
    if (_identity == identity) return;
    _identity = identity;
    _generation++;
    _translated = null;
    _busy = _attempted = false;
    _waitingCapacity = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _request();
    });
  }

  String? _dictionary(_TranslationScope? scope) =>
      widget.tag && scope?.original != true
      ? TagTranslations.instance.lookup(
          widget.source,
          scope?.locale ??
              AppLocalizations.localeKey(AppLocalizations.of(context).locale),
          widget.text,
          namespace: widget.namespace,
        )
      : null;

  Future<void> _request() async {
    var scope = _TranslationScope.of(context);
    if (widget.tag &&
        _visible &&
        scope?.active == true &&
        scope?.original != true &&
        _routeCurrent) {
      final generation = _generation;
      try {
        await TagTranslations.instance.ensureLoaded(
          widget.source,
          scope!.locale,
        );
      } catch (_) {
        // 本站损坏词包不能影响其他站点；保留原标签和显式重试入口。
      }
      if (!mounted || generation != _generation) return;
      scope = _TranslationScope.of(context);
    }
    if (!_visible ||
        _busy ||
        _attempted ||
        scope == null ||
        !scope.enabled ||
        scope.original ||
        widget.text.trim().isEmpty ||
        _dictionary(scope) != null ||
        !_routeCurrent) {
      return;
    }
    final cached = _queue.cached(widget.text, scope.locale, scope.engine);
    if (cached != null) {
      setState(() {
        _translated = cached;
        _attempted = true;
      });
      return;
    }
    if (!_queue.hasCapacity) {
      _waitingCapacity = true;
      return;
    }
    _busy = true;
    final generation = _generation;
    final result = await _queue.request(
      widget.text,
      scope.locale,
      scope.engine,
      isActive: () =>
          mounted &&
          _visible &&
          generation == _generation &&
          _dictionary(_TranslationScope.of(context)) == null &&
          _routeCurrent,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _busy = false;
      // Network failures wait for explicit retry. Hidden/cancelled views may re-enter.
      _attempted = _visible && _routeCurrent;
      _translated = result;
    });
  }

  @override
  void dispose() {
    _generation++;
    _queue.removeListener(_capacityAvailable);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 返回页面的构建直接读取缓存，即使请求完成时页面依赖更新被暂停。
    ModalRoute.isCurrentOf(context);
    final scope = _TranslationScope.of(context);
    if (scope == null) return widget.builder(widget.text);
    final value = scope.original == true
        ? widget.text
        : _dictionary(scope) ??
              _translated ??
              (scope.enabled
                  ? _queue.cached(widget.text, scope.locale, scope.engine)
                  : null) ??
              widget.text;
    return OnVisible(
      onVisible: (visible) {
        _visible = visible;
        if (visible) {
          unawaited(_request());
          if (widget.tag && scope.active && _routeCurrent && !scope.original) {
            unawaited(
              showTagDownloadGuide(context, widget.source, scope.locale),
            );
          }
        }
      },
      child: widget.builder(value),
    );
  }
}

/// Unicode-safe small units; concatenation reproduces the original exactly.
List<String> translationChunks(String text) {
  final runes = text.runes.toList();
  return [
    for (var start = 0; start < runes.length; start += 400)
      String.fromCharCodes(
        runes.sublist(start, (start + 400).clamp(0, runes.length)),
      ),
  ];
}

class TranslationControls extends StatelessWidget {
  const TranslationControls({super.key, this.source});
  final String? source;

  @override
  Widget build(BuildContext context) {
    final scope = _TranslationScope.of(context);
    if (scope == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: tr('内容翻译'),
      icon: Icon(
        Icons.translate_rounded,
        color: scope.enabled && !scope.original
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      onPressed: () => showAdaptiveSheet<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, refresh) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.translate),
                    title: SelectionContainer.disabled(
                      child: Text(tr('翻译当前页面')),
                    ),
                    onTap: () {
                      scope.owner.change(() {
                        scope.owner.manual = true;
                        scope.owner.original = false;
                        scope.owner.retry++;
                      });
                      Navigator.pop(ctx);
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    title: SelectionContainer.disabled(
                      child: Text(tr('自动翻译可见内容')),
                    ),
                    value: AppSettings.instance.autoTranslateContent,
                    onChanged: (value) {
                      AppSettings.instance.autoTranslateContent = value;
                      refresh(() {});
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    title: SelectionContainer.disabled(
                      child: Text(tr('显示原文（仅当前页面）')),
                    ),
                    value: scope.owner.original,
                    onChanged: (value) {
                      scope.owner.change(() => scope.owner.original = value);
                      refresh(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 多站点页面用当前站点展示安装状态，不依赖列表中是否恰好有可见标签。
class TagTranslationPackStatus extends StatelessWidget {
  const TagTranslationPackStatus({super.key, required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    final scope = _TranslationScope.of(context);
    final locale =
        scope?.locale ??
        AppLocalizations.localeKey(AppLocalizations.of(context).locale);
    final service = TagTranslations.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final available = service.availableLocales(source).contains(locale);
        return OnVisible(
          key: ValueKey('$source/$locale'),
          onVisible: (visible) {
            if (visible &&
                scope?.active == true &&
                scope?.original != true &&
                ModalRoute.of(context)?.isCurrent != false) {
              unawaited(showTagDownloadGuide(context, source, locale));
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () =>
                    showTagTranslationPacks(context, source: source),
                icon: const Icon(Icons.translate_rounded),
                label: SelectionContainer.disabled(child: Text(tr('官方标签翻译包'))),
              ),
              if (service.installed(source, locale))
                Text(tr('翻译包已安装'))
              else if (!available)
                Text(tr('本站暂无专用词包，开启内容翻译后可翻译标签')),
            ],
          ),
        );
      },
    );
  }
}

Future<void> showTagDownloadGuide(
  BuildContext context,
  String source,
  String locale,
) async {
  final service = TagTranslations.instance;
  if (!service.claimDownloadGuide(source, locale)) return;
  var deferred = false;
  try {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('下载标签翻译词库')),
        content: Text(tr('仅下载本站当前语言的标签词库；其他站点可在各自页面或设置中独立下载。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'never'),
            child: SelectionContainer.disabled(child: Text(tr('不再提醒'))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'later'),
            child: SelectionContainer.disabled(child: Text(tr('下次提醒'))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'download'),
            child: SelectionContainer.disabled(child: Text(tr('立即下载'))),
          ),
        ],
      ),
    );
    if (choice != 'download') {
      deferred = true;
      if (choice == 'never') AppSettings.instance.tagDownloadReminders = false;
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(tr('可在设置中手动下载词库'))));
      }
      return;
    }
    if (service.bundled(source, locale)) {
      await service.download(source, locale);
    } else {
      await service.updateFromRepository(source, locale);
    }
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(tr('翻译包已安装'))));
    }
  } catch (_) {
    deferred = true;
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(tr('翻译包安装失败，请重试')),
          action: SnackBarAction(
            label: tr('重试'),
            onPressed: () => showTagTranslationPacks(context, source: source),
          ),
        ),
      );
    }
  } finally {
    service.finishDownloadGuide(deferred: deferred);
  }
}

Future<void> showTagTranslationPacks(
  BuildContext context, {
  String? source,
}) async {
  final service = TagTranslations.instance;
  String? selected = service.sources.contains(source)
      ? source
      : service.sources.firstOrNull;
  var locale = AppLocalizations.localeKey(AppLocalizations.of(context).locale);
  bool busy = false;
  String? message;
  void normalize() {
    if (selected == null || !service.sources.contains(selected)) {
      selected = service.sources.firstOrNull;
    }
    final languages = selected == null
        ? <String>[]
        : service.availableLocales(selected!);
    if (!languages.contains(locale) && languages.isNotEmpty) {
      locale = languages.first;
    }
  }

  normalize();
  if (selected != null) {
    try {
      await service.ensureLoaded(selected!, locale);
    } catch (_) {}
    if (!context.mounted) return;
  }
  await showAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, refresh) {
        Future<void> operation(
          Future<void> Function() action,
          String success,
        ) async {
          if (busy) return;
          refresh(() {
            busy = true;
            message = null;
          });
          try {
            await action();
            if (ctx.mounted) {
              refresh(() {
                normalize();
                message = success.isEmpty ? null : tr(success);
              });
            }
          } catch (_) {
            if (ctx.mounted) refresh(() => message = tr('翻译包安装失败，请重试'));
          } finally {
            if (ctx.mounted) refresh(() => busy = false);
          }
        }

        final languages = selected == null
            ? <String>[]
            : service.availableLocales(selected!);
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('官方标签翻译包'),
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  if (source != null && !service.sources.contains(source))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(tr('本站暂无专用词包，开启内容翻译后可翻译标签')),
                    ),
                  if (selected != null) ...[
                    const SizedBox(height: 12),
                    SelectionContainer.disabled(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('source-$selected'),
                        initialValue: selected,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('站点')),
                        items: [
                          for (final key in service.sources)
                            DropdownMenuItem(
                              value: key,
                              child: SelectionContainer.disabled(
                                child: Text(
                                  SourceManager.instance.manifest(key)?.name ??
                                      key,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) {
                                refresh(() {
                                  selected = value;
                                  message = null;
                                  normalize();
                                });
                                final key = selected!, language = locale;
                                unawaited(
                                  operation(
                                    () => service.ensureLoaded(key, language),
                                    '',
                                  ),
                                );
                              },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectionContainer.disabled(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('locale-$selected-$locale'),
                        initialValue: locale,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('语言')),
                        items: [
                          for (final language in languages)
                            DropdownMenuItem(
                              value: language,
                              child: SelectionContainer.disabled(
                                child: Text(
                                  AppLocalizations.languageNames[language] ??
                                      language,
                                ),
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) {
                                refresh(() {
                                  locale = value!;
                                  message = null;
                                });
                                final key = selected!, language = locale;
                                unawaited(
                                  operation(
                                    () => service.ensureLoaded(key, language),
                                    '',
                                  ),
                                );
                              },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(tr('词包优先显示译文；未命中时按内容翻译开关处理，搜索与屏蔽仍使用原文')),
                    if (service.installed(selected!, locale))
                      Text(tr('翻译包已安装')),
                    for (final origin
                        in service.pack(selected!, locale)?.provenance ??
                            <Map<String, dynamic>>[])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '${origin['name'] ?? ''} · ${origin['license'] ?? ''}\n${origin['scope'] ?? ''}',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        if (service.bundled(selected!, locale))
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () {
                                    final key = selected!, language = locale;
                                    operation(
                                      () => service.download(key, language),
                                      '翻译包已安装',
                                    );
                                  },
                            child: SelectionContainer.disabled(
                              child: Text(tr('安装内置词包')),
                            ),
                          ),
                        if (service.remoteAvailable(selected!, locale))
                          TextButton(
                            onPressed: busy
                                ? null
                                : () {
                                    final key = selected!, language = locale;
                                    operation(
                                      () => service.updateFromRepository(
                                        key,
                                        language,
                                      ),
                                      '翻译包已安装',
                                    );
                                  },
                            child: SelectionContainer.disabled(
                              child: Text(tr('从官方仓库下载更新')),
                            ),
                          ),
                        if (service.installed(selected!, locale))
                          TextButton(
                            onPressed: busy
                                ? null
                                : () {
                                    final key = selected!, language = locale;
                                    operation(
                                      () => service.remove(key, language),
                                      '词库已移除',
                                    );
                                  },
                            child: SelectionContainer.disabled(
                              child: Text(tr('移除词库')),
                            ),
                          ),
                      ],
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(tr('暂无可用词包，可使用内容翻译')),
                    ),
                  if (message != null) Text(message!),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: SelectionContainer.disabled(
                      child: Text(tr('检查官方可用词包')),
                    ),
                    onPressed: busy
                        ? null
                        : () =>
                              operation(service.refreshRepository, '已更新可用词包列表'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
