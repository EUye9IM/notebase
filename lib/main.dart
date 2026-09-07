import 'package:flutter/material.dart';

import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await NoteStore.load();
  runApp(NotebaseApp(store: store));
}

class NotebaseApp extends StatelessWidget {
  const NotebaseApp({super.key, required this.store});

  final NoteStore store;

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
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'Notebase',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: store.themeMode,
        home: HomePage(store: store),
      ),
    );
  }
}

/// 应用壳：宽屏（>=720）左侧 NavigationRail，窄屏底部 NavigationBar，
/// 三个主页面用 IndexedStack 保活切换；编辑器一律 Navigator.push。
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final NoteStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.notes_outlined, selectedIcon: Icons.notes, label: '笔记'),
    (icon: Icons.search_outlined, selectedIcon: Icons.search, label: '搜索'),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '设置'),
  ];

  void _openEditor([Note? note]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorPage(store: widget.store, note: note),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: _index,
      children: [
        NotesListPage(store: widget.store, onOpen: _openEditor),
        SearchPage(store: widget.store, onOpen: _openEditor),
        SettingsPage(store: widget.store),
      ],
    );

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 720) {
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ]),
        );
      }
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    });
  }
}

class NotesListPage extends StatelessWidget {
  const NotesListPage({super.key, required this.store, required this.onOpen});

  final NoteStore store;
  final void Function([Note? note]) onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('笔记')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final notes = store.notes;
          if (notes.isEmpty) {
            return const Center(child: Text('还没有笔记，点右下角新建一条'));
          }
          return ListView.separated(
            itemCount: notes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => NoteTile(
              note: notes[i],
              onTap: () => onOpen(notes[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: onOpen,
        tooltip: '新建笔记',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class NoteTile extends StatelessWidget {
  const NoteTile({super.key, required this.note, this.subtitle, this.onTap});

  final Note note;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title:
          Text(note.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle ?? _formatTime(note.updatedAt),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.store, this.note});

  final NoteStore store;
  final Note? note;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final Note _note;
  late final TextEditingController _title;
  late final TextEditingController _content;

  @override
  void initState() {
    super.initState();
    _note = widget.note ?? widget.store.create();
    _title = TextEditingController(text: _note.title);
    _content = TextEditingController(text: _note.content);
  }

  @override
  void dispose() {
    // 退出时清掉从未写过内容的空笔记。
    if (_note.title.trim().isEmpty && _note.content.trim().isEmpty) {
      widget.store.delete(_note);
    }
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条笔记？'),
        content: Text(_note.displayTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.store.delete(_note);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: _delete,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              hintText: '标题',
              border: InputBorder.none,
            ),
            style: Theme.of(context).textTheme.titleLarge,
            onChanged: (v) => widget.store.update(_note, title: v),
          ),
          const Divider(height: 1),
          Expanded(
            child: TextField(
              controller: _content,
              decoration: const InputDecoration(
                hintText: '开始记录…',
                border: InputBorder.none,
              ),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              onChanged: (v) => widget.store.update(_note, content: v),
            ),
          ),
        ]),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.store, required this.onOpen});

  final NoteStore store;
  final void Function([Note? note]) onOpen;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索标题或内容…',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          if (_query.trim().isEmpty) {
            return const Center(child: Text('输入关键词开始搜索'));
          }
          final results = widget.store.search(_query);
          if (results.isEmpty) {
            return const Center(child: Text('没有匹配的笔记'));
          }
          return ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final note = results[i];
              return NoteTile(
                note: note,
                subtitle: _snippet(note),
                onTap: () => widget.onOpen(note),
              );
            },
          );
        },
      ),
    );
  }

  /// 命中内容时截取关键词附近片段，未命中内容时回退到时间。
  String _snippet(Note note) {
    final q = _query.trim().toLowerCase();
    final at = note.content.toLowerCase().indexOf(q);
    if (at < 0) return _formatTime(note.updatedAt);
    final start = at > 12 ? at - 12 : 0;
    final end = (at + q.length + 24).clamp(0, note.content.length);
    return note.content.substring(start, end).replaceAll('\n', ' ');
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});

  final NoteStore store;

  static const _themeOptions = [
    (ThemeMode.system, '跟随系统'),
    (ThemeMode.light, '浅色'),
    (ThemeMode.dark, '深色'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => RadioGroup<ThemeMode>(
          groupValue: store.themeMode,
          onChanged: (v) => store.setThemeMode(v!),
          child: ListView(children: [
            for (final (mode, label) in _themeOptions)
              RadioListTile<ThemeMode>(title: Text(label), value: mode),
          ]),
        ),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
