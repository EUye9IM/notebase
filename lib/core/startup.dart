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
  try {
    return StoreLoadResult(store: await AppStore.load(storage));
  } on Object catch (error) {
    final quarantined = await storage.quarantineCorruptFiles();
    return StoreLoadResult(
      store: await AppStore.load(storage), // 失败则向上抛，交给调用方兜底
      quarantined: quarantined,
      error: error,
    );
  }
}
