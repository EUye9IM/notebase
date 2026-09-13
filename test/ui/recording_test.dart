import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/ui/app.dart';
import 'package:notebase/ui/media_recorder.dart';

import '../support/memory_storage.dart';

/// M6b 验收（ui-design §5.2）：录音状态机、时长守卫、丢弃、中断兜底。
/// 用假录音器驱动，widget 测试不触碰平台通道。
class FakeMediaRecorder implements MediaRecorder {
  FakeMediaRecorder({
    this.unavailable,
    this.stopDuration = const Duration(seconds: 3),
    this.levelValue = 0.5,
    this.throwOnLevel = false,
  });

  /// 非 null 表示不可用（缺二进制 / 无权限等），内容即原因。
  final String? unavailable;
  final Duration stopDuration;
  final double levelValue;
  final bool throwOnLevel;

  final startedPaths = <String>[];
  bool discarded = false;
  bool stopped = false;
  bool disposed = false;
  int levelCalls = 0;

  @override
  Future<String?> unavailableReason() async => unavailable;

  @override
  Future<void> start(String path) async => startedPaths.add(path);

  @override
  Future<Duration> stop() async {
    stopped = true;
    return stopDuration;
  }

  @override
  Future<void> discard() async => discarded = true;

  @override
  Future<double> level() async {
    levelCalls++;
    if (throwOnLevel) throw StateError('设备被抢占');
    return levelValue;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  Future<(AppStore, MemoryStorage)> freshStore() async {
    final storage = MemoryStorage();
    return (await AppStore.load(storage), storage);
  }

  Future<void> pumpApp(
    WidgetTester tester,
    AppStore store, {
    MediaRecorder? recorder,
  }) async {
    await tester.pumpWidget(NotebaseApp(store: store, recorder: recorder));
    await tester.pumpAndSettle();
  }

  // 用图标定位 IconButton 本体（byTooltip 命中的是 Tooltip 包装，取不到按钮状态）
  Finder recordButton() => find.widgetWithIcon(IconButton, Icons.mic_none);
  Finder saveButton() => find.widgetWithIcon(IconButton, Icons.check);
  Finder discardButton() => find.widgetWithIcon(IconButton, Icons.close);

  Iterable<String> tempFiles(MemoryStorage storage) =>
      storage.media.keys.where((k) => k.contains('.tmp'));

  group('录音状态机（§5.2）', () {
    testWidgets('点 🎤 进入录音态：输入栏被录音条替换并开始计时', (tester) async {
      final (store, storage) = await freshStore();
      final recorder = FakeMediaRecorder();
      await pumpApp(tester, store, recorder: recorder);

      await tester.tap(recordButton());
      await tester.pumpAndSettle();

      expect(recorder.startedPaths, hasLength(1)); // 已开始录音
      expect(tempFiles(storage), hasLength(1)); // 已准备临时落点
      expect(saveButton(), findsOneWidget);
      expect(discardButton(), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // 输入框被替换

      await tester.pump(const Duration(seconds: 1)); // 计时在走：秒数增加
      await tester.pumpAndSettle();
      expect(find.text('00:01'), findsOneWidget);
    });

    testWidgets('✓ 停止即保存：生成录音条目，文件名与时长正确', (tester) async {
      final (store, storage) = await freshStore();
      final recorder = FakeMediaRecorder(
        stopDuration: const Duration(milliseconds: 2500),
      );
      await pumpApp(tester, store, recorder: recorder);

      await tester.tap(recordButton());
      await tester.pumpAndSettle();
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(recorder.stopped, isTrue);
      final entry = store.entries.single;
      expect(entry.type, EntryType.audio);
      expect(entry.file, 'media/${entry.id}.ogg'); // 命名约定
      expect(entry.duration, closeTo(2.5, 0.01));
      expect(tempFiles(storage), isEmpty); // 临时文件已归档
      expect(storage.media.keys, contains(entry.file));
      expect(find.byType(TextField), findsOneWidget); // 回到输入栏
      expect(recordButton(), findsOneWidget);
    });

    testWidgets('时长 < 1s 视为误触：丢弃并提示「太短了」', (tester) async {
      final (store, storage) = await freshStore();
      final recorder = FakeMediaRecorder(
        stopDuration: const Duration(milliseconds: 400),
      );
      await pumpApp(tester, store, recorder: recorder);

      await tester.tap(recordButton());
      await tester.pumpAndSettle();
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(store.entries, isEmpty);
      expect(tempFiles(storage), isEmpty); // 临时文件被清掉
      expect(find.text('太短了'), findsOneWidget);
    });

    testWidgets('✗ 立即丢弃：不留条目也不留文件', (tester) async {
      final (store, storage) = await freshStore();
      final recorder = FakeMediaRecorder();
      await pumpApp(tester, store, recorder: recorder);

      await tester.tap(recordButton());
      await tester.pumpAndSettle();
      await tester.tap(discardButton());
      await tester.pumpAndSettle();

      expect(recorder.discarded, isTrue);
      expect(store.entries, isEmpty);
      expect(tempFiles(storage), isEmpty);
      expect(find.byType(TextField), findsOneWidget); // 回到输入栏
    });
  });

  group('可用性与中断（§5.2 / §10）', () {
    testWidgets('不可用时给出可读原因，不进入录音态', (tester) async {
      final (store, _) = await freshStore();
      final recorder = FakeMediaRecorder(
        unavailable: '系统缺少 parecord，无法录音（需安装 pulseaudio-utils 与 ffmpeg）',
      );
      await pumpApp(tester, store, recorder: recorder);

      await tester.tap(recordButton());
      await tester.pumpAndSettle();

      expect(find.textContaining('系统缺少 parecord'), findsOneWidget);
      expect(recorder.startedPaths, isEmpty);
      expect(find.byType(TextField), findsOneWidget); // 未进入录音态
    });

    testWidgets('未注入录音能力时 🎤 置灰', (tester) async {
      final (store, _) = await freshStore();
      await pumpApp(tester, store);

      final button = tester.widget<IconButton>(recordButton());
      expect(button.onPressed, isNull);
    });

    testWidgets('录音中断（设备被抢占）：保存已录部分并提示', (tester) async {
      final (store, storage) = await freshStore();
      final recorder = FakeMediaRecorder(
        throwOnLevel: true,
        stopDuration: const Duration(seconds: 4),
      );
      await pumpApp(tester, store, recorder: recorder);

      await tester.tap(recordButton());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300)); // 触发一次 tick → 抛错

      expect(find.textContaining('已保存已录部分'), findsOneWidget);
      expect(store.entries.single.type, EntryType.audio);
      expect(tempFiles(storage), isEmpty);
    });

    testWidgets('电平来自真实采集：展示值随录音器返回变化', (tester) async {
      final (store, _) = await freshStore();
      final recorder = FakeMediaRecorder(levelValue: 1.0);
      await pumpApp(tester, store, recorder: recorder);

      await tester.tap(recordButton());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));

      expect(recorder.levelCalls, greaterThan(0)); // 真的去采集了
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 1.0);
    });
  });
}
