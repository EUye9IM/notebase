import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/ui/app.dart';
import 'package:notebase/ui/editor_sheet.dart';

import '../support/memory_storage.dart';

/// M6 评审 P2-1 回归（ui-design §8）：菜单必须按类型给项，且「编辑」不得把
/// 文字写进媒体条目永远不显示的 `entry.text`。
void main() {
  late MemoryStorage storage;
  late AppStore store;

  setUp(() async {
    storage = MemoryStorage();
    store = await AppStore.load(storage);
  });

  Future<Entry> addAudio({String? summary, String? transcript}) async {
    final temp = await store.prepareMediaTemp('ogg');
    await storage.prepareMediaPath(temp.relativePath);
    final entry = await store.addMedia(
      type: EntryType.audio,
      sourceRelativePath: temp.relativePath,
      extension: 'ogg',
      duration: 3,
    );
    if (summary != null) await store.updateEntrySummary(entry.id, summary);
    if (transcript != null) {
      await store.updateEntryTranscript(entry.id, transcript);
    }
    return store.entries.firstWhere((e) => e.id == entry.id);
  }

  Future<Entry> addPhoto({String? summary}) async {
    final temp = await store.prepareMediaTemp('png');
    await storage.prepareMediaPath(temp.relativePath);
    final entry = await store.addMedia(
      type: EntryType.photo,
      sourceRelativePath: temp.relativePath,
      extension: 'png',
    );
    if (summary != null) await store.updateEntrySummary(entry.id, summary);
    return store.entries.firstWhere((e) => e.id == entry.id);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(NotebaseApp(store: store));
    await tester.pumpAndSettle();
  }

  Future<void> openMenuOn(WidgetTester tester, String caption) async {
    await tester.longPress(find.text(caption));
    await tester.pumpAndSettle();
  }

  Future<void> editField(
    WidgetTester tester, {
    required String input,
  }) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(FieldEditorSheet),
        matching: find.byType(TextField),
      ),
      input,
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
  }

  testWidgets('录音条目菜单：编辑转写 / 编辑摘要，没有会写进不可见字段的「编辑」', (tester) async {
    await addAudio(summary: '摘要文字');
    await pumpApp(tester);

    await openMenuOn(tester, '摘要文字');

    expect(find.text('编辑转写'), findsOneWidget);
    expect(find.text('编辑摘要'), findsOneWidget);
    expect(find.text('编辑'), findsNothing); // 关键：不再出现通用「编辑」
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('编辑转写：保存后可见可搜，且不会污染 entry.text', (tester) async {
    final audio = await addAudio(summary: '摘要文字');
    await pumpApp(tester);

    await openMenuOn(tester, '摘要文字');
    await tester.tap(find.text('编辑转写'));
    await tester.pumpAndSettle();
    expect(find.text('编辑转写'), findsOneWidget); // 弹层标题
    await editField(tester, input: '跟师傅约了周三上门');

    final saved = store.entries.firstWhere((e) => e.id == audio.id);
    expect(saved.transcript, '跟师傅约了周三上门');
    expect(saved.text, isNull); // 没有被写进不可见字段
    expect(store.search('周三').single.id, audio.id); // 搜索命中（§7 终态规则）
  });

  testWidgets('编辑摘要：清空保存 = 删除该字段', (tester) async {
    final audio = await addAudio(summary: '待清空的摘要');
    await pumpApp(tester);

    await openMenuOn(tester, '待清空的摘要');
    await tester.tap(find.text('编辑摘要'));
    await tester.pumpAndSettle();
    await editField(tester, input: '   ');

    final saved = store.entries.firstWhere((e) => e.id == audio.id);
    expect(saved.summary, isNull);
    expect(find.text('待清空的摘要'), findsNothing); // 摘要位不再占位
  });

  testWidgets('摘要位点按即编辑：显示摘要就编辑摘要，只有转写则编辑转写', (tester) async {
    await addAudio(summary: '点我编辑摘要');
    await pumpApp(tester);

    await tester.tap(find.text('点我编辑摘要'));
    await tester.pumpAndSettle();
    expect(find.byType(FieldEditorSheet), findsOneWidget);
    expect(find.text('编辑摘要'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 换一条：无摘要但有转写 → 摘要位显示转写首行，点按应编辑转写
    final second = await addAudio(transcript: '转写首行在这里\n第二行');
    await tester.pumpAndSettle();
    await tester.tap(find.text('转写首行在这里'));
    await tester.pumpAndSettle();
    expect(find.byType(FieldEditorSheet), findsOneWidget);
    expect(find.text('编辑转写'), findsOneWidget);
    await editField(tester, input: '改过的转写');
    expect(
      store.entries.firstWhere((e) => e.id == second.id).transcript,
      '改过的转写',
    );
  });

  testWidgets('照片条目菜单：复制 / 编辑摘要 / 删除，没有转写与通用「编辑」', (tester) async {
    await addPhoto(summary: '瓷砖型号');
    await pumpApp(tester);

    await openMenuOn(tester, '瓷砖型号');

    expect(find.text('复制'), findsOneWidget); // §4：整条复制对媒体同样可用
    expect(find.text('编辑摘要'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('编辑转写'), findsNothing); // 照片没有转写
    expect(find.text('编辑'), findsNothing); // 不得出现会写进 entry.text 的通用项
  });
}
