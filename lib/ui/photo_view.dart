import 'dart:io';

import 'package:flutter/material.dart';

/// 照片渲染与查看（ui-design §4 / §5.3 / §10）。

/// 缩略图：等比、宽约列宽的 60%；铺满 4:3 框以保证列表高度稳定。
/// 文件缺失/损坏时给占位，不 crash（§10）。
class PhotoThumbnail extends StatefulWidget {
  const PhotoThumbnail({super.key, required this.path});

  final String path;

  @override
  State<PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<PhotoThumbnail> {
  /// 存在性检查放在 State 里只做一次：时间流没有虚拟化，若在 build 里 stat，
  /// 每次 store 通知都会对所有照片行做同步 IO（评审 P3-8）。
  late bool _exists = File(widget.path).existsSync();

  @override
  void didUpdateWidget(PhotoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _exists = File(widget.path).existsSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
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
              ? Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      const _MissingPhoto(label: '图片已丢失'),
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
Future<void> showPhotoViewer(BuildContext context, String path) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoViewerPage(path: path),
      ),
    );

class PhotoViewerPage extends StatelessWidget {
  const PhotoViewerPage({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
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
            child: file.existsSync()
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
