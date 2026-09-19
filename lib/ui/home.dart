import 'dart:async';

import 'package:flutter/material.dart';

import '../core/store.dart';
import 'input_bar.dart';
import 'media_importer.dart';
import 'media_player.dart';
import 'media_recorder.dart';
import 'notebook_list.dart';
import 'recording_session.dart';
import 'search_view.dart';
import 'settings_view.dart';
import 'startup_views.dart';
import 'stream_view.dart';

/// 应用壳（ui-design §3）：
/// 宽屏（≥720）= 侧栏 + 流头部 + 时间流 + 输入栏；
/// 窄屏 = 顶栏 + 时间流 + 输入栏。
///
/// 搜索（§7）为原地模式：顶栏 / 流头部切换成输入行，下方内容区替换为结果，
/// 退出后恢复原流与滚动位置（靠 IndexedStack 保活时间流实现）。
/// 笔记本管理（§6）见 notebook_list.dart。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    this.startupNotice,
    this.recorder,
    this.importer,
    this.playback,
  });

  final AppStore store;

  /// 录音能力，透传给输入栏（§5.2）。
  final MediaRecorder? recorder;

  /// 图片导入能力，透传给输入栏（§5.3）。
  final MediaImporter? importer;

  /// 播放编排：切笔记本时停播，避免「声音继续但当前本没有任何播放控件」。
  final PlaybackController? playback;

  /// 启动期提示（数据损坏等），显示为可关闭的提示条（ui-design §10）。
  final String? startupNotice;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _inputFocus = FocusNode();

  /// 草稿由页面持有：宽/窄布局各自构造 InputBar，State 会重建，
  /// 草稿放 State 里会在拖动窗口跨 720 时丢失（§10 / M5 评审 P3-1）。
  final _drafts = DraftStore();

  /// 跨 720 布局重建时**保住子树自己的 State**（M6 后复检 P2）：宽/窄是两套
  /// 不同的祖先链，同一个 GlobalKey 会让 Flutter 把元素搬过去而不是重建——
  /// 输入栏的发送/导入守卫与输入框内容、时间流的滚动位置与「已见基线」都在
  /// State 里，重建就会丢：前者导致同一条文本重复入库、草稿残留，后者导致
  /// 每次跨越宽窄都强制滚底（§4 只把「打开/发送/切本」列为滚底触发）。
  final _inputBarKey = GlobalKey();
  final _streamKey = GlobalKey();

  /// 录音会话由页面持有：实现是「InputBar 的 State 在宽窄布局切换时被销毁」
  /// 这条坑的根治（M6 评审 P1-1）——录音中拖窗口不再丢录音条、不再占用麦克风。
  late final RecordingSession _recording;

  bool _searching = false;
  bool _noticeDismissed = false;

  /// 宽窄布局由 build 判定；退出搜索时用它决定是否把焦点交还输入栏。
  bool _wide = true;

  String? _lastNotebookId;

  @override
  void initState() {
    super.initState();
    _recording = RecordingSession(
      store: widget.store,
      recorder: widget.recorder,
    );
    _lastNotebookId = widget.store.currentNotebookId;
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.store.currentNotebookId;
    if (_lastNotebookId != null && _lastNotebookId != id) {
      // 切本即停播：否则声音继续，而新本的列表里没有任何播放控件可停（评审 P3-2）。
      // 必须延到帧后：stopAll 会同步 notifyListeners，而 didUpdateWidget 处在
      // build 阶段，同步通知会把其它元素标脏（!_dirty 断言）。
      final playback = widget.playback;
      if (playback != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(playback.stopAll());
        });
      }
    }
    _lastNotebookId = id;
  }

  @override
  void dispose() {
    // 收尾：释放麦克风、清掉临时文件；已录够 1s 的内容尽力保住。
    // shutdown 是异步的，收尾完成后才 dispose（否则通知会打到已销毁的 notifier）。
    unawaited(_recording.shutdown().whenComplete(_recording.dispose));
    _searchController.dispose();
    _searchFocus.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _startSearch() {
    _searchController.clear();
    setState(() => _searching = true);
    // 主动聚焦：宽屏下输入栏启动即 autofocus 并持有 primary focus，
    // 搜索框的 autofocus 不会生效，键输入会落进输入栏（评审 P1）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  /// 退出搜索：清空关键词，恢复时间流（滚动位置由 IndexedStack 保活）；
  /// 宽屏把焦点交还输入栏，接回「打开即可打字」的节奏（§5.1）。
  void _exitSearch() {
    _searchFocus.unfocus();
    _searchController.clear();
    setState(() => _searching = false);
    if (_wide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
  }

  /// 启动期提示条（可关闭）。
  Widget get _notice {
    final message = widget.startupNotice;
    if (message == null || _noticeDismissed) return const SizedBox.shrink();
    return StartupNotice(
      message: message,
      onDismiss: () => setState(() => _noticeDismissed = true),
    );
  }

  void _clearQuery() {
    _searchController.clear();
    setState(() {});
  }

  Widget get _content => IndexedStack(
        index: _searching ? 1 : 0,
        children: [
          StreamView(
            key: _streamKey, // 跨 720 搬家而不是重建：滚动位置与基线都要留
            store: widget.store,
            autoScroll: !_searching,
          ),
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
            focusNode: _searchFocus,
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
      _wide = wide; // 供退出搜索后决定焦点去向
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
                    _notice,
                    Expanded(child: _content),
                    InputBar(
                      key: _inputBarKey, // 跨 720 搬家：守卫与输入框内容都要留
                      store: widget.store,
                      wide: true,
                      focusNode: _inputFocus,
                      drafts: _drafts,
                      session: _recording,
                      importer: widget.importer,
                    ),
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
                  focusNode: _searchFocus,
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
          _notice,
          Expanded(child: _content),
          InputBar(
            key: _inputBarKey, // 跨 720 搬家：守卫与输入框内容都要留
            store: widget.store,
            wide: false,
            drafts: _drafts,
            session: _recording,
            importer: widget.importer,
          ),
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
