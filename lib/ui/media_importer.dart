import 'package:file_selector/file_selector.dart';

/// 图片导入能力抽象（UI 层）：测试注入假实现即可驱动导入流程，
/// 不必弹出真实文件对话框。
abstract class MediaImporter {
  /// 选择一张图片；返回其**绝对路径**，用户取消返回 null。
  Future<String?> pickImage();
}

/// 基于 `file_selector` 的实现：Linux 走 GTK 原生对话框
/// （`file_selector_linux` 自带，不依赖 zenity/kdialog，M6 spike 已确认）。
///
/// Linux 桌面端**没有应用内取景器**（官方 camera 插件不支持 Linux，
/// `image_picker` 在 Linux 上也只委托文件对话框），故 §5.3 的「📷」在
/// Linux 落地为文件导入；应用内取景器随 Android（M8）。
class FileSelectorMediaImporter implements MediaImporter {
  const FileSelectorMediaImporter();

  static const _imageTypes = XTypeGroup(
    label: '图片',
    extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
  );

  @override
  Future<String?> pickImage() async {
    final file = await openFile(acceptedTypeGroups: const [_imageTypes]);
    return file?.path;
  }
}

/// 从路径取扩展名（小写、无点）；无扩展名时回退 png。
String imageExtensionOf(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return 'png';
  return name.substring(dot + 1).toLowerCase();
}
