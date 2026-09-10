import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/ui/app.dart';

import '../support/memory_storage.dart';

/// M3 验收（ui-design §6、§11）：
/// 切换笔记本 = 宽屏 1 步 / 窄屏 2 步；新建并切换 = 3 步；
/// 删除笔记本条目并入 default，条目永不陪葬。
void main() {
  /// 建好「工作」笔记本并回到 default，便于测试切换。
  Future<AppStore> storeWithWorkNotebook() async {
    final store = await AppStore.load(MemoryStorage());
    await store.createNotebook('工作');
    await store.switchNotebook(Notebook.defaultId);
    return store;
  }

  Future<void> pumpApp(WidgetTester tester, AppStore store) async {
    await tester.pumpWidget(NotebaseApp(store: store));
    await tester.pumpAndSettle();
  }

  void useNarrowWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('宽屏：侧栏点按切换笔记本（1 步）', (tester) async {
    final store = await storeWithWorkNotebook();
    await pumpApp(tester, store);

    await tester.tap(find.text('工作'));
    await tester.pumpAndSettle();

    expect(store.currentNotebook.name, '工作');
  });

  testWidgets('窄屏：顶栏弹层切换笔记本（2 步）', (tester) async {
    useNarrowWindow(tester);
    final store = await storeWithWorkNotebook();
    await pumpApp(tester, store);

    await tester.tap(find.byIcon(Icons.arrow_drop_down)); // 点顶栏笔记本名
    await tester.pumpAndSettle();
    expect(find.text('新建笔记本'), findsOneWidget); // 弹层已展开

    await tester.tap(find.text('工作'));
    await tester.pumpAndSettle();

    expect(store.currentNotebook.name, '工作');
    expect(find.text('新建笔记本'), findsNothing); // 弹层已关闭
  });

  testWidgets('新建笔记本：对话框 → 创建 → 立即切换为当前', (tester) async {
    final store = await AppStore.load(MemoryStorage());
    await pumpApp(tester, store);

    await tester.tap(find.text('新建笔记本'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '灵感',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(store.notebooks.map((n) => n.name), contains('灵感'));
    expect(store.currentNotebook.name, '灵感');
  });

  testWidgets('新建对话框：空名拦截', (tester) async {
    final store = await AppStore.load(MemoryStorage());
    await pumpApp(tester, store);

    await tester.tap(find.text('新建笔记本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(find.text('名称不能为空'), findsOneWidget); // 对话框未关闭
    expect(store.notebooks, hasLength(1));
  });

  testWidgets('长按菜单删除笔记本：确认文案含条目数，条目并入 default', (tester) async {
    final store = await AppStore.load(MemoryStorage());
    await store.createNotebook('工作');
    await store.addText('搬家条目');
    await pumpApp(tester, store);

    await tester.longPress(find.text('工作').first); // 侧栏行（当前笔记本）
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('其中 1 条记录将移入 default。'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(store.notebooks.map((n) => n.name), ['default']);
    expect(store.currentNotebookId, Notebook.defaultId);
    expect(store.entries.single.text, '搬家条目'); // 条目未陪葬
  });

  testWidgets('桌面右键菜单：重命名笔记本', (tester) async {
    final store = await storeWithWorkNotebook();
    await pumpApp(tester, store);

    await tester.tapAt(
      tester.getCenter(find.text('工作')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '工作区',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(store.notebooks.map((n) => n.name), contains('工作区'));
  });

  testWidgets('default 笔记本没有管理菜单', (tester) async {
    final store = await AppStore.load(MemoryStorage());
    await pumpApp(tester, store);

    await tester.longPress(find.text('default').first);
    await tester.pumpAndSettle();

    expect(find.text('重命名'), findsNothing);
    expect(find.text('删除'), findsNothing);
  });
}
