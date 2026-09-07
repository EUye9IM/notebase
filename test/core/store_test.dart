import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/storage/json_storage.dart';
import 'package:notebase/core/store.dart';

void main() {
  late Directory dir;
  late JsonFileStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('notebase_store_test');
    storage = JsonFileStorage(dir.path);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// 重新加载：所有持久化断言都从磁盘走一遍。
  Future<AppStore> reload() => AppStore.load(storage);

  DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  Notebook nb(String id, String name) =>
      Notebook(id: id, name: name, createdAt: at(1));

  Entry textEntry(String id, String text, {int created = 1000}) => Entry(
        id: id,
        notebookId: 'default',
        type: EntryType.text,
        text: text,
        createdAt: at(created),
      );

  Entry mediaEntry(
    String id,
    EntryType type, {
    String? transcript,
    String? summary,
    int created = 1000,
  }) =>
      Entry(
        id: id,
        notebookId: 'default',
        type: type,
        transcript: transcript,
        summary: summary,
        createdAt: at(created),
      );

  group('初始化不变式', () {
    test('空数据创建 default 并设为当前', () async {
      final s = await reload();
      expect(s.notebooks.map((n) => n.id), [Notebook.defaultId]);
      expect(s.currentNotebookId, Notebook.defaultId);
      expect(s.entries, isEmpty);
    });

    test('数据缺 default 时自动补建', () async {
      await storage.saveNotebooks([nb('work', '工作')]);
      final s = await reload();
      expect(s.notebooks.any((n) => n.id == Notebook.defaultId), isTrue);
      expect(s.notebooks, hasLength(2));
    });

    test('失效的 currentNotebookId 回退 default', () async {
      await storage.savePrefs(const Prefs(currentNotebookId: 'nonexistent'));
      final s = await reload();
      expect(s.currentNotebookId, Notebook.defaultId);
    });
  });

  group('文本条目', () {
    test('新增并持久化', () async {
      final s = await reload();
      final added = await s.addText('  买了猫粮  ');
      expect(s.entries.single.text, '买了猫粮'); // trim 后入库
      expect(added.id, isNotEmpty);

      final again = await reload();
      expect(again.entries.single.text, '买了猫粮');
    });

    test('空白文本抛错', () async {
      final s = await reload();
      await expectLater(s.addText('   '), throwsArgumentError);
    });

    test('更新并持久化；不改 createdAt', () async {
      final s = await reload();
      final e = await s.addText('旧');
      await s.updateEntryText(e.id, '新');
      expect(s.entries.single.text, '新');
      expect(s.entries.single.createdAt, e.createdAt);

      final again = await reload();
      expect(again.entries.single.text, '新');
    });

    test('删除并持久化', () async {
      final s = await reload();
      final e = await s.addText('待删除');
      await s.deleteEntry(e.id);
      expect(s.entries, isEmpty);
      expect((await reload()).entries, isEmpty);
    });

    test('未知条目 id 抛错', () async {
      final s = await reload();
      Object? updateErr;
      Object? deleteErr;
      try {
        await s.updateEntryText('nope', 'x');
      } catch (e) {
        updateErr = e;
      }
      try {
        await s.deleteEntry('nope');
      } catch (e) {
        deleteErr = e;
      }
      expect(updateErr, isArgumentError);
      expect(deleteErr, isArgumentError);
    });

    test('条目按时间升序，最新在末尾', () async {
      await storage.saveEntries('default', [
        textEntry('b', '第二条', created: 2000),
        textEntry('a', '第一条', created: 1000),
      ]);
      final s = await reload();
      expect(s.entries.map((e) => e.id), ['a', 'b']);
    });

    test('变更时通知监听器', () async {
      final s = await reload();
      var notified = 0;
      s.addListener(() => notified++);
      await s.addText('触发一次');
      await s.deleteEntry(s.entries.single.id);
      expect(notified, 2);
    });
  });

  group('笔记本', () {
    test('创建即切换并持久化', () async {
      final s = await reload();
      final nb = await s.createNotebook(' 工作 ');
      expect(s.currentNotebookId, nb.id);
      expect(s.currentNotebook.name, '工作');

      final again = await reload();
      expect(again.currentNotebookId, nb.id);
    });

    test('空名抛错', () async {
      final s = await reload();
      await expectLater(s.createNotebook('  '), throwsArgumentError);
    });

    test('重命名持久化；default 拒绝重命名', () async {
      final s = await reload();
      final made = await s.createNotebook('temp');
      await s.renameNotebook(made.id, '改名');
      expect(s.currentNotebook.name, '改名');
      expect((await reload()).currentNotebook.name, '改名');

      await expectLater(
        s.renameNotebook(Notebook.defaultId, 'x'),
        throwsArgumentError,
      );
    });

    test('删除：条目并入 default；当前切回 default', () async {
      final s = await reload();
      final made = await s.createNotebook('待删');
      await s.addText('搬家条目');
      expect(s.entries.single.notebookId, made.id);

      await s.deleteNotebook(made.id);
      expect(s.currentNotebookId, Notebook.defaultId);
      expect(s.entries.single.text, '搬家条目');
      expect(s.notebooks.map((n) => n.id), [Notebook.defaultId]);

      final again = await reload();
      expect(again.entries.single.text, '搬家条目');
      expect(await storage.loadEntries(made.id), isEmpty); // 源文件已删
    });

    test('default 拒绝删除', () async {
      final s = await reload();
      await expectLater(
        s.deleteNotebook(Notebook.defaultId),
        throwsArgumentError,
      );
    });

    test('切换时惰性加载对应条目并持久化偏好', () async {
      await storage.saveNotebooks([nb('work', '工作'), nb('default', 'default')]);
      await storage.saveEntries('work', [textEntry('w1', '工作笔记')]);
      final s = await reload(); // 当前 default，work 尚未加载
      expect(s.entries, isEmpty);

      await s.switchNotebook('work');
      expect(s.entries.single.text, '工作笔记');

      expect((await reload()).currentNotebookId, 'work'); // 偏好已持久化
    });
  });

  group('搜索（ui-design §7 终态规则）', () {
    test('文本命中正文；大小写不敏感', () async {
      await storage.saveEntries('default', [
        textEntry('a', 'Shopping List'),
        textEntry('b', 'nothing here'),
      ]);
      final s = await reload();
      expect(s.search('shopping').single.id, 'a');
      expect(s.search('LIST').single.id, 'a');
    });

    test('照片命中摘要；无摘要不命中', () async {
      await storage.saveEntries('default', [
        mediaEntry('p1', EntryType.photo, summary: '瓷砖型号确认'),
        mediaEntry('p2', EntryType.photo),
      ]);
      final s = await reload();
      expect(s.search('瓷砖').single.id, 'p1');
      expect(s.search('p1'), isEmpty); // 无文本可命中
    });

    test('录音命中转写或摘要', () async {
      await storage.saveEntries('default', [
        mediaEntry('a1', EntryType.audio, transcript: '跟师傅约了周三上门'),
        mediaEntry('a2', EntryType.audio, summary: '会议要点'),
        mediaEntry('a3', EntryType.audio),
      ]);
      final s = await reload();
      expect(s.search('师傅').single.id, 'a1');
      expect(s.search('会议').single.id, 'a2');
      expect(s.search('周三'), hasLength(1));
    });

    test('空关键词返回空；结果最新在前', () async {
      await storage.saveEntries('default', [
        textEntry('old', '猫粮', created: 1000),
        textEntry('new', '猫砂', created: 2000),
      ]);
      final s = await reload();
      expect(s.search('  '), isEmpty);
      expect(s.search('猫').map((e) => e.id), ['new', 'old']);
    });

    test('仅搜索当前笔记本', () async {
      await storage.saveNotebooks([nb('work', '工作'), nb('default', 'default')]);
      await storage.saveEntries('default', [textEntry('d1', '家里的猫')]);
      await storage.saveEntries('work', [textEntry('w1', '公司的猫')]);
      await storage.savePrefs(const Prefs(currentNotebookId: 'work'));

      final s = await reload();
      expect(s.currentNotebookId, 'work');
      expect(s.search('猫').single.id, 'w1');
    });
  });

  group('偏好', () {
    test('主题切换持久化', () async {
      final s = await reload();
      expect(s.theme, ThemeSetting.system);
      await s.setTheme(ThemeSetting.dark);
      expect((await reload()).theme, ThemeSetting.dark);
    });
  });
}
