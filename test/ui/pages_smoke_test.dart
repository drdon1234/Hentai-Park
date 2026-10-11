import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/core/models.dart';
import 'package:hentai_park/core/settings.dart';
import 'package:hentai_park/core/storage.dart';
import 'package:hentai_park/data/database.dart';
import 'package:hentai_park/library/downloads.dart';
import 'package:hentai_park/library/library.dart';
import 'package:hentai_park/ui/history/history_page.dart';
import 'package:hentai_park/ui/library/category_manage_page.dart';
import 'package:hentai_park/ui/library/downloads_page.dart';
import 'package:hentai_park/ui/library/library_options_sheet.dart';
import 'package:hentai_park/ui/library/library_page.dart';
import 'package:hentai_park/ui/reader/reader_settings_sheet.dart';
import 'package:hentai_park/ui/settings/blocklist_page.dart';
import 'package:hentai_park/ui/shell.dart';
import 'package:hentai_park/ui/updates/updates_page.dart';

/// Builds each new page against an in-memory library to catch layout and runtime errors
/// (the app cannot be launched on a device in CI).
void main() {
  late AppDatabase db;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final tmp = await Directory.systemTemp.createTemp('park_ui');
    AppPaths.data = AppPaths.cache = AppPaths.downloads = AppPaths.backups = AppPaths.downloadRoot = tmp;
  });

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = AppDatabase.memory();
      final lib = Library.instance;
      await lib.open(db);
      await DownloadManager.instance.load(db);
      final cat = await lib.createCategory('连载');
      for (var i = 0; i < 6; i++) {
        final w = WorkItem({'id': '$i', 'title': '作品 $i', 'cover': ''}, i.isEven ? 'jm' : 'ehentai');
        lib.addFavorite(w, categories: i < 3 ? {cat!.id} : {});
        await lib.syncChapters(w, [Chapter('a', '第1话')]);
        await lib.syncChapters(w, [Chapter('a', '第1话'), Chapter('b', '第2话')]);
        lib.recordProgress(w, chapterId: 'a', chapterTitle: '第1话', page: 3, pageCount: 10);
      }
      await lib.flush();
    });
  }

  Future<void> show(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(home: page));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  tearDown(() async {
    await db.close();
  });

  testWidgets('library page with category tabs, grid and list', (tester) async {
    await seed(tester);
    await show(tester, const LibraryPage());
    expect(find.textContaining('全部 6'), findsOneWidget);
    expect(find.textContaining('连载 3'), findsOneWidget);
    expect(find.text('作品 5'), findsWidgets);
    // Long-press enters selection mode.
    // Newest favorite first: "作品 5" is on screen.
    await tester.longPress(find.text('作品 5').hitTestable().first);
    await tester.pump();
    expect(find.text('已选 1'), findsOneWidget);
  });

  testWidgets('library options sheet', (tester) async {
    await seed(tester);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => TextButton(onPressed: () => showLibraryOptions(c), child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('筛选'), findsOneWidget);
    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();
    expect(find.text('最近更新'), findsOneWidget);
  });

  testWidgets('updates feed lists new chapters', (tester) async {
    await seed(tester);
    await show(tester, const UpdatesPage());
    expect(find.text('第2话'), findsNWidgets(6));
    expect(find.text('今天'), findsOneWidget);
  });

  testWidgets('history page groups by day', (tester) async {
    await seed(tester);
    await show(tester, const HistoryPage());
    expect(find.text('今天'), findsOneWidget);
    expect(find.textContaining('第1话 4/10'), findsWidgets);
  });

  testWidgets('category management, downloads and blocklist pages build', (tester) async {
    await seed(tester);
    await show(tester, const CategoryManagePage());
    expect(find.text('连载'), findsOneWidget);
    await show(tester, const DownloadsPage());
    expect(find.text('没有下载任务'), findsOneWidget);
    await show(tester, const BlocklistPage());
    expect(find.text('没有屏蔽任何标签'), findsOneWidget);
  });

  testWidgets('shell switches between all five tabs', (tester) async {
    await seed(tester);
    await show(tester, const Shell());
    for (final tab in ['书架', '更新', '历史', '我的', '发现']) {
      await tester.tap(find.text(tab).last);
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(find.text('无痕模式', skipOffstage: false), findsOneWidget); // settings tab stays alive in the IndexedStack
  });

  testWidgets('reader settings sheet tabs', (tester) async {
    await seed(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => showReaderSettings(c, mode: AppSettings.instance.readerMode, modeIsOverride: false, onMode: (_) {}, onUseDefault: () {}),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('裁剪白边'), findsOneWidget);
    await tester.tap(find.text('通用'));
    await tester.pumpAndSettle();
    expect(find.text('点击区域'), findsOneWidget);
    await tester.tap(find.text('滤镜'));
    await tester.pumpAndSettle();
    expect(find.text('灰度'), findsOneWidget);
  });
}
