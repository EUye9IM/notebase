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

  /// 媒体文件的绝对路径（父目录会被创建）。
  ///
  /// 相对路径约定见 ui-design §2：`media/<entry-id>.<ext>`。core 不解读媒体
  /// 内容，只提供落点——录音/导入由 UI 层的平台能力完成。
  Future<String> prepareMediaPath(String relativePath);

  /// 把已落盘的临时媒体移动到正式位置（`media/<entry-id>.<ext>`）。
  Future<void> adoptMedia({
    required String sourcePath,
    required String relativePath,
  });

  /// 删除媒体文件；文件不存在则忽略。
  Future<void> deleteMedia(String relativePath);

  /// 隔离无法解析的数据，返回被隔离项的描述（供 UI 告知用户）。
  ///
  /// 用于启动期数据损坏兜底（ui-design §10）：默认无操作，文件型实现会
  /// 把坏文件改名保留；隔离后再次 [loadNotebooks] / [loadEntries] 应能
  /// 正常返回（当作缺失）。
  Future<List<String>> quarantineCorruptFiles() => Future.value(const []);
}
