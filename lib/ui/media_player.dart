import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import '../core/model.dart';

/// 播放能力抽象（UI 层）：与录音同理，测试注入假实现即可驱动交互，
/// 不必触碰平台通道。
abstract class MediaPlayer {
  /// 播放 [absolutePath]，替代当前内容。
  Future<void> play(String absolutePath);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();

  /// 当前播放位置（实现精度自定；用于进度显示）。
  Future<Duration> position();

  /// 自然播放完成。
  Stream<void> get onComplete;

  Future<void> dispose();
}

/// 基于 `audioplayers`（Linux 走 GStreamer）的实现。
///
/// M6 spike 实测：基础 GStreamer 插件集能解码 ogg/Opus、wav、flac、vorbis，
/// **不能解码 aac/m4a**（需额外装 gst-plugins-bad/libav）——这也是录音选
/// ogg/Opus 的原因之一。注意 Linux 上 `getDuration()` 返回 null，
/// 故时长以条目自带的 `duration` 为准。
class AudioPlayersMediaPlayer implements MediaPlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> play(String absolutePath) =>
      _player.play(DeviceFileSource(absolutePath));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<Duration> position() async =>
      await _player.getCurrentPosition() ?? Duration.zero;

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> dispose() => _player.dispose();
}

/// 内联播放编排（ui-design §4 / §8）：同一时刻只播一条，位置用于进度条。
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this.player,
    required this.resolvePath,
    this.available = true,
  });

  final MediaPlayer player;

  /// 是否具备真实播放能力：false 时条目行渲染为不可播放（不误导用户点击）。
  final bool available;

  /// 条目的媒体相对路径 → 绝对路径（由 core 的落点约定决定）。
  final Future<String> Function(Entry entry) resolvePath;

  String? _playingId;
  bool _playing = false;
  Duration _position = Duration.zero;
  Timer? _ticker;
  StreamSubscription<void>? _completeSub;

  /// 正在播放的条目 id（暂停时仍指向该条目）。
  String? get playingId => _playingId;

  bool isPlaying(String entryId) => _playingId == entryId && _playing;

  bool isCurrent(String entryId) => _playingId == entryId;

  Duration get position => _position;

  /// 进度 0..1；无已知时长时返回 null（不显示进度）。
  double? progressFor(Entry entry) {
    if (_playingId != entry.id) return null;
    final total = entry.duration;
    if (total == null || total <= 0) return null;
    return (_position.inMilliseconds / (total * 1000)).clamp(0.0, 1.0);
  }

  /// ▶ / ⏸：同一条切换播放暂停，另一条则切换过去。
  Future<void> toggle(Entry entry) async {
    if (_playingId == entry.id) {
      if (_playing) {
        await player.pause();
        _playing = false;
        _stopTicker();
      } else {
        await player.resume();
        _playing = true;
        _startTicker();
      }
      notifyListeners();
      return;
    }
    await _stopCurrent();
    try {
      final path = await resolvePath(entry);
      await player.play(path);
      _playingId = entry.id;
      _playing = true;
      _position = Duration.zero;
      _completeSub ??= player.onComplete.listen((_) => _handleComplete());
      _startTicker();
    } on Object {
      // 播放失败（文件丢失 / 缺解码器）：复位为未播放，UI 表现为点不动。
      _playingId = null;
      _playing = false;
    }
    notifyListeners();
  }

  Future<void> _stopCurrent() async {
    if (_playingId == null) return;
    _stopTicker();
    try {
      await player.stop();
    } on Object {
      // 忽略：底层可能已自然结束
    }
    _playingId = null;
    _playing = false;
    _position = Duration.zero;
  }

  void _handleComplete() {
    _playingId = null;
    _playing = false;
    _position = Duration.zero;
    _stopTicker();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      try {
        _position = await player.position();
        notifyListeners();
      } on Object {
        _stopTicker();
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    _completeSub?.cancel();
    player.dispose();
    super.dispose();
  }
}

/// 把播放编排提供给条目行（避免逐层透传）：继承自 [InheritedNotifier]，
/// 控制器变更时依赖它的行会自动重建。
class PlaybackScope extends InheritedNotifier<PlaybackController> {
  const PlaybackScope({
    super.key,
    required PlaybackController controller,
    required super.child,
  }) : super(notifier: controller);

  static PlaybackController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackScope>()?.notifier;

  /// 不建立依赖的读取（在回调里用）：只有音频行需要在进度变化时重建，
  /// 文本行不该被牵连。
  static PlaybackController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlaybackScope>()?.notifier;
}
