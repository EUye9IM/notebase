import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';

final _t0 = DateTime.fromMillisecondsSinceEpoch(1700000000000);

void main() {
  group('Entry JSON', () {
    test('文本条目最小字段往返，空字段不序列化', () {
      final entry = Entry(
        id: '1',
        notebookId: 'default',
        type: EntryType.text,
        text: 'hello',
        createdAt: _t0,
      );
      final json = entry.toJson();
      expect(json.containsKey('text'), isTrue);
      expect(json.containsKey('file'), isFalse);
      expect(json.containsKey('duration'), isFalse);
      expect(json.containsKey('transcript'), isFalse);
      expect(json.containsKey('summary'), isFalse);

      final back = Entry.fromJson(json);
      expect(back.id, entry.id);
      expect(back.notebookId, entry.notebookId);
      expect(back.type, EntryType.text);
      expect(back.text, 'hello');
      expect(back.createdAt, entry.createdAt);
      expect(back.file, isNull);
    });

    test('媒体条目全字段往返', () {
      final entry = Entry(
        id: '2',
        notebookId: 'default',
        type: EntryType.audio,
        file: 'media/2.m4a',
        duration: 42.5,
        transcript: '转写全文',
        summary: '摘要',
        createdAt: _t0,
      );
      final back = Entry.fromJson(entry.toJson());
      expect(back.type, EntryType.audio);
      expect(back.file, 'media/2.m4a');
      expect(back.duration, 42.5);
      expect(back.transcript, '转写全文');
      expect(back.summary, '摘要');
    });

    test('未知 type 抛 FormatException（数据损坏应当可见）', () {
      expect(
        () => Entry.fromJson({
          'id': '3',
          'notebookId': 'default',
          'type': 'video',
          'createdAt': 1700000000000,
        }),
        throwsFormatException,
      );
    });

    test('copyWith 可显式置空（清空转写/摘要 = 删除该字段）', () {
      final entry = Entry(
        id: '4',
        notebookId: 'default',
        type: EntryType.audio,
        transcript: '旧转写',
        summary: '旧摘要',
        createdAt: _t0,
      );
      final cleared = entry.copyWith(transcript: null, summary: null);
      expect(cleared.transcript, isNull);
      expect(cleared.summary, isNull);
      // 未指定字段保持不变
      expect(cleared.id, '4');
      expect(cleared.type, EntryType.audio);
    });
  });

  group('Notebook JSON', () {
    test('往返', () {
      final nb = Notebook(id: 'work', name: '工作', createdAt: _t0);
      final back = Notebook.fromJson(nb.toJson());
      expect(back.id, 'work');
      expect(back.name, '工作');
      expect(back.createdAt, _t0);
    });
  });

  group('Prefs JSON', () {
    test('默认值与往返', () {
      const prefs = Prefs();
      expect(prefs.theme, ThemeSetting.system);
      expect(prefs.currentNotebookId, isNull);
      expect(Prefs.fromJson(prefs.toJson()).theme, ThemeSetting.system);

      const set = Prefs(theme: ThemeSetting.dark, currentNotebookId: 'work');
      final back = Prefs.fromJson(set.toJson());
      expect(back.theme, ThemeSetting.dark);
      expect(back.currentNotebookId, 'work');
    });

    test('未知主题回退 system', () {
      expect(
        Prefs.fromJson({'theme': 'pink'}).theme,
        ThemeSetting.system,
      );
    });
  });
}
