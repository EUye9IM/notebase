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
///
/// 并发正确性（M6 评审 P2-2）：
/// - **意图同步落地**：点击后立刻更新 `playingId`/`playing`，所以「最后一次点击」
///   决定哪一行显示播放态，不会被底层 await 的返回顺序左右；
/// - **底层操作串行化**：播放器只有一个，所有 play/pause/stop 走同一条队列，
///   避免并发下两次 play 同时下发、谁都没被 stop。
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this.player,
    required this.resolvePath,
    this.available = true,
  });

  final MediaPlayer player;

  /// 是否具备真实播放能力：false 时条目行渲染为不可播放，且点按不会 toggle
  /// （否则会把行标成「播放中」而其实毫无声音）。
  final bool available;

  /// 条目的媒体相对路径 → 绝对路径（由 core 的落点约定决定）。
  final Future<String> Function(Entry entry) resolvePath;

  String? _playingId;
  bool _playing = false;

  /// 底层播放器是否已装载当前条目（暂停后可 resume，不必重头播）。
  bool _loaded = false;

  /// 播放器里**真正装载着**的条目 id：完成事件不带身份，只能靠它判断事件
  /// 归属。否则 A 自然播完的完成事件若晚于「点 B」送达，会无条件清空
  /// `_playingId`，把 B 的播放态抹掉（M6 全段评审 P2-1）。
  String? _loadedId;

  Duration _position = Duration.zero;
  Timer? _ticker;
  StreamSubscription<void>? _completeSub;
  Future<void> _queue = Future<void>.value();

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
  Future<void> toggle(Entry entry) {
    if (_playingId == entry.id) {
      _playing = !_playing;
    } else {
      _playingId = entry.id;
      _playing = true;
      _loaded = false;
      _position = Duration.zero;
    }
    _completeSub ??= player.onComplete.listen((_) => _handleComplete());
    if (_playing) {
      _startTicker();
    } else {
      _stopTicker();
    }
    notifyListeners();
    return _enqueue(() => _apply(entry));
  }

  Future<void> _apply(Entry entry) async {
    if (_playingId != entry.id) return; // 期间已被别的条目接管
    if (!_playing) {
      try {
        await player.pause();
      } on Object {
        // 播放器可能已自然结束
      }
      return;
    }
    try {
      if (_loaded) {
        await player.resume();
        return;
      }
      final path = await resolvePath(entry);
      if (_playingId != entry.id) return; // 解析路径期间被接管
      await player.stop(); // 单播放器：先停再播，保证同时只播一条
      _loadedId = null; // 停掉之后，之前装载的条目的完成事件不再算数
      await player.play(path);
      if (_playingId != entry.id) return;
      _loaded = true;
      _loadedId = entry.id;
    } on Object {
      // 播放失败（文件缺失 / 缺解码器）：复位为未播放，UI 表现为点不动
      if (_playingId == entry.id) {
        _playingId = null;
        _playing = false;
        _loaded = false;
        _loadedId = null;
        _position = Duration.zero;
        _stopTicker();
        notifyListeners();
      }
    }
  }

  /// 条目被删除/移除时停止播放并复位，避免进度定时器空转（评审 P3-1）。
  Future<void> stopIfPlaying(String entryId) {
    if (_playingId != entryId) return Future<void>.value();
    _playingId = null;
    _playing = false;
    _loaded = false;
    _loadedId = null;
    _position = Duration.zero;
    _stopTicker();
    notifyListeners();
    return _enqueue(() async {
      try {
        await player.stop();
      } on Object {
        // 忽略
      }
    });
  }

  /// 停止一切播放（切笔记本时调用：否则声音继续、当前本却没有任何播放控件）。
  Future<void> stopAll() => stopIfPlaying(_playingId ?? '');

  /// 串行化底层播放器操作（沿用存储写队列的思路）。
  Future<void> _enqueue(Future<void> Function() operation) {
    final op = _queue.catchError((_) {}).then((_) => operation());
    _queue = op;
    return op;
  }

  void _handleComplete() {
    // 严格判定：完成事件只对「播放器里真正装载着的那条」有效。
    // play 尚在途中、或已被别的条目接管时（_loadedId 为 null 或指向旧条目），
    // 事件一律忽略——否则会抹掉新起播条目的播放态（评审 P2-1）。
    if (_loadedId != _playingId) return;
    _loadedId = null;
    _playingId = null;
    _playing = false;
    _loaded = false;
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
