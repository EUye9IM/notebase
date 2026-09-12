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

    // M3 评审 P1 回归：固定临时文件名 + 无串行化时，并发写会在 rename
    // 处抛 PathNotFoundException（实测 120/120 轮），且可能静默丢数据。
    test('并发写同一文件：不抛错且按提交顺序串行生效', () async {
      final all = [
        for (var i = 1; i <= 20; i++)
          Entry(
            id: '$i',
            notebookId: 'default',
            type: EntryType.text,
            text: 't$i',
            createdAt: DateTime.fromMillisecondsSinceEpoch(i),
          ),
      ];
      await Future.wait([
        for (var i = 1; i <= 20; i++)
          storage.saveEntries('default', all.take(i).toList()),
      ]);
      // 最后一次提交的写入最后落地 → 全量 20 条，且无并发异常。
      expect(await storage.loadEntries('default'), hasLength(20));
    });

    // 启动期数据损坏兜底（ui-design §10）：坏文件改名保留，之后按缺失处理。
    test('隔离损坏文件：改名保留、返回清单、正常文件不受影响', () async {
      await storage.saveNotebooks([Notebook.createDefault()]);
      await File('${dir.path}/nb_default.json').writeAsString('{ 坏掉的 JSON');
      await File('${dir.path}/nb_work.json').writeAsString(
          '[{"id":"1","notebookId":"work","type":"video","createdAt":1}]'); // 结构坏
      await storage.savePrefs(const Prefs(theme: ThemeSetting.dark));

      final quarantined = await storage.quarantineCorruptFiles();
      expect(quarantined, hasLength(2));
      expect(quarantined.any((n) => n.startsWith('nb_default.json.corrupt-')),
          isTrue);
      expect(quarantined.any((n) => n.startsWith('nb_work.json.corrupt-')),
          isTrue);

      // 坏文件已挪走：之后按「文件缺失」返回空，应用得以启动
      expect(await storage.loadEntries('default'), isEmpty);
      expect(await storage.loadEntries('work'), isEmpty);
      expect((await storage.loadPrefs()).theme, ThemeSetting.dark); // 未受影响
      for (final name in quarantined) {
        expect(File('${dir.path}/$name').existsSync(), isTrue); // 备份仍在
      }
    });

    test('隔离对健康数据无副作用', () async {
      await storage.saveNotebooks([Notebook.createDefault()]);
      await storage.saveEntries('default', [
        Entry(
          id: '1',
          notebookId: 'default',
          type: EntryType.text,
          text: '好数据',
          createdAt: DateTime.now(),
        ),
      ]);
      expect(await storage.quarantineCorruptFiles(), isEmpty);
      expect(await storage.loadEntries('default'), hasLength(1));
    });

    // 队列毒化回归：前序写失败后，该路径仍必须可写。
    test('前序写入失败不毒化队列：故障排除后可继续写', () async {
      final blocked = File('${dir.path}/blocked');
      await blocked.writeAsString('占位文件：让目录创建失败');
      final bad = JsonFileStorage(blocked.path);

      await expectLater(
        bad.savePrefs(const Prefs()),
        throwsA(isA<FileSystemException>()),
      );

      await blocked.delete(); // 故障排除，同一实例继续写
      await bad.savePrefs(const Prefs(theme: ThemeSetting.dark));
      expect((await bad.loadPrefs()).theme, ThemeSetting.dark);
    });
  });
}
