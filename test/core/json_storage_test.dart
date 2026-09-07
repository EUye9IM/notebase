import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/storage/json_storage.dart';

void main() {
  late Directory dir;
  late JsonFileStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('notebase_storage_test');
    storage = JsonFileStorage(dir.path);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  group('JsonFileStorage', () {
    test('notebooks 读写往返；缺失返回空', () async {
      expect(await storage.loadNotebooks(), isEmpty);

      final notebooks = [
        Notebook.createDefault(),
        Notebook(id: 'work', name: '工作', createdAt: DateTime.now()),
      ];
      await storage.saveNotebooks(notebooks);
      final back = await storage.loadNotebooks();
      expect(back, hasLength(2));
      expect(back.map((n) => n.id), containsAll(['default', 'work']));
    });

    test('entries 读写往返；deleteEntries 清除；缺失返回空', () async {
      expect(await storage.loadEntries('default'), isEmpty);

      final entries = [
        Entry(
          id: '1',
          notebookId: 'default',
          type: EntryType.text,
          text: '第一条',
          createdAt: DateTime.now(),
        ),
      ];
      await storage.saveEntries('default', entries);
      final back = await storage.loadEntries('default');
      expect(back, hasLength(1));
      expect(back.single.text, '第一条');

      await storage.deleteEntries('default');
      expect(await storage.loadEntries('default'), isEmpty);
    });

    test('prefs 缺失返回默认值；保存后往返', () async {
      final def = await storage.loadPrefs();
      expect(def.theme, ThemeSetting.system);
      expect(def.currentNotebookId, isNull);

      await storage.savePrefs(
          const Prefs(theme: ThemeSetting.light, currentNotebookId: 'work'));
      final back = await storage.loadPrefs();
      expect(back.theme, ThemeSetting.light);
      expect(back.currentNotebookId, 'work');
    });

    test('baseDir 不存在时写入自动创建', () async {
      final nested = JsonFileStorage('${dir.path}/a/b/c');
      await nested.saveNotebooks([Notebook.createDefault()]);
      expect(await nested.loadNotebooks(), hasLength(1));
      expect(await Directory('${dir.path}/a/b/c').exists(), isTrue);
    });

    test('文件写入为缩进 JSON（可直接人工检查）', () async {
      await storage.savePrefs(const Prefs());
      final raw = await File('${dir.path}/prefs.json').readAsString();
      expect(raw, contains('\n  "theme"'));
    });
  });
}
