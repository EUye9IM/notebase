import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单条笔记。字段直接可变，由 [NoteStore] 统一管理生命周期。
class Note {
  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  final String id;
  String title;
  String content;
  DateTime updatedAt;

  /// 列表展示用标题：标题为空时取内容首行，再空则给占位。
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = content.trim().split('\n').firstOrNull ?? '';
    return firstLine.isEmpty ? '（无标题）' : firstLine;
  }

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };
}

/// 全局数据与偏好存储：笔记列表放内存，变更即整体序列化为 JSON 写回
/// shared_preferences。数据量大起来之后（Phase 2）整体迁移到 SQLite。
class NoteStore extends ChangeNotifier {
  NoteStore._(this._prefs);

  static const _notesKey = 'notes';
  static const _themeModeKey = 'themeMode';

  final SharedPreferences _prefs;
  final List<Note> _notes = [];
  ThemeMode _themeMode = ThemeMode.system;

  /// 按更新时间倒序的笔记列表。
  List<Note> get notes => List.unmodifiable(_notes);
  ThemeMode get themeMode => _themeMode;

  static Future<NoteStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final store = NoteStore._(prefs);
    final raw = prefs.getString(_notesKey);
    if (raw != null) {
      for (final item in jsonDecode(raw) as List<dynamic>) {
        store._notes.add(Note.fromJson(item as Map<String, dynamic>));
      }
      store._sort();
    }
    store._themeMode =
        ThemeMode.values[prefs.getInt(_themeModeKey) ?? ThemeMode.system.index];
    return store;
  }

  Note create() {
    final note = Note(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: '',
      content: '',
      updatedAt: DateTime.now(),
    );
    _notes.insert(0, note);
    _save();
    return note;
  }

  void update(Note note, {String? title, String? content}) {
    if (title != null) note.title = title;
    if (content != null) note.content = content;
    note.updatedAt = DateTime.now();
    _sort();
    _save();
  }

  void delete(Note note) {
    _notes.removeWhere((n) => n.id == note.id);
    _save();
  }

  /// LIKE 式检索：标题或内容包含查询串（忽略大小写）。
  List<Note> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return notes;
    return _notes
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.content.toLowerCase().contains(q))
        .toList();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs.setInt(_themeModeKey, mode.index);
    notifyListeners();
  }

  void _sort() => _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  void _save() {
    _prefs.setString(
        _notesKey, jsonEncode(_notes.map((n) => n.toJson()).toList()));
    notifyListeners();
  }
}
