import 'package:flutter/material.dart';

import 'camera_capture.dart';

/// 应用内取景器（ui-design §5.3）：全屏、预览铺满、**快门即保存**。
///
/// - 主路径只有一个控件：快门（底部居中，拇指可达）。关闭在左上；
///   多镜头设备右上给切换；左下角是次要的「相册」入口（需要时才有）。
/// - **没有**预览确认、没有重拍：误拍的代价是「长按 → 删除 → 确认」（§9 论证过）。
/// - 出错（无权限 / 相机被占用 / 初始化失败）时给可读原因 + 关闭，不把用户扔在黑屏里（§10）。
///
/// 相机会话由 [createSession] 提供，测试注入假会话即可驱动整页状态机。
class CameraViewfinderPage extends StatefulWidget {
  const CameraViewfinderPage({
    super.key,
    required this.createSession,
    required this.targetPath,
    this.pickFromGallery,
  });

  final CameraSessionFactory createSession;

  /// core 给的临时落点：拍到的照片直接写在这里（UI 不做文件搬运）。
  final String targetPath;

  /// 角落「相册」入口：返回用户选中的文件路径（null = 取消）。
  /// 为 null 时不显示该入口（未注入导入能力）。
  final Future<String?> Function()? pickFromGallery;

  @override
  State<CameraViewfinderPage> createState() => _CameraViewfinderPageState();
}

class _CameraViewfinderPageState extends State<CameraViewfinderPage> {
  CameraSession? _session;
  String? _error;

  /// 快门防重入：拍照 + 归档期间再点不生效（reviewer 教训：并发点两条会出双条目）。
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final session = await widget.createSession();
      await session.initialize();
      if (!mounted) {
        await session.dispose(); // 页面已销毁：别把相机占着
        return;
      }
      setState(() => _session = session);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    }
  }

  /// 面向用户的原因（§10：按下入口就立刻说清楚，不让用户进到一半失败）。
  static String _readableError(Object error) {
    final text = error.toString();
    if (text.contains('AccessDenied') || text.contains('permission')) {
      return '没有相机权限，请在系统设置中允许后重试';
    }
    if (text.contains('NoCamera')) return '这台设备没有可用相机';
    return '相机打不开：$text';
  }

  Future<void> _shoot() async {
    final session = _session;
    if (session == null || _busy) return;
    setState(() => _busy = true);
    try {
      await session.takePicture(widget.targetPath);
      if (mounted) Navigator.of(context).pop(CameraShot(widget.targetPath));
    } on Object catch (error) {
      // 拍失败留在取景器里可重试（不建条目、不留孤儿文件）
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失败：$error')),
        );
      }
    }
  }

  Future<void> _fromGallery() async {
    final pick = widget.pickFromGallery;
    if (pick == null || _busy) return;
    setState(() => _busy = true);
    final path = await pick();
    if (!mounted) return;
    if (path == null) {
      setState(() => _busy = false); // 用户取消：留在取景器
      return;
    }
    Navigator.of(context).pop(CameraShot(path, fromGallery: true));
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _preview(session)),
            Positioned(
              left: 4,
              top: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (session != null && session.canSwitchLens)
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  icon: const Icon(Icons.cameraswitch_outlined,
                      color: Colors.white),
                  tooltip: '切换镜头',
                  onPressed: _busy ? null : session.switchLens,
                ),
              ),
            // 出错（无权限 / 相机打不开）时不显示快门与相册入口：没什么可拍的，
            // 只留左上「关闭」（§10：给可读原因，不把用户扔在黑屏里）。
            if (_error == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SizedBox(
                    width: 56,
                    child: widget.pickFromGallery == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.photo_library_outlined,
                                color: Colors.white),
                            tooltip: '从相册选择',
                            onPressed: _busy ? null : _fromGallery,
                          ),
                  ),
                  _ShutterButton(onPressed: _busy ? null : _shoot),
                  const SizedBox(width: 56), // 让快门保持居中
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(CameraSession? session) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(child: session.buildPreview(context));
  }
}

/// 快门（唯一主控件）：大圆钮，按下期间禁用（防重入）。
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: '拍照',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? Colors.white : Colors.white54,
            border: Border.all(color: Colors.white70, width: 4),
          ),
          child: const Icon(Icons.camera_alt, color: Colors.black54),
        ),
      ),
    );
  }
}
