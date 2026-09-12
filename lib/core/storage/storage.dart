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

  /// 隔离无法解析的数据，返回被隔离项的描述（供 UI 告知用户）。
  ///
  /// 用于启动期数据损坏兜底（ui-design §10）：默认无操作，文件型实现会
  /// 把坏文件改名保留；隔离后再次 [loadNotebooks] / [loadEntries] 应能
  /// 正常返回（当作缺失）。
  Future<List<String>> quarantineCorruptFiles() => Future.value(const []);
}
