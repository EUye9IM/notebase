import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/ui/app.dart';
import 'package:notebase/ui/input_bar.dart';
import 'package:notebase/ui/settings_view.dart';

import '../support/memory_storage.dart';

/// 设置页（ui-design §3）：独立整页，宽窄屏一致；主题三态走 core 偏好。
/// 此前设置是底部弹层且整体没有 widget 测试（复检指出），这次一并补上。
void main() {
  Future<AppStore> storeWith() async => AppStore.load(MemoryStorage());

  Future<void> pumpApp(WidgetTester tester, AppStore store) async {
    await tester.pumpWidget(NotebaseApp(store: store));
    await tester.pumpAndSettle();
  }

  void useNarrow(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('窄屏：顶栏 ⚙ 打开整页设置，切主题并返回', (tester) async {
    useNarrow(tester);
    final store = await storeWith();
    await pumpApp(tester, store);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.byType(RadioListTile<ThemeSetting>), findsNWidgets(3));

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(store.theme, ThemeSetting.dark);

    await tester.tap(find.byType(BackButton)); // 返回壳
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(InputBar), findsOneWidget);
  });

  testWidgets('宽屏：侧栏「设置」也打开同一个整页', (tester) async {
    final storage = MemoryStorage();
    final store = await AppStore.load(storage);
    await pumpApp(tester, store); // 默认 800x600 → 宽屏

    await tester.tap(find.widgetWithText(ListTile, '设置'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);

    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(store.theme, ThemeSetting.light);
    expect((await AppStore.load(storage)).theme, ThemeSetting.light); // 落盘
  });
}
