import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';
import 'stream_view.dart';

/// 搜索模式的输入框（ui-design §7）：窄屏放顶栏、宽屏放流头部；
/// 桌面按 Esc 退出搜索。
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onExit,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onExit?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '搜索当前笔记本…',
          border: InputBorder.none,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// 搜索结果区：原地替换时间流（不新开页面，ui-design §7）。
/// 结果按时间倒序（core 的 `search` 已保证），渲染与时间流条目一致。
class SearchResults extends StatelessWidget {
  const SearchResults({
    super.key,
    required this.store,
    required this.query,
    required this.onClear,
  });

  final AppStore store;
  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) {
      return const Center(child: Text('输入关键词，仅搜索当前笔记本'));
    }
    final hits = store.search(query);
    if (hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('“$q”没有匹配'),
            const SizedBox(height: 8),
            TextButton(onPressed: onClear, child: const Text('清空')),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '${hits.length} 条结果',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: hits.length,
            itemBuilder: (context, i) =>
                EntryTile(store: store, entry: hits[i]),
          ),
        ),
      ],
    );
  }
}
