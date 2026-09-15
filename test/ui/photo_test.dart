import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/ui/app.dart';
import 'package:notebase/ui/media_importer.dart';
import 'package:notebase/ui/photo_view.dart';

import '../support/memory_storage.dart';

/// M6d 验收（ui-design §4 / §5.3 / §8 / §10）：导入交互、缩略图占位、全屏查看器。
///
/// 注：widget 测试的 fake-async 下真实文件 I/O 不会完成（`Image.file` 解码、
/// 复制文件都会挂住），因此**「导入只复制不移动」的语义由 core 的真实文件
/// 测试覆盖**（见 `test/core/media_test.dart`「importPhoto 只复制不移动」），
/// 这里只测交互与渲染分支（含文件缺失的占位，不触发解码）。
class FakeMediaImporter implements MediaImporter {
  FakeMediaImporter({this.path, this.throwOnPick = false});

  /// 返回给「用户选中」的文件路径；null 表示用户取消。
  String? path;
  final bool throwOnPick;
  int pickCount = 0;

  @override
  Future<String?> pickImage() async {
    pickCount++;
    if (throwOnPick) throw StateError('对话框起不来');
    return path;
  }
}

void main() {
  late MemoryStorage storage;
  late AppStore store;
  late Directory dir;

  setUp(() async {
    // 全程用**同步**文件 I/O：widget 测试跑在 fake-async 区里，
    // await 真实 I/O 的 Future 永远不会完成（会直接挂住测试）。
    dir = Directory.systemTemp.createTempSync('notebase_photo_ui');
    storage = MemoryStorage();
    store = await AppStore.load(storage);
  });

  tearDown(() async {
    dir.deleteSync(recursive: true);
  });

  String pickedImage(String name) {
    final file = File('${dir.path}/$name')..writeAsBytesSync(const [1, 2, 3]);
    return file.path;
  }

  /// 构造一条照片条目，并让它的文件不存在（渲染走占位分支，不触发解码）。
  Future<void> addPhotoWithMissingFile() async {
    await storage.prepareMediaPath('media/.tmp/p.png');
    final entry = await store.addMedia(
      type: EntryType.photo,
      sourceRelativePath: 'media/.tmp/p.png',
      extension: 'png',
    );
    await store.discardMedia(entry.file!);
  }

  Future<void> pumpApp(WidgetTester tester, {MediaImporter? importer}) async {
    await tester.pumpWidget(NotebaseApp(store: store, importer: importer));
    await tester.pumpAndSettle();
  }

  Finder importButton() =>
      find.widgetWithIcon(IconButton, Icons.photo_outlined);

  group('导入交互（§5.3）', () {
    testWidgets('点 📷 选图 → 立即入流（成功路径，一次一张）', (tester) async {
      final picked = pickedImage('IMG_1.png');
      final importer = FakeMediaImporter(path: picked);
      await pumpApp(tester, importer: importer);

      await tester.tap(importButton());
      await tester.pumpAndSettle();

      expect(importer.pickCount, 1);
      final entry = store.entries.single;
      expect(entry.type, EntryType.photo);
      expect(entry.file, 'media/${entry.id}.png'); // 命名约定：文件名=条目 id
      expect(File(picked).existsSync(), isTrue); // 原图仍在原处（只复制不移动）
    });

    testWidgets('用户取消：不产生条目', (tester) async {
      final importer = FakeMediaImporter(path: null);
      await pumpApp(tester, importer: importer);

      await tester.tap(importButton());
      await tester.pumpAndSettle();

      expect(importer.pickCount, 1);
      expect(store.entries, isEmpty);
    });

    testWidgets('对话框失败：给出可读提示，不留条目', (tester) async {
      final importer = FakeMediaImporter(throwOnPick: true);
      await pumpApp(tester, importer: importer);

      await tester.tap(importButton());
      await tester.pumpAndSettle();

      expect(find.textContaining('导入图片失败'), findsOneWidget);
      expect(store.entries, isEmpty);
    });

    testWidgets('未注入导入能力：📷 置灰', (tester) async {
      await pumpApp(tester);
      expect(tester.widget<IconButton>(importButton()).onPressed, isNull);
    });

    test('扩展名跟随所选文件（imageExtensionOf）', () {
      expect(imageExtensionOf('/home/u/Pictures/IMG_0001.JPG'), 'jpg');
      expect(imageExtensionOf('/home/u/a.b.png'), 'png');
      expect(imageExtensionOf('/home/u/noext'), 'png'); // 无扩展名回退
    });
  });

  group('缩略图与查看器（§4 / §8 / §10）', () {
    testWidgets('媒体文件缺失：缩略图占位「图片已丢失」，不 crash（§10）', (tester) async {
      await addPhotoWithMissingFile();
      await pumpApp(tester);

      expect(find.byType(PhotoThumbnail), findsOneWidget);
      expect(find.text('图片已丢失'), findsOneWidget);
      // 关键：走的是「同步存在性检查」分支，没有发起 Image.file 解码
      // （两者文案相同，只断言文案无法证明这条安全要点）
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点按缩略图打开全屏查看器，点空白关闭（§8）', (tester) async {
      await addPhotoWithMissingFile();
      await pumpApp(tester);

      await tester.tap(find.byType(PhotoThumbnail));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewerPage), findsOneWidget);
      expect(find.text('图片已丢失'), findsOneWidget); // 查看器内同样是占位

      await tester.tapAt(const Offset(200, 500)); // 点空白处关闭
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewerPage), findsNothing);
    });
  });
}
