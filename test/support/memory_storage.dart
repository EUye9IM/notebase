import 'dart:io';

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
    if (failSaveEntries) {
      throw const FileSystemException('磁盘写失败（模拟）');
    }
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

  /// 内存「磁盘」：相对路径 → 内容字节数（测试断言用）。
  final media = <String, int>{};

  /// 置 true 后 saveEntries 抛错：用于验证「写盘失败要回滚」的路径。
  bool failSaveEntries = false;

  @override
  Future<String> prepareMediaPath(String relativePath) async {
    media.putIfAbsent(relativePath, () => 0);
    return '/memory/$relativePath';
  }

  @override
  String mediaPath(String relativePath) => '/memory/$relativePath';

  @override
  Future<void> copyIntoMedia({
    required String sourceAbsolutePath,
    required String relativePath,
  }) async {
    if (!File(sourceAbsolutePath).existsSync()) {
      throw FileSystemException('源文件不存在', sourceAbsolutePath);
    }
    media[relativePath] = File(sourceAbsolutePath).lengthSync(); // 只复制
  }

  @override
  Future<void> adoptMedia({
    required String sourcePath,
    required String relativePath,
  }) async {
    // 与 JsonFileStorage 一致：源文件不存在要抛错，否则测试会放过
    // 「临时文件根本没落盘」这类缺陷（M6 评审指出）。
    if (!media.containsKey(sourcePath)) {
      throw FileSystemException('源文件不存在', sourcePath);
    }
    media[relativePath] = media.remove(sourcePath)!;
  }

  @override
  Future<void> deleteMedia(String relativePath) async {
    media.remove(relativePath);
  }

  /// 默认不隔离；测试可赋值以模拟「坏文件已隔离」的返回。
  List<String> quarantineResult = const [];

  @override
  Future<List<String>> quarantineCorruptFiles() async => quarantineResult;
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
