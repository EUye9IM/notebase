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
/// 写入走「唯一临时文件 + rename」保证原子性，同一路径的并发写串行化；
/// 文件缺失一律返回空/默认值（首次启动）。
class JsonFileStorage implements Storage {
  JsonFileStorage(this.baseDir);

  final String baseDir;

  /// 每路径的写入队列：同一文件的写操作按提交顺序串行执行。
  /// 固定临时文件名的写法会让并发写入互相抢 rename（PathNotFoundException），
  /// 这里既串行化又使用唯一 tmp 名，两道保险。
  static final Map<String, Future<void>> _queues = {};
  static int _tmpSeq = 0;

  Future<void> _ensureDir() async {
    final dir = Directory(baseDir);
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  Future<Object?> _read(File file) async {
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  }

  Future<void> _write(File file, Object? data) =>
      _enqueueFor(file, () => _writeNow(file, data));

  /// 把**针对同一路径**的操作排进同一条队列（写、删都走这里）。
  ///
  /// 删除必须排队：否则「删条目文件」会插到在飞的写入之前执行，写落地后文件
  /// 又冒出来（僵尸文件，里面还留着已并入 default 的条目；复检 P2）。
  Future<void> _enqueueFor(File file, Future<void> Function() action) {
    final key = file.absolute.path;
    final prev = _queues[key] ?? Future<void>.value();
    // catchError：前序操作失败不得毒化队列，否则该文件此后永远写不进去。
    final next = prev.catchError((_) {}).then((_) => action());
    _queues[key] = next;
    return next.whenComplete(() {
      // 队列排空即回收，避免 map 随笔记本数量无限增长。
      if (identical(_queues[key], next)) _queues.remove(key);
    });
  }

  Future<void> _writeNow(File file, Object? data) async {
    await _ensureDir();
    final tmp = File('${file.path}.${_tmpSeq++}.tmp');
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

  /// 拒绝越界路径：媒体相对路径必须落在应用数据目录内。
  File _mediaFile(String relativePath) {
    if (relativePath.startsWith('/') ||
        relativePath.split('/').contains('..')) {
      throw ArgumentError('媒体路径必须是数据目录内的相对路径: $relativePath');
    }
    return File('$baseDir/$relativePath');
  }

  @override
  String mediaPath(String relativePath) => _mediaFile(relativePath).path;

  @override
  bool mediaExists(String relativePath) => _mediaFile(relativePath).existsSync();

  @override
  Future<void> copyIntoMedia({
    required String sourceAbsolutePath,
    required String relativePath,
  }) async {
    final target = _mediaFile(relativePath);
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    // copy（不是 rename）：用户原图必须留在原处
    await File(sourceAbsolutePath).copy(target.path);
  }

  @override
  Future<String> prepareMediaPath(String relativePath) async {
    final file = _mediaFile(relativePath);
    final dir = file.parent;
    if (!await dir.exists()) await dir.create(recursive: true);
    return file.path;
  }

  @override
  Future<void> adoptMedia({
    required String sourcePath,
    required String relativePath,
  }) async {
    final source = _mediaFile(sourcePath);
    final target = _mediaFile(relativePath);
    if (!await target.parent.exists()) await target.parent.create(recursive: true);
    try {
      await source.rename(target.path); // 同盘：原子移动
    } on FileSystemException {
      await source.copy(target.path); // 跨设备退化
      await source.delete();
    }
  }

  @override
  Future<void> deleteMedia(String relativePath) async {
    final file = _mediaFile(relativePath);
    if (await file.exists()) await file.delete();
  }

  /// 隔离无法解析的数据文件：重命名为 `<名>.corrupt-<时间戳>`，
  /// 返回被隔离的文件名列表（供 UI 告知用户）。
  ///
  /// 启动期数据损坏的兜底（ui-design §10）：坏文件不删、只挪走，
  /// 之后 [loadNotebooks] / [loadEntries] 会当作「文件缺失」返回空，
  /// 应用得以以 default 启动，而不是抛 FormatException 崩在启动路径上。
  @override
  Future<List<String>> quarantineCorruptFiles() async {
    final Directory dir;
    final List<FileSystemEntity> entities;
    try {
      dir = Directory(baseDir);
      if (!await dir.exists()) return const [];
      entities = dir.listSync();
    } on Object {
      // 目录本身读不了（权限 / 只读挂载）：不该把启动拦下来（复检 P2）
      return const [];
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final quarantined = <String>[];
    for (final entity in entities) {
      // 逐文件兜底：单个文件读不了 / 改不了名（EACCES、EIO、跨设备 rename…）
      // 只跳过它继续扫其余文件。此前这类异常会一路逃到启动路径，把「有一个
      // 读不了的文件」升级成「整个应用打不开」，违反 ui-design §10。
      try {
        await _scanFile(entity, stamp, quarantined);
      } on Object {
        continue;
      }
    }
    return quarantined;
  }

  Future<void> _scanFile(
    FileSystemEntity entity,
    int stamp,
    List<String> sink,
  ) async {
    if (entity is! File) return;
    final name = entity.uri.pathSegments.last;
    final isData = name == 'notebooks.json' ||
        name == 'prefs.json' ||
        (name.startsWith('nb_') && name.endsWith('.json'));
    if (!isData) return;
    // 只读一遍、解析一遍：启动期扫描此前对每个文件读两遍 decode 两遍
    final Object? raw;
    try {
      raw = jsonDecode(await entity.readAsString());
    } on FormatException {
      // 语法坏了：无法解析
      await _quarantine(entity, name, stamp, sink);
      return;
    }
    // 语法合法但结构不对（如未知条目 type）也要隔离——这类错误只有
    // 走到模型解析时才暴露，所以用同一套「试解析」判断。
    try {
      if (name == 'notebooks.json') {
        for (final item in raw as List) {
          Notebook.fromJson(item as Map<String, dynamic>);
        }
      } else if (name.startsWith('nb_')) {
        for (final item in raw as List) {
          Entry.fromJson(item as Map<String, dynamic>);
        }
      }
    } on Object {
      await _quarantine(entity, name, stamp, sink);
    }
  }

  Future<void> _quarantine(
    File file,
    String name,
    int stamp,
    List<String> sink,
  ) async {
    final target = '$name.corrupt-$stamp';
    await file.rename('$baseDir/$target');
    sink.add(target);
  }

  @override
  Future<void> deleteEntries(String notebookId) {
    final file = File('$baseDir/nb_$notebookId.json');
    return _enqueueFor(file, () async {
      if (await file.exists()) await file.delete();
    });
  }

  @override
  Future<Prefs> loadPrefs() async {
    try {
      final raw = await _read(File('$baseDir/prefs.json'));
      if (raw == null) return const Prefs();
      return Prefs.fromJson(raw as Map<String, dynamic>);
    } on Object {
      // 偏好只存主题与当前笔记本，重置零代价：读不出来就回默认，
      // 绝不因此把启动挡在 StartupErrorApp 上（ui-design §10）。
      // 下次任何偏好变更都会重写该文件。
      return const Prefs();
    }
  }

  @override
  Future<void> savePrefs(Prefs prefs) =>
      _write(File('$baseDir/prefs.json'), prefs.toJson());
}
