import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/model.dart';
import '../core/store.dart';
import 'media_recorder.dart';

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
    this.recorder,
  });

  final AppStore store;
  final bool wide;

  /// 外部焦点节点：宽屏退出搜索后把焦点交还输入栏（§5.1 宽屏自动聚焦）。
  final FocusNode? focusNode;

  /// 外部持有的草稿暂存（见 [DraftStore]）。
  final DraftStore? drafts;

  /// 注入的录音能力（§5.2）。为 null 时 🎤 置灰——测试与不支持录音的平台
  /// 都不会碰到平台通道。
  final MediaRecorder? recorder;

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

  /// 录音态（§5.2）：true 时输入栏整体替换为录音条。
  bool _recording = false;
  bool _busy = false; // 启动/停止录音的过渡，避免连点
  Duration _elapsed = Duration.zero;
  double _level = 0;
  Timer? _ticker;
  ({String absolutePath, String relativePath})? _recordingTemp;

  /// 程序化改写输入框内容时置位，避免触发 onChanged 的 setState。
  bool _swapping = false;

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
    _ticker?.cancel();
    widget.drafts?.write(_notebookId, _controller.text); // 布局重建时兜底
    _controller.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  // ---------- 录音（ui-design §5.2） ----------

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _startRecording() async {
    final recorder = widget.recorder;
    if (recorder == null || _recording || _busy) return;
    setState(() => _busy = true);
    try {
      final reason = await recorder.unavailableReason();
      if (!mounted) return;
      if (reason != null) {
        _toast(reason); // 缺二进制 / 无权限：明确告知，不静默失败
        return;
      }
      final temp = await widget.store.prepareMediaTemp('ogg');
      await recorder.start(temp.absolutePath);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordingTemp = temp;
        _elapsed = Duration.zero;
        _level = 0;
      });
      _ticker = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _tick(),
      );
    } on Object catch (error) {
      _toast('无法开始录音：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  Future<void> _tick() async {
    if (!mounted || !_recording) return;
    setState(() => _elapsed += const Duration(milliseconds: 100));
    try {
      final level = await widget.recorder!.level();
      if (mounted && _recording) setState(() => _level = level);
    } on Object {
      // §10：录音被系统打断——保存已录部分，不静默丢失。
      await _finishRecording();
    }
  }

  /// ✓ 停止并保存；时长不足 1s 视为误触丢弃（§5.2）。
  Future<void> _stopAndSave() async {
    final recorder = widget.recorder;
    if (recorder == null || !_recording || _busy) return;
    _stopTicker();
    setState(() => _busy = true);

    Duration duration = _elapsed;
    try {
      duration = await recorder.stop();
    } on Object catch (error) {
      _toast('停止录音出错：$error');
    }
    await _commitRecording(duration);
  }

  /// ✗ 立即丢弃，不确认（§5.2）。
  Future<void> _discardRecording() async {
    final recorder = widget.recorder;
    if (recorder == null || !_recording || _busy) return;
    _stopTicker();
    setState(() => _busy = true);
    try {
      await recorder.discard();
    } on Object {
      // 丢弃失败也要把临时文件清掉，避免留下孤儿
    }
    await _cleanupRecording();
    if (mounted) {
      setState(() {
        _recording = false;
        _elapsed = Duration.zero;
        _level = 0;
        _busy = false;
      });
    } else {
      _busy = false;
    }
  }

  /// 中断兜底：尽力停下录音并把已录部分入库（ui-design §10）。
  Future<void> _finishRecording() async {
    if (!_recording) return;
    _stopTicker();
    Duration duration = _elapsed;
    try {
      duration = await widget.recorder!.stop();
    } on Object {
      // 用已计时长兜底
    }
    if (mounted) {
      _toast('录音被中断，已保存已录部分');
    }
    await _commitRecording(duration);
  }

  Future<void> _commitRecording(Duration duration) async {
    final temp = _recordingTemp;
    _recordingTemp = null;
    if (temp == null) {
      if (mounted) setState(() => _recording = false);
      return;
    }
    if (duration < const Duration(seconds: 1)) {
      await widget.store.discardMedia(temp.relativePath); // 误触：丢弃
      if (mounted) {
        setState(() {
          _recording = false;
          _busy = false;
          _elapsed = Duration.zero;
          _level = 0;
        });
        _toast('太短了');
      }
      return;
    }
    try {
      await widget.store.addMedia(
        type: EntryType.audio,
        sourceRelativePath: temp.relativePath,
        extension: 'ogg',
        duration: duration.inMilliseconds / 1000,
      );
    } on Object catch (error) {
      await widget.store.discardMedia(temp.relativePath);
      _toast('保存录音失败：$error');
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _busy = false;
        _elapsed = Duration.zero;
        _level = 0;
      });
    } else {
      _busy = false;
    }
  }

  Future<void> _cleanupRecording() async {
    final temp = _recordingTemp;
    _recordingTemp = null;
    if (temp != null) await widget.store.discardMedia(temp.relativePath);
  }

  void _onTextChanged() {
    if (_swapping) return;
    widget.drafts?.write(_notebookId, _controller.text);
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
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
        child: _recording
            ? _RecordingRow(
                elapsed: _elapsed,
                level: _level,
                busy: _busy,
                onDiscard: _discardRecording,
                onSave: _stopAndSave,
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_outlined),
                    tooltip: '拍照（后续版本）',
                    onPressed: null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.mic_none),
                    tooltip: '录音',
                    onPressed: widget.recorder == null || _busy
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
    );
  }
}

/// 录音条（ui-design §5.2）：左 ✗ 丢弃 · 中 实时时长 + 真实电平 · 右 ✓ 停止并保存。
class _RecordingRow extends StatelessWidget {
  const _RecordingRow({
    required this.elapsed,
    required this.level,
    required this.busy,
    required this.onDiscard,
    required this.onSave,
  });

  final Duration elapsed;
  final double level;
  final bool busy;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  static String _mmss(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: '丢弃',
          onPressed: busy ? null : onDiscard,
        ),
        const SizedBox(width: 4),
        Icon(Icons.circle, size: 10, color: colors.error),
        const SizedBox(width: 8),
        Text(
          _mmss(elapsed),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: level.clamp(0.0, 1.0),
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          icon: const Icon(Icons.check),
          tooltip: '停止并保存',
          onPressed: busy ? null : onSave,
        ),
      ],
    );
  }
}
