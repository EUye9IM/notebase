import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';

/// 常驻输入栏（ui-design §5.1）：
/// - 文本：窄屏 Enter = 换行、➤ 发送；宽屏 Enter = 发送、Shift+Enter = 换行；
///   宽屏自动聚焦，窄屏不自动弹键盘。
/// - 📷 / 🎤 为占位（M6 接入录音与拍照）。
class InputBar extends StatefulWidget {
  const InputBar({super.key, required this.store, required this.wide});

  final AppStore store;
  final bool wide;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();
  bool _hasText = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
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
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter &&
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
