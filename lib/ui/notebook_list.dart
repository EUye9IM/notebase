import 'package:flutter/material.dart';

import '../core/model.dart';
import '../core/store.dart';
import 'listenable_bridge.dart';

/// 窄屏：点顶栏笔记本名弹出的切换弹层（ui-design §6）。
Future<void> showNotebookSwitcher(BuildContext context, AppStore store) {
  final bridge = CoreListenableBridge(store);
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => ListenableBuilder(
      listenable: bridge,
      builder: (context, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('笔记本'),
            ),
            Flexible(
              child: NotebookRows(
                store: store,
                onDone: () => Navigator.pop(sheetContext),
              ),
            ),
            const Divider(height: 1),
            NewNotebookRow(
              store: store,
              onDone: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    ),
  ).whenComplete(bridge.dispose);
}

/// 笔记本行列表：点按切换（宽屏 1 步 / 窄屏弹层内 1 步），
/// 长按（触屏）或右键（桌面）弹出「重命名 / 删除」。default 不提供管理菜单。
class NotebookRows extends StatelessWidget {
  const NotebookRows({super.key, required this.store, this.onDone});

  final AppStore store;

  /// 切换 / 删除后的回调，窄屏弹层用于关闭自己。
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(8),
      children: [
        for (final notebook in store.notebooks)
          _NotebookTile(store: store, notebook: notebook, onDone: onDone),
      ],
    );
  }
}

class _NotebookTile extends StatelessWidget {
  const _NotebookTile({
    required this.store,
    required this.notebook,
    this.onDone,
  });

  final AppStore store;
  final Notebook notebook;
  final VoidCallback? onDone;

  bool get _manageable => notebook.id != Notebook.defaultId;

  Future<void> _switch() async {
    if (notebook.id != store.currentNotebookId) {
      await store.switchNotebook(notebook.id);
    }
    onDone?.call();
  }

  /// 长按（触屏）/ 右键（桌面）菜单锚点。
  Offset _anchor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final action = await showNotebookMenu(context, position);
    if (action == null || !context.mounted) return;
    switch (action) {
      case NotebookAction.rename:
        await _rename(context);
      case NotebookAction.delete:
        await _delete(context);
    }
  }

  Future<void> _rename(BuildContext context) async {
    final name = await showNotebookNameDialog(
      context,
      title: '重命名笔记本',
      initial: notebook.name,
      confirmLabel: '保存',
    );
    if (name == null || !context.mounted) return;
    await store.renameNotebook(notebook.id, name);
  }

  Future<void> _delete(BuildContext context) async {
    final count = await store.entryCountOf(notebook.id);
    if (!context.mounted) return;
    final confirmed = await showDeleteNotebookDialog(
      context,
      notebook: notebook,
      entryCount: count,
    );
    if (confirmed != true || !context.mounted) return;
    await store.deleteNotebook(notebook.id);
    onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      dense: true,
      selected: notebook.id == store.currentNotebookId,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(notebook.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: _switch,
      onLongPress: _manageable ? () => _showMenu(context, _anchor(context)) : null,
    );
    if (!_manageable) return tile;
    return GestureDetector(
      onSecondaryTapUp: (details) => _showMenu(context, details.globalPosition),
      child: tile,
    );
  }
}

/// 「＋ 新建笔记本」行（ui-design §6：列表底部固定）。
class NewNotebookRow extends StatelessWidget {
  const NewNotebookRow({super.key, required this.store, this.onDone});

  final AppStore store;
  final VoidCallback? onDone;

  Future<void> _create(BuildContext context) async {
    final name = await showNotebookNameDialog(context, title: '新建笔记本');
    if (name == null || !context.mounted) return;
    await store.createNotebook(name); // 建完即切换为当前笔记本
    onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.add),
      title: const Text('新建笔记本'),
      onTap: () => _create(context),
    );
  }
}

enum NotebookAction { rename, delete }

/// 桌面右键 / 触屏长按的位置菜单。
Future<NotebookAction?> showNotebookMenu(
    BuildContext context, Offset position) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final action = await showMenu<NotebookAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & (overlay?.size ?? Size.zero),
    ),
    items: const [
      PopupMenuItem(value: NotebookAction.rename, child: Text('重命名')),
      PopupMenuItem(value: NotebookAction.delete, child: Text('删除')),
    ],
  );
  return action;
}

/// 新建 / 重命名的单字段对话框；返回 trim 后的名称，取消返回 null。
Future<String?> showNotebookNameDialog(
  BuildContext context, {
  required String title,
  String? initial,
  String confirmLabel = '创建',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: title,
        initial: initial ?? '',
        confirmLabel: confirmLabel,
      ),
    );

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '名称不能为空');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: '名称', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// 删除确认；文案说明非空笔记本的条目去向（ui-design §6：条目永不陪葬）。
Future<bool?> showDeleteNotebookDialog(
  BuildContext context, {
  required Notebook notebook,
  required int entryCount,
}) =>
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除笔记本「${notebook.name}」？'),
        content: Text(
          entryCount == 0 ? '该笔记本没有记录。' : '其中 $entryCount 条记录将移入 default。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
