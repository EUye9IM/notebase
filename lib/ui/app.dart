import 'package:flutter/material.dart';

import '../core/model.dart';
import '../core/store.dart';
import 'home.dart';
import 'listenable_bridge.dart';
import 'media_importer.dart';
import 'media_player.dart';
import 'media_recorder.dart';

/// 应用根：主题偏好驱动 MaterialApp，全局监听 store 变更。
class NotebaseApp extends StatefulWidget {
  const NotebaseApp({
    super.key,
    required this.store,
    this.startupNotice,
    this.recorder,
    this.player,
    this.importer,
  });

  final AppStore store;

  /// 录音能力（§5.2）。由 main 注入真实实现，测试注入假实现。
  final MediaRecorder? recorder;

  /// 播放能力（§4/§8）。为 null 时媒体条目不可播放。
  final MediaPlayer? player;

  /// 图片导入能力（§5.3）。为 null 时 📷 置灰。
  final MediaImporter? importer;

  /// 启动期数据损坏等需要告知用户的信息（ui-design §10），可关闭。
  final String? startupNotice;

  @override
  State<NotebaseApp> createState() => _NotebaseAppState();
}

class _NotebaseAppState extends State<NotebaseApp> {
  late final CoreListenableBridge _bridge;
  late final PlaybackController _playback;

  @override
  void initState() {
    super.initState();
    _bridge = CoreListenableBridge(widget.store);
    // 必须在 initState 创建并持有：早先在 build 里现造过一次，控制器无人
    // dispose，播放进度定时器会一直挂着（被「未注入播放能力」用例抓到）。
    _playback = PlaybackController(
      player: widget.player ?? _NoopMediaPlayer(),
      available: widget.player != null,
      resolvePath: (entry) async =>
          entry.file == null ? '' : widget.store.mediaAbsolutePath(entry.file!),
    );
  }

  @override
  void dispose() {
    _bridge.dispose();
    _playback.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _bridge,
      builder: (context, _) => MaterialApp(
        title: 'Notebase',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: switch (widget.store.theme) {
          ThemeSetting.system => ThemeMode.system,
          ThemeSetting.light => ThemeMode.light,
          ThemeSetting.dark => ThemeMode.dark,
        },
        home: PlaybackScope(
          controller: _playback,
          child: HomePage(
            store: widget.store,
            startupNotice: widget.startupNotice,
            recorder: widget.recorder,
            importer: widget.importer,
          ),
        ),
      ),
    );
  }
}

/// 未注入播放能力时的占位：点播放什么都不发生，但界面结构一致。
class _NoopMediaPlayer implements MediaPlayer {
  @override
  Future<void> play(String absolutePath) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<Duration> position() async => Duration.zero;
  @override
  Stream<void> get onComplete => const Stream<void>.empty();
  @override
  Future<void> dispose() async {}
}
