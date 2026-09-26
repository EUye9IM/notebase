import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_view.dart';
import 'media_importer.dart';

/// 一次「拿到一张照片」的结果：路径 + 来源。
///
/// 来源很重要：相机照片写在**我们提供的临时落点**里（core 约定 → 走 `addMedia` 归档），
/// 相册选中的是**用户的文件**（只能复制 → 走 `importPhoto`，原图必须留在原处）。
class CameraShot {
  const CameraShot(this.path, {this.fromGallery = false});

  final String path;
  final bool fromGallery;
}

/// 相机拍照能力抽象（UI 层），与 `MediaRecorder` / `MediaImporter` 同款：
/// widget 测试注入假实现即可驱动交互，不必触碰平台通道。
abstract class CameraCapture {
  /// 有没有可用相机。无相机的平台（Linux 桌面、`camera` 插件不支持）返回 false，
  /// 此时「📷」退回文件导入（ui-design §5.3）。
  Future<bool> available();

  /// 打开取景器（整屏）。返回拍到的照片，用户取消返回 null。
  ///
  /// [targetPath] 是 core 给的临时落点：会话把照片**直接写在/搬到**这里，
  /// 因此 UI 层不需要自己做任何文件搬运（也避免在 widget 测试里 await 真实 I/O）。
  /// [gallery] 非空时，取景器左下角提供「相册」入口（系统选图器）。
  Future<CameraShot?> open(
    BuildContext context, {
    required String targetPath,
    MediaImporter? gallery,
  });
}

/// 基于官方 `camera` 插件的实现（Android / iOS）。
class CameraCaptureImpl implements CameraCapture {
  const CameraCaptureImpl();

  @override
  Future<bool> available() async {
    try {
      return (await availableCameras()).isNotEmpty;
    } on Object {
      // 没权限 / 没实现 / 没相机：一律当作「没有」，让 📷 退回文件导入
      return false;
    }
  }

  @override
  Future<CameraShot?> open(
    BuildContext context, {
    required String targetPath,
    MediaImporter? gallery,
  }) =>
      Navigator.of(context).push<CameraShot>(
        MaterialPageRoute<CameraShot>(
          fullscreenDialog: true,
          builder: (_) => CameraViewfinderPage(
            createSession: _createSession,
            targetPath: targetPath,
            pickFromGallery: gallery?.pickImage,
          ),
        ),
      );

  static Future<CameraSession> _createSession() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw CameraException('NoCamera', '没有可用相机');
    }
    return PluginCameraSession(cameras);
  }
}

/// 取景器背后的相机会话：把 `camera` 插件的 `CameraController` 收在这层之后，
/// 让 [CameraViewfinderPage] 可以在 widget 测试里注入假会话（不碰平台通道）。
abstract class CameraSession {
  Future<void> initialize();

  /// 实时预览（cover 铺满由调用方决定）。
  Widget buildPreview(BuildContext context);

  /// 拍一张，写到 [targetPath]（core 约定的临时落点）。
  Future<void> takePicture(String targetPath);

  /// 是否有多个镜头可切换。
  bool get canSwitchLens;

  Future<void> switchLens();

  Future<void> dispose();
}

typedef CameraSessionFactory = Future<CameraSession> Function();

/// 真实会话：默认后置，可在多镜头设备上切换。
class PluginCameraSession implements CameraSession {
  PluginCameraSession(this._cameras) : _index = _defaultIndex(_cameras);

  final List<CameraDescription> _cameras;
  int _index;
  CameraController? _controller;

  static int _defaultIndex(List<CameraDescription> cameras) {
    final back = cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    return back >= 0 ? back : 0;
  }

  @override
  Future<void> initialize() async {
    final controller = CameraController(
      _cameras[_index],
      ResolutionPreset.high,
      enableAudio: false, // 只拍照：不要麦克风权限
    );
    try {
      await controller.initialize();
    } on Object {
      await controller.dispose(); // 初始化失败要释放，否则相机被占住
      rethrow;
    }
    _controller = controller;
  }

  @override
  Widget buildPreview(BuildContext context) =>
      CameraPreview(_controller!);

  @override
  Future<void> takePicture(String targetPath) async {
    // 插件先写进自己的缓存目录，再搬到 core 给的落点（真实 I/O 只发生在这里，
    // widget 测试注入假会话，不会 await 到它）。
    final shot = await _controller!.takePicture();
    await _moveInto(File(shot.path), targetPath);
  }

  /// 同盘 rename；跨盘退化为复制 + 删除。
  static Future<void> _moveInto(File source, String target) async {
    try {
      await source.rename(target);
    } on FileSystemException {
      await source.copy(target);
      try {
        await source.delete();
      } on Object {
        // 删不掉只会在插件缓存目录里留一个文件，交给系统清理
      }
    }
  }

  @override
  bool get canSwitchLens => _cameras.length > 1;

  @override
  Future<void> switchLens() async {
    if (!canSwitchLens) return;
    _index = (_index + 1) % _cameras.length;
    await _controller!.setDescription(_cameras[_index]);
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
