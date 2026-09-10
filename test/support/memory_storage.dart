import 'package:notebase/core/model.dart';
import 'package:notebase/core/storage/storage.dart';

/// 内存 Storage：widget 测试用，避免触碰真实文件系统与平台目录。
class MemoryStorage implements Storage {
  final _notebooks = <Notebook>[];
  final _entries = <String, List<Entry>>{};
  Prefs _prefs = const Prefs();

  @override
  Future<List<Notebook>> loadNotebooks() async => List.of(_notebooks);

  @override
  Future<void> saveNotebooks(List<Notebook> notebooks) async {
    _notebooks
      ..clear()
      ..addAll(notebooks);
  }

  @override
  Future<List<Entry>> loadEntries(String notebookId) async =>
      List.of(_entries[notebookId] ?? const []);

  @override
  Future<void> saveEntries(String notebookId, List<Entry> entries) async {
    _entries[notebookId] = List.of(entries);
  }

  @override
  Future<void> deleteEntries(String notebookId) async {
    _entries.remove(notebookId);
  }

  @override
  Future<Prefs> loadPrefs() async => _prefs;

  @override
  Future<void> savePrefs(Prefs prefs) async {
    _prefs = prefs;
  }
}

/// 带写延迟的内存 Storage：模拟真实磁盘写窗口，用于发送重入类测试。
class SlowMemoryStorage extends MemoryStorage {
  SlowMemoryStorage({this.delay = const Duration(milliseconds: 50)});

  final Duration delay;

  @override
  Future<void> saveEntries(String notebookId, List<Entry> entries) async {
    await Future<void>.delayed(delay);
    return super.saveEntries(notebookId, entries);
  }
}
