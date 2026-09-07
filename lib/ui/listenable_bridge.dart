import 'package:flutter/foundation.dart';

import '../core/listenable.dart';

/// 把 core 的监听对象桥接为 Flutter 的 Listenable。
///
/// core 层零 Flutter 依赖的代价集中在这里解决：core 定义自己的监听机制，
/// UI 侧经此类适配。桥接对象与 store 同生命周期，由持有方创建/释放。
class CoreListenableBridge extends ChangeNotifier {
  CoreListenableBridge(CoreListenable listenable) : _listenable = listenable {
    listenable.addListener(_relay);
  }

  final CoreListenable _listenable;

  void _relay() => notifyListeners();

  @override
  void dispose() {
    _listenable.removeListener(_relay);
    super.dispose();
  }
}
