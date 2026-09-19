import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/ui/app.dart';
import 'package:notebase/ui/input_bar.dart';
import 'package:notebase/ui/stream_view.dart';

import '../support/memory_storage.dart';

/// M5 打磨项（ui-design §4 / §5.1 / §10）：
/// 回到最新按钮、数字小键盘 Enter、分笔记本草稿、启动期提示条。
void main() {
  Future<AppStore> storeWith(int count) async {
    final store = await AppStore.load(MemoryStorage());
    for (var i = 0; i < count; i++) {
      await store.addText('条目 $i');
    }
    return store;
  }

  Future<void> pumpApp(WidgetTester tester, AppStore store,
      {String? notice}) async {
    await tester.pumpWidget(NotebaseApp(store: store, startupNotice: notice));
    await tester.pumpAndSettle();
  }

  Finder streamScrollable() => find.descendant(
        of: find.byType(StreamView),
        matching: find.byType(Scrollable),
      );

  group('回到最新按钮（§4）', () {
    testWidgets('上翻超过一屏才浮现，点击后回到底部并消失', (tester) async {
      final store = await storeWith(60);
      await pumpApp(tester, store);

      expect(find.byTooltip('回到最新'), findsNothing); // 底部时不显示

      await tester.drag(streamScrollable(), const Offset(0, 400)); // 上翻约一屏内
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到最新'), findsNothing);

      await tester.drag(streamScrollable(), const Offset(0, 800)); // 累计超过一屏
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到最新'), findsOneWidget);

      await tester.tap(find.byTooltip('回到最新'));
      await tester.pumpAndSettle();

      final position = tester.state<ScrollableState>(streamScrollable()).position;
      expect(position.pixels, position.maxScrollExtent);
      expect(find.byTooltip('回到最新'), findsNothing); // 回到底部后自行消失
    });

    // P2-1 回归：内容不足一屏时不该有按钮；上翻后切到短本，按钮必须消失。
    testWidgets('内容不足一屏的笔记本不显示按钮，切换后不残留', (tester) async {
      final store = await AppStore.load(MemoryStorage());
      for (var i = 0; i < 60; i++) {
        await store.addText('长本 $i');
      }
      final short = await store.createNotebook('短本');
      await store.addText('只有一条');
      await store.switchNotebook(Notebook.defaultId);
      await pumpApp(tester, store);

      await tester.drag(streamScrollable(), const Offset(0, 1200));
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到最新'), findsOneWidget); // 长本上翻后浮现

      await store.switchNotebook(short.id); // 切到内容不足一屏的笔记本
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到最新'), findsNothing); // 当前实现会残留
    });

    // 回归（M6 后复检 P2-2）：跨 720 会重建 StreamView 的 State——滚动位置与
    // `_lastNotebookId` 基线一起归零，新 State 首帧必判「切本了」而强制滚底，
    // 于是把窗口最大化 / 拉窄都会丢掉阅读位置、并把「回到最新」按钮一并重置。
    testWidgets('跨 720 重建后滚动位置与按钮状态保持（不强制滚底）', (tester) async {
      final store = await storeWith(60);
      await pumpApp(tester, store);

      // 上翻 1200px：既超过宽屏一屏（按钮浮现），跨到更高的窄屏后距底
      // 仍有近一屏多——「距底超过一屏」这条派生判定在两套布局下都成立。
      await tester.drag(streamScrollable(), const Offset(0, 1200));
      await tester.pumpAndSettle();
      final before =
          tester.state<ScrollableState>(streamScrollable()).position.pixels;
      expect(find.byTooltip('回到最新'), findsOneWidget);

      tester.view.physicalSize = const Size(400, 800); // 跨 720 → 窄屏布局
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();

      expect(
        tester.state<ScrollableState>(streamScrollable()).position.pixels,
        before, // 当前实现：被强制滚到底（= maxScrollExtent）
      );
      expect(find.byTooltip('回到最新'), findsOneWidget); // 按钮状态随之保留
    });
  });

  group('发送写盘窗口（P2-2 回归）', () {
    testWidgets('窗口内切本：目标本草稿不被发送完成的 clear 抹掉', (tester) async {
      final store = await AppStore.load(SlowMemoryStorage());
      final work = await store.createNotebook('工作');
      await store.switchNotebook(Notebook.defaultId);
      await pumpApp(tester, store);

      String fieldText() => tester
          .widget<EditableText>(find.descendant(
            of: find.byType(InputBar),
            matching: find.byType(EditableText),
          ))
          .controller
          .text;

      await tester.enterText(find.byType(TextField), 'AAA');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_outlined)); // 开始写盘（50ms 窗口）
      await tester.pump(const Duration(milliseconds: 10));

      await store.switchNotebook(work.id); // 窗口内切本
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '工作的草稿');
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 300)); // 写盘完成
      await tester.pumpAndSettle();

      // 条目进的是「发送时所在的本」（当前已是工作本，故按归属查）
      expect(await store.entryCountOf(Notebook.defaultId), 1);
      expect(fieldText(), '工作的草稿'); // 曾经被发送完成的 clear 抹掉
    });

    testWidgets('窗口内继续打字：新输入不被吞掉', (tester) async {
      final store = await AppStore.load(SlowMemoryStorage());
      await pumpApp(tester, store);

      String fieldText() => tester
          .widget<EditableText>(find.descendant(
            of: find.byType(InputBar),
            matching: find.byType(EditableText),
          ))
          .controller
          .text;

      await tester.enterText(find.byType(TextField), 'AAA');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_outlined));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.enterText(find.byType(TextField), 'AAABBB'); // 窗口内继续打字
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(store.entries.single.text, 'AAA');
      expect(fieldText(), 'AAABBB'); // 当前实现被吞成空
    });

    // 回归（M6 后复检 P2-1）：宽/窄两套布局各自构造 InputBar，跨 720 会重建
    // State——`_sending` 守卫随之归零，而新 State 会从 DraftStore 里把**还没
    // 清空的原文**读回来，于是输入框残留刚发出去的文字、➤ 重新可用，再点一次
    // 同一条文本入库两次（探针实测：写完 1 条，二次发送后 2 条）。
    testWidgets('写盘窗口内拖动窗口跨 720：草稿不残留、不重复入库', (tester) async {
      final store = await AppStore.load(SlowMemoryStorage());
      await pumpApp(tester, store);

      String fieldText() => tester
          .widget<EditableText>(find.descendant(
            of: find.byType(InputBar),
            matching: find.byType(EditableText),
          ))
          .controller
          .text;

      await tester.enterText(find.byType(TextField), 'AAA');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_outlined)); // 开始写盘（50ms 窗口）
      await tester.pump(const Duration(milliseconds: 10));

      tester.view.physicalSize = const Size(400, 800); // 窗口内跨 720 → 窄屏
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // 只出帧、不推进时钟：重建必须发生在写盘仍在途时，否则发送完成的清空
      // 会先跑（旧 State 还没被销毁），竞态窗口就消失了。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // 写盘完成
      await tester.pumpAndSettle();

      expect(fieldText(), isEmpty); // 曾经残留刚发出去的原文
      expect(store.entries.length, 1); // 且残留的原文可以再发一次 → 重复入库
    });
  });

  group('键盘（§5.1）', () {
    testWidgets('数字小键盘 Enter 也能发送（宽屏）', (tester) async {
      final store = await AppStore.load(MemoryStorage());
      await pumpApp(tester, store);

      await tester.enterText(find.byType(TextField), '小键盘发送');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();

      expect(store.entries.single.text, '小键盘发送');
    });

    testWidgets('Shift+Enter 换行不发送（宽屏）', (tester) async {
      final store = await AppStore.load(MemoryStorage());
      await pumpApp(tester, store);

      await tester.enterText(find.byType(TextField), '第一行');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(store.entries, isEmpty); // 仍是换行，未发送
    });

    testWidgets('窄屏不自动弹键盘；宽屏自动聚焦输入栏', (tester) async {
      // 宽屏（默认 800x600）
      final wideStore = await AppStore.load(MemoryStorage());
      await pumpApp(tester, wideStore);
      final wideField = tester.widget<EditableText>(find.descendant(
        of: find.byType(InputBar),
        matching: find.byType(EditableText),
      ));
      expect(wideField.focusNode.hasFocus, isTrue);

      // 窄屏
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final narrowStore = await AppStore.load(MemoryStorage());
      await pumpApp(tester, narrowStore);
      final narrowField = tester.widget<EditableText>(find.descendant(
        of: find.byType(InputBar),
        matching: find.byType(EditableText),
      ));
      expect(narrowField.focusNode.hasFocus, isFalse);
    });
  });

  group('§11 步数表：窄屏记一段文字 = 2 步', () {
    testWidgets('点输入框 → 打字 → ➤ 发送', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final store = await AppStore.load(MemoryStorage());
      await pumpApp(tester, store);

      await tester.tap(find.byType(TextField)); // 第 1 步：点输入框
      await tester.pump();
      tester.testTextInput.enterText('窄屏速记'); // 真实键盘路径：点框即聚焦
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.descendant(
              of: find.byType(InputBar),
              matching: find.byType(EditableText),
            ))
            .controller
            .text,
        '窄屏速记',
      );
      await tester.tap(find.byIcon(Icons.send_outlined)); // 第 2 步：➤
      await tester.pumpAndSettle();

      expect(store.entries.single.text, '窄屏速记');
    });

    // 注：widget 测试环境里 Enter 既不会发送也不会真的插入换行，
    // 因此这里只能断言「未误发、原文未丢」；真实换行行为在真机验证。
    testWidgets('窄屏 Enter 不误发，且原文不丢', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final store = await AppStore.load(MemoryStorage());
      await pumpApp(tester, store);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '第一行');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(store.entries, isEmpty);
      expect(
        tester
            .widget<EditableText>(find.descendant(
              of: find.byType(InputBar),
              matching: find.byType(EditableText),
            ))
            .controller
            .text,
        contains('第一行'),
      );
    });
  });

  group('草稿归属（§10 决策）', () {
    testWidgets('窗口跨 720 宽窄切换，草稿不丢（P3-1 回归）', (tester) async {
      final store = await AppStore.load(MemoryStorage());
      await pumpApp(tester, store);

      String fieldText() => tester
          .widget<EditableText>(find.descendant(
            of: find.byType(InputBar),
            matching: find.byType(EditableText),
          ))
          .controller
          .text;

      await tester.enterText(find.byType(TextField), '拖动窗口前写的草稿');
      await tester.pump();

      tester.view.physicalSize = const Size(400, 800); // 跨 720 → 窄屏分支
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();

      expect(fieldText(), '拖动窗口前写的草稿'); // 当前实现会丢
    });

    testWidgets('草稿按笔记本各自保存，切换不丢也不串味', (tester) async {
      final store = await AppStore.load(MemoryStorage());
      final work = await store.createNotebook('工作');
      await store.switchNotebook(Notebook.defaultId);
      await pumpApp(tester, store);

      String fieldText() => tester
          .widget<EditableText>(find.descendant(
            of: find.byType(InputBar),
            matching: find.byType(EditableText),
          ))
          .controller
          .text;

      await tester.enterText(find.byType(TextField), 'default 的草稿');
      await tester.pump();

      await store.switchNotebook(work.id); // 切到工作
      await tester.pumpAndSettle();
      expect(fieldText(), isEmpty); // 工作本没有草稿

      await tester.enterText(find.byType(TextField), '工作的草稿');
      await tester.pump();

      await store.switchNotebook(Notebook.defaultId); // 切回
      await tester.pumpAndSettle();
      expect(fieldText(), 'default 的草稿'); // 原草稿还在

      await store.switchNotebook(work.id);
      await tester.pumpAndSettle();
      expect(fieldText(), '工作的草稿');
      expect(store.entries, isEmpty); // 全程没有误发
    });
  });

  group('启动期提示条（§10）', () {
    testWidgets('有提示时显示，可关闭', (tester) async {
      final store = await AppStore.load(MemoryStorage());
      await pumpApp(tester, store, notice: '部分数据未能读取，已备份到：nb_x.json.corrupt-1');
      expect(find.textContaining('部分数据未能读取'), findsOneWidget);

      await tester.tap(find.byTooltip('知道了'));
      await tester.pumpAndSettle();
      expect(find.textContaining('部分数据未能读取'), findsNothing);
    });

    testWidgets('无提示时不占位', (tester) async {
      final store = await AppStore.load(MemoryStorage());
      await pumpApp(tester, store);
      expect(find.byTooltip('知道了'), findsNothing);
    });
  });
}
