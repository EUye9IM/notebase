import 'dart:convert';
import 'dart:io';

import '../model.dart';
import 'storage.dart';

/// Storage 的 JSON 文件实现，布局：
///
/// ```
/// <baseDir>/notebooks.json    笔记本索引
/// <baseDir>/nb_<id>.json      每笔记本一个条目数组
/// <baseDir>/prefs.json        偏好（主题、当前笔记本）
/// ```
///
/// baseDir 由 UI 层（path_provider）注入，本类不感知平台；
/// 写入走「临时文件 + rename」保证原子性；文件缺失一律返回空/默认值（首次启动）。
class JsonFileStorage implements Storage {
  JsonFileStorage(this.baseDir);

  final String baseDir;

  Future<void> _ensureDir() async {
    final dir = Directory(baseDir);
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  Future<Object?> _read(File file) async {
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  }

  Future<void> _write(File file, Object? data) async {
    await _ensureDir();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await tmp.rename(file.path);
  }

  @override
  Future<List<Notebook>> loadNotebooks() async {
    final raw = await _read(File('$baseDir/notebooks.json'));
    if (raw == null) return [];
    return [
      for (final item in raw as List)
        Notebook.fromJson(item as Map<String, dynamic>)
    ];
  }

  @override
  Future<void> saveNotebooks(List<Notebook> notebooks) => _write(
        File('$baseDir/notebooks.json'),
        [for (final n in notebooks) n.toJson()],
      );

  @override
  Future<List<Entry>> loadEntries(String notebookId) async {
    final raw = await _read(File('$baseDir/nb_$notebookId.json'));
    if (raw == null) return [];
    return [
      for (final item in raw as List)
        Entry.fromJson(item as Map<String, dynamic>)
    ];
  }

  @override
  Future<void> saveEntries(String notebookId, List<Entry> entries) => _write(
        File('$baseDir/nb_$notebookId.json'),
        [for (final e in entries) e.toJson()],
      );

  @override
  Future<void> deleteEntries(String notebookId) async {
    final file = File('$baseDir/nb_$notebookId.json');
    if (await file.exists()) await file.delete();
  }

  @override
  Future<Prefs> loadPrefs() async {
    final raw = await _read(File('$baseDir/prefs.json'));
    if (raw == null) return const Prefs();
    return Prefs.fromJson(raw as Map<String, dynamic>);
  }

  @override
  Future<void> savePrefs(Prefs prefs) =>
      _write(File('$baseDir/prefs.json'), prefs.toJson());
}
