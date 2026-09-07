import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notebase/store.dart';

Future<NoteStore> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  return NoteStore.load();
}

void main() {
  group('NoteStore', () {
    test('create 后出现在列表顶部，并持久化', () async {
      final store = await freshStore();
      final note = store.create();
      store.update(note, title: '第一条', content: '内容');

      expect(store.notes.single.id, note.id);

      // 重新加载验证持久化。
      final reloaded = await NoteStore.load();
      expect(reloaded.notes.single.title, '第一条');
      expect(reloaded.notes.single.content, '内容');
    });

    test('update 修改字段并刷新排序', () async {
      final store = await freshStore();
      final a = store.create();
      final b = store.create();
      store.update(a, title: '旧的被更新');

      expect(store.notes.first.id, a.id);
      expect(store.notes.last.id, b.id);
    });

    test('delete 移除并持久化', () async {
      final store = await freshStore();
      final note = store.create();
      store.update(note, content: '待删除');
      store.delete(note);

      expect(store.notes, isEmpty);
      final reloaded = await NoteStore.load();
      expect(reloaded.notes, isEmpty);
    });

    test('search 匹配标题与内容，忽略大小写', () async {
      final store = await freshStore();
      store.update(store.create(), title: 'Shopping List', content: '牛奶');
      store.update(store.create(), title: '日记', content: '今天去购物');
      store.update(store.create(), title: '无关', content: 'nothing');

      expect(store.search('shopping'), hasLength(1));
      expect(store.search('购物'), hasLength(1));
      expect(store.search('不存在'), isEmpty);
      expect(store.search('  '), hasLength(3));
    });

    test('displayTitle 回退：标题空时取内容首行', () async {
      final store = await freshStore();
      final note = store.create();
      store.update(note, content: '首行内容\n第二行');
      expect(note.displayTitle, '首行内容');

      store.update(note, content: '');
      expect(note.displayTitle, '（无标题）');
    });

    test('themeMode 默认跟随系统，可切换并持久化', () async {
      final store = await freshStore();
      expect(store.themeMode, ThemeMode.system);

      store.setThemeMode(ThemeMode.dark);
      final reloaded = await NoteStore.load();
      expect(reloaded.themeMode, ThemeMode.dark);
    });
  });
}
