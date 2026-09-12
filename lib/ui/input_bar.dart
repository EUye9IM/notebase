import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';

/// 常驻输入栏（ui-design §5.1）：
/// - 文本：窄屏 Enter = 换行、➤ 发送；宽屏 Enter = 发送、Shift+Enter = 换行；
///   宽屏自动聚焦，窄屏不自动弹键盘。
/// - 📷 / 🎤 为占位（M6 接入录音与拍照）。
class InputBar extends StatefulWidget {
  const InputBar({
    super.key,
    required this.store,
    required this.wide,
    this.focusNode,
  });

  final AppStore store;
  final bool wide;

  /// 外部焦点节点：宽屏退出搜索后把焦点交还输入栏（§5.1 宽屏自动聚焦）。
  final FocusNode? focusNode;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();

  /// 各笔记本的草稿（仅内存，重启即失）：切换笔记本时草稿各归其位，
  /// 既不会丢，也不会把 A 里写的内容误发进 B（ui-design §10）。
  final _drafts = <String, String>{};

  /// 注意：必须在 initState 里赋值。写成 `late String _notebookId =
  /// widget.store.currentNotebookId;` 会惰性求值——首次读取发生在切换之后，
  /// 直接捕获新 id，换稿逻辑永不触发（已被草稿测试抓到）。
  late String _notebookId;

  bool _hasText = false;
  bool _sending = false;

  /// 程序化改写输入框内容时置位，避免触发 onChanged 的 setState。
  bool _swapping = false;

  @override
  void initState() {
    super.initState();
    _notebookId = widget.store.currentNotebookId;
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(InputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.store.currentNotebookId;
    if (id == _notebookId) return;
    _drafts[_notebookId] = _controller.text; // 存旧本草稿
    _notebookId = id;
    final restored = _drafts[id] ?? '';
    _swapping = true;
    _controller.text = restored;
    _swapping = false;
    _hasText = restored.trim().isNotEmpty; // 已在重建中，直接改状态
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_swapping) return;
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  Future<void> _send() async {
    // 重入守卫：写入期间 ➤ 置灰、再次触发直接返回，
    // 避免双击 ➤ / Enter 连击产生重复条目（写延迟窗口内最多一条）。
    if (_sending) return;
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.store.addText(text);
      if (mounted) _controller.clear();
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
          final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
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
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.4),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.photo_outlined),
              tooltip: '拍照（后续版本）',
              onPressed: null,
            ),
            IconButton(
              icon: const Icon(Icons.mic_none),
              tooltip: '录音（后续版本）',
              onPressed: null,
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
    );
  }
}
