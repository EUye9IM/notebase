import 'package:flutter/material.dart';

import '../core/model.dart';
import '../core/store.dart';

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
      final day = DateTime(
          entry.createdAt.year, entry.createdAt.month, entry.createdAt.day);
      if (lastDay == null || day != lastDay) {
        lastDay = day;
        rows.add(_DayHeader(date: entry.createdAt));
      }
      rows.add(_EntryRow(entry: entry));
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
        _dayLabel(date),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
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
    );
  }
}

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (d.year == now.year) return '${d.month}月${d.day}日';
  return '${d.year}年${d.month}月${d.day}日';
}

String _timeLabel(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}
