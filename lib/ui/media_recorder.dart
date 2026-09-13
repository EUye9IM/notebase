import 'dart:io';

import 'package:record/record.dart';

/// 录音能力抽象（UI 层）。
///
/// core 保持零 Flutter 依赖，平台能力一律由 UI 注入；这里再抽一层是为了
/// **让 widget 测试不触碰平台通道**——测试注入假实现即可驱动 §5.2 状态机。
abstract class MediaRecorder {
  /// 可用性检查：返回 null 表示可用，否则返回面向用户的原因（缺二进制、无权限等）。
  Future<String?> unavailableReason();

  /// 开始录音，音频落到 [path]（绝对路径，由 core 约定位置）。
  Future<void> start(String path);

  /// 停止并返回本次录制时长。
  Future<Duration> stop();

  /// 丢弃当前录制（不保留文件内容）。
  Future<void> discard();

  /// 当前电平 0..1，用于电平动画（真实采集）。
  Future<double> level();

  Future<void> dispose();
}

/// 基于 `record` 插件的实现。
///
/// Linux 后端为 `parecord`（PulseAudio utils）+ `ffmpeg` 两个外部二进制：
/// 缺任一个都无法录音，故 [unavailableReason] 会显式检查并给出可读原因，
/// 而不是让录音静默失败（ui-design §5.2）。
///
/// 编码选 **ogg/Opus**：M6 spike 实测基础 GStreamer 即可解码播放，
/// 且体积约为 wav 的 1/23；aac 需要额外的解码插件，不能假设用户装齐。
class RecordMediaRecorder implements MediaRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  Stopwatch? _stopwatch;

  static const _encoder = AudioEncoder.opus;
  static const _requiredBinaries = ['parecord', 'ffmpeg'];

  @override
  Future<String?> unavailableReason() async {
    if (!await _recorder.hasPermission(request: true)) {
      return '没有麦克风权限，请在系统设置中允许后重试';
    }
    if (Platform.isLinux) {
      for (final bin in _requiredBinaries) {
        if (!await _binaryExists(bin)) {
          return '系统缺少 $bin，无法录音（需安装 pulseaudio-utils 与 ffmpeg）';
        }
      }
    }
    if (!await _recorder.isEncoderSupported(_encoder)) {
      return '当前设备不支持 Opus 编码';
    }
    return null;
  }

  Future<bool> _binaryExists(String name) async {
    try {
      final result = await Process.run('which', [name]);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> start(String path) async {
    await _recorder.start(
      const RecordConfig(encoder: _encoder, bitRate: 64000, sampleRate: 48000),
      path: path,
    );
    _stopwatch = Stopwatch()..start();
  }

  @override
  Future<Duration> stop() async {
    _stopwatch?.stop();
    await _recorder.stop();
    final elapsed = _stopwatch?.elapsed ?? Duration.zero;
    _stopwatch = null;
    return elapsed;
  }

  @override
  Future<void> discard() async {
    _stopwatch?.stop();
    _stopwatch = null;
    await _recorder.cancel();
  }

  @override
  Future<double> level() async {
    final amplitude = await _recorder.getAmplitude();
    return _normalize(amplitude.current);
  }

  /// dBFS（约 -60..0）→ 0..1，供电平动画使用。
  static double _normalize(double dbfs) =>
      ((dbfs + 60) / 60).clamp(0.0, 1.0).toDouble();

  @override
  Future<void> dispose() => _recorder.dispose();
}
