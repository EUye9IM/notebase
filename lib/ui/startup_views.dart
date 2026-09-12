import 'package:flutter/material.dart';

import '../core/startup.dart';

/// 启动期视图：提示条与兜底错误界面（ui-design §10）。
/// 文案推导是纯函数，便于测试——「不谎报、不溢出」都要能被断言。

/// 由 [StoreLoadResult] 推导提示文案；无需告知时返回 null。
String? startupNoticeText(StoreLoadResult result) {
  if (result.error == null && result.quarantined.isEmpty) return null;

  if (result.quarantined.isEmpty) {
    // 首次读取失败但重试成功、且没有任何文件被隔离：数据是完好的，
    // 不能说「已重置为空白笔记本」（M5 评审 P3-3）。
    return '启动时读取数据出错，已用可用数据继续（${result.error}）。';
  }

  final names = result.quarantined;
  final shown = names.take(2).join('、');
  final more = names.length > 2 ? ' 等 ${names.length} 个文件' : '';
  return '部分数据未能读取，已备份：$shown$more';
}

/// 启动期提示条：明确告知、可关闭、不阻塞使用（§10）。
class StartupNotice extends StatelessWidget {
  const StartupNotice({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.errorContainer,
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(children: [
        Icon(Icons.warning_amber_outlined,
            size: 18, color: colors.onErrorContainer),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            // 限高：损坏文件很多时文案会很长，必须折叠而不是挤爆布局
            // （评审实测 30 行会 RenderFlex overflow）。
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.onErrorContainer),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          color: colors.onErrorContainer,
          tooltip: '知道了',
          onPressed: onDismiss,
        ),
      ]),
    );
  }
}

/// 兜底失败时的最小可读界面（此时没有可用 store，纯展示）。
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    super.key,
    required this.message,
    required this.directory,
  });

  final String message;
  final String directory;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  const Text('数据目录无法读取，Notebase 无法启动'),
                  const SizedBox(height: 8),
                  SelectableText(
                    '目录：$directory\n$message',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
