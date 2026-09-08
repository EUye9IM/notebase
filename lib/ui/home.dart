import 'package:flutter/material.dart';

import '../core/store.dart';
import 'input_bar.dart';
import 'settings_view.dart';
import 'stream_view.dart';

/// 应用壳（ui-design §3）：
/// 宽屏（≥720）= 侧栏 + 流头部 + 时间流 + 输入栏；
/// 窄屏 = 顶栏 + 时间流 + 输入栏。
///
/// 笔记本切换 / 新建 / 重命名 / 删除在 M3 接入，当前侧栏与顶栏仅展示。
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      if (wide) {
        return Scaffold(
          body: Row(children: [
            _Sidebar(store: store),
            const VerticalDivider(width: 1),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(children: [
                    _StreamHeader(store: store),
                    Expanded(child: StreamView(store: store)),
                    InputBar(store: store, wide: true),
                  ]),
                ),
              ),
            ),
          ]),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(store.currentNotebook.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '设置',
              onPressed: () => showSettingsSheet(context, store),
            ),
          ],
        ),
        body: Column(children: [
          Expanded(child: StreamView(store: store)),
          InputBar(store: store, wide: false),
        ]),
      );
    });
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final nb in store.notebooks)
                ListTile(
                  dense: true,
                  selected: nb.id == store.currentNotebookId,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  title: Text(
                    nb.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // M3：点按切换、长按重命名/删除，底部「＋ 新建」
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          dense: true,
          leading: const Icon(Icons.settings_outlined),
          title: const Text('设置'),
          onTap: () => showSettingsSheet(context, store),
        ),
      ]),
    );
  }
}

class _StreamHeader extends StatelessWidget {
  const _StreamHeader({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        store.currentNotebook.name,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
