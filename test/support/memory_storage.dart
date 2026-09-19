import 'dart:async';
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

  /// 与 [mediaPath] 配套：内存「磁盘」里登记过就算存在，删掉即消失——
  /// 渲染层的「缺失占位 / 不可播放」分支因此可以在不碰真实文件的前提下被测。
  @override
  bool mediaExists(String relativePath) => media.containsKey(relativePath);

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

  /// 置 true 让隔离本身失败：用于验证「扫描失败也不拦启动」（复检 P2）。
  bool quarantineThrows = false;

  @override
  Future<List<String>> quarantineCorruptFiles() async {
    if (quarantineThrows) {
      throw const FileSystemException('数据目录读不了（模拟）');
    }
    return quarantineResult;
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

/// 可闸门化的内存 Storage：`hold()` 之后 `saveEntries` / `savePrefs` /
/// `loadEntries` 会停在闸门上，直到 `release()`。
///
/// 用途：把「await 在途」这个窗口变成**确定性**的——路由竞态（await 之后
/// pop 打到底下那条路由）需要「写盘未完成 + 弹层已在退场」同时成立，
/// 用时间延迟无法稳定复现。
///
/// 刻意用 [Completer] 而不是 `Future.delayed`：widget 测试跑在 fake-async 区，
/// 真实 Timer 只有推进时钟才会完成，在 `await store.xxx()` 这种不给 pump 的
/// 位置会直接把测试挂死（本项目已因此踩过坑）。
class GatedMemoryStorage extends MemoryStorage {
  Completer<void>? _gate;

  /// 关门：后续的保存/加载停住。
  void hold() => _gate = Completer<void>();

  /// 放行：等在闸门上的操作继续。
  void release() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> _waitAtGate() async {
    final gate = _gate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> saveEntries(String notebookId, List<Entry> entries) async {
    await _waitAtGate();
    return super.saveEntries(notebookId, entries);
  }

  @override
  Future<void> savePrefs(Prefs prefs) async {
    await _waitAtGate();
    return super.savePrefs(prefs);
  }

  @override
  Future<List<Entry>> loadEntries(String notebookId) async {
    await _waitAtGate();
    return super.loadEntries(notebookId);
  }
}
