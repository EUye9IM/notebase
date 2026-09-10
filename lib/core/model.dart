// 数据模型：Notebook / Entry / Prefs。
//
// core 层：只允许 import `dart:*`。字段语义与不变式见 docs/ui-design.mdx §2。

/// 条目类型。v1 只有 text 暴露 UI 入口，photo / audio 为预留（M6）。
enum EntryType { text, photo, audio }

/// 主题偏好。core 不依赖 Flutter，自有枚举；UI 层映射为 ThemeMode。
enum ThemeSetting { system, light, dark }

class Notebook {
  const Notebook({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  /// 默认笔记本：永存、不可删除、不可重命名（删除其他笔记本时条目的去处）。
  static const defaultId = 'default';

  final String id;
  final String name;
  final DateTime createdAt;

  factory Notebook.createDefault() => Notebook(
        id: defaultId,
        name: 'default',
        createdAt: DateTime.now(),
      );

  Notebook copyWith({String? name}) => Notebook(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
      );

  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (json['createdAt'] as num).toInt()),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };
}

/// 一条记录：一段文字、一张照片或一段录音（一条一档，无标题）。
class Entry {
  const Entry({
    required this.id,
    required this.notebookId,
    required this.type,
    required this.createdAt,
    this.text,
    this.file,
    this.duration,
    this.transcript,
    this.summary,
  });

  final String id;
  final String notebookId;
  final EntryType type;

  /// type == text 的正文（可含换行）。
  final String? text;

  /// type == photo / audio 的媒体文件相对路径（相对应用数据目录）。
  final String? file;

  /// type == audio 的时长（秒）。
  final double? duration;

  /// type == audio 的转写全文（完整文字面，等价于文本条目的正文）。
  final String? transcript;

  /// type == photo / audio 的摘要（时间线展示面）。
  final String? summary;

  final DateTime createdAt;

  /// 使用哨兵默认值以支持显式置空（清空转写/摘要 = 删除该字段，§8）。
  static const _unset = Object();

  Entry copyWith({
    Object? notebookId = _unset,
    Object? text = _unset,
    Object? transcript = _unset,
    Object? summary = _unset,
  }) =>
      Entry(
        id: id,
        notebookId: identical(notebookId, _unset)
            ? this.notebookId
            : notebookId as String,
        type: type,
        createdAt: createdAt,
        text: identical(text, _unset) ? this.text : text as String?,
        file: file,
        duration: duration,
        transcript: identical(transcript, _unset)
            ? this.transcript
            : transcript as String?,
        summary: identical(summary, _unset) ? this.summary : summary as String?,
      );

  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
        id: json['id'] as String,
        notebookId: json['notebookId'] as String,
        type: EntryType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => throw FormatException('未知条目类型: ${json['type']}'),
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (json['createdAt'] as num).toInt()),
        text: json['text'] as String?,
        file: json['file'] as String?,
        duration: (json['duration'] as num?)?.toDouble(),
        transcript: json['transcript'] as String?,
        summary: json['summary'] as String?,
      );

  /// 只序列化非空字段，文件里不留 null 噪音。
  Map<String, dynamic> toJson() => {
        'id': id,
        'notebookId': notebookId,
        'type': type.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (text != null) 'text': text,
        if (file != null) 'file': file,
        if (duration != null) 'duration': duration,
        if (transcript != null) 'transcript': transcript,
        if (summary != null) 'summary': summary,
      };
}

/// 应用偏好。
class Prefs {
  const Prefs({this.theme = ThemeSetting.system, this.currentNotebookId});

  final ThemeSetting theme;

  /// 为空（或指向不存在的笔记本）时回退 default。
  final String? currentNotebookId;

  Prefs copyWith({ThemeSetting? theme, String? currentNotebookId}) => Prefs(
        theme: theme ?? this.theme,
        currentNotebookId: currentNotebookId ?? this.currentNotebookId,
      );

  factory Prefs.fromJson(Map<String, dynamic> json) => Prefs(
        theme: ThemeSetting.values.firstWhere(
          (t) => t.name == json['theme'],
          orElse: () => ThemeSetting.system,
        ),
        currentNotebookId: json['currentNotebookId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        if (currentNotebookId != null) 'currentNotebookId': currentNotebookId,
      };
}
