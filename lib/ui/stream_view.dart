import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/model.dart';
import '../core/store.dart';
import 'editor_sheet.dart';

/// 时间流（ui-design §4）：时间升序、最新在底、按天分组（今天 / 昨天 /
/// M月d日，跨年带年份）；打开、发送、切换笔记本后自动滚到底部。
class StreamView extends StatefulWidget {
  const StreamView({super.key, required this.store, this.autoScroll = true});

  final AppStore store;

  /// 是否因「条目数变化」自动滚底。搜索态下由 HomePage 传 false：
  /// 此时时间流处于 offstage，若仍滚底会破坏「退出搜索恢复滚动位置」
  /// （ui-design §7）。笔记本切换始终滚底（§4），不受此开关影响。
  final bool autoScroll;

  @override
  State<StreamView> createState() => _StreamViewState();
}

class _StreamViewState extends State<StreamView> {
  final _scroll = ScrollController();
  int _lastCount = -1;
  String _lastNotebookId = '';

  /// 是否离底部超过一屏：决定「↓ 回到最新」按钮是否浮现（§4）。
  bool _farFromBottom = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  /// 是否离底超过一屏。用滚动位置**实时**判定，而不是只信缓存状态：
  /// 切到内容不足一屏的笔记本时，越界修正是静默的（correctPixels 不发通知），
  /// 缓存状态会停在 true，按钮就永远赖着且点不掉（M5 评审 P2-1）。
  bool get _isFarFromBottom {
    if (!_scroll.hasClients) return false;
    final position = _scroll.position;
    return position.maxScrollExtent - position.pixels >
        position.viewportDimension;
  }

  void _onScroll() {
    final far = _isFarFromBottom;
    if (far != _farFromBottom) setState(() => _farFromBottom = far);
  }

  /// 搜索态（offstage）下发生过新增：退出搜索后补一次滚底，
  /// 保证「发送后滚底」（§4）在退出搜索时兑现，而删除不打扰阅读位置。
  bool _pendingScroll = false;

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottomAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    _scroll
        .animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        )
        // 无像素变化时不会有滚动通知，主动重建一次让按钮按新位置收敛。
        .whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.store.entries;
    final count = entries.length;
    final notebookId = widget.store.currentNotebookId;

    // 滚底规则（§4 与 §7 的优先级）：
    // - 切换笔记本：始终滚底（§4）
    // - 可见时的条目变化：滚底（§4「发送后自动滚底」）
    // - 搜索态（offstage）：不立刻滚，保住退出搜索后的滚动位置（§7）；
    //   但「新增」排队一次，退出搜索后滚底，「删除」不排队。
    final notebookChanged = notebookId != _lastNotebookId;
    final countChanged = count != _lastCount;
    // 「新增」以长度增长判定：不能用「最新 id 变了」——删掉最新一条同样会
    // 改变末位 id，会把删除误判成新增，从而在退出搜索时错误地滚到底部。
    final added = count > _lastCount;
    _lastNotebookId = notebookId;
    _lastCount = count;

    if (notebookChanged) {
      _pendingScroll = false;
      _scrollToBottomAfterFrame();
    } else if (widget.autoScroll) {
      if (countChanged || _pendingScroll) {
        _pendingScroll = false;
        _scrollToBottomAfterFrame();
      }
    } else if (added) {
      _pendingScroll = true;
    }

    if (entries.isEmpty) {
      _farFromBottom = false; // 空态：无内容可滚，按钮必须消失
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

    final farFromBottom = _isFarFromBottom;
    _farFromBottom = farFromBottom; // 同步基线，供滚动监听器比较
    // 布局阶段的越界修正是静默的（不发滚动通知）：内容变短后按钮可能还停在
    // 上一帧的判定上。帧末补一次重算，让状态自动收敛（§4 / 评审 P2-1）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final far = _isFarFromBottom;
      if (far != _farFromBottom) setState(() => _farFromBottom = far);
    });

    return Stack(children: [
      SingleChildScrollView(
        controller: _scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            ...rows,
            const SizedBox(height: 8),
          ],
        ),
      ),
      // 上翻超过一屏时浮现（§4）；回到最新后自行消失。
      if (farFromBottom)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            tooltip: '回到最新',
            onPressed: _jumpToLatest,
            child: const Icon(Icons.arrow_downward),
          ),
        ),
    ]);
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
/// [canCopy] 为 false（无可复制文本，如尚无转写/摘要的媒体条目）时不显示「复制」。
Future<EntryAction?> showEntryMenu(
  BuildContext context,
  Offset position, {
  bool canCopy = true,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  return showMenu<EntryAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & (overlay?.size ?? Size.zero),
    ),
    items: [
      if (canCopy)
        const PopupMenuItem(value: EntryAction.copy, child: Text('复制')),
      const PopupMenuItem(value: EntryAction.edit, child: Text('编辑')),
      const PopupMenuItem(value: EntryAction.delete, child: Text('删除')),
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

  /// 可复制的文字面：文本条目取正文；媒体条目取转写/摘要
  /// （ui-design §7 的终态规则：照片=摘要，录音=转写+摘要）。
  String get _copyableText =>
      entry.text ?? entry.transcript ?? entry.summary ?? '';

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final action = await showEntryMenu(
      context,
      position,
      canCopy: _copyableText.isNotEmpty,
    );
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
    final text = _copyableText;
    if (text.isEmpty) return; // 无文本可复制，不误报「已复制」
    await Clipboard.setData(ClipboardData(text: text));
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
    if (!context.mounted) return;
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
            // 点按（编辑）与长按（菜单）；整条复制走上文菜单的「复制」（§8），
            // 代价是正文不能局部选中。
            // TODO(M6): 媒体条目按 §4 渲染（缩略图 / 播放行 + 摘要或转写首行兜底）。
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
