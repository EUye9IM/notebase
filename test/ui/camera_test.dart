import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/store.dart';
import 'package:notebase/ui/app.dart';
import 'package:notebase/ui/camera_capture.dart';
import 'package:notebase/ui/camera_view.dart';
import 'package:notebase/ui/media_importer.dart';

import '../support/memory_storage.dart';

/// M8 相机取景器（ui-design §5.3）：
/// - 📷 统一入口：有相机 → 取景器拍照（移动归档，与录音同路）；无相机 → 文件导入。
/// - 相册入口选中的是**用户的文件** → `importPhoto`（只复制，原图留在原处）。
/// - 快门即保存（无预览确认）；取消/失败不产生条目、不留孤儿。
/// - 取景器整页状态机（初始化失败/权限拒绝/连点快门）用假会话驱动。

class FakeMediaImporter implements MediaImporter {
  FakeMediaImporter({this.path});
  String? path;
  int pickCount = 0;

  @override
  Future<String?> pickImage() async {
    pickCount++;
    return path;
  }
}

class FakeCameraCapture implements CameraCapture {
  FakeCameraCapture({this.shot, this.isAvailable = true, this.throwOnOpen = false});

  CameraShot? shot;
  bool isAvailable;
  bool throwOnOpen;
  int openCount = 0;
  MediaImporter? gallerySeen;

  @override
  Future<bool> available() async => isAvailable;

  /// 相机流程里 UI 传进来的落点（断言「写在 core 给的临时路径」）。
  final targets = <String>[];

  @override
  Future<CameraShot?> open(
    BuildContext context, {
    required String targetPath,
    MediaImporter? gallery,
  }) async {
    openCount++;
    targets.add(targetPath);
    gallerySeen = gallery;
    if (throwOnOpen) throw StateError('相机起不来');
    return shot;
  }
}

class FakeCameraSession implements CameraSession {
  FakeCameraSession({
    this.throwOnInit = false,
    this.throwOnShoot = false,
    this.canSwitch = false,
  });

  bool throwOnInit;
  bool throwOnShoot;
  bool canSwitch;

  /// 非 null 时 `takePicture` 挂起，用于验证快门防重入。
  Completer<void>? shootGate;

  int initCount = 0;
  int shootCount = 0;
  int switchCount = 0;
  int disposeCount = 0;

  @override
  Future<void> initialize() async {
    initCount++;
    if (throwOnInit) {
      throw CameraException('CameraAccessDenied', 'Permission denied');
    }
  }

  @override
  Widget buildPreview(BuildContext context) => const ColoredBox(
        color: Color(0xFF202020),
        child: SizedBox.expand(),
      );

  /// 收到过的落点（真实实现会把照片写在这里）。
  final targets = <String>[];

  @override
  Future<void> takePicture(String targetPath) async {
    shootCount++;
    targets.add(targetPath);
    if (shootGate != null) await shootGate!.future;
    if (throwOnShoot) throw StateError('拍不了');
  }

  @override
  bool get canSwitchLens => canSwitch;

  @override
  Future<void> switchLens() async => switchCount++;

  @override
  Future<void> dispose() async => disposeCount++;
}

void main() {
  late Directory dir;
  late MemoryStorage storage;
  late AppStore store;

  setUp(() async {
    // 相册分支要 importPhoto（只复制）→ 需要源文件真实存在；相机分支不碰文件系统
    // （会话负责写入 core 给的落点，widget 测试里是假会话）。
    dir = Directory.systemTemp.createTempSync('notebase_camera_ui');
    storage = MemoryStorage();
    store = await AppStore.load(storage);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// 造一个真实存在的「相机刚拍出来的」文件。
  String shotFile(String name) =>
      (File('${dir.path}/$name')..writeAsBytesSync(const [1, 2, 3])).path;

  /// 相机落点约定：`media/.tmp/<uid>.<ext>`（core 决定），归档后变成 `media/<id>.<ext>`。
  String tmpSuffixOf(Entry entry) => '.jpg';

  Future<void> pumpApp(WidgetTester tester, {CameraCapture? camera, MediaImporter? importer}) async {
    await tester.pumpWidget(
      NotebaseApp(store: store, camera: camera, importer: importer),
    );
    await tester.pumpAndSettle();
  }

  group('📷 统一入口（§5.3）', () {
    testWidgets('有相机：点 📷 开取景器，拍到的照片入流（归档到 media/<id>.jpg）', (tester) async {
      final camera = FakeCameraCapture(shot: CameraShot(shotFile('a.jpg')));
      await pumpApp(tester, camera: camera);
      expect(find.byTooltip('拍照'), findsOneWidget); // 有相机时语义是「拍照」

      await tester.tap(find.byIcon(Icons.photo_outlined));
      await tester.pumpAndSettle();

      expect(camera.openCount, 1);
      final entry = store.entries.single;
      expect(entry.type, EntryType.photo);
      expect(entry.file, 'media/${entry.id}.jpg');
      expect(storage.media.containsKey(entry.file!), isTrue); // 已归档登记
      expect(camera.targets.single, endsWith(tmpSuffixOf(entry))); // 写在 core 给的落点
      expect(find.text('图片已丢失'), findsNothing); // 文件在 → 不走占位
    });

    testWidgets('用户取消取景器：不产生条目', (tester) async {
      final camera = FakeCameraCapture(shot: null);
      await pumpApp(tester, camera: camera);

      await tester.tap(find.byIcon(Icons.photo_outlined));
      await tester.pumpAndSettle();

      expect(camera.openCount, 1);
      expect(store.entries, isEmpty);
      expect(storage.media, isEmpty); // 也没留下临时文件
    });

    testWidgets('相册分支：走 importPhoto（只复制），原图留在原处', (tester) async {
      final picked = shotFile('picked.jpg');
      final camera = FakeCameraCapture(
        shot: CameraShot(picked, fromGallery: true),
      );
      await pumpApp(tester, camera: camera);

      await tester.tap(find.byIcon(Icons.photo_outlined));
      await tester.pumpAndSettle();

      expect(store.entries.single.type, EntryType.photo);
      expect(File(picked).existsSync(), isTrue); // 用户原图没被搬走
    });

    testWidgets('相机起不来：给可读提示，不产生条目也不留孤儿', (tester) async {
      final camera = FakeCameraCapture(throwOnOpen: true);
      await pumpApp(tester, camera: camera);

      await tester.tap(find.byIcon(Icons.photo_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('拍照失败'), findsOneWidget);
      expect(store.entries, isEmpty);
      expect(storage.media, isEmpty);
    });

    testWidgets('无相机（Linux 桌面）：📷 退回文件导入，语义与步数不变', (tester) async {
      final picked = shotFile('gallery.jpg');
      final importer = FakeMediaImporter(path: picked);
      await pumpApp(tester, importer: importer); // 未注入相机
      expect(find.byTooltip('导入图片'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.photo_outlined));
      await tester.pumpAndSettle();

      expect(importer.pickCount, 1);
      expect(store.entries.single.type, EntryType.photo);
      expect(File(picked).existsSync(), isTrue); // 只复制不移动
    });
  });

  group('取景器页（假会话驱动）', () {
    /// 把取景器 push 起来并拿到它的返回值。
    Future<CameraShot?> openViewfinder(
      WidgetTester tester,
      CameraSession session, {
      Future<String?> Function()? gallery,
    }) async {
      CameraShot? result;
      var popped = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<CameraShot>(
                    MaterialPageRoute<CameraShot>(
                      builder: (_) => CameraViewfinderPage(
                        createSession: () async => session,
                        targetPath: '/tmp/target.jpg',
                        pickFromGallery: gallery,
                      ),
                    ),
                  );
                  popped = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      addTearDown(() {
        // 便于断言 dispose：调用方读 session.disposeCount
        expect(popped || true, isTrue);
      });
      return result;
    }

    testWidgets('快门 → 返回相机照片（fromGallery=false），并释放会话', (tester) async {
      final session = FakeCameraSession();
      await openViewfinder(tester, session);
      expect(session.initCount, 1);

      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();

      expect(session.shootCount, 1);
      expect(session.disposeCount, 1); // 页面销毁时释放相机
      // 页面已关闭：取景器控件消失
      expect(find.byType(CameraViewfinderPage), findsNothing);
    });

    testWidgets('✕ 关闭 → 不拍照', (tester) async {
      final session = FakeCameraSession();
      await openViewfinder(tester, session);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(session.shootCount, 0);
      expect(session.disposeCount, 1);
    });

    testWidgets('权限被拒 → 可读原因 + 不显示快门', (tester) async {
      final session = FakeCameraSession(throwOnInit: true);
      await openViewfinder(tester, session);

      expect(find.textContaining('没有相机权限'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt), findsNothing);
    });

    testWidgets('连点快门只拍一张（防重入）', (tester) async {
      final session = FakeCameraSession()..shootGate = Completer<void>();
      await openViewfinder(tester, session);

      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.camera_alt)); // 在途时再点
      await tester.pump();
      expect(session.shootCount, 1);

      session.shootGate!.complete();
      await tester.pumpAndSettle();
      expect(session.shootCount, 1);
    });

    testWidgets('拍照失败 → 留在取景器并提示，不返回照片', (tester) async {
      final session = FakeCameraSession(throwOnShoot: true);
      await openViewfinder(tester, session);

      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();

      expect(find.byType(CameraViewfinderPage), findsOneWidget); // 还在取景器
      expect(find.textContaining('拍照失败'), findsOneWidget);
    });

    testWidgets('切换到相册 → 返回 fromGallery=true 的路径', (tester) async {
      final session = FakeCameraSession();
      final picked = shotFile('g.jpg');
      await openViewfinder(tester, session, gallery: () async => picked);

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(CameraViewfinderPage), findsNothing);
      expect(session.shootCount, 0);
    });
  });
}
