import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/model.dart';
import '../core/store.dart';
import 'editor_sheet.dart';
import 'media_player.dart';
import 'photo_view.dart';

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
      return const Center(child: Text('⬇ 在下面记第一条，或点 🎤 / 📷'));
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

enum EntryAction { copy, editText, editTranscript, editSummary, delete }

String _actionLabel(EntryAction action) => switch (action) {
      EntryAction.copy => '复制',
      EntryAction.editText => '编辑',
      EntryAction.editTranscript => '编辑转写',
      EntryAction.editSummary => '编辑摘要',
      EntryAction.delete => '删除',
    };

/// 条目操作菜单（长按 / 右键的位置菜单）：**按类型给不同项**（ui-design §8）
/// —— 文本=复制/编辑/删除；录音=复制/编辑转写/编辑摘要/删除；
/// 照片=复制/编辑摘要/删除。
Future<EntryAction?> showEntryMenu(
  BuildContext context,
  Offset position,
  List<EntryAction> actions,
) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  return showMenu<EntryAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & (overlay?.size ?? Size.zero),
    ),
    items: [
      for (final action in actions)
        PopupMenuItem(value: action, child: Text(_actionLabel(action))),
    ],
  );
}

/// 时间流与搜索结果共用的条目行（ui-design §4 / §8）。
///
/// 按类型渲染：文本=正文；音频=播放行（时长/进度）+ 文字面；照片=缩略图。
/// 点按：文本=编辑底 sheet，音频=内联播放/暂停（§8），照片=查看器（M6d）。
/// 长按（触屏）/ 右键（桌面）= 复制 / 编辑转写与摘要 / 删除。
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

  /// §8 的菜单项：按类型给不同动作。
  List<EntryAction> get _menuActions => [
        if (_copyableText.isNotEmpty) EntryAction.copy,
        ...switch (entry.type) {
          EntryType.text => const [EntryAction.editText],
          EntryType.audio => const [
              EntryAction.editTranscript,
              EntryAction.editSummary,
            ],
          EntryType.photo => const [EntryAction.editSummary],
        },
        EntryAction.delete,
      ];

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final action = await showEntryMenu(context, position, _menuActions);
    if (action == null || !context.mounted) return;
    switch (action) {
      case EntryAction.copy:
        await _copy(context);
      case EntryAction.editText:
        await showEntryEditor(context, store, entry);
      case EntryAction.editTranscript:
        await _editTranscript(context);
      case EntryAction.editSummary:
        await _editSummary(context);
      case EntryAction.delete:
        await _delete(context);
    }
  }

  Future<void> _editTranscript(BuildContext context) => showFieldEditor(
        context,
        title: '编辑转写',
        initial: entry.transcript,
        hint: '录音的完整文字（留空即删除）',
        onSave: (value) => store.updateEntryTranscript(entry.id, value),
      );

  Future<void> _editSummary(BuildContext context) => showFieldEditor(
        context,
        title: '编辑摘要',
        initial: entry.summary,
        hint: '这条记录的一句话摘要（留空即删除）',
        onSave: (value) => store.updateEntrySummary(entry.id, value),
      );

  /// 摘要位点按即编辑（§8）：显示什么就编辑什么——摘要优先，兜底的转写首行编辑转写。
  Future<void> _editCaption(BuildContext context) async {
    final hasSummary = (entry.summary?.trim().isNotEmpty ?? false);
    if (hasSummary || entry.type == EntryType.photo) {
      await _editSummary(context);
    } else {
      await _editTranscript(context);
    }
  }

  /// 媒体条目的文字面：摘要优先；**录音**在无摘要时用转写首行兜底（§4）。
  /// 照片只认摘要——转写是录音的概念，照片即便被写入转写也不显示。
  String? get _caption {
    final summary = entry.summary?.trim();
    if (summary != null && summary.isNotEmpty) return summary;
    if (entry.type != EntryType.audio) return null;
    final transcript = entry.transcript?.trim();
    if (transcript != null && transcript.isNotEmpty) {
      return transcript.split('\n').first;
    }
    return null;
  }

  /// 摘要位显示的是**转写兜底**（录音无摘要 → 转写首行）。§4 要求它截断：
  /// 转写可能很长且不含换行，不截断就会把整段铺进流里，违背「转写全文不进
  /// 时间流」的用意。摘要本身不截断——那是用户写的展示面，按正文样式整段渲染。
  bool get _captionIsTranscriptFallback {
    final summary = entry.summary?.trim();
    return (summary == null || summary.isEmpty) &&
        entry.type == EntryType.audio &&
        (entry.transcript?.trim().isNotEmpty ?? false);
  }

  void _handleTap(BuildContext context) {
    switch (entry.type) {
      case EntryType.text:
        showEntryEditor(context, store, entry);
      case EntryType.audio:
        // §8：音频条目的点按 = 列表内联播放/暂停。
        // 不可播放时（未注入播放能力 / 文件已丢失）不能 toggle：否则会把行
        // 标成「播放中」而其实毫无声音，进度定时器还空转（评审 P3-1）。
        // 「文件已丢失」要真的查文件——只看 `file != null` 会让缺失的录音
        // 渲染成可播放、点下去静默失败（§10，复检 P2）。
        final playback = PlaybackScope.read(context);
        if (playback != null && playback.available && _audioFileExists) {
          playback.toggle(entry);
        }
      case EntryType.photo:
        final file = entry.file;
        if (file != null) {
          showPhotoViewer(context, store: store, relativePath: file);
        }

    }
  }

  /// 录音文件是否真的在：§10 要求媒体缺失时音频行渲染为**不可播放**。
  /// 只在用户点按（手势路径）与 State 初始化时做检查，不在每帧 build 里做。
  bool get _audioFileExists {
    final file = entry.file;
    return file != null && store.mediaExists(file);
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
    // 正在播放的条目被删：先停播，避免进度定时器空转（M6 评审 P3-1）
    await PlaybackScope.read(context)?.stopIfPlaying(entry.id);
    try {
      await store.deleteEntry(entry.id);
    } on Object catch (error) {
      // 只有失败才提示：删除没落盘时 store 侧已回滚（条目还在），说一声才不会
      // 让人以为删掉了（复检 P2）。成功不打扰（v1.1 起不再有撤销条）。
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final caption = _caption;
    final theme = Theme.of(context);
    final row = InkWell(
      onTap: () => _handleTap(context),
      onLongPress: () => _showMenu(context, _anchor(context)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用 Text 而非 SelectableText：后者的选择手势会吞掉本行的
            // 点按（编辑/播放）与长按（菜单）；整条复制走菜单的「复制」（§8），
            // 代价是正文不能局部选中。
            switch (entry.type) {
              EntryType.text => Text(
                  entry.text ?? '',
                  style: theme.textTheme.bodyLarge,
                ),
              EntryType.audio => _AudioRow(store: store, entry: entry),
              EntryType.photo => _PhotoRow(store: store, entry: entry),
            },
            if (caption != null) ...[
              const SizedBox(height: 4),
              GestureDetector(
                // §8：摘要位显示的文本点按即编辑（显示什么就编辑什么）
                onTap: () => _editCaption(context),
                child: Text(
                  caption,
                  // 转写兜底要截断（§4）；摘要按正文样式整段渲染。
                  maxLines: _captionIsTranscriptFallback ? 2 : null,
                  overflow: _captionIsTranscriptFallback
                      ? TextOverflow.ellipsis
                      : null,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              _timeLabel(entry.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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

/// 音频行（ui-design §4）：`[▶/⏸] 时长 进度条`，播放中显示进度。
/// 媒体文件缺失时渲染为**不可播放**（§10）：图标走次要色、点按无反应，
/// 而不是让用户点了才发现没声音。
class _AudioRow extends StatefulWidget {
  const _AudioRow({required this.store, required this.entry});

  final AppStore store;
  final Entry entry;

  @override
  State<_AudioRow> createState() => _AudioRowState();
}

class _AudioRowState extends State<_AudioRow> {
  static String _durationLabel(double? seconds) {
    if (seconds == null) return '--:--';
    final d = Duration(milliseconds: (seconds * 1000).round());
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  /// 存在性检查缓存在 State 里（同 PhotoThumbnail，评审 P3-8）：时间流没有
  /// 虚拟化，放在 build 里会让每次 store 通知都对所有音频行做一遍同步检查。
  late bool _exists = _checkExists();

  bool _checkExists() {
    final file = widget.entry.file;
    return file != null && widget.store.mediaExists(file);
  }

  @override
  void didUpdateWidget(_AudioRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.file != widget.entry.file) _exists = _checkExists();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    // 依赖 PlaybackScope：只有音频行会随播放进度重建（文本行不依赖）。
    final playback = PlaybackScope.maybeOf(context);
    final playing = playback?.isPlaying(entry.id) ?? false;
    final progress = playback?.progressFor(entry) ?? 0;
    final colors = Theme.of(context).colorScheme;
    final playable = playback != null && playback.available && _exists;

    return Row(children: [
      Icon(
        playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
        size: 32,
        color: playable ? colors.primary : colors.outlineVariant,
      ),
      const SizedBox(width: 8),
      Text(
        _durationLabel(entry.duration),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          minHeight: 4,
          backgroundColor: colors.surfaceContainerHighest,
        ),
      ),
    ]);
  }
}

/// 照片行（ui-design §4）：等比缩略图（约列宽 60%），点按进全屏查看器（§8）。
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.store, required this.entry});

  final AppStore store;
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final file = entry.file;
    if (file == null) {
      return Row(children: [
        Icon(Icons.image_not_supported_outlined,
            size: 32, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 8),
        Text('图片已丢失', style: Theme.of(context).textTheme.labelMedium),
      ]);
    }
    return PhotoThumbnail(store: store, relativePath: file);
  }
}
