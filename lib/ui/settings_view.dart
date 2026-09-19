import 'package:flutter/material.dart';

import '../core/model.dart';
import '../core/store.dart';
import 'listenable_bridge.dart';

/// 设置（v1 仅主题偏好），底部队列展示。
Future<void> showSettingsSheet(BuildContext context, AppStore store) {
  final bridge = CoreListenableBridge(store);
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => ListenableBuilder(
      listenable: bridge,
      builder: (context, _) => SettingsSheet(store: store),
    ),
  ).whenComplete(bridge.dispose);
}

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.store});

  final AppStore store;

  static const _options = [
    (ThemeSetting.system, '跟随系统'),
    (ThemeSetting.light, '浅色'),
    (ThemeSetting.dark, '深色'),
  ];

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
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('设置', style: Theme.of(context).textTheme.titleMedium),
          ),
          RadioGroup<ThemeSetting>(
            groupValue: store.theme,
            onChanged: (v) => _setTheme(context, store, v!),
            child: Column(
              children: [
                for (final (mode, label) in _options)
                  RadioListTile<ThemeSetting>(title: Text(label), value: mode),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
