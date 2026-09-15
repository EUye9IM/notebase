import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';
import 'media_importer.dart';
import 'recording_session.dart';

/// 常驻输入栏（ui-design §5.1）：
/// - 文本：窄屏 Enter = 换行、➤ 发送；宽屏 Enter = 发送、Shift+Enter = 换行；
///   宽屏自动聚焦，窄屏不自动弹键盘。
/// - 🎤 进入录音（§5.2）：输入栏整体替换为录音条 ✗ / 实时时长+电平 / ✓，
///   停止即保存、丢弃不确认、时长 < 1s 视为误触丢弃；📷 待 M6d。
/// - 录音中断（系统抢占麦克风等）保存已录部分（§10）。
/// 草稿暂存（仅内存）：跨笔记本切换、跨宽窄布局重建都不丢（ui-design §10）。
/// 由 HomePage 持有——宽/窄两套布局各自构造 InputBar，State 会重建，
/// 草稿若放在 State 里会在拖动窗口跨 720 时丢失（M5 评审 P3-1）。
class DraftStore {
  final _byNotebook = <String, String>{};

  String read(String notebookId) => _byNotebook[notebookId] ?? '';

  void write(String notebookId, String text) {
    if (text.isEmpty) {
      _byNotebook.remove(notebookId);
    } else {
      _byNotebook[notebookId] = text;
    }
  }
}

class InputBar extends StatefulWidget {
  const InputBar({
    super.key,
    required this.store,
    required this.wide,
    this.focusNode,
    this.drafts,
    required this.session,
    this.importer,
  });

  final AppStore store;
  final bool wide;

  /// 外部焦点节点：宽屏退出搜索后把焦点交还输入栏（§5.1 宽屏自动聚焦）。
  final FocusNode? focusNode;

  /// 外部持有的草稿暂存（见 [DraftStore]）。
  final DraftStore? drafts;

  /// 录音会话（§5.2）。由 HomePage 持有，跨布局重建存活；无录音能力时
  /// `session.available` 为 false，🎤 置灰。
  final RecordingSession session;

  /// 图片导入能力（§5.3）。为 null 时 📷 置灰。
  final MediaImporter? importer;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();

  /// 各笔记本的草稿（仅内存，重启即失）：切换笔记本时草稿各归其位，
  /// 既不会丢，也不会把 A 里写的内容误发进 B（ui-design §10）。
  /// 注意：必须在 initState 里赋值。写成 `late String _notebookId =
  /// widget.store.currentNotebookId;` 会惰性求值——首次读取发生在切换之后，
  /// 直接捕获新 id，换稿逻辑永不触发（已被草稿测试抓到）。
  late String _notebookId;

  bool _hasText = false;
  bool _sending = false;

  /// 程序化改写输入框内容时置位，避免触发 onChanged 的 setState。
  bool _swapping = false;

  /// 录音会话的异步提示（中断保存等）。
  StreamSubscription<String>? _messages;

  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _notebookId = widget.store.currentNotebookId;
    final restored = widget.drafts?.read(_notebookId) ?? '';
    _swapping = true;
    _controller.text = restored;
    _swapping = false;
    _hasText = restored.trim().isNotEmpty;
    _controller.addListener(_onTextChanged);
    _messages = widget.session.messages.listen(_toast);
  }

  @override
  void didUpdateWidget(InputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.store.currentNotebookId;
    if (id == _notebookId) return;
    _notebookId = id;
    final restored = widget.drafts?.read(id) ?? '';
    _swapping = true;
    _controller.text = restored;
    _swapping = false;
    _hasText = restored.trim().isNotEmpty; // 已在重建中，直接改状态
  }

  @override
  void dispose() {
    _messages?.cancel();
    widget.drafts?.write(_notebookId, _controller.text); // 布局重建时兜底
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_swapping) return;
    widget.drafts?.write(_notebookId, _controller.text);
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 图片导入（§5.3）：点 📷 → 选图 → 保存并关闭 → 流内立即可见。
  /// 无预览确认步骤；一次一张；只复制不移动用户原图。
  Future<void> _importPhoto() async {
    final importer = widget.importer;
    if (importer == null || _importing) return;
    setState(() => _importing = true);
    try {
      final source = await importer.pickImage();
      if (source == null || !mounted) return; // 用户取消
      await widget.store.importPhoto(
        sourceAbsolutePath: source,
        extension: imageExtensionOf(source),
      );
    } on Object catch (error) {
      _toast('导入图片失败：$error');
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      } else {
        _importing = false;
      }
    }
  }

  Future<void> _startRecording() async {
    final message = await widget.session.start();
    if (message != null) _toast(message);
  }

  Future<void> _send() async {
    // 重入守卫：写入期间 ➤ 置灰、再次触发直接返回，
    // 避免双击 ➤ / Enter 连击产生重复条目（写延迟窗口内最多一条）。
    if (_sending) return;
    final text = _controller.text;
    if (text.trim().isEmpty) return;

    final sentFrom = _notebookId; // 发送时所在的笔记本
    setState(() => _sending = true);
    try {
      await widget.store.addText(text);
      if (!mounted) return;
      // 只在「仍在同一笔记本」且「输入框内容仍是刚发出去的那段」时清空。
      // 写盘窗口内用户可能切了笔记本或继续打字，无条件 clear 会抹掉
      // 目标本的草稿 / 新输入（M5 评审 P2-2）。
      if (_notebookId == sentFrom && _controller.text == text) {
        _swapping = true;
        _controller.clear();
        _swapping = false;
        _hasText = false;
        widget.drafts?.write(_notebookId, '');
        setState(() {});
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      } else {
        _sending = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field = TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.wide,
      maxLines: null,
      decoration: const InputDecoration(
        hintText: '记点什么…',
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 12),
      ),
    );

    // 宽屏：拦下不带修饰键的 Enter 改为发送；Shift+Enter 落回默认换行。
    // 本包装位于 TextField 与 MaterialApp 级默认文本快捷键之间，先于换行处理。
    if (widget.wide) {
      field = Focus(
        onKeyEvent: (node, event) {
          final isEnter =
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter;
          if (event is KeyDownEvent &&
              isEnter &&
              !HardwareKeyboard.instance.isShiftPressed) {
            _send();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: field,
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: ListenableBuilder(
          listenable: widget.session,
          builder: (context, _) => widget.session.recording
              ? RecordingRow(session: widget.session, onMessage: _toast)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.photo_outlined),
                      tooltip: '导入图片',
                      onPressed: widget.importer == null || _importing
                          ? null
                          : _importPhoto,
                    ),
                    IconButton(
                      icon: const Icon(Icons.mic_none),
                      tooltip: '录音',
                      onPressed:
                          !widget.session.available || widget.session.busy
                          ? null
                          : _startRecording,
                    ),
                    Expanded(child: field),
                    IconButton(
                      icon: const Icon(Icons.send_outlined),
                      tooltip: '发送',
                      onPressed: _hasText && !_sending ? _send : null,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
