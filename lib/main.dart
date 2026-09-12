import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/startup.dart';
import 'core/storage/json_storage.dart';
import 'ui/app.dart';

/// 启动：注入应用目录 → 加载 store → 启动。
///
/// 数据损坏兜底（ui-design §10）：解析失败时隔离坏文件（改名保留，不删），
/// 以 default 重新启动并把隔离结果告知用户；连兜底加载都失败时给一个
/// 可读的错误界面，而不是红屏。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final storage = JsonFileStorage(dir.path);

  late final StoreLoadResult result;
  try {
    result = await loadStoreResilient(storage);
  } on Object catch (fatal) {
    runApp(StartupErrorApp(message: '$fatal', directory: dir.path));
    return;
  }
  final notice = result.error == null
      ? null
      : (result.quarantined.isEmpty
          ? '部分数据未能读取（${result.error}），已重置为空白笔记本。'
          : '部分数据未能读取，已备份到：\n${result.quarantined.join('\n')}');
  runApp(NotebaseApp(store: result.store, startupNotice: notice));
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
            child: Padding(
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
