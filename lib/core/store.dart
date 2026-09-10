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

  // ---------- 笔记本 ----------

  /// 新建并切换为当前笔记本（ui-design §6：建完即切换）。
  Future<Notebook> createNotebook(String name) async {
    final notebook = Notebook(
      id: _uid(),
      name: _validName(name),
      createdAt: DateTime.now(),
    );
    _notebooks.add(notebook);
    await _storage.saveNotebooks(_notebooks);
    await switchNotebook(notebook.id);
    return notebook;
  }

  Future<void> renameNotebook(String id, String name) async {
    if (id == Notebook.defaultId) {
      throw ArgumentError('default 笔记本不可重命名');
    }
    final i = _notebooks.indexWhere((n) => n.id == id);
    if (i < 0) throw ArgumentError('笔记本不存在: $id');
    _notebooks[i] = _notebooks[i].copyWith(name: _validName(name));
    await _storage.saveNotebooks(_notebooks);
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
    _entries[Notebook.defaultId] = merged;
    await _storage.saveEntries(Notebook.defaultId, merged);
    await _storage.deleteEntries(id);
    _entries.remove(id);
    _notebooks.removeWhere((n) => n.id == id);
    final wasCurrent = _currentId == id;
    if (wasCurrent) _currentId = Notebook.defaultId;
    await _storage.saveNotebooks(_notebooks);
    if (wasCurrent) await _storage.savePrefs(_prefs());
    notifyListeners();
  }

  /// 切换当前笔记本（惰性加载条目），并持久化偏好。
  Future<void> switchNotebook(String id) async {
    if (!_notebooks.any((n) => n.id == id)) {
      throw ArgumentError('笔记本不存在: $id');
    }
    _currentId = id;
    await _loadEntriesOf(id);
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
    list.add(entry);
    _sort(list);
    await _storage.saveEntries(_currentId, list);
    notifyListeners();
    return entry;
  }

  /// 编辑文本（不改 createdAt，排序不变，ui-design §8）。
  Future<void> updateEntryText(String entryId, String text) async {
    final t = text.trim();
    if (t.isEmpty) throw ArgumentError('文本不能为空');
    await _replaceEntry(entryId, (e) => e.copyWith(text: t));
  }

  Future<void> deleteEntry(String entryId) async {
    final list = _entries[_currentId] ??= [];
    if (!list.any((e) => e.id == entryId)) {
      throw ArgumentError('条目不存在: $entryId');
    }
    list.removeWhere((e) => e.id == entryId);
    await _storage.saveEntries(_currentId, list);
    notifyListeners();
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
    final list = _entries[_currentId] ??= [];
    final i = list.indexWhere((e) => e.id == entryId);
    if (i < 0) throw ArgumentError('条目不存在: $entryId');
    list[i] = transform(list[i]);
    await _storage.saveEntries(_currentId, list);
    notifyListeners();
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
