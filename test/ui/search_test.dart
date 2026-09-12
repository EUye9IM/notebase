import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/ui/app.dart';
import 'package:notebase/ui/editor_sheet.dart';
import 'package:notebase/ui/search_view.dart';
import 'package:notebase/ui/stream_view.dart';

import '../support/memory_storage.dart';

/// M4 验收（ui-design §7 / §8 / §11）：
/// 搜索 = 1 步进入 + 输入即过滤（限当前笔记本、结果倒序）；
/// 删除 = 长按 → 删除 → 确认（3 步），并支持 5s 撤销。
void main() {
  Future<AppStore> storeWith(List<String> texts) async {
    final store = await AppStore.load(MemoryStorage());
    for (final t in texts) {
      await store.addText(t);
    }
    return store;
  }

  Future<void> pumpApp(WidgetTester tester, AppStore store) async {
    await tester.pumpWidget(NotebaseApp(store: store));
    await tester.pumpAndSettle();
  }

  /// 当前显示的是哪一屏：0 = 时间流，1 = 搜索结果（ui-design §7 原地切换）。
  int visibleIndex(WidgetTester tester) =>
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

  group('搜索', () {
    testWidgets('1 步进入，输入即过滤，退出恢复时间流', (tester) async {
      final store = await storeWith(['买了猫粮', '今天开会']);
      await pumpApp(tester, store);

      await tester.tap(find.byIcon(Icons.search)); // 1 步进入搜索
      await tester.pumpAndSettle();
      expect(visibleIndex(tester), 1);
      expect(find.text('输入关键词，仅搜索当前笔记本'), findsOneWidget);

      await tester.enterText(find.byType(SearchField), '猫粮');
      await tester.pumpAndSettle();
      expect(find.text('1 条结果'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SearchResults),
          matching: find.text('买了猫粮'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SearchResults),
          matching: find.text('今天开会'),
        ),
        findsNothing, // 未命中
      );

      await tester.tap(find.byIcon(Icons.arrow_back)); // 退出搜索
      await tester.pumpAndSettle();
      expect(visibleIndex(tester), 0);
    });

    testWidgets('无结果提示带「清空」', (tester) async {
      final store = await storeWith(['买了猫粮']);
      await pumpApp(tester, store);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('“zzz”没有匹配'), findsOneWidget);
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('输入关键词，仅搜索当前笔记本'), findsOneWidget);
    });

    testWidgets('窄屏：顶栏进入搜索并过滤', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final store = await storeWith(['买了猫粮', '今天开会']);
      await pumpApp(tester, store);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      expect(visibleIndex(tester), 1);

      await tester.enterText(find.byType(SearchField), '开会');
      await tester.pumpAndSettle();
      expect(find.text('1 条结果'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(visibleIndex(tester), 0);
    });

    testWidgets('退出搜索恢复时间流的滚动位置（§7）', (tester) async {
      final store = await AppStore.load(MemoryStorage());
      for (var i = 0; i < 60; i++) {
        await store.addText('条目 $i');
      }
      await pumpApp(tester, store);

      final scrollable = find.descendant(
        of: find.byType(StreamView),
        matching: find.byType(Scrollable),
      );
      await tester.drag(scrollable, const Offset(0, 600)); // 向上翻一屏
      await tester.pumpAndSettle();
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(before, greaterThan(0)); // 确实翻上去了（不在底部）

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      final after = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(after, before);
    });

    testWidgets('结果按时间倒序（最新在前）', (tester) async {
      final store = await storeWith(['猫粮一号', '猫粮二号']);
      await pumpApp(tester, store);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchField), '猫粮');
      await tester.pumpAndSettle();

      final first = tester.getTopLeft(find.text('猫粮二号'));
      final second = tester.getTopLeft(find.text('猫粮一号'));
      expect(first.dy, lessThan(second.dy));
    });
  });

  group('编辑', () {
    testWidgets('点条目开底 sheet：保存改内容且不改 createdAt', (tester) async {
      final store = await storeWith(['原文']);
      final original = store.entries.single;
      await pumpApp(tester, store);

      await tester.tap(find.text('原文'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryEditorSheet), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byType(EntryEditorSheet),
          matching: find.byType(TextField),
        ),
        '改后',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(store.entries.single.text, '改后');
      expect(store.entries.single.createdAt, original.createdAt); // 排序不变
    });

    testWidgets('清空文本时「保存」禁用（删除必须显式）', (tester) async {
      final store = await storeWith(['别误删']);
      await pumpApp(tester, store);

      await tester.tap(find.text('别误删'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(EntryEditorSheet),
          matching: find.byType(TextField),
        ),
        '',
      );
      await tester.pump();

      final save =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存'));
      expect(save.onPressed, isNull);
      expect(store.entries.single.text, '别误删'); // 未被隐式删除
    });
  });

  group('删除与撤销', () {
    testWidgets('长按 → 删除 → 确认（3 步），并可用 5s 撤销找回', (tester) async {
      final store = await storeWith(['要删掉的', '留着的']);
      await pumpApp(tester, store);

      await tester.longPress(find.text('要删掉的')); // 1 长按
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除')); // 2 菜单项
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除')); // 3 确认
      await tester.pumpAndSettle();

      expect(store.entries.single.text, '留着的');
      expect(find.text('已删除'), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(store.entries.map((e) => e.text), ['要删掉的', '留着的']);
    });

    testWidgets('取消确认则不删除', (tester) async {
      final store = await storeWith(['留着']);
      await pumpApp(tester, store);

      await tester.longPress(find.text('留着'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(store.entries, hasLength(1));
    });

    testWidgets('复制菜单把正文写入剪贴板', (tester) async {
      // widget 测试无平台通道实现，先接管剪贴板通道并记录写入内容。
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final store = await storeWith(['复制我']);
      await pumpApp(tester, store);

      await tester.longPress(find.text('复制我'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();

      expect(copied, '复制我'); // 真正落到剪贴板的正文
      expect(find.text('已复制'), findsOneWidget);
    });
  });
}
