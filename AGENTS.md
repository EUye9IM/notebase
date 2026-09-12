# AGENTS.md

面向在本仓库工作的编码 agent。**先读这份，再动手。**

## 项目是什么

Notebase：本地优先的**快速笔记本**——打开即记，一条一档（文字 / 语音 / 拍照），
按笔记本分组，完全离线。当前阶段只做**文本条目**闭环，Linux 桌面端先行。

- 交互规格（**唯一契约**）：`docs/ui-design.mdx`
- 开发计划（里程碑 M1–M5，多媒体后置 M6）：`docs/dev-plan.md`
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
│            search_view / editor_sheet / settings_view / listenable_bridge
└── main.dart  入口：注入应用目录 → 加载 AppStore → 启动
```

1. **`lib/core/**` 禁止 `import 'package:flutter/...'`**——由
   `test/core/architecture_test.dart` 机器校验。core 内部用自己的
   `CoreListenable`/`CoreChangeNotifier`，UI 侧经 `listenable_bridge.dart` 适配。
2. **依赖单向**：`ui → core`。平台能力（应用目录、剪贴板等）由 UI 取得后**注入** core，
   core 不感知平台。
3. **`Storage` 接口收口所有持久化**：换 SQLite（M7）只换实现，不动上层。
4. **偏好也走 core 的 storage**（`prefs.json`），不要引入 `shared_preferences`。
5. **测试分层**：`test/core/**` 不 pump widget；`test/ui/**` 才是 widget 测试。

## 数据不变式（改动 core 时必须守住）

- `default` 笔记本永存：不可删除、不可重命名；删除其它笔记本时条目**并入 default**。
- **一条条目恰好属于一个笔记本**（`entry.notebookId`）：并入 default、撤销回退等
  任何迁移都要重写归属。
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
  关闭）**：`persist = persist ?? action != null`。撤销条必须显式
  `persist: false`，否则 `duration` 形同虚设、底栏长期占位（已修，
  回归测试在 `test/ui/search_test.dart`）。
- **别用真实文件系统做 UI 测试**：用 `test/support/memory_storage.dart`
  （`MemoryStorage` / `SlowMemoryStorage`——后者模拟写延迟，用于发送重入类测试）。
- 断言要能失败：写完先想「代码坏掉时它会不会照样绿」。弱断言示例（已修）：
  撤销回退用例里当前本恰好是 default，无法区分「落到 default」与「落到当前本」。

## 已知坑（并发与异步）

- `JsonFileStorage` 的写入是**按路径串行 + 唯一 tmp 名**，且队列用 `catchError`
  吞掉前序错误（否则一次失败会永久毒化该文件的写队列）。改这里时保持这两点，
  回归测试在 `test/core/json_storage_test.dart`。
- 固定临时文件名 + 并发写会抛 `PathNotFoundException`，还会**静默丢数据**（实测）。
- UI 里 `await` 之后再用 `context`/`ScaffoldMessenger` 前先查 `mounted`；
  messenger 在 `await` **之前**捕获。

## 已定的产品决策（不要擅自推翻）

- 录入路径**零确认**：发送/录音停止/快门即保存；只有删除才确认（另配 5s 撤销）。
- 搜索限当前笔记本、原地模式、退出恢复滚动位置；结果最新在前。
- 录音双层文本（转写全文 + 摘要）；两者**用户可编辑，编辑过即定稿**，
  AI 自动生成不得覆盖（Phase 3）。
- 撤销回退目标：原笔记本已删除时落到**当前笔记本**（§8 有理由说明），
  与 §6「删除笔记本并入 default」是不同语义。
- 未实装但字段已预留的（`photo`/`audio`/`transcript`/`summary`）不要删除；
  M6 前 UI 不暴露媒体入口。

## 里程碑节奏

按 `docs/dev-plan.md` 的 M1–M5 推进，一个里程碑一次提交；每个里程碑结束必须满足
「检查清单」。当前：**M1–M5 已完成**（§11 验收记录见 `docs/dev-plan.md` §5），
下一步是 M6 多媒体（录音 / 拍照 / 相册）。

**未完成 / 待观察项**（勿遗忘）：
- 真实 Linux IM 路径下的 Enter 发送（widget 测试走框架内 key 分发，不等于真实输入法）
- 流渲染无虚拟化（`SingleChildScrollView + Column`），条目上千需换 `ListView.builder`
- JSON 全量写的性能上限 → 触发时提前做 M7（SQLite）
- 输入栏草稿仅内存（重启即失），如需持久化再定
