import 'store.dart';
import 'storage/storage.dart';

/// 启动加载结果。
class StoreLoadResult {
  const StoreLoadResult({
    required this.store,
    this.quarantined = const [],
    this.error,
  });

  final AppStore store;

  /// 被隔离（改名保留）的损坏数据文件描述；为空表示未发生损坏。
  final List<String> quarantined;

  /// 首次加载失败的原因（仅用于向用户说明），成功时为 null。
  final Object? error;
}

/// 带兜底的启动加载（ui-design §10）：
/// 首次解析失败 → 隔离坏文件 → 重试；重试仍失败则抛出，由调用方给出
/// 可读的错误界面。保证「数据损坏不 crash 在启动路径上」这条契约可被测试。
Future<StoreLoadResult> loadStoreResilient(Storage storage) async {
  // 用 LinkedHashSet 去重：隔离可能被调用两次，同一项不该报告两遍。
  final quarantined = <String>{};
  Object? error;
  late final AppStore store;
  try {
    store = await AppStore.load(storage);
  } on Object catch (firstError) {
    error = firstError;
    quarantined.addAll(await storage.quarantineCorruptFiles());
    store = await AppStore.load(storage); // 失败则向上抛，交给调用方兜底
  }
  // 启动期全量扫描：非当前笔记本的条目文件是**惰性加载**的，首次 load 不会
  // 暴露它们的损坏（ui-design §10 把 nb_*.json 也列为启动期损坏情形）。
  // 不扫的话，切到那个笔记本才会抛异常，且该笔记本永久打不开。
  quarantined.addAll(await storage.quarantineCorruptFiles());
  return StoreLoadResult(
    store: store,
    quarantined: quarantined.toList(),
    error: error,
  );
}
