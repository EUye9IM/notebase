import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/startup.dart';

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
}
