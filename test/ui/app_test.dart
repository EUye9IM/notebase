import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/ui/app.dart';
import 'package:notebase/ui/stream_view.dart';

import '../support/memory_storage.dart';

/// M2 验收（ui-design §11）：记一段文字 = 宽屏 1 步（Enter 发送）。
void main() {
  testWidgets('宽屏输入文字后 Enter 发送：入流、清空输入框', (tester) async {
    final store = await AppStore.load(MemoryStorage());
    await tester.pumpWidget(NotebaseApp(store: store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '买了猫粮');
    // 测试默认窗口 800x600 → 宽屏 → Enter 即发送
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(store.entries.single.text, '买了猫粮');
    expect(
      find.descendant(
        of: find.byType(StreamView),
        matching: find.text('买了猫粮'),
      ),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('➤ 按钮发送；空文本时按钮禁用', (tester) async {
    final store = await AppStore.load(MemoryStorage());
    await tester.pumpWidget(NotebaseApp(store: store));
    await tester.pumpAndSettle();

    expect(
      tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.send_outlined),
      ),
      predicate<IconButton>((b) => b.onPressed == null),
    );

    await tester.enterText(find.byType(TextField), '从按钮发送');
    await tester.pump(); // 让 _hasText 状态重建，按钮由禁用变为可用
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pumpAndSettle();

    expect(store.entries.single.text, '从按钮发送');
  });

  testWidgets('时间流按天分组：同日条目共用一个「今天」组头', (tester) async {
    final store = await AppStore.load(MemoryStorage());
    await store.addText('第一条');
    await store.addText('第二条');
    await tester.pumpWidget(NotebaseApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('今天'), findsOneWidget);
    expect(find.text('第一条'), findsOneWidget);
    expect(find.text('第二条'), findsOneWidget);
  });

  // M3 评审 P4 回归：写延迟窗口内连点 ➤ 曾产生两条重复条目。
  testWidgets('发送重入守卫：写入期间连点 ➤ 只记一条', (tester) async {
    final store = await AppStore.load(SlowMemoryStorage());
    await tester.pumpWidget(NotebaseApp(store: store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '重复风险');
    await tester.pump(); // 按钮由禁用变可用
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(store.entries, hasLength(1));
    expect(store.entries.single.text, '重复风险');
  });
}
