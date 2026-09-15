import 'dart:async';

import 'package:flutter/material.dart';

import '../core/model.dart';
import '../core/store.dart';
import 'media_recorder.dart';

/// 录音会话（ui-design §5.2）。
///
/// **必须由 HomePage 持有**：录音状态若放在 InputBar 的 State 里，拖动窗口跨
/// 720 触发宽窄布局切换会销毁 State —— 录音条消失、麦克风仍被占用、临时文件
/// 成孤儿、还能二次开录（M6 评审 P1-1，与 M5 草稿丢失同源）。
///
/// 会话同时负责异常路径的清理：临时落点在 `start()` 之前登记，任何失败都能清掉。
class RecordingSession extends ChangeNotifier {
  RecordingSession({required this.store, required this.recorder});

  final AppStore store;
  final MediaRecorder? recorder;

  /// 异步来源的提示（如「录音被中断，已保存已录部分」）：会话不持有 context，
  /// 由 UI 订阅后自行 toast。
  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  bool _recording = false;
  bool _busy = false;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  Timer? _ticker;
  ({String absolutePath, String relativePath})? _temp;

  /// 开始录制时所在的笔记本：录音期间切本，条目仍归这里（评审 P3-2）。
  String? _startedIn;

  /// 会话已销毁：shutdown 的异步续体可能晚于 dispose，需守卫通知与消息投递。
  bool _disposed = false;

  bool get recording => _recording;
  bool get busy => _busy;
  Duration get elapsed => _elapsed;
  double get level => _level;
  bool get available => recorder != null;

  /// 开始录音。返回 null 表示已开始，否则返回面向用户的原因。
  Future<String?> start() async {
    final device = recorder;
    if (device == null || _recording || _busy) return null;
    _busy = true;
    _notify();
    try {
      final reason = await device.unavailableReason();
      if (reason != null) return reason;
      // 先登记临时落点再开录：start 抛错、页面卸载都能据此清理。
      final temp = await store.prepareMediaTemp('ogg');
      _temp = temp;
      _startedIn = store.currentNotebookId;
      await device.start(temp.absolutePath);
      _recording = true;
      _elapsed = Duration.zero;
      _level = 0;
      _ticker = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _tick(),
      );
      return null;
    } on Object catch (error) {
      await _discardTemp();
      return '无法开始录音：$error';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _tick() async {
    if (!_recording) return;
    _elapsed += const Duration(milliseconds: 100);
    _notify();
    try {
      final level = await recorder!.level();
      if (_recording) {
        _level = level;
        _notify();
      }
    } on Object {
      // §10：录音被系统打断（设备被抢占等）——保存已录部分，不静默丢失。
      final message = await stopAndSave(interrupted: true);
      if (message != null && !_messages.isClosed) _messages.add(message);
    }
  }

  /// ✓ 停止并保存。返回 null 表示成功，否则返回提示文案（如「太短了」）。
  Future<String?> stopAndSave({bool interrupted = false}) async {
    if (!_recording || _busy) return null;
    _stopTicker();
    _busy = true;
    _notify();

    Duration duration = _elapsed;
    try {
      duration = await recorder!.stop();
    } on Object {
      // 停不下来时用已计时长兜底
    }
    final message = await _commit(duration);
    if (interrupted && message == null) return '录音被中断，已保存已录部分';
    return message;
  }

  /// ✗ 立即丢弃，不确认（§5.2）。
  Future<void> discard() async {
    if (!_recording || _busy) return;
    _stopTicker();
    _busy = true;
    _notify();
    try {
      await recorder?.discard();
    } on Object {
      // 丢弃失败也要清掉临时文件，避免留下孤儿
    }
    await _discardTemp();
    _reset();
    _busy = false;
    _notify();
  }

  /// 页面/应用销毁时收尾：绝不留下被占用的麦克风与孤儿临时文件。
  /// 已录够 1 秒的内容尽量保住。
  Future<void> shutdown() async {
    if (!_recording) return;
    _stopTicker();
    _recording = false;
    Duration duration = _elapsed;
    try {
      duration = await recorder?.stop() ?? duration;
    } on Object {
      // 忽略
    }
    if (duration >= const Duration(seconds: 1)) {
      await _commit(duration);
    } else {
      await _discardTemp();
    }
  }

  Future<String?> _commit(Duration duration) async {
    final temp = _temp;
    _temp = null;
    // 开录时的笔记本可能已被删除：此时落到当前笔记本（与 §8 撤销回退同语义），
    // 而不是把内部 id 抛进文案、丢掉整段录音（评审 P3-4）。
    final notebookId =
        (_startedIn != null && store.notebooks.any((n) => n.id == _startedIn))
        ? _startedIn
        : null;

    if (temp == null) {
      _reset();
      _busy = false;
      _notify();
      return null;
    }
    if (duration < const Duration(seconds: 1)) {
      await store.discardMedia(temp.relativePath); // 误触：丢弃
      _reset();
      _busy = false;
      _notify();
      return '太短了';
    }

    String? message;
    try {
      await store.addMedia(
        type: EntryType.audio,
        sourceRelativePath: temp.relativePath,
        extension: 'ogg',
        duration: duration.inMilliseconds / 1000,
        notebookId: notebookId,
      );
    } on Object catch (error) {
      await store.discardMedia(temp.relativePath);
      message = '保存录音失败：$error';
    }
    _reset();
    _busy = false;
    _notify();
    return message;
  }

  Future<void> _discardTemp() async {
    final temp = _temp;
    _temp = null;
    if (temp != null) await store.discardMedia(temp.relativePath);
  }

  void _reset() {
    _recording = false;
    _elapsed = Duration.zero;
    _level = 0;
    _startedIn = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    if (!_messages.isClosed) _messages.close();
    // 录音器的释放归属本会话（与播放器归 PlaybackController 同理）：
    // 否则 RecordMediaRecorder 会一直活到进程结束（评审 P3-6）。
    unawaited(recorder?.dispose() ?? Future<void>.value());
    super.dispose();
  }
}

/// 录音条（ui-design §5.2）：左 ✗ 丢弃 · 中 实时时长 + 真实电平 · 右 ✓ 停止并保存。
class RecordingRow extends StatelessWidget {
  const RecordingRow({
    super.key,
    required this.session,
    required this.onMessage,
  });

  final RecordingSession session;

  /// 需要告知用户时的回调（toast 等由外层负责，会话不持有 context）。
  final void Function(String message) onMessage;

  static String mmss(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _stop() async {
    final message = await session.stopAndSave();
    if (message != null) onMessage(message);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(children: [
      IconButton(
        icon: const Icon(Icons.close),
        tooltip: '丢弃',
        onPressed: session.busy ? null : session.discard,
      ),
      const SizedBox(width: 4),
      Icon(Icons.circle, size: 10, color: colors.error),
      const SizedBox(width: 8),
      Text(mmss(session.elapsed), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(width: 12),
      Expanded(
        child: SizedBox(
          height: 6,
          child: LinearProgressIndicator(
            value: session.level.clamp(0.0, 1.0),
            backgroundColor: colors.surfaceContainerHighest,
          ),
        ),
      ),
      const SizedBox(width: 12),
      IconButton(
        icon: const Icon(Icons.check),
        tooltip: '停止并保存',
        onPressed: session.busy ? null : _stop,
      ),
    ]);
  }
}
