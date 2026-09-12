import 'package:flutter/material.dart';

import '../core/store.dart';
import 'input_bar.dart';
import 'notebook_list.dart';
import 'search_view.dart';
import 'settings_view.dart';
import 'stream_view.dart';

/// 应用壳（ui-design §3）：
/// 宽屏（≥720）= 侧栏 + 流头部 + 时间流 + 输入栏；
/// 窄屏 = 顶栏 + 时间流 + 输入栏。
///
/// 搜索（§7）为原地模式：顶栏 / 流头部切换成输入行，下方内容区替换为结果，
/// 退出后恢复原流与滚动位置（靠 IndexedStack 保活时间流实现）。
/// 笔记本管理（§6）见 notebook_list.dart。
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final AppStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _startSearch() {
    _searchController.clear();
    setState(() => _searching = true);
  }

  /// 退出搜索：清空关键词，恢复时间流（滚动位置由 IndexedStack 保活）。
  void _exitSearch() {
    _searchController.clear();
    setState(() => _searching = false);
  }

  void _clearQuery() {
    _searchController.clear();
    setState(() {});
  }

  Widget get _content => IndexedStack(
        index: _searching ? 1 : 0,
        children: [
          StreamView(store: widget.store),
          SearchResults(
            store: widget.store,
            query: _searchController.text,
            onClear: _clearQuery,
          ),
        ],
      );

  Widget _searchRow(BuildContext context) => Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '退出搜索',
          onPressed: _exitSearch,
        ),
        Expanded(
          child: SearchField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            onExit: _exitSearch,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: '清空',
          onPressed: _searchController.text.isEmpty ? null : _clearQuery,
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      if (wide) {
        return Scaffold(
          body: Row(children: [
            _Sidebar(store: widget.store),
            const VerticalDivider(width: 1),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(children: [
                    _searching
                        ? _searchRow(context)
                        : _StreamHeader(
                            store: widget.store,
                            onSearch: _startSearch,
                          ),
                    Expanded(child: _content),
                    InputBar(store: widget.store, wide: true),
                  ]),
                ),
              ),
            ),
          ]),
        );
      }
      return Scaffold(
        appBar: _searching
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '退出搜索',
                  onPressed: _exitSearch,
                ),
                title: SearchField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  onExit: _exitSearch,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '清空',
                    onPressed: _searchController.text.isEmpty
                        ? null
                        : _clearQuery,
                  ),
                ],
              )
            : AppBar(
                title: InkWell(
                  onTap: () =>
                      showNotebookSwitcher(context, widget.store),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.store.currentNotebook.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: '搜索',
                    onPressed: _startSearch,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: '设置',
                    onPressed: () => showSettingsSheet(context, widget.store),
                  ),
                ],
              ),
        body: Column(children: [
          Expanded(child: _content),
          InputBar(store: widget.store, wide: false),
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
        Expanded(child: NotebookRows(store: store)),
        const Divider(height: 1),
        NewNotebookRow(store: store),
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
  const _StreamHeader({required this.store, required this.onSearch});

  final AppStore store;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(children: [
        Expanded(
          child: Text(
            store.currentNotebook.name,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: '搜索',
          onPressed: onSearch,
        ),
      ]),
    );
  }
}
