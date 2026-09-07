/// core 层最小监听机制：不依赖 Flutter 的 Listenable/ChangeNotifier 替代品。
/// UI 层通过桥接类（ui/listenable_bridge.dart）适配为 Flutter 的 Listenable。
library;

/// 可监听对象。
abstract class CoreListenable {
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}

/// 极简 ChangeNotifier：添加/移除监听器、派发通知。
class CoreChangeNotifier implements CoreListenable {
  final List<void Function()> _listeners = [];
  bool _disposed = false;

  @override
  void addListener(void Function() listener) {
    if (!_disposed) _listeners.add(listener);
  }

  @override
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// 通知所有监听器。复制一份列表，允许监听器中增删监听器。
  void notifyListeners() {
    if (_disposed) return;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void dispose() {
    _listeners.clear();
    _disposed = true;
  }
}
