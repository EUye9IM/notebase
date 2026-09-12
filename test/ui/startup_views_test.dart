import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/startup.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/ui/startup_views.dart';

import '../support/memory_storage.dart';

/// 启动期视图（ui-design §10）：文案不谎报、超长不溢出、错误界面可读。
void main() {
  Future<AppStore> freshStore() => AppStore.load(MemoryStorage());

  group('startupNoticeText（纯函数）', () {
    test('无错误、无隔离 → 无提示', () async {
      final result = StoreLoadResult(store: await freshStore());
      expect(startupNoticeText(result), isNull);
    });

    test('有隔离 → 点名备份文件；多于两个时折叠计数', () async {
      final store = await freshStore();
      expect(
        startupNoticeText(
          StoreLoadResult(store: store, quarantined: ['nb_default.json.corrupt-1']),
        ),
        contains('nb_default.json.corrupt-1'),
      );
      final many = startupNoticeText(StoreLoadResult(
        store: store,
        quarantined: ['a.json.corrupt-1', 'b', 'c', 'd'],
      ))!;
      expect(many, contains('等 4 个文件'));
    });

    // P3-3 回归：首次读失败但重试成功、且没有文件被隔离时，数据是完好的，
    // 不能谎称「已重置为空白笔记本」。
    test('仅首次读取失败（无隔离）→ 不谎报已重置', () async {
      final text = startupNoticeText(StoreLoadResult(
        store: await freshStore(),
        error: const FormatException('坏'),
      ))!;
      expect(text, contains('已用可用数据继续'));
      expect(text, isNot(contains('重置')));
    });
  });

  group('StartupNotice', () {
    Future<void> pumpNotice(WidgetTester tester, String message) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            StartupNotice(message: message, onDismiss: () {}),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
    }

    String longMessage() =>
        List.generate(30, (i) => 'nb_x$i.json.corrupt-1789227951060').join('、');

    // P3-2 回归：文案很长时只折叠，不挤爆布局（评审实测 30 行会 overflow）。
    testWidgets('宽屏超长文案不溢出', (tester) async {
      await pumpNotice(tester, longMessage());
      expect(tester.takeException(), isNull);
    });

    testWidgets('窄屏超长文案不溢出，且可关闭', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpNotice(tester, longMessage());
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('知道了'), findsOneWidget);
    });
  });

  group('StartupErrorApp', () {
    testWidgets('渲染原因与目录，可滚动不溢出', (tester) async {
      await tester.pumpWidget(const StartupErrorApp(
        message: 'FormatException: 手工写坏',
        directory: '/tmp/notebase-data',
      ));
      await tester.pumpAndSettle();

      expect(find.text('数据目录无法读取，Notebase 无法启动'), findsOneWidget);
      expect(find.textContaining('/tmp/notebase-data'), findsOneWidget);
      expect(find.textContaining('FormatException'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
