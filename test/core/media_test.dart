import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notebase/core/model.dart';
import 'package:notebase/core/storage/json_storage.dart';
import 'package:notebase/core/store.dart';

import '../support/memory_storage.dart';

/// M6a：core 媒体层——媒体条目登记、文字层（转写/摘要）编辑、媒体文件落点约定。
/// core 不解读媒体内容，只负责「引用 + 落点 + 归属」。
void main() {
  group('媒体条目（内存存储）', () {
    test('新增照片/录音条目并持久化，归属当前笔记本', () async {
      final storage = MemoryStorage();
      final store = await AppStore.load(storage);

      final audio = await _recordAudio(store, storage, duration: 3.5);
      final photo = await _importPhoto(store, storage);

      expect(audio.type, EntryType.audio);
      expect(audio.file, 'media/${audio.id}.ogg'); // 文件名 = 条目 id
      expect(audio.duration, 3.5);
      expect(audio.notebookId, Notebook.defaultId);
      expect(photo.type, EntryType.photo);
      expect(photo.text, isNull);
      expect(photo.file, 'media/${photo.id}.png');

      final reloaded = await AppStore.load(storage);
      expect(reloaded.entries, hasLength(2));
      expect(reloaded.entries.last.file, photo.file); // 升序，最新在末尾
    });

    test('addMedia 拒绝文本类型', () async {
      final store = await AppStore.load(MemoryStorage());
      await expectLater(
        store.addMedia(
          type: EntryType.text,
          sourceRelativePath: 'media/.tmp/x.ogg',
          extension: 'ogg',
        ),
        throwsArgumentError,
      );
    });

    test('录音：转写与摘要可设可清（空 = 删除该字段）并持久化', () async {
      final storage = MemoryStorage();
      final store = await AppStore.load(storage);
      final entry = await _recordAudio(store, storage, duration: 2);

      await store.updateEntryTranscript(entry.id, '  跟师傅约了周三  ');
      await store.updateEntrySummary(entry.id, '装修');
      expect(store.entries.single.transcript, '跟师傅约了周三'); // trim 入库
      expect(store.entries.single.summary, '装修');

      await store.updateEntryTranscript(entry.id, '   '); // 清空
      expect(store.entries.single.transcript, isNull);

      final reloaded = await AppStore.load(storage);
      expect(reloaded.entries.single.transcript, isNull);
      expect(reloaded.entries.single.summary, '装修');
    });

    test('照片：只有摘要可编辑，转写仍可写但不显示（模型层不设限）', () async {
      final storage = MemoryStorage();
      final store = await AppStore.load(storage);
      final photo = await _importPhoto(store, storage);
      await store.updateEntrySummary(photo.id, '瓷砖型号');
      expect(store.entries.single.summary, '瓷砖型号');
    });

    test('搜索命中媒体：照片看摘要，录音看转写或摘要（§7 终态规则）', () async {
      final storage = MemoryStorage();
      final store = await AppStore.load(storage);
      final audio = await _recordAudio(store, storage);
      final photo = await _importPhoto(store, storage);
      await store.updateEntryTranscript(audio.id, '跟师傅约了周三上门');
      await store.updateEntrySummary(photo.id, '瓷砖型号确认');

      expect(store.search('周三').single.id, audio.id);
      expect(store.search('瓷砖').single.id, photo.id);
      expect(store.search('不存在的词'), isEmpty);
    });

    test('媒体条目也可编辑正文？不——updateEntryText 对媒体不适用但不会崩', () async {
      final storage = MemoryStorage();
      final store = await AppStore.load(storage);
      final photo = await _importPhoto(store, storage);
      // 模型允许写 text，但 UI 不会对媒体走这条路径；此处只保证不抛错。
      await store.updateEntryText(photo.id, '备注');
      expect(store.entries.single.text, '备注');
    });
  });

  group('媒体文件落点（真实文件系统）', () {
    late Directory dir;
    late JsonFileStorage storage;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('notebase_media_test');
      storage = JsonFileStorage(dir.path);
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('prepareMediaPath 创建父目录并返回绝对路径', () async {
      final path = await storage.prepareMediaPath('media/a1.ogg');
      expect(path, '${dir.path}/media/a1.ogg');
      expect(Directory('${dir.path}/media').existsSync(), isTrue);
    });

    test('deleteMedia 删除文件；不存在则忽略', () async {
      final path = await storage.prepareMediaPath('media/a1.ogg');
      await File(path).writeAsBytes([1, 2, 3]);
      await storage.deleteMedia('media/a1.ogg');
      expect(File(path).existsSync(), isFalse);

      await storage.deleteMedia('media/a1.ogg'); // 幂等
    });

    test('越界路径被拒绝（不接受绝对路径与 ..）', () async {
      await expectLater(
        storage.prepareMediaPath('/etc/passwd'),
        throwsArgumentError,
      );
      await expectLater(
        storage.prepareMediaPath('media/../../escape.ogg'),
        throwsArgumentError,
      );
    });

    test('临时文件归档为 media/<条目 id>.ogg；删除条目不删文件', () async {
      final store = await AppStore.load(storage);
      final temp = await store.prepareMediaTemp('ogg');
      await File(temp.absolutePath).writeAsBytes([1, 2, 3]);

      final entry = await store.addMedia(
        type: EntryType.audio,
        sourceRelativePath: temp.relativePath,
        extension: 'ogg',
        duration: 2,
      );

      final finalPath = '${dir.path}/${entry.file}';
      expect(File(temp.absolutePath).existsSync(), isFalse); // 临时文件已移走
      expect(File(finalPath).existsSync(), isTrue);

      final removed = await store.deleteEntry(entry.id);
      await store.restoreEntry(removed); // 撤销可用：文件还在

      expect(store.entries.single.file, entry.file);
      expect(File(finalPath).existsSync(), isTrue);
    });

    test('discardMedia 删除未登记的临时文件', () async {
      final store = await AppStore.load(storage);
      final temp = await store.prepareMediaTemp('ogg');
      await File(temp.absolutePath).writeAsBytes([1, 2, 3]);

      await store.discardMedia(temp.relativePath);
      expect(File(temp.absolutePath).existsSync(), isFalse);
      expect(store.entries, isEmpty);
    });
  });
}

/// 模拟一次录音：准备临时落点 → 写字节 → 归档为条目。
Future<Entry> _recordAudio(
  AppStore store,
  MemoryStorage storage, {
  double? duration,
}) async {
  final temp = await store.prepareMediaTemp('ogg');
  await storage.prepareMediaPath(temp.relativePath);
  return store.addMedia(
    type: EntryType.audio,
    sourceRelativePath: temp.relativePath,
    extension: 'ogg',
    duration: duration,
  );
}

/// 模拟一次图片导入。
Future<Entry> _importPhoto(AppStore store, MemoryStorage storage) async {
  final temp = await store.prepareMediaTemp('png');
  await storage.prepareMediaPath(temp.relativePath);
  return store.addMedia(
    type: EntryType.photo,
    sourceRelativePath: temp.relativePath,
    extension: 'png',
  );
}
