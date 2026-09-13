import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/ui/app.dart';
import 'package:notebase/ui/media_player.dart';
import 'package:notebase/ui/stream_view.dart';

import '../support/memory_storage.dart';

/// M6c 验收（ui-design §4 / §8）：音频内联播放、进度、同一时刻只播一条、
/// 摘要/转写兜底渲染。
class FakeMediaPlayer implements MediaPlayer {
  final playedPaths = <String>[];

  /// 非 null 时 play() 会挂起，用于制造并发窗口。
  Completer<void>? playGate;
  final _complete = StreamController<void>.broadcast();
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;
  Duration currentPosition = Duration.zero;

  /// 触发一次「自然播放完成」。
  void complete() => _complete.add(null);

  @override
  Future<void> play(String absolutePath) async {
    playedPaths.add(absolutePath);
    if (playGate != null) await playGate!.future;
  }

  @override
  Future<void> pause() async => pauseCount++;

  @override
  Future<void> resume() async => resumeCount++;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<Duration> position() async => currentPosition;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Future<void> dispose() => _complete.close();
}

void main() {
  late MemoryStorage storage;
  late AppStore store;

  setUp(() async {
    storage = MemoryStorage();
    store = await AppStore.load(storage);
  });

  /// 造一条录音：临时文件 → 归档（与 M6b 的真实链路一致）。
  Future<Entry> addAudio({
    double? duration = 3,
    String? summary,
    String? transcript,
  }) async {
    final temp = await store.prepareMediaTemp('ogg');
    await storage.prepareMediaPath(temp.relativePath);
    final entry = await store.addMedia(
      type: EntryType.audio,
      sourceRelativePath: temp.relativePath,
      extension: 'ogg',
      duration: duration,
    );
    if (summary != null) await store.updateEntrySummary(entry.id, summary);
    if (transcript != null) {
      await store.updateEntryTranscript(entry.id, transcript);
    }
    return store.entries.firstWhere((e) => e.id == entry.id);
  }

  Future<void> pumpApp(WidgetTester tester, {MediaPlayer? player}) async {
    await tester.pumpWidget(NotebaseApp(store: store, player: player));
    await tester.pumpAndSettle();
  }

  group('音频行渲染（§4）', () {
    testWidgets('显示时长；摘要渲染在下方', (tester) async {
      await addAudio(duration: 42, summary: '跟师傅确认瓷砖型号');
      await pumpApp(tester);

      expect(find.text('00:42'), findsOneWidget);
      expect(find.text('跟师傅确认瓷砖型号'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
    });

    testWidgets('无摘要但有转写：转写首行兜底；都没有则不占位', (tester) async {
      await addAudio(transcript: '第一行转写\n第二行内容');
      await pumpApp(tester);

      expect(find.text('第一行转写'), findsOneWidget);
      expect(find.text('第二行内容'), findsNothing); // 只显示首行
    });

    testWidgets('时长未知显示 --:--', (tester) async {
      await addAudio(duration: null);
      await pumpApp(tester);
      expect(find.text('--:--'), findsOneWidget);
    });
  });

  group('内联播放（§8）', () {
    testWidgets('点音频行开始播放：路径来自 core 落点约定', (tester) async {
      final entry = await addAudio();
      final player = FakeMediaPlayer();
      await pumpApp(tester, player: player);

      await tester.tap(find.byIcon(Icons.play_circle_filled));
      await tester.pumpAndSettle();

      expect(player.playedPaths, ['/memory/${entry.file}']);
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget); // 变为暂停
    });

    testWidgets('再点一次暂停，第三次继续', (tester) async {
      await addAudio();
      final player = FakeMediaPlayer();
      await pumpApp(tester, player: player);

      await tester.tap(find.byIcon(Icons.play_circle_filled));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.pause_circle_filled));
      await tester.pumpAndSettle();
      expect(player.pauseCount, 1);
      expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_circle_filled));
      await tester.pumpAndSettle();
      expect(player.resumeCount, 1);
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
    });

    testWidgets('播放另一条时前一条停止（同一时刻只播一条）', (tester) async {
      await addAudio(summary: '第一条');
      await addAudio(summary: '第二条');
      final player = FakeMediaPlayer();
      await pumpApp(tester, player: player);

      final rows = find.byIcon(Icons.play_circle_filled);
      await tester.tap(rows.first); // 最新的那条（列表末尾在上方？取第一个可见行）
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.play_circle_filled).first);
      await tester.pumpAndSettle();

      expect(player.playedPaths, hasLength(2));
      expect(player.stopCount, greaterThanOrEqualTo(1));
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget); // 只有一条在播
    });

    testWidgets('自然播放完成：复位为可播放状态', (tester) async {
      await addAudio();
      final player = FakeMediaPlayer();
      await pumpApp(tester, player: player);

      await tester.tap(find.byIcon(Icons.play_circle_filled));
      await tester.pumpAndSettle();
      player.complete();
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_filled), findsNothing);
    });

    testWidgets('播放中进度随位置更新', (tester) async {
      final entry = await addAudio(duration: 10);
      final player = FakeMediaPlayer()..currentPosition = const Duration(seconds: 5);
      await pumpApp(tester, player: player);

      await tester.tap(find.byIcon(Icons.play_circle_filled));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250)); // 等一次进度 tick

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.5, 0.01)); // 5s / 10s
      expect(entry.type, EntryType.audio); // 顺带确认播放的是媒体条目
    });

    // P2-2 回归：两次点击都发生在第一次 play 尚未返回的窗口内时，
    // 「同一时刻只播一条」与「播放态标对行」都必须成立。
    testWidgets('并发点两条：底层操作串行、最终只播最后点击的那条、标对行', (tester) async {
      final first = await addAudio(summary: '第一条');
      final second = await addAudio(summary: '第二条');
      final player = FakeMediaPlayer()..playGate = Completer<void>();
      await pumpApp(tester, player: player);

      await tester.tap(find.byIcon(Icons.play_circle_filled).first);
      await tester.pump(); // 不 settle：第一次 play 悬在窗口里
      await tester.tap(find.byIcon(Icons.play_circle_filled).first);
      await tester.pump();

      // 串行化：第一次 play 未返回前，第二次 play 不得下发
      // （修复前这里是并发两次 play、且谁都没被 stop）
      expect(player.playedPaths, hasLength(1));
      expect(player.playedPaths.single, '/memory/${first.file}');

      player.playGate!.complete();
      await tester.pumpAndSettle();

      expect(player.playedPaths.last, '/memory/${second.file}'); // 最后播的是后点的
      expect(player.stopCount, greaterThanOrEqualTo(1)); // 且中途停过一次
      final playingRow = find.ancestor(
        of: find.byIcon(Icons.pause_circle_filled),
        matching: find.byType(EntryTile),
      );
      expect(
        find.descendant(of: playingRow, matching: find.text('第二条')),
        findsOneWidget, // 播放态落在最后点击的那条，不被返回顺序左右
      );
    });

    // P3-1 回归：删除正在播放的条目要停播，否则进度定时器空转。
    testWidgets('删除正在播放的条目：停止播放并复位', (tester) async {
      await addAudio(summary: '要删的');
      final player = FakeMediaPlayer();
      await pumpApp(tester, player: player);

      await tester.tap(find.byIcon(Icons.play_circle_filled));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

      await tester.longPress(find.text('要删的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(player.stopCount, greaterThanOrEqualTo(1));
      expect(find.byIcon(Icons.pause_circle_filled), findsNothing);
    });

    testWidgets('未注入播放能力：行仍渲染但不可播放，点击不抛错', (tester) async {
      await addAudio(duration: 3, summary: '静静躺着');
      await pumpApp(tester); // 无 player

      expect(find.text('00:03'), findsOneWidget);
      expect(find.text('静静躺着'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_circle_filled));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
