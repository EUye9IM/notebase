import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/startup.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/core/storage/json_storage.dart';

import '../support/memory_storage.dart';

/// 启动期数据损坏兜底（ui-design §10）：解析失败不 crash 在启动路径上，
/// 隔离坏文件后以 default 启动；连兜底都失败才抛给 UI 出错误界面。
class _FlakyStorage extends MemoryStorage {
  bool corrupt = true;

  @override
  Future<List<Notebook>> loadNotebooks() async {
    if (corrupt) throw const FormatException('坏掉的 notebooks.json');
    return super.loadNotebooks();
  }

  @override
  Future<List<String>> quarantineCorruptFiles() async {
    corrupt = false; // 隔离把坏文件挪走，之后的加载恢复正常
    return ['notebooks.json.corrupt-1'];
  }
}

class _AlwaysBrokenStorage extends MemoryStorage {
  @override
  Future<List<Notebook>> loadNotebooks() async =>
      throw const FormatException('怎么也读不出来');
}

void main() {
  test('数据损坏 → 隔离 → 以 default 启动，并带回隔离清单', () async {
    final result = await loadStoreResilient(_FlakyStorage());

    expect(result.quarantined, ['notebooks.json.corrupt-1']);
    expect(result.error, isA<FormatException>());
    expect(result.store.notebooks.map((n) => n.id), [Notebook.defaultId]);
    expect(result.store.entries, isEmpty);
  });

  test('健康数据：不触发隔离，无错误信息', () async {
    final result = await loadStoreResilient(MemoryStorage());

    expect(result.error, isNull);
    expect(result.quarantined, isEmpty);
    expect(result.store.notebooks.map((n) => n.id), [Notebook.defaultId]);
  });

  test('兜底仍失败则向上抛，交给 UI 出可读错误界面', () async {
    await expectLater(
      loadStoreResilient(_AlwaysBrokenStorage()),
      throwsFormatException,
    );
  });

  group('真实文件：启动扫描与切本原子性（P2-3 / P2-4 回归）', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('notebase_startup_test');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('非当前笔记本的坏 nb_*.json 在启动时也被隔离', () async {
      final storage = JsonFileStorage(dir.path);
      await storage.saveNotebooks([
        Notebook.createDefault(),
        Notebook(id: 'work', name: '工作', createdAt: DateTime.now()),
      ]);
      // 坏的是「非当前」笔记本：首次加载只读当前本，惰性加载不会暴露它
      await File('${dir.path}/nb_work.json').writeAsString('{ 坏文件');

      final result = await loadStoreResilient(storage);

      expect(result.error, isNull); // 当前本没坏，首次加载成功
      expect(result.quarantined.single, startsWith('nb_work.json.corrupt-'));

      // 关键：切到该笔记本不再抛错（隔离后按「缺文件」处理）
      await result.store.switchNotebook('work');
      expect(result.store.currentNotebookId, 'work');
      expect(result.store.entries, isEmpty);
    });

    test('切本失败不改变当前状态（原子性）', () async {
      final storage = JsonFileStorage(dir.path);
      await storage.saveNotebooks([
        Notebook.createDefault(),
        Notebook(id: 'work', name: '工作', createdAt: DateTime.now()),
      ]);
      await File('${dir.path}/nb_work.json').writeAsString('{ 坏文件');

      // 绕过启动扫描（直接用 AppStore.load）：模拟「运行期才损坏」
      final store = await AppStore.load(storage);
      await expectLater(store.switchNotebook('work'), throwsFormatException);
      expect(store.currentNotebookId, Notebook.defaultId); // 未停在半切换态
      expect(store.currentNotebook.name, 'default');
    });

    test('prefs 结构坏：回默认值启动，不再挡住启动（P2-4 回归）', () async {
      final storage = JsonFileStorage(dir.path);
      await File('${dir.path}/prefs.json')
          .writeAsString('{"theme": 5, "currentNotebookId": 123}');

      final result = await loadStoreResilient(storage);

      expect(result.error, isNull); // 不再抛 TypeError
      expect(result.store.theme, ThemeSetting.system); // 主题回默认
      expect(result.store.currentNotebookId, Notebook.defaultId);
    });
  });
}
