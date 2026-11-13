import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../tavern/store.dart';
import '../../tavern/transfer.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import 'tavern_chat_page.dart';

class TavernLibraryPage extends StatefulWidget {
  const TavernLibraryPage({super.key});
  @override
  State<TavernLibraryPage> createState() => _TavernLibraryPageState();
}

class _TavernLibraryPageState extends State<TavernLibraryPage> {
  int _tab = 0;
  bool _importing = false;
  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final file = await FilePicker.pickFile();
      if (file == null || !mounted) return;
      if (await file.xFile.length() > 32 * 1024 * 1024) {
        throw const FormatException();
      }
      await TavernTransfer.importBytes(
        await file.xFile.readAsBytes(),
        file.xFile.name,
      );
      if (mounted) context.toast(tr('已导入'));
    } catch (_) {
      if (mounted) context.toast(tr('导入失败，请检查文件格式'));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _retry() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr('加载失败')),
        TextButton(onPressed: () => setState(() {}), child: Text(tr('重试'))),
      ],
    ),
  );

  Future<void> _deleteResource(String uid) async {
    final confirmed = await confirmAction(
      context,
      title: tr('删除已保存的资源？'),
      message: tr('使用此资源的会话需要先删除。'),
      confirmLabel: tr('删除'),
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await TavernStore.instance.removeResource(uid);
    } on StateError {
      if (mounted) context.toast(tr('请先删除使用此资源的会话'));
    } catch (_) {
      if (mounted) context.toast(tr('删除失败，请重试'));
    }
  }

  Future<void> _deleteSession(TavernSession session) async {
    final confirmed = await confirmAction(
      context,
      title: tr('删除会话？'),
      message: tr('会话中的消息将被删除。'),
      confirmLabel: tr('删除'),
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await TavernStore.instance.removeSession(session.id);
    } catch (_) {
      if (mounted) context.toast(tr('删除失败，请重试'));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageHeader(
      title: tr('已保存与会话'),
      actions: [
        IconButton(
          tooltip: tr('导入'),
          onPressed: _importing ? null : _import,
          icon: const Icon(Icons.file_open_outlined),
        ),
      ],
    ),
    body: ReadableWidth(
      child: Column(
        children: [
          if (_importing) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            child: HeaderTabs(
              tabs: [HeaderTab(tr('已保存')), HeaderTab(tr('会话'))],
              selected: _tab,
              onSelected: (value) => setState(() => _tab = value),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: TavernStore.instance,
              builder: (context, _) {
                if (_tab == 0) {
                  return FutureBuilder(
                    future: TavernStore.instance.resources(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _retry();
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final items = snapshot.data!;
                      if (items.isEmpty) {
                        return Center(child: Text(tr('还没有保存角色卡或世界书')));
                      }
                      return ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            title: Text(item.title),
                            subtitle: Text(
                              item.json['tavernKind'] == 'lorebook'
                                  ? tr('世界书')
                                  : tr('角色卡'),
                            ),
                            leading: const Icon(Icons.bookmark_outline_rounded),
                            onTap: () => Nav.openWork(context, item),
                            trailing: IconButton(
                              tooltip: tr('删除'),
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _deleteResource(item.uid),
                            ),
                          );
                        },
                      );
                    },
                  );
                }
                return FutureBuilder(
                  future: TavernStore.instance.sessions(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return _retry();
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final sessions = snapshot.data!;
                    if (sessions.isEmpty) {
                      return Center(child: Text(tr('还没有会话')));
                    }
                    return ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        return ListTile(
                          title: Text(session.title),
                          subtitle: Text(
                            tr('{count} 条消息', {
                              'count': session.messages.length,
                            }),
                          ),
                          leading: const Icon(
                            Icons.chat_bubble_outline_rounded,
                          ),
                          onTap: () => Nav.push(
                            context,
                            TavernChatPage(session: session),
                          ),
                          trailing: IconButton(
                            tooltip: tr('删除'),
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => _deleteSession(session),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
