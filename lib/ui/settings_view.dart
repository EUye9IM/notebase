import 'package:flutter/material.dart';

import '../core/model.dart';
import '../core/store.dart';
import 'listenable_bridge.dart';

/// 设置页（ui-design §3）：**独立整页**，宽窄屏一致。
///
/// 之前是底部弹层：可扩展性差——导出、媒体清理、AI 接入这些都要往设置里放，
/// 弹层塞不下也不方便分层。改成整页后，加分区只需往 [ListView] 里追加。
/// 数据维护类能力（导出 / 清理无主媒体）见 dev-plan §7 的排期。
Future<void> openSettings(BuildContext context, AppStore store) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsPage(store: store)),
    );

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 页面自己持有监听桥：设置改的是 core 里的偏好，这里要跟着重建。
  late final CoreListenableBridge _bridge = CoreListenableBridge(widget.store);

  static const _options = [
    (ThemeSetting.system, '跟随系统'),
    (ThemeSetting.light, '浅色'),
    (ThemeSetting.dark, '深色'),
  ];

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  static Future<void> _setTheme(
    BuildContext context,
    AppStore store,
    ThemeSetting theme,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.setTheme(theme);
    } on Object catch (error) {
      // 偏好写盘失败：界面已按新主题渲染，但重启会回旧主题——要说一声（复检 P2）
      messenger.showSnackBar(SnackBar(content: Text('保存设置失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: _bridge,
        builder: (context, _) => ListView(
          children: [
            const _SectionHeader('外观'),
            RadioGroup<ThemeSetting>(
              groupValue: widget.store.theme,
              onChanged: (v) => _setTheme(context, widget.store, v!),
              child: Column(
                children: [
                  for (final (mode, label) in _options)
                    RadioListTile<ThemeSetting>(title: Text(label), value: mode),
                ],
              ),
            ),
            const Divider(height: 1),
            // 之后的分区（数据导出、媒体清理…）接在这里
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
