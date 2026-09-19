import 'dart:io';

import 'package:flutter/material.dart';

import '../core/store.dart';

/// 照片渲染与查看（ui-design §4 / §5.3 / §10）。

/// 缩略图：等比、宽约列宽的 60%；铺满 4:3 框以保证列表高度稳定。
/// 文件缺失/损坏时给占位，不 crash（§10）。
class PhotoThumbnail extends StatefulWidget {
  const PhotoThumbnail({
    super.key,
    required this.store,
    required this.relativePath,
  });

  final AppStore store;

  /// 媒体相对路径（`media/<条目 id>.<ext>`）。
  final String relativePath;

  @override
  State<PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<PhotoThumbnail> {
  /// 存在性检查放在 State 里只做一次：时间流没有虚拟化，若在 build 里查，
  /// 每次 store 通知都会对所有照片行做一遍同步检查（评审 P3-8）。
  /// 「文件在不在」由 Storage 回答，UI 不直接摸文件系统。
  late bool _exists = widget.store.mediaExists(widget.relativePath);

  @override
  void didUpdateWidget(PhotoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath) {
      _exists = widget.store.mediaExists(widget.relativePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.store.mediaPath(widget.relativePath);
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: 0.6,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          // 先做存在性检查：文件没了就直接占位，不必发起一次注定失败的
          // 异步解码（也让「缺失占位」这条契约可被测试）。
          child: _exists
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    // 按**目标显示尺寸**解码：不传 cacheWidth 会整幅解码原图
                    // （12MP ≈ 48MB 位图），叠加「时间流无虚拟化」＝首帧为所有
                    // 照片一起解码，ImageCache 反复淘汰重解码（复检 P2）。
                    // 这里的约束已经是 FractionallySizedBox 之后的 60% 列宽。
                    final dpr = MediaQuery.devicePixelRatioOf(context);
                    final target = (constraints.maxWidth * dpr).round();
                    return Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      cacheWidth: target > 0 ? target : null,
                      errorBuilder: (context, error, stack) =>
                          const _MissingPhoto(label: '图片已丢失'),
                    );
                  },
                )
              : const _MissingPhoto(label: '图片已丢失'),
        ),
      ),
    );
  }
}

class _MissingPhoto extends StatelessWidget {
  const _MissingPhoto({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: colors.outline),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// 全屏查看器（§8：点按照片打开，点空白或返回关闭）。
Future<void> showPhotoViewer(
  BuildContext context, {
  required AppStore store,
  required String relativePath,
}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoViewerPage(store: store, relativePath: relativePath),
      ),
    );

class PhotoViewerPage extends StatelessWidget {
  const PhotoViewerPage({
    super.key,
    required this.store,
    required this.relativePath,
  });

  final AppStore store;
  final String relativePath;

  @override
  Widget build(BuildContext context) {
    final file = File(store.mediaPath(relativePath));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        // 点空白处关闭（§8）
        onTap: () => Navigator.of(context).maybePop(),
        child: SizedBox.expand(
          child: InteractiveViewer(
            maxScale: 6,
            child: store.mediaExists(relativePath)
                ? Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) =>
                        const _MissingPhoto(label: '图片已丢失'),
                  )
                : const _MissingPhoto(label: '图片已丢失'),
          ),
        ),
      ),
    );
  }
}
