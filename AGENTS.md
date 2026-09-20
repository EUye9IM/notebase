# AGENTS.md

面向在本仓库工作的编码 agent。**先读这份，再动手。**

## 项目是什么

Notebase：本地优先的**快速笔记本**——打开即记，一条一档（文字 / 语音 / 拍照），
按笔记本分组，完全离线。文本闭环与多媒体（录音 / 播放 / 图片导入）均已完成，Linux 桌面端先行。

- 交互规格（**唯一契约**）：`docs/ui-design.mdx`
- 开发计划（里程碑 M1–M5 + M6 多媒体分段）：`docs/dev-plan.md`
- 进度与状态：`README.md`

**设计文档是契约，不是参考。** 任何行为变更都要在同一次提交里更新 `ui-design.mdx`
对应章节；§11 的操作步数表是硬验收指标。

## 环境与命令

Flutter **不在默认 PATH**（SDK 在 `/opt/dev/flutter`，stable 3.47.2）：

```bash
export PATH="$PATH:/opt/dev/flutter/bin"

flutter pub get
flutter analyze                 # 必须 0 issue
flutter test                    # 全量；必须全绿
flutter test test/ui/search_test.dart          # 单文件
flutter test --plain-name "关键词"              # 单用例
TZ=Europe/Berlin flutter test test/ui/stream_view_test.dart   # DST 用例需在 DST 时区跑
flutter run -d linux
flutter build linux --debug
```

推送（系统 `ssh_config.d` 权限有问题，必须绕过）：

```bash
git -c core.sshCommand="ssh -F /dev/null" push origin main
```

应用数据目录（调试用，JSON 可直接看/改）：
`~/.local/share/com.example.notebase/` → `notebooks.json`、`nb_<id>.json`、`prefs.json`。

## 架构铁律

```
lib/
├── core/    纯 Dart，零 Flutter 依赖：model / store / listenable / storage
├── ui/      Flutter：app / home / stream_view / input_bar / notebook_list /
│            search_view / editor_sheet / sheet_nav / settings_view / listenable_bridge /
│            media_recorder（录音抽象）/ media_player（播放编排）/ recording_session（录音会话）/
│            media_importer（选图抽象）/ photo_view（缩略图与查看器）/ startup_views（启动视图）
└── main.dart  入口：注入应用目录 → 加载 AppStore → 启动
```

1. **`lib/core/**` 禁止 `import 'package:flutter/...'`**——由
   `test/core/architecture_test.dart` 机器校验。core 内部用自己的
   `CoreListenable`/`CoreChangeNotifier`，UI 侧经 `listenable_bridge.dart` 适配。
2. **依赖单向**：`ui → core`。平台能力（应用目录、剪贴板等）由 UI 取得后**注入** core，
   core 不感知平台。
3. **`Storage` 接口收口所有持久化与媒体落点**（路径、存在性、归档/删除）：
   换 SQLite（M7）只换实现，不动上层；UI 不直接摸文件系统（用 `store.mediaPath` /
   `store.mediaExists`）。
4. **偏好也走 core 的 storage**（`prefs.json`），不要引入 `shared_preferences`。
5. **测试分层**：`test/core/**` 不 pump widget；`test/ui/**` 才是 widget 测试。

## 数据不变式（改动 core 时必须守住）

- `default` 笔记本永存：不可删除、不可重命名；删除其它笔记本时条目**并入 default**。
- **一条条目恰好属于一个笔记本**（`entry.notebookId`）：并入 default 等任何迁移都要重写归属。
- 条目无标题；文本条目 `text` 即内容；媒体条目文字层 = `transcript`（录音全文）
  + `summary`（照片/录音的短文字）。
- 排序恒为 `(createdAt, id)` 升序，最新在末尾。
- 搜索范围**仅当前笔记本**；命中规则：文本=正文、照片=摘要、录音=转写+摘要。

## 提交前检查清单

1. `flutter analyze` → 0 issue
2. `flutter test` → 全绿（涉及日期/DST 时加跑 `TZ=Europe/Berlin`）
3. 涉及 UI 壳或平台集成 → `flutter build linux --debug` 通过
4. 行为变更 → 同步更新 `docs/ui-design.mdx`（必要时 `docs/dev-plan.md`、`README.md`）
5. 新契约 → 补测试，并**确认该测试在修复/实现前会失败**（避免恒真断言）

提交信息用 Conventional Commits，**描述用中文**（`feat(core): …`、`fix(ui): …`），
正文写清根因与验证结果。

## 测试写法陷阱（都是踩过的）

- **`tester.enterText(finder)` 会强制聚焦目标控件**——用它验证「自动聚焦」类需求会得到
  **假阴性**。要验证真实键盘路径，用 `tester.testTextInput.enterText('…')`（文本送给
  当前有输入连接者）+ `tester.sendKeyEvent(…)`。M4 的宽屏搜索焦点失效正是被这个盲区放过的。
- **`IndexedStack` 的 offstage 子节点仍会 build/layout 并响应 store 变更**（`hasClients`
  为真）。搜索态保活时间流时，必须显式抑制副作用的自动滚底（见 `StreamView.autoScroll`）。
- **不要长按/点击 `ListView` 缓存区内不可见的行**：命中测试会落空，得到假失败
  （探针自身的问题）。用 `.first` 时先确认目标确实可见，或改用可见行的 finder。
- **`KeyRepeatEvent` 与 `KeyDownEvent` 是平级类型**（都继承 `KeyEvent`），
  `event is KeyDownEvent` 天然过滤按住不放的重复事件。
- **`SelectableText` 会吞掉所在行的点按/长按手势**：条目的点按=编辑、长按=菜单，
  因此条目行用 `Text`；整条复制走菜单的「复制」。
- **widget 测试没有平台通道实现**（剪贴板等）：需
  `tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(...)`。
- **带 `action` 的 `SnackBar` 在 Flutter 3.47 起默认 `persist: true`（永不自动
  关闭）**：`persist = persist ?? action != null`。v1.1 已移除删除撤销条，因此现在
  没有代码路径踩它、也没有用例守着；**将来若再加带 action 的提示条，必须显式
  `persist: false`**，否则 `duration` 形同虚设、底栏长期占位（当年实测）。
- **滚动越界修正是静默的**：内容变短（如切到条目更少的笔记本）时 `correctPixels` 不发通知，
  只信缓存的滚动判定会让「回到最新」之类的按钮残留且点不掉。要在帧末重算或监听
  `ScrollMetricsNotification`（M5 评审 P2-1）。
- **跨布局重建会重建 State**：宽/窄两套布局各自构造同一组件时，拖动窗口跨 720 会丢 State 内的
  数据。两条应对，按状态性质选：
  - **页面持有的模型/会话**上提到页面对象里——输入草稿（`DraftStore`，M5 评审 P3-1）
    与**录音会话**（`RecordingSession`，M6 评审 P1-1：放 State 里会导致录音条消失、麦克风仍占用、
    临时文件成孤儿、还能二次开录）。
  - **组件自己的 State 必须整体存活**时，用页面持有的 `GlobalKey` 让元素跨布局**搬家**
    而不是重建（时间流与输入栏：滚动位置与「已见基线」、发送/导入守卫与输入框内容，
    M6 后复检 P2）。只上提个别字段容易漏，GlobalKey 一次覆盖整棵子树。
- **别用真实文件系统做 UI 测试**：用 `test/support/memory_storage.dart`
  （`MemoryStorage` / `SlowMemoryStorage`——后者模拟写延迟，用于发送重入类测试）。
- **widget 测试里不要 `await` 真实文件 I/O**：`testWidgets` 跑在 fake-async 区，
  真实 I/O 的 Future 永不完成，测试会**直接挂死**（本项目已因此超时两次）。
  需要真实文件时用**同步** API（`writeAsBytesSync` / `existsSync` / `createTempSync`）
  或在 `setUp` 里准备；`Image.file` 的解码同理，UI 层要覆盖「缺失占位」就先用
  `existsSync` 分支渲染占位，不要依赖 `errorBuilder`。
- 断言要能失败：写完先想「代码坏掉时它会不会照样绿」。弱断言示例（真实踩到、已修）：
  照片搜索用例的查询词用的是**条目 id**（id 从不是搜索字段）→ 恒真；「退出搜索恢复滚动位置」
  进出之间没有任何 store 变更 → 位置本来就不会变。改成能区分的输入才有价值。
- **断言「路由被弹掉」要给足帧**：`pump(Duration(milliseconds: 400))` 只走**一帧**，
  被 pop 的路由可能还没走完销毁、仍被 finder 找到，于是**假绿**；这种用例要用
  `pumpAndSettle()`（本坑在弹层路由竞态的回归用例上真实踩到过）。

## 已知坑（并发与异步）

- `JsonFileStorage` 的写入是**按路径串行 + 唯一 tmp 名**，且队列用 `catchError`
  吞掉前序错误（否则一次失败会永久毒化该文件的写队列）。**删除也要走同一条队列**
  （`_enqueueFor`）：否则删除插到在飞的写入之前，写落地后 `nb_*.json` 又冒出来成
  僵尸文件。改这里时保持这三点，回归测试在 `test/core/json_storage_test.dart`。
- **兜底自身的失败不能升级成更大的失败**：启动扫描里单个文件读不了/改不了名只跳过
  （`loadStoreResilient` 对扫描整体兜底）——「数据目录里有一个读不了的文件」绝不能变成
  「应用打不开」（§10）。
- 固定临时文件名 + 并发写会抛 `PathNotFoundException`，还会**静默丢数据**（实测）。
- **惰性加载会掩盖损坏**：`AppStore.load` 只读当前笔记本的条目文件，其它 `nb_*.json` 坏了
  启动时毫无征兆，切过去才炸且该本永久打不开——启动期必须**主动全量扫描**（M5 评审 P2-3）。
- **低价值数据不要挡住启动**：`prefs.json`（主题 + 当前笔记本）任何损坏都应回默认值继续，
  而不是把用户拦在错误界面上（M5 评审 P2-4）。
- **core 的写路径统一走 `AppStore._mutateAndSave`**：先备份、变更、落盘，**失败原地回滚**
  后 rethrow——否则留下「内存有、磁盘无」的幽灵条目（下次通知冒出来、重启又消失）。
  UI 侧必须 catch 并给可读提示，且失败时**不关弹层、不清输入框**（复检 P2，回归在
  `store_test.dart` / `polish_test.dart`）。
- UI 里 `await` 之后再用 `context`/`ScaffoldMessenger` 前先查 `mounted`；
  messenger 在 `await` **之前**捕获。
- **`await` 之后关弹层，光查 `mounted` 不够**：弹层若已因点遮罩/下滑/Esc 进入退场动画，
  路由处于 `popping`——`mounted` 仍为 true，但它已不是 navigator 的 present 栈顶
  （Flutter 在 `_RouteLifecycle` 里把 `popping` 标为 "routes that are not present"），
  `Navigator.pop` 会选中**下面那条**路由，把 HomePage 弹掉（实测：应用零路由、窗口空白；
  弹层已整个销毁时还会抛「deactivated widget's ancestor」）。用 `ui/sheet_nav.dart` 的
  `sheetCloser(context)`：await **之前**捕获本弹层的路由，之后只在 `route.isCurrent`
  时 pop（M6 后评审 P1-1，回归用例在 `notebook_test.dart` / `search_test.dart`）。

## 已定的产品决策（不要擅自推翻）

- 录入路径**零确认**：发送/录音停止/快门即保存；只有删除才确认。
- **删除不给撤销**（v1.1 决策，推翻 v1 的「toast + 5s 撤销」）：删前确认是唯一的防误删措施，
  删成功不打扰、只有失败才提示。别擅自把撤销条加回来。
- `default` 不可删除/重命名，但**有「清空」**（仅 default）：条目与它们引用的媒体文件一并删除、
  **不可撤销**（确认文案写明条数与媒体文件数）。「删除笔记本 = 条目并入 default」与
  「清空 = 销毁条目与媒体」是两套语义，别互相套用。
- 搜索限当前笔记本、原地模式、退出恢复滚动位置；结果最新在前。
- 录音双层文本（转写全文 + 摘要）；两者**用户可编辑，编辑过即定稿**，
  AI 自动生成不得覆盖（Phase 3）。
- 媒体条目：录音=ogg/Opus（基础 GStreamer 可解码，aac 不行）；删除条目不删媒体文件
  （回收统一交给「无主媒体清理」，见 `dev-plan §7`）；长按菜单按类型给项
  （文本=复制/编辑/删除；录音=复制/编辑转写/编辑摘要/删除；照片=复制/编辑摘要/删除，
  有可复制文字才出现「复制」）。
- 照片渲染：缩略图先做**同步存在性检查**（`store.mediaExists`）再决定是否发起解码，缺失即占位
  「图片已丢失」（§10）；解码按目标显示尺寸传 `cacheWidth`，不整幅解码原图。点击进全屏查看器，
  点空白关闭。导入用 `file_selector`，**只复制不移动**用户原图。

## 里程碑节奏

按 `docs/dev-plan.md` 的 M1–M5 推进，一个里程碑一次提交；每个里程碑结束必须满足
「检查清单」。当前：**M1–M5 已完成**（§11 验收记录见 `docs/dev-plan.md` §5，
M5 评审修复记录见 §6），**M6 多媒体已完成**（M6a 核心媒体层 / M6b 录音 / M6c 播放与媒体渲染 / M6d 图片导入 /
M6e 转写摘要编辑），剩下的是 `dev-plan §7` 的收尾项（无主媒体清理、真机手动核对）。

**未完成 / 待观察项**（勿遗忘，另有 `dev-plan §7`）：
- **无主媒体清理**：删除条目不删媒体文件（统一回收），会留下不再被引用的
  `media/*.ogg|png` 与异常退出的 `media/.tmp/*`
- **真机手动核对**：应用内完整链路（录音 → 播放；选图 → 缩略图 → 查看器）尚未手点过，
  插件层已由 M6 spike 与构建验证（widget 测试受 fake-async 限制，不覆盖真实文件 I/O）
- 真实 Linux IM 路径下的 Enter 发送（widget 测试走框架内 key 分发，不等于真实输入法）
- 流渲染无虚拟化（`SingleChildScrollView + Column`），条目上千需换 `ListView.builder`
- JSON 全量写的性能上限 → 触发时提前做 M7（SQLite）
- 输入栏草稿仅内存（重启即失），如需持久化再定
