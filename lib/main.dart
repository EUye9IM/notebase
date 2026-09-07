import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/model.dart';
import 'core/store.dart';
import 'core/storage/json_storage.dart';
import 'ui/listenable_bridge.dart';

/// M1 冒烟壳：只验证 core 层端到端（加载 / 持久化 / 通知 / 主题偏好），
/// 完整的应用壳（时间流 / 输入栏 / 搜索 / 笔记本管理）在 M2 重建。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final store = await AppStore.load(JsonFileStorage(dir.path));
  runApp(SmokeApp(store: store));
}

class SmokeApp extends StatefulWidget {
  const SmokeApp({super.key, required this.store});

  final AppStore store;

  @override
  State<SmokeApp> createState() => _SmokeAppState();
}

class _SmokeAppState extends State<SmokeApp> {
  late final CoreListenableBridge _bridge;

  @override
  void initState() {
    super.initState();
    _bridge = CoreListenableBridge(widget.store);
  }

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _bridge,
      builder: (context, _) => MaterialApp(
        title: 'Notebase',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: switch (widget.store.theme) {
          ThemeSetting.system => ThemeMode.system,
          ThemeSetting.light => ThemeMode.light,
          ThemeSetting.dark => ThemeMode.dark,
        },
        home: SmokeHome(store: widget.store),
      ),
    );
  }
}

class SmokeHome extends StatelessWidget {
  const SmokeHome({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final entries = store.entries.reversed.toList(); // 冒烟壳倒序，最新在前
    return Scaffold(
      appBar: AppBar(title: const Text('Notebase · M1 冒烟')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '当前笔记本：${store.currentNotebook.name} · ${store.entries.length} 条 · 主题 ${store.theme.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final nb in store.notebooks)
            ListTile(
              dense: true,
              leading: const Icon(Icons.book_outlined),
              title: Text(nb.name),
              trailing: nb.id == store.currentNotebookId
                  ? const Text('当前')
                  : null,
              onTap: () => store.switchNotebook(nb.id),
            ),
          const Divider(),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('（空）M2 起提供录入'),
            )
          else
            for (final e in entries)
              ListTile(
                dense: true,
                title: Text(e.text ?? '[${e.type.name}]',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(_fmt(e.createdAt)),
              ),
        ],
      ),
    );
  }
}

String _fmt(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
