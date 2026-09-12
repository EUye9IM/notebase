import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/startup.dart';
import 'core/storage/json_storage.dart';
import 'ui/app.dart';
import 'ui/startup_views.dart';

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
  runApp(NotebaseApp(
    store: result.store,
    startupNotice: startupNoticeText(result),
  ));
}
