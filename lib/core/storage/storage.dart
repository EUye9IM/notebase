import '../model.dart';

/// 持久化接口：当前 JSON 文件实现与未来的 SQLite 实现共用（M7 换实现不动上层）。
abstract class Storage {
  Future<List<Notebook>> loadNotebooks();
  Future<void> saveNotebooks(List<Notebook> notebooks);

  Future<List<Entry>> loadEntries(String notebookId);
  Future<void> saveEntries(String notebookId, List<Entry> entries);
  Future<void> deleteEntries(String notebookId);

  Future<Prefs> loadPrefs();
  Future<void> savePrefs(Prefs prefs);
}
