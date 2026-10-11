import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/app_lock.dart';
import '../../core/crash_log.dart';
import '../../core/settings.dart';
import '../../core/storage.dart';
import '../../core/tag_blocklist.dart';
import '../../core/translator.dart';
import '../../engine/js_engine.dart';
import '../../images/image_store.dart';
import '../../library/downloads.dart';
import '../library/category_manage_page.dart';
import '../library/downloads_page.dart';
import '../nav.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'backup_page.dart';
import 'blocklist_page.dart';
import 'source_manage_page.dart';
import 'storage_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.initialSection});
  final String? initialSection;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final s = AppSettings.instance;
  int? _cacheBytes;
  final _networkKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    ImageStore.instance.cacheSize().then((v) => mounted ? setState(() => _cacheBytes = v) : null);
    if (widget.initialSection == 'network') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _networkKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
      });
    }
  }

  Future<void> _pickRefreshRate() async {
    final rates = await PlatformBridge.refreshRates();
    final current = await PlatformBridge.currentRefreshRate();
    if (!mounted) return;
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('屏幕刷新率'),
        children: [
          if (current != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('当前 ${current.round()} Hz', style: ctx.text.bodySmall?.copyWith(color: ctx.colors.onSurfaceVariant)),
            ),
          for (final hz in [0, ...rates])
            ListTile(
              title: Text(hz == 0 ? '自动（最高刷新率）' : '$hz Hz'),
              trailing: hz == s.refreshRate ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, hz),
            ),
          if (rates.length <= 1)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text('系统没有报告其他可用的刷新率'),
            ),
        ],
      ),
    );
    if (v == null) return;
    s.refreshRate = v;
    await PlatformBridge.applyRefreshRate(v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(widget.initialSection == null ? '我的' : '设置')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (widget.initialSection == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.visibility_off_outlined),
                        title: const Text('无痕模式'),
                        subtitle: const Text('暂停记录历史、阅读进度与已读状态'),
                        value: s.incognito,
                        onChanged: (v) => s.incognito = v,
                      ),
                      ListenableBuilder(
                        listenable: DownloadManager.instance,
                        builder: (context, _) {
                          final tasks = DownloadManager.instance.tasks;
                          final active = tasks.where((t) => t.status == DownloadStatus.running || t.status == DownloadStatus.queued).length;
                          return ListTile(
                            leading: const Icon(Icons.download_rounded),
                            title: const Text('下载队列'),
                            subtitle: Text(active > 0 ? '$active 个任务进行中' : '${tasks.length} 个下载'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Nav.push(context, const DownloadsPage()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            _Group('源站', [
              ListTile(
                leading: const Icon(Icons.extension_outlined),
                title: const Text('源站管理'),
                subtitle: const Text('启用、排序、账号、安装新源'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Nav.push(context, const SourceManagePage()),
              ),
            ]),
            _Group('书库', [
              ListTile(
                leading: const Icon(Icons.update_rounded),
                title: const Text('自动检查更新'),
                subtitle: const Text('打开应用或回到前台时，如果已到间隔就检查收藏的新章节'),
                trailing: DropdownButton<int>(
                  value: s.libraryUpdateHours,
                  underline: const SizedBox.shrink(),
                  items: const [
                    (0, '关闭'),
                    (6, '6 小时'),
                    (12, '12 小时'),
                    (24, '每天'),
                    (48, '2 天'),
                    (168, '每周'),
                  ].map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
                  onChanged: (v) {
                    s.libraryUpdateHours = v ?? 0;
                    if ((v ?? 0) > 0) PlatformBridge.requestNotificationPermission();
                  },
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.auto_stories_outlined),
                title: const Text('只检查多章节作品'),
                subtitle: const Text('单本画廊不会出新章节，跳过可以省去大部分请求'),
                value: s.updateOnlyMultiChapter,
                onChanged: (v) => s.updateOnlyMultiChapter = v,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.mark_email_unread_outlined),
                title: const Text('跳过有未读章节的作品'),
                value: s.updateSkipUnread,
                onChanged: (v) => s.updateSkipUnread = v,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.hourglass_empty_rounded),
                title: const Text('跳过还没开始读的作品'),
                value: s.updateSkipNotStarted,
                onChanged: (v) => s.updateSkipNotStarted = v,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.label_outline_rounded),
                title: const Text('收藏时选择分类'),
                value: s.askCategoryOnFavorite,
                onChanged: (v) => s.askCategoryOnFavorite = v,
              ),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('管理分类'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Nav.push(context, const CategoryManagePage()),
              ),
            ]),
            _Group('下载', [
              SwitchListTile(
                secondary: const Icon(Icons.wifi_rounded),
                title: const Text('仅在 Wi-Fi 下下载'),
                subtitle: const Text('使用移动数据时暂停，连上 Wi-Fi 后自动继续'),
                value: s.downloadWifiOnly,
                onChanged: (v) => s.downloadWifiOnly = v,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.download_for_offline_outlined),
                title: const Text('自动下载新章节'),
                subtitle: const Text('书库更新发现新章节后自动加入下载队列'),
                value: s.autoDownloadNew,
                onChanged: (v) => s.autoDownloadNew = v,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.auto_delete_outlined),
                title: const Text('读完后删除'),
                subtitle: const Text('章节被标记为已读后删除它的下载（本地导入的作品除外）'),
                value: s.deleteAfterRead,
                onChanged: (v) => s.deleteAfterRead = v,
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('下载位置'),
                subtitle: SelectableText(AppPaths.downloadRoot.path, style: context.text.bodySmall),
              ),
            ]),
            _Group('数据', [
              ListTile(
                leading: const Icon(Icons.settings_backup_restore_rounded),
                title: const Text('备份与恢复'),
                subtitle: const Text('创建、恢复、自动备份'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Nav.push(context, const BackupPage()),
              ),
            ]),
            _Group('外观', [
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text('主题'),
                trailing: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('跟随')),
                    ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => s.themeMode = v.first,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('主题色'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final e in ParkTheme.accents.entries)
                        Tooltip(
                          message: e.value,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => s.seedColor = e.key,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: Color(e.key),
                              child: s.seedColor == e.key ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.grid_view_rounded),
                title: const Text('每行封面数'),
                trailing: DropdownButton<int>(
                  value: s.gridColumns,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('自动')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                    DropdownMenuItem(value: 3, child: Text('3')),
                    DropdownMenuItem(value: 4, child: Text('4')),
                  ],
                  onChanged: (v) => s.gridColumns = v ?? 0,
                ),
              ),
              if (Platform.isAndroid)
                ListTile(
                  leading: const Icon(Icons.speed_outlined),
                  title: const Text('屏幕刷新率'),
                  subtitle: Text(s.refreshRate == 0 ? '自动（跟随屏幕最高刷新率）' : '${s.refreshRate} Hz'),
                  onTap: _pickRefreshRate,
                ),
            ]),
            _Group('隐私', [
              SwitchListTile(
                secondary: const Icon(Icons.blur_on_rounded),
                title: const Text('模糊封面'),
                subtitle: const Text('在列表与预览中模糊所有封面'),
                value: s.blurCovers,
                onChanged: (v) => s.blurCovers = v,
              ),
              _AppLockTile(settings: s),
              SwitchListTile(
                secondary: const Icon(Icons.screenshot_monitor_outlined),
                title: const Text('防截屏与多任务预览'),
                subtitle: const Text('最近任务中隐藏内容，并禁止截屏（Android）'),
                value: s.secureScreen,
                onChanged: (v) {
                  s.secureScreen = v;
                  PlatformBridge.applySecureScreen(v || s.appLock);
                },
              ),
            ]),
            _Group('阅读', [
              ListTile(
                leading: Icon(s.readerMode.icon),
                title: const Text('默认阅读模式'),
                subtitle: Text(s.readerMode.label),
                onTap: () async {
                  final m = await showModalBottomSheet<ReaderMode>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final m in ReaderMode.values)
                            ListTile(
                              leading: Icon(m.icon),
                              title: Text(m.label),
                              trailing: m == s.readerMode ? const Icon(Icons.check_rounded) : null,
                              onTap: () => Navigator.pop(ctx, m),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (m != null) s.readerMode = m;
                },
              ),
              ListTile(
                leading: const Icon(Icons.fast_forward_outlined),
                title: const Text('预加载页数'),
                subtitle: Slider(
                  value: s.preloadPages.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: '${s.preloadPages}',
                  onChanged: (v) => s.preloadPages = v.round(),
                ),
                trailing: Text('${s.preloadPages}'),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.touch_app_outlined),
                title: const Text('点击屏幕边缘翻页'),
                value: s.tapToPage,
                onChanged: (v) => s.tapToPage = v,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_outlined),
                title: const Text('音量键翻页'),
                value: s.volumeKeyPaging,
                onChanged: (v) => s.volumeKeyPaging = v,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.light_mode_outlined),
                title: const Text('阅读时保持屏幕常亮'),
                value: s.keepScreenOn,
                onChanged: (v) => s.keepScreenOn = v,
              ),
            ]),
            _Group('网络', key: _networkKey, [
              ListTile(
                leading: const Icon(Icons.vpn_lock_outlined),
                title: const Text('HTTP 代理'),
                subtitle: Text(s.proxy.isEmpty ? '未设置（使用系统网络 / VPN）' : s.proxy),
                onTap: () async {
                  final v = await _input(context, 'HTTP 代理', s.proxy, hint: '例如 127.0.0.1:7890，留空表示不使用');
                  if (v != null) s.proxy = v;
                },
              ),
              ListTile(
                leading: const Icon(Icons.speed_rounded),
                title: const Text('每个站点的图片并发数'),
                subtitle: Slider(
                  value: s.imageConcurrency.toDouble(),
                  min: 2,
                  max: 12,
                  divisions: 10,
                  label: '${s.imageConcurrency}',
                  onChanged: (v) => s.imageConcurrency = v.round(),
                ),
                trailing: Text('${s.imageConcurrency}'),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('每个下载任务的并发页数'),
                subtitle: Slider(
                  value: s.downloadConcurrency.toDouble(),
                  min: 1,
                  max: 8,
                  divisions: 7,
                  label: '${s.downloadConcurrency}',
                  onChanged: (v) => s.downloadConcurrency = v.round(),
                ),
                trailing: Text('${s.downloadConcurrency}'),
              ),
            ]),
            _Group('多语言搜索', [
              ListTile(
                leading: const Icon(Icons.g_translate_rounded),
                title: const Text('翻译服务'),
                subtitle: Text(translateEngines[s.translateEngine] ?? s.translateEngine),
                onTap: () async {
                  final v = await showDialog<String>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: const Text('翻译服务'),
                      children: [
                        for (final e in translateEngines.entries)
                          ListTile(
                            title: Text(e.value),
                            trailing: e.key == s.translateEngine ? const Icon(Icons.check_rounded) : null,
                            onTap: () => Navigator.pop(ctx, e.key),
                          ),
                      ],
                    ),
                  );
                  if (v != null) s.translateEngine = v;
                },
              ),
              ListTile(
                leading: const Icon(Icons.translate_rounded),
                title: const Text('目标语言'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in translateLanguages.entries)
                        FilterChip(
                          label: Text(e.value),
                          selected: s.translateTargets.contains(e.key),
                          visualDensity: VisualDensity.compact,
                          onSelected: (on) {
                            final list = s.translateTargets;
                            on ? list.add(e.key) : list.remove(e.key);
                            s.translateTargets = list;
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ]),
            _Group('内容过滤', [
              ListTile(
                leading: const Icon(Icons.block_rounded),
                title: const Text('屏蔽标签'),
                subtitle: Text(() {
                  final presets = BlockPresetConfig.current().where((c) => c.on).length;
                  final parts = [if (s.blockedTags.isNotEmpty) '已屏蔽 ${s.blockedTags.length} 项', if (presets > 0) '$presets 组预设'];
                  return parts.isEmpty ? '隐藏带有指定标签的作品，可启用预设分组' : parts.join(' · ');
                }()),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Nav.push(context, const BlocklistPage()),
              ),
            ]),
            _Group('存储', [
              ListTile(
                leading: const Icon(Icons.pie_chart_outline_rounded),
                title: const Text('存储空间'),
                subtitle: const Text('缓存、下载、数据库占用与清理'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Nav.push(context, const StoragePage()),
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('清除图片缓存'),
                subtitle: Text(_cacheBytes == null ? '计算中…' : '已用 ${formatBytes(_cacheBytes!)}，上限 ${s.cacheLimitMb} MB'),
                onTap: () async {
                  await ImageStore.instance.clear();
                  imageCache.clear();
                  setState(() => _cacheBytes = 0);
                  if (context.mounted) context.toast('缓存已清除');
                },
              ),
              ListTile(
                leading: const Icon(Icons.storage_rounded),
                title: const Text('缓存上限'),
                trailing: DropdownButton<int>(
                  value: s.cacheLimitMb,
                  underline: const SizedBox.shrink(),
                  items: const [
                    512,
                    1024,
                    2048,
                    4096,
                  ].map((v) => DropdownMenuItem(value: v, child: Text('${v ~/ 1024 > 0 ? '${v ~/ 1024} GB' : '$v MB'}'))).toList(),
                  onChanged: (v) => s.cacheLimitMb = v ?? 1024,
                ),
              ),
            ]),
            _Group('关于', [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('HentaiPark'),
                subtitle: const Text('可插拔的多源站本子 / 里番客户端。内容来自第三方站点，仅限成年人在合法地区使用。'),
              ),
              ListTile(leading: const Icon(Icons.terminal_rounded), title: const Text('运行日志'), onTap: () => Nav.push(context, const _LogsPage())),
            ]),
          ],
        ),
      ),
    );
  }
}

class _AppLockTile extends StatelessWidget {
  const _AppLockTile({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline_rounded),
          title: const Text('应用锁'),
          subtitle: const Text('打开应用时需要指纹 / 面部 / 锁屏密码验证'),
          value: s.appLock,
          onChanged: AppLock.platformSupported
              ? (v) async {
                  if (!v) {
                    AppLock.instance.disable();
                    PlatformBridge.applySecureScreen(s.secureScreen);
                    return;
                  }
                  if (!await AppLock.instance.available()) {
                    if (context.mounted) context.toast('设备没有设置锁屏或生物识别，无法开启');
                    return;
                  }
                  if (await AppLock.instance.enable()) PlatformBridge.applySecureScreen(true);
                }
              : null,
        ),
        if (s.appLock)
          ListTile(
            leading: const SizedBox(width: 24),
            title: const Text('离开多久后重新锁定'),
            trailing: DropdownButton<int>(
              value: s.appLockAfter,
              underline: const SizedBox.shrink(),
              items: const [
                (0, '立即'),
                (60, '1 分钟'),
                (300, '5 分钟'),
                (900, '15 分钟'),
              ].map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
              onChanged: (v) => s.appLockAfter = v ?? 0,
            ),
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.children, {super.key});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          child: Text(
            title,
            style: context.text.labelLarge?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Card(child: Column(children: children)),
        ),
      ],
    );
  }
}

class _LogsPage extends StatelessWidget {
  const _LogsPage();

  @override
  Widget build(BuildContext context) {
    final logs = JsEngine.instance.logs.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            tooltip: '导出诊断日志',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () async {
              final text = await CrashLog.report(JsEngine.instance.logs);
              final file = File(p.join(AppPaths.cache.path, 'hentaipark_log.txt'));
              await file.writeAsString(text);
              await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
            },
          ),
        ],
      ),
      body: logs.isEmpty
          ? const MessageView(icon: Icons.notes_rounded, title: '暂无日志')
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SelectableText(logs[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
    );
  }
}

Future<String?> _input(BuildContext context, String title, String initial, {String? hint}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('保存')),
      ],
    ),
  );
}
