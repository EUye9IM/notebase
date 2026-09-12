# 开发计划 v1（初版）

> 范围声明：**文本优先，Linux 先行**。照片 / 录音整体后置（模型字段已预留，UI 不暴露入口），
> AI 与多平台再后置。交互规格以 [ui-design.mdx](ui-design.mdx) 为准（下文 § 均指该文档章节）。

## 1. 原则

1. **文字先行** — v1 只做文本条目完整闭环；`Entry` 预留 `type/file/duration/summary/transcript` 字段，但 UI 只出现文本入口。
2. **Linux 先行** — 只在 Linux 桌面端开发与验证。平台能力（应用目录、权限、相机/麦克风）一律隔离在 UI 层边缘，由 UI 注入 core，多平台后置。
3. **UI 与核心分离** — `core/` 零 Flutter 依赖；`ui/ → core/` 单向依赖。核心逻辑可纯 Dart 测试，未来换 UI（Android、其他前端）不动核心。
4. **小步可验收** — 每个里程碑结束应用可运行。验收标准固定三件套：`flutter analyze` 0 issue、测试全绿、手动核对 §11 操作步数表。

## 2. 分层

```
lib/
├── core/                      # 纯 Dart，禁止 import package:flutter/**
│   ├── model.dart             # Notebook、Entry（含媒体预留字段）
│   ├── listenable.dart        # 最小 Listenable / ChangeNotifier（自实现，~20 行）
│   ├── store.dart             # AppStore：笔记本 + 当前流 + 搜索 + 偏好
│   └── storage/
│       ├── storage.dart       # 接口：notebooks / entries / prefs 读写
│       └── json_storage.dart  # JSON 文件实现（baseDir 由外部注入）
└── ui/                        # Flutter 层
    ├── app.dart               # MaterialApp + 主题（偏好驱动）
    ├── listenable_bridge.dart # core→Flutter 监听桥接（core 零 Flutter 的代价集中处）
    ├── home.dart              # 应用壳：宽屏 / 窄屏布局切换（§3）
    ├── stream_view.dart       # 时间流：按天分组、升序、空态（§4）
    ├── input_bar.dart         # 常驻输入栏，v1 仅文本（§5.1）
    ├── notebook_list.dart     # 笔记本切换 / 新建 / 重命名 / 删除（§6，M3）
    ├── search_view.dart       # 原地搜索模式（§7，M4 待建）
    ├── editor_sheet.dart      # 条目编辑底 sheet（§8，M4 待建）
    └── settings_view.dart     # 设置：主题
```

规则：

- core 只 import `dart:*` 与自身文件；测试（`test/core/`）不 pump 任何 widget。
- UI 通过构造函数注入 `AppStore`；store 持有 `Storage` 实例。
- 应用数据目录由 UI 用 `path_provider` 取得后注入 `JsonFileStorage`（core 不感知平台）。
- 偏好（主题）也走 core 的 storage（`prefs.json`）——**M1 起废弃 `shared_preferences` 依赖**，core 才能保持零 Flutter 依赖。旧原型数据不迁移。

存储布局（§2 已定，初版即生效）：

```
<app-data>/notebooks.json        # 笔记本索引
<app-data>/nb_<id>.json          # 每笔记本一个条目数组
<app-data>/prefs.json            # 偏好（主题、当前笔记本）
<app-data>/media/                # 预留，v1 为空
```

## 3. 里程碑

### M1 核心层

- `Entry` / `Notebook` 模型 + JSON 序列化（预留媒体字段）
- `Storage` 接口 + `JsonFileStorage` 实现
- `AppStore`：文本条目增删改、笔记本 CRUD 与切换、搜索（文本包含匹配）、主题偏好
- 不变式：default 永存不可删；删除笔记本时条目并入 default
- 交付：`test/core/` 全绿；删除旧 `lib/store.dart`；pubspec 移除 `shared_preferences`
- 备注：大量逻辑可从旧 `store.dart` 迁移，工作量小

### M2 时间流 + 文本录入

- 应用壳：窄屏（顶栏 / 时间流 / 输入栏）、宽屏 ≥720（侧栏 / 流头部 / 流 / 输入栏），§3
- 文本录入：窄屏 Enter 换行、➤ 发送；宽屏 Enter 发送、Shift+Enter 换行（§5.1）
- 时间流：升序、最新在底、按天分组（今天 / 昨天 / M月d日）、空态提示、录入后自动滚底（§4）
- 顶栏 / 侧栏暂放笔记本名占位（M3 补切换功能）
- 验收：记一段文字 = 窄屏 2 步 / 宽屏 1 步

### M3 笔记本管理

- 切换：窄屏底部弹层 / 宽屏侧栏即列表（§6）
- 新建（单字段对话框 + 建完即切换）、重命名、删除（确认 + 条目并入 default）
- 当前笔记本持久化到 prefs.json
- 验收：切换 窄屏 2 / 宽屏 1 步；新建并切换 3 步

### M4 搜索 + 条目编辑 / 删除

- 原地搜索模式：顶栏切换、输入即过滤、结果倒序、N 条结果、无结果态、退出恢复滚动位置（§7）
- 文本编辑底 sheet：保存无确认、不改 createdAt（§8）
- 删除：确认弹窗 + toast 撤销 5s（建议 store 层 `deleteEntry` 返回可回滚快照，UI 不自己缓存条目）
- 验收：搜索 1 步进入 + 即时过滤；删除 3 步（含唯一必要确认）

### M5 打磨

- 回到最新按钮（上翻超过一屏浮现，§4）
- 焦点细节：窄屏不自动弹键盘、宽屏自动聚焦（§5.1）
- 键盘行为显式核对：`numpadEnter`（当前只匹配 `enter`）、真实 Linux IM/嵌入层下的 Enter 发送路径（现有覆盖仅 widget 测试，走框架内 key 分发）
- 启动期数据损坏兜底：`notebooks.json` / `nb_*.json` 解析失败时不 crash（方案见 ui-design §10）
- §10 边界情况清单逐条核对（含输入框草稿跨笔记本切换的处理决策）
- Linux release 构建自测 + 操作步数表（§11）全量过一遍

### 后置（有依赖顺序，不排期）

| 项 | 说明 |
|---|---|
| M6 多媒体 | 录音（`record`，Linux 实现已存在）、播放（`audioplayers`）、拍照与相册导入（`image_picker` Linux 桌面支持有限，届时评估 `file_picker` 替代）；媒体文件管理；转写/摘要手动编辑入口 |
| M7 SQLite | `sqflite` + `sqflite_common_ffi`，`Storage` 换实现；FTS5 |
| M8 Android | 权限（麦克风/相机）、输入栏键盘适配、真机构建 |
| M9 AI | Phase 3：自动转写→摘要、图片描述、语义搜索；接入点已在模型与 UI 预留 |

## 4. 风险与开放问题

- **媒体插件 Linux 成熟度**：M6 开始前做一轮 spike（录音→播放→文件落盘），不阻塞文本线。
- **JSON 全量写的性能上限**：每条变更全量序列化单笔记本文件。触发条件（单本条目过万 / 写入卡顿）出现时提前 M7，不为预防而提前。
- **旧原型数据**：`shared_preferences` 里的旧笔记为原型数据，M1 直接废弃不迁移；主题偏好重置为默认可接受。
- **写入并发**（M3 评审后已修）：`JsonFileStorage` 按路径串行化 + 唯一 tmp 名；修前实测并发写 120/120 轮 `PathNotFoundException`、300 轮中 1 轮静默丢数据，回归测试已固化（`json_storage_test.dart`）。
- **流渲染无虚拟化**：`SingleChildScrollView + Column` 全量构建，条目上千后需换 `ListView.builder`；与「JSON 全量写」同源，触发条件出现时一并处理。

## 5. M5 验收记录（§11 操作步数表）

每行都对应一条自动化断言；媒体相关行属 M6（N/A）。一处例外：**换行行为在 widget 测试里无法真正验证**
（Enter 在测试环境既不发送也不插入换行），对应用例断言的是「未误发且原文不丢」，真换行留待真机核对：

| §11 行 | 步数 | 自动化证据 |
|---|---|---|
| 记一段文字（窄屏） | 2 | `test/ui/polish_test.dart`「点输入框 → 打字 → ➤ 发送」（走真实键盘路径） |
| 记一段文字（宽屏） | 1 | `test/ui/app_test.dart`「宽屏输入文字后 Enter 发送」 |
| 搜索定位一条文本 | 1 + 输入 | `test/ui/search_test.dart`「1 步进入，输入即过滤，退出恢复时间流」 |
| 切换笔记本（窄屏） | 2 | `test/ui/notebook_test.dart`「窄屏：顶栏弹层切换笔记本（2 步）」 |
| 切换笔记本（宽屏） | 1 | 同上文件「宽屏：侧栏点按切换笔记本（1 步）」 |
| 新建并切到新笔记本 | 3 | 同上文件「新建笔记本：对话框 → 创建 → 立即切换为当前」 |
| 删除一条记录 | 3 | `test/ui/search_test.dart`「长按 → 删除 → 确认（3 步），并可用 5s 撤销找回」 |
| 录一段音 / 拍一张照 / 相册导入 / 查看补录转写或摘要 | — | M6 未实装，N/A |

工程门禁（M5 实测）：

- `flutter analyze` → 0 issue
- `flutter test` → 全绿；`TZ=Europe/Berlin` 下 DST 用例通过
- `flutter build linux --release` 通过；release 二进制实跑 8s 无崩溃（仅 Impeller / 光标主题无害提示）
- 启动兜底实测（真实数据副本）：`notebooks.json` 写坏后仍以 default 启动，坏文件隔离为
  `notebooks.json.corrupt-<时间戳>` 并保留在数据目录

## 6. 评审修复记录（M5，提交后续）

M5 评审（对抗性、只读、实测）发现 4 个 P2 与若干 P3，均已修复并配「修复前会失败」的回归用例：

| 编号 | 问题 | 修法 | 回归用例 |
|---|---|---|---|
| P2-1 | 「回到最新」切到内容不足一屏的笔记本后残留且点不掉（越界修正是静默的） | 按钮可见性改为帧末实时重算，空态强制 false | `polish_test.dart`「内容不足一屏的笔记本不显示按钮，切换后不残留」 |
| P2-2 | 发送写盘窗口内切本/继续打字，被写盘完成后的 `clear()` 抹掉 | 捕获发送时的笔记本与文本，仅在两者都未变时清空 | `polish_test.dart`「窗口内切本…」「窗口内继续打字…」 |
| P2-3 | 非当前笔记本的 `nb_*.json` 损坏无人兜底，切本抛未捕获异常且该本永久打不开 | 启动期全量扫描隔离；切本先加载后改状态；UI 切本失败给提示 | `startup_test.dart` 两条 + `store` 切本原子性 |
| P2-4 | `prefs.json` 结构坏 → 兜底失效直接进错误界面 | `loadPrefs` 容错回默认 + `Prefs.fromJson` 类型容错 | `startup_test.dart`「prefs 结构坏：回默认值启动」 |
| P3-1 | 拖动窗口跨 720 丢草稿 | 草稿抽为 HomePage 持有的 `DraftStore` | `polish_test.dart`「窗口跨 720 宽窄切换，草稿不丢」 |
| P3-2 | 启动提示条无高度上限，多文件时溢出 | 文案折叠计数 + 限 4 行 | `startup_views_test.dart` 两条溢出用例 |
| P3-3 | 提示文案可能谎报「已重置」；启动视图无测试 | 文案推导抽成纯函数并测试；`StartupErrorApp` 移入可测文件 | `startup_views_test.dart`「不谎报已重置」等 |

P3-4（弱断言）同批处理：窄屏录入用例改走真实键盘路径并断言输入落点，换行类用例改名并补「原文不丢」断言。
