import 'package:flutter/material.dart';

import '../core/model.dart';
import '../core/store.dart';

/// 条目的编辑与删除交互（ui-design §8）。
///
/// 文本条目：底 sheet = textarea + 「保存 / 删除」；保存无确认且不改 createdAt。
/// 删除：确认弹窗（破坏性操作例外）→ toast + 5s 撤销。

/// 打开文本条目编辑底 sheet。
Future<void> showEntryEditor(
  BuildContext context,
  AppStore store,
  Entry entry, {
  bool autofocus = true,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          EntryEditorSheet(store: store, entry: entry, autofocus: autofocus),
    );

class EntryEditorSheet extends StatefulWidget {
  const EntryEditorSheet({
    super.key,
    required this.store,
    required this.entry,
    this.autofocus = true,
  });

  final AppStore store;
  final Entry entry;
  final bool autofocus;

  @override
  State<EntryEditorSheet> createState() => _EntryEditorSheetState();
}

class _EntryEditorSheetState extends State<EntryEditorSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.entry.text ?? '');

  /// 文本为空时禁用「保存」——删除必须走显式的「删除」，
  /// 不让「清空后保存」变成隐式删除。
  bool get _canSave => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _save() async {
    if (!_canSave) return;
    await widget.store.updateEntryText(widget.entry.id, _controller.text);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await showDeleteEntryDialog(context);
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final removed = await widget.store.deleteEntry(widget.entry.id);
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(undoSnackBar(widget.store, removed));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('编辑', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: widget.autofocus,
                minLines: 3,
                maxLines: 10,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '内容',
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: const Text('保存'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// 删除条目的确认弹窗（ui-design §8：破坏性操作才确认）。
Future<bool?> showDeleteEntryDialog(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条记录？'),
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

/// 删除后的 toast + 5s 撤销（ui-design §8：撤销是唯一的后悔药）。
SnackBar undoSnackBar(AppStore store, Entry removed) => SnackBar(
      content: const Text('已删除'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () => store.restoreEntry(removed),
      ),
    );
