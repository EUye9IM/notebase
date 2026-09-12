import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/model.dart';
import '../core/store.dart';
import 'editor_sheet.dart';

/// 时间流（ui-design §4）：时间升序、最新在底、按天分组（今天 / 昨天 /
/// M月d日，跨年带年份）；打开、发送、切换笔记本后自动滚到底部。
class StreamView extends StatefulWidget {
  const StreamView({super.key, required this.store});

  final AppStore store;

  @override
  State<StreamView> createState() => _StreamViewState();
}

class _StreamViewState extends State<StreamView> {
  final _scroll = ScrollController();
  int _lastCount = -1;
  String _lastNotebookId = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.store.entries;
    final count = entries.length;
    final notebookId = widget.store.currentNotebookId;

    // 条目数或笔记本变化 → 帧渲染后滚到底部（主题等无关变更不触发）。
    if (count != _lastCount || notebookId != _lastNotebookId) {
      _lastCount = count;
      _lastNotebookId = notebookId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }

    if (entries.isEmpty) {
      return const Center(child: Text('⬇ 在下面记第一条'));
    }

    final rows = <Widget>[];
    DateTime? lastDay;
    for (final entry in entries) {
      final day = _calendarDay(entry.createdAt);
      if (lastDay == null || day != lastDay) {
        lastDay = day;
        rows.add(_DayHeader(date: entry.createdAt));
      }
      rows.add(EntryTile(store: widget.store, entry: entry));
    }

    return SingleChildScrollView(
      controller: _scroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          ...rows,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        dayLabel(date),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

enum EntryAction { copy, edit, delete }

/// 条目操作菜单（长按 / 右键的位置菜单，ui-design §8）。
Future<EntryAction?> showEntryMenu(BuildContext context, Offset position) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  return showMenu<EntryAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & (overlay?.size ?? Size.zero),
    ),
    items: const [
      PopupMenuItem(value: EntryAction.copy, child: Text('复制')),
      PopupMenuItem(value: EntryAction.edit, child: Text('编辑')),
      PopupMenuItem(value: EntryAction.delete, child: Text('删除')),
    ],
  );
}

/// 时间流与搜索结果共用的条目行（ui-design §4 / §8）。
///
/// 点按 = 编辑底 sheet；长按（触屏）/ 右键（桌面）= 复制 / 编辑 / 删除。
/// 删除走「确认 → toast + 5s 撤销」，撤销快照来自 store 层。
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.store, required this.entry});

  final AppStore store;
  final Entry entry;

  Offset _anchor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final action = await showEntryMenu(context, position);
    if (action == null || !context.mounted) return;
    switch (action) {
      case EntryAction.copy:
        await _copy(context);
      case EntryAction.edit:
        await showEntryEditor(context, store, entry);
      case EntryAction.delete:
        await _delete(context);
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: entry.text ?? ''));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDeleteEntryDialog(context);
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final removed = await store.deleteEntry(entry.id);
    messenger.showSnackBar(undoSnackBar(store, removed));
  }

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      onTap: () => showEntryEditor(context, store, entry),
      onLongPress: () => _showMenu(context, _anchor(context)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用 Text 而非 SelectableText：后者的选择手势会吞掉本行的
            // 点按（编辑）与长按（菜单），而「复制」已由菜单提供（§8）。
            Text(
              entry.text ?? '',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 2),
            Text(
              _timeLabel(entry.createdAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
    return GestureDetector(
      onSecondaryTapUp: (details) => _showMenu(context, details.globalPosition),
      child: row,
    );
  }
}

/// 自然日（UTC 零点）表示，仅用于分组比较与天数差：
/// 夏令时切换日只有 23 小时，用本地零点相减会被截断成 0 天，把「昨天」
/// 错标成「今天」；UTC 日不存在跳变，跨时区结果一致。
DateTime _calendarDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day);

/// 组头文案：今天 / 昨天 / M月d日（跨年带年份）。[now] 可注入以便测试。
String dayLabel(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = _calendarDay(current).difference(_calendarDay(date)).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (date.year == current.year) return '${date.month}月${date.day}日';
  return '${date.year}年${date.month}月${date.day}日';
}

String _timeLabel(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}
