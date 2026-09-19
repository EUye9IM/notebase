import 'package:flutter/widgets.dart';

/// 弹层 / 对话框的「安全关闭」：把 pop 绑定到**弹层自己的路由**，
/// 而不是调用瞬间的栈顶（M6 后评审 P1）。
///
/// 为什么不能只查 `mounted`：弹层若已因点遮罩 / 下滑 / Esc 进入退场动画，
/// 路由处于 `popping` —— `mounted` 仍为 true，但它已不再是 navigator 的
/// present 栈顶（Flutter 在 `_RouteLifecycle` 里把 `popping` 明确标为
/// "routes that are not present"）。而 `NavigatorState.pop` 取的是最后一个
/// present 路由，于是会选中**下面那条**：实测把 HomePage 弹掉，应用零路由、
/// 整个窗口空白（`pumpAndSettle` 之后 `find.byType(HomePage)` 为 0）。
///
/// 用法——**在任何 await 之前**取一次，await 之后再调用：
///
/// ```dart
/// final close = sheetCloser(context);
/// await store.updateEntryText(entry.id, text);
/// if (mounted) close();
/// ```
///
/// 弹层已经关闭或正在关闭时，调用是安全的空操作；弹层还开着时等价于
/// `Navigator.pop(context)`。
VoidCallback sheetCloser(BuildContext sheetContext) {
  // 路由必须在弹层还挂载、且尚未 await 时取：路由销毁后 context 已经查不动
  // 祖先，这正是「弹层整个关掉之后 onDone 再 pop」会抛
  // 「Looking up a deactivated widget's ancestor」的原因。
  final route = ModalRoute.of(sheetContext);
  return () {
    // 已经不是栈顶：只可能是自己已在退场（或已关闭），此时绝不能 pop——
    // 那会打到别人的路由上。
    if (route == null || !route.isCurrent) return;
    route.navigator?.pop();
  };
}
