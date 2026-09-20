import 'listenable.dart';
import 'model.dart';
import 'storage/storage.dart';

/// 全局状态与业务规则：笔记本、当前笔记本的条目流、偏好、搜索。
///
/// 变更模式统一为：同步更新内存状态 → 落盘 → `notifyListeners()`。
/// 条目按 (createdAt, id) 升序（最新在末尾）；各笔记本条目惰性加载、
/// 内存缓存；删除笔记本时其条目并入 default（不变式见 ui-design §2）。
class AppStore extends CoreChangeNotifier {
  AppStore._(
    this._storage,
    this._notebooks,
    this._currentId,
    this._theme,
    this._entries,
  );

  /// 从持久化恢复；空数据或残缺数据自动补 default 笔记本。
  static Future<AppStore> load(Storage storage) async {
    var notebooks = await storage.loadNotebooks();
    if (!notebooks.any((n) => n.id == Notebook.defaultId)) {
      notebooks = [...notebooks, Notebook.createDefault()];
      await storage.saveNotebooks(notebooks);
    }
    final prefs = await storage.loadPrefs();
    final currentId = notebooks.any((n) => n.id == prefs.currentNotebookId)
        ? prefs.currentNotebookId!
        : Notebook.defaultId;
    final entries = <String, List<Entry>>{};
    final current = await storage.loadEntries(currentId);
    _sort(current);
    entries[currentId] = current;
    return AppStore._(storage, notebooks, currentId, prefs.theme, entries);
  }

  final Storage _storage;
  final List<Notebook> _notebooks;
  final Map<String, List<Entry>> _entries;
  String _currentId;
  ThemeSetting _theme;
  int _lastId = 0;

  // ---------- 读 ----------

  List<Notebook> get notebooks => List.unmodifiable(_notebooks);

  String get currentNotebookId => _currentId;

  Notebook get currentNotebook => _notebooks
      .firstWhere((n) => n.id == _currentId, orElse: () => _notebooks.first);

  /// 当前笔记本条目，时间升序（最新在末尾）。
  List<Entry> get entries =>
      List.unmodifiable(_entries[_currentId] ?? const <Entry>[]);

  ThemeSetting get theme => _theme;

  /// 当前笔记本内搜索（ui-design §7 终态规则）：文本=正文，照片=摘要，
  /// 录音=转写+摘要；忽略大小写；结果按时间倒序（最新在前）；空关键词返回空。
  List<Entry> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits =
        _entries[_currentId]?.where((e) => e.matches(q)).toList() ?? const [];
    return hits.reversed.toList();
  }

  /// 指定笔记本的条目数（必要时加载并缓存），供笔记本管理 UI 使用。
  Future<int> entryCountOf(String notebookId) async =>
      (await _loadEntriesOf(notebookId)).length;

  /// 指定笔记本引用的、**仍然存在**的媒体文件数（清空确认文案用：只说
  /// 真正会被删掉的数）。
  Future<int> mediaFileCountOf(String notebookId) async {
    final list = await _loadEntriesOf(notebookId);
    var count = 0;
    for (final entry in list) {
      final file = entry.file;
      if (file != null && _storage.mediaExists(file)) count++;
    }
    return count;
  }

  /// 清空笔记本的全部条目，并删除这些条目引用的媒体文件（**不可撤销**）。
  ///
  /// ui-design §6：default 不可删除，因此给它这个出口；UI 只对 default 暴露
  /// （其它笔记本用「删除笔记本」，条目并入 default 而非销毁）。
  ///
  /// 失败语义：先落盘「空条目」——失败则回滚内存并抛出，一个文件都不删；
  /// 成功后再逐个删媒体文件，单个删不掉（占用/权限）不影响其余，也不回滚
  /// 已清空的条目（剩下的由「无主媒体清理」兜底，dev-plan §7）。
  Future<({int entries, int media})> clearNotebook(String notebookId) async {
    if (!_notebooks.any((n) => n.id == notebookId)) {
      throw ArgumentError('笔记本不存在: $notebookId');
    }
    final list = await _loadEntriesOf(notebookId);
    final files = [
      for (final entry in list)
        if (entry.file != null) entry.file!,
    ];
    final removed = list.length;
    await _mutateAndSave(notebookId, list, list.clear);

    var deleted = 0;
    for (final file in files) {
      try {
        await _storage.deleteMedia(file);
        deleted++;
      } on Object {
        // 删不掉就留着：条目已经清空，剩下的由「无主媒体清理」回收
      }
    }
    return (entries: removed, media: deleted);
  }

  // ---------- 笔记本 ----------

  /// 新建并切换为当前笔记本（ui-design §6：建完即切换）。
  Future<Notebook> createNotebook(String name) async {
    final notebook = Notebook(
      id: _uid(),
      name: _validName(name),
      createdAt: DateTime.now(),
    );
    _notebooks.add(notebook);
    try {
      await _storage.saveNotebooks(_notebooks);
    } on Object {
      _notebooks.removeWhere((n) => n.id == notebook.id); // 不留幽灵笔记本
      rethrow;
    }
    await switchNotebook(notebook.id);
    return notebook;
  }

  Future<void> renameNotebook(String id, String name) async {
    if (id == Notebook.defaultId) {
      throw ArgumentError('default 笔记本不可重命名');
    }
    final i = _notebooks.indexWhere((n) => n.id == id);
    if (i < 0) throw ArgumentError('笔记本不存在: $id');
    final previous = _notebooks[i];
    _notebooks[i] = previous.copyWith(name: _validName(name));
    try {
      await _storage.saveNotebooks(_notebooks);
    } on Object {
      _notebooks[i] = previous;
      rethrow;
    }
    notifyListeners();
  }

  /// 删除笔记本；其条目并入 default。条目永不陪葬（ui-design §6）。
  Future<void> deleteNotebook(String id) async {
    if (id == Notebook.defaultId) {
      throw ArgumentError('default 笔记本不可删除');
    }
    if (!_notebooks.any((n) => n.id == id)) {
      throw ArgumentError('笔记本不存在: $id');
    }
    final moved = await _loadEntriesOf(id);
    final defaults = await _loadEntriesOf(Notebook.defaultId);
    // 归属重写：并入 default 的条目必须改 notebookId，否则违反
    // 「一条条目恰好属于一个笔记本」不变式（ui-design §2）。
    final merged = [
      ...defaults,
      for (final entry in moved)
        entry.copyWith(notebookId: Notebook.defaultId),
    ];
    _sort(merged);
    final wasCurrent = _currentId == id;
    final nextNotebooks =
        _notebooks.where((n) => n.id != id).toList(growable: false);
    // 先把三份文件都落盘，**全部成功后再改内存**：否则写盘中途失败会留下
    // 「内存已删、磁盘还在」或「条目已并、笔记本还在」的半状态（复检 P2）。
    await _storage.saveEntries(Notebook.defaultId, merged);
    await _storage.deleteEntries(id);
    await _storage.saveNotebooks(nextNotebooks);
    if (wasCurrent) {
      await _storage.savePrefs(
        Prefs(theme: _theme, currentNotebookId: Notebook.defaultId),
      );
    }
    // 原地更新 default 的列表对象：撤销之类的异步续体可能还捕获着它（评审 P3-1）
    defaults
      ..clear()
      ..addAll(merged);
    _entries.remove(id);
    _notebooks
      ..clear()
      ..addAll(nextNotebooks);
    if (wasCurrent) _currentId = Notebook.defaultId;
    notifyListeners();
  }

  /// 切换当前笔记本（惰性加载条目），并持久化偏好。
  Future<void> switchNotebook(String id) async {
    if (!_notebooks.any((n) => n.id == id)) {
      throw ArgumentError('笔记本不存在: $id');
    }
    // 先加载、后改状态：条目文件读失败时不留「已切走但没数据」的半切换态
    // （ui-design §10：数据损坏不得让应用停在不可用状态）。
    await _loadEntriesOf(id);
    _currentId = id;
    await _storage.savePrefs(_prefs());
    notifyListeners();
  }

  // ---------- 条目（当前笔记本） ----------

  /// 追加一条文本记录。
  Future<Entry> addText(String text) async {
    final t = text.trim();
    if (t.isEmpty) throw ArgumentError('文本不能为空');
    final entry = Entry(
      id: _uid(),
      notebookId: _currentId,
      type: EntryType.text,
      text: t,
      createdAt: DateTime.now(),
    );
    final list = _entries.putIfAbsent(_currentId, () => []);
    await _mutateAndSave(_currentId, list, () {
      list.add(entry);
      _sort(list);
    });
    return entry;
  }

  /// 媒体条目的相对路径约定（ui-design §2）。
  static String mediaPathFor(String entryId, String extension) =>
      'media/$entryId.$extension';

  /// 为即将录制的媒体准备临时落点。返回绝对路径（交给录音器写）与相对路径
  /// （交给 [addMedia] / [discardMedia]）；位置约定由 core 决定，UI 不拼路径。
  Future<({String absolutePath, String relativePath})> prepareMediaTemp(
    String extension,
  ) async {
    final relativePath = 'media/.tmp/${_uid()}.$extension';
    final absolute = await _storage.prepareMediaPath(relativePath);
    return (absolutePath: absolute, relativePath: relativePath);
  }

  /// 新增一条媒体条目：把临时文件归档到 `media/<entry-id>.<ext>` 并登记引用
  /// ——core 不解读媒体内容，只负责落点与归属。
  Future<Entry> addMedia({
    required EntryType type,
    required String sourceRelativePath,
    required String extension,
    double? duration,
    String? notebookId,
  }) async {
    if (type == EntryType.text) {
      throw ArgumentError('文本条目请用 addText');
    }
    // 归属按「开始录制时的笔记本」：录音期间切本不应把内容记到别处
    // （M6 评审 P3-2，与 §10「不会把 A 里写的内容误发进 B」同理）。
    final targetId = notebookId ?? _currentId;
    if (!_notebooks.any((n) => n.id == targetId)) {
      throw ArgumentError('笔记本不存在: $targetId');
    }
    final id = _uid();
    final relativePath = mediaPathFor(id, extension);
    await _storage.adoptMedia(
      sourcePath: sourceRelativePath,
      relativePath: relativePath,
    );
    final entry = Entry(
      id: id,
      notebookId: targetId,
      type: type,
      file: relativePath,
      duration: duration,
      createdAt: DateTime.now(),
    );
    // 必须走 _loadEntriesOf：目标本未加载时若用 putIfAbsent 造空列表写盘，
    // 会覆盖该本既有条目（评审 P3-5）。
    final list = await _loadEntriesOf(targetId);
    list.add(entry);
    _sort(list);
    try {
      await _storage.saveEntries(targetId, list);
    } on Object {
      // 写盘失败：回滚内存与已归档的文件，避免「幽灵条目」与孤儿媒体（P3-3）
      list.removeWhere((e) => e.id == id);
      await _storage.deleteMedia(relativePath);
      rethrow;
    }
    notifyListeners();
    return entry;
  }

  /// 媒体文件的绝对路径（供播放/查看使用，父目录会被创建）。
  Future<String> mediaAbsolutePath(String relativePath) =>
      _storage.prepareMediaPath(relativePath);

  /// 导入外部图片为照片条目（ui-design §5.3，Linux 端落地方式）。
  ///
  /// **只复制不移动**：用户选中的原图留在原处。一次一张（一图一条）。
  Future<Entry> importPhoto({
    required String sourceAbsolutePath,
    required String extension,
    String? notebookId,
  }) async {
    final targetId = notebookId ?? _currentId;
    if (!_notebooks.any((n) => n.id == targetId)) {
      throw ArgumentError('笔记本不存在: $targetId');
    }
    final id = _uid();
    final relativePath = mediaPathFor(id, extension);
    await _storage.copyIntoMedia(
      sourceAbsolutePath: sourceAbsolutePath,
      relativePath: relativePath,
    );
    final entry = Entry(
      id: id,
      notebookId: targetId,
      type: EntryType.photo,
      file: relativePath,
      createdAt: DateTime.now(),
    );
    final list = await _loadEntriesOf(targetId); // 同上：不可覆盖未加载笔记本
    list.add(entry);
    _sort(list);
    try {
      await _storage.saveEntries(targetId, list);
    } on Object {
      list.removeWhere((e) => e.id == id);
      await _storage.deleteMedia(relativePath); // 清掉刚复制进来的图，不留孤儿
      rethrow;
    }
    notifyListeners();
    return entry;
  }

  /// 媒体文件的绝对路径（同步、不建目录）：供缩略图等渲染路径使用。
  String mediaPath(String relativePath) => _storage.mediaPath(relativePath);

  /// 媒体文件是否存在（同步）：渲染层据此决定「不可播放 / 占位」（ui-design §10），
  /// 由 Storage 回答，UI 不直接摸文件系统。
  bool mediaExists(String relativePath) => _storage.mediaExists(relativePath);

  /// 丢弃尚未登记的媒体文件（录音点 ✗、时长过短，ui-design §5.2）。
  Future<void> discardMedia(String relativePath) =>
      _storage.deleteMedia(relativePath);

  /// 编辑录音转写全文（null / 空白 = 删除该字段，ui-design §8）。
  Future<void> updateEntryTranscript(String entryId, String? transcript) =>
      _replaceEntry(
        entryId,
        (e) => e.copyWith(transcript: _normalizeOptional(transcript)),
      );

  /// 编辑媒体摘要（null / 空白 = 删除该字段，ui-design §8）。
  Future<void> updateEntrySummary(String entryId, String? summary) =>
      _replaceEntry(
        entryId,
        (e) => e.copyWith(summary: _normalizeOptional(summary)),
      );

  static String? _normalizeOptional(String? text) {
    final trimmed = text?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// 编辑文本（不改 createdAt，排序不变，ui-design §8）。
  Future<void> updateEntryText(String entryId, String text) async {
    final t = text.trim();
    if (t.isEmpty) throw ArgumentError('文本不能为空');
    await _replaceEntry(entryId, (e) => e.copyWith(text: t));
  }

  /// 删除条目并返回被删快照，供 UI 层「撤销」使用（ui-design §8）。
  /// 快照归 store 层管理，UI 不自行缓存条目。
  ///
  /// **不删除媒体文件**：撤销窗口内仍需要它（删了会让撤销出「媒体已丢失」）。
  /// 无主媒体的清理见 dev-plan §7 待办。
  ///
  /// 条目可能不在当前笔记本（UI 拿着旧 tile 操作时遇到切本竞态），
  /// 因此按 [_locateEntry] 定位，始终在它真正所属的笔记本里修改。
  Future<Entry> deleteEntry(String entryId) async {
    final located = _locateEntry(entryId);
    if (located == null) throw ArgumentError('条目不存在: $entryId');
    final (notebookId, list) = located;
    final index = list.indexWhere((e) => e.id == entryId);
    final removed = list[index];
    await _mutateAndSave(notebookId, list, () => list.removeAt(index));
    return removed;
  }

  /// 撤销删除：把条目放回其所属笔记本，按 (createdAt, id) 复位排序。
  ///
  /// 若原笔记本已被删除，则落到当前笔记本并重写归属——维持
  /// 「一条条目恰好属于一个笔记本」不变式（ui-design §2）。
  /// 幂等：条目已在列表中时不做任何事。
  Future<void> restoreEntry(Entry entry) async {
    final exists = _notebooks.any((n) => n.id == entry.notebookId);
    final targetId = exists ? entry.notebookId : _currentId;
    final restored =
        exists ? entry : entry.copyWith(notebookId: targetId);
    final list = await _loadEntriesOf(targetId);
    if (list.any((e) => e.id == restored.id)) return;
    await _mutateAndSave(targetId, list, () {
      list.add(restored);
      _sort(list);
    });
  }

  // ---------- 偏好 ----------

  Future<void> setTheme(ThemeSetting theme) async {
    _theme = theme;
    await _storage.savePrefs(_prefs());
    notifyListeners();
  }

  // ---------- 内部 ----------

  Future<List<Entry>> _loadEntriesOf(String id) async {
    final cached = _entries[id];
    if (cached != null) return cached;
    final list = await _storage.loadEntries(id);
    _sort(list);
    return _entries[id] = list;
  }

  Future<void> _replaceEntry(
      String entryId, Entry Function(Entry) transform) async {
    final located = _locateEntry(entryId);
    if (located == null) throw ArgumentError('条目不存在: $entryId');
    final (notebookId, list) = located;
    final i = list.indexWhere((e) => e.id == entryId);
    await _mutateAndSave(notebookId, list, () {
      list[i] = transform(list[i]);
    });
  }

  /// 变更内存 + 落盘：**写盘失败必须回滚内存**，否则留下「内存有、磁盘无」的
  /// 幽灵状态——下一次任意通知它就冒出来，重启又消失（复检 P2）。回滚用
  /// 原地清空 + 回填，保持列表对象身份（撤销等异步续体可能还持有它）。
  /// 异常照旧向上抛：调用方负责让用户看到失败（UI 侧 catch + toast）。
  Future<void> _mutateAndSave(
    String notebookId,
    List<Entry> list,
    void Function() mutate,
  ) async {
    final backup = List<Entry>.of(list);
    mutate();
    try {
      await _storage.saveEntries(notebookId, list);
    } on Object {
      list
        ..clear()
        ..addAll(backup);
      rethrow;
    }
    notifyListeners();
  }

  /// 定位条目：优先当前笔记本，其次其它已加载笔记本；找不到返回 null。
  /// 让「跨本竞态」下不抛未捕获异常，并保证条目在所属笔记本内被修改
  /// （ui-design §2「一条条目恰好属于一个笔记本」）。
  (String, List<Entry>)? _locateEntry(String entryId) {
    final current = _entries[_currentId];
    if (current != null && current.any((e) => e.id == entryId)) {
      return (_currentId, current);
    }
    for (final cached in _entries.entries) {
      if (cached.key == _currentId) continue;
      if (cached.value.any((e) => e.id == entryId)) {
        return (cached.key, cached.value);
      }
    }
    return null;
  }

  /// 校验并规范化笔记本名：trim、非空。
  static String _validName(String name) {
    final t = name.trim();
    if (t.isEmpty) throw ArgumentError('笔记本名不能为空');
    return t;
  }

  Prefs _prefs() =>
      Prefs(theme: _theme, currentNotebookId: _currentId);

  /// 单调递增 id：同一进程内保证唯一，且时间有序（排序稳定兜底）。
  String _uid() {
    final now = DateTime.now().microsecondsSinceEpoch;
    _lastId = now > _lastId ? now : _lastId + 1;
    return _lastId.toString();
  }

  static void _sort(List<Entry> list) => list.sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
}

extension on Entry {
  /// 搜索命中判断（小写化后的关键词）。
  bool matches(String lowercaseQuery) => switch (type) {
        EntryType.text => text?.toLowerCase().contains(lowercaseQuery) ?? false,
        EntryType.photo =>
          summary?.toLowerCase().contains(lowercaseQuery) ?? false,
        EntryType.audio =>
            (transcript?.toLowerCase().contains(lowercaseQuery) ?? false) ||
                (summary?.toLowerCase().contains(lowercaseQuery) ?? false),
      };
}
