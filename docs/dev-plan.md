# 开发计划 v1（初版）

> 范围声明：**Linux 先行**。文本闭环（M1–M5）与多媒体（M6a–M6e：录音 / 播放 / 图片导入 /
> 转写摘要编辑）均已完成；AI、跨设备同步与多平台仍后置。交互规格以
> [ui-design.mdx](ui-design.mdx) 为准（下文 § 均指该文档章节）。

## 1. 原则

1. **文字先行** — 先做文本条目完整闭环，再叠多媒体（已完成）。`Entry` 的 `type/file/duration/summary/transcript` 现均已落地。
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
│   ├── startup.dart           # 带兜底的启动加载（损坏隔离后重试，§10）
│   └── storage/
│       ├── storage.dart       # 接口：notebooks / entries / prefs / 媒体落点与隔离
│       └── json_storage.dart  # JSON 文件实现（baseDir 由外部注入）
└── ui/                        # Flutter 层
    ├── app.dart               # MaterialApp + 主题（偏好驱动）
    ├── listenable_bridge.dart # core→Flutter 监听桥接（core 零 Flutter 的代价集中处）
    ├── home.dart              # 应用壳：宽屏 / 窄屏布局切换（§3）
    ├── stream_view.dart       # 时间流：按天分组、升序、空态（§4）
    ├── input_bar.dart         # 常驻输入栏：文本 + 🎤 录音 + 📷 导入（§5.1/§5.2/§5.3）
    ├── notebook_list.dart     # 笔记本切换 / 新建 / 重命名 / 删除（§6）
    ├── startup_views.dart     # 启动提示条与兜底错误界面（§10）
    ├── media_recorder.dart    # 录音抽象 + record 实现（§5.2）
    ├── media_player.dart      # 播放抽象 + 播放编排/Scope（§4/§8）
    ├── recording_session.dart # 录音会话（由页面持有，跨布局重建存活，§5.2）
    ├── media_importer.dart    # 选图抽象 + file_selector 实现（§5.3）
    ├── photo_view.dart        # 照片缩略图与全屏查看器（§4/§8）
    ├── search_view.dart       # 原地搜索模式（§7）
    ├── editor_sheet.dart      # 条目编辑底 sheet 与字段编辑（§8）
    ├── sheet_nav.dart         # 弹层安全关闭：await 之后只关自己的路由（§10）
    └── settings_view.dart     # 设置页（整页）：主题；后续导出 / 数据维护
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
<app-data>/media/<条目 id>.<ext>  # 录音 ogg / 图片，文件名即条目 id
<app-data>/media/.tmp/<uid>.<ext> # 录制中的临时落点（成功即归档）
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
| M6 多媒体 | **分段进行中**：M6a 核心媒体层 ✅ / M6b 录音 UI ✅ / M6c 播放与媒体渲染 ✅ / M6d 图片导入 ✅ / M6e 转写摘要编辑 ✅。原计划：录音（`record`，Linux 实现已存在）、播放（`audioplayers`）、拍照与相册导入（`image_picker` Linux 桌面支持有限，届时评估 `file_picker` 替代）；媒体文件管理；转写/摘要手动编辑入口 |
| M7 SQLite | `sqflite` + `sqflite_common_ffi`，`Storage` 换实现；FTS5 |
| M8 Android | 权限（麦克风/相机）、输入栏键盘适配、真机构建 |
| M9 AI | Phase 3：自动转写→摘要、图片描述、语义搜索；接入点已在模型与 UI 预留 |

## 4. 风险与开放问题

- **媒体插件 Linux 成熟度**：✅ M6 前 spike 已完成（隔离工程实测，2026-09 于本机）：
  录音 `record`（后端 `parecord` + `ffmpeg`，二者本机已装）→ 落盘 OK；播放 `audioplayers`（GStreamer）
  在**基础插件集**下只能解码 ogg/opus、wav、flac、vorbis，**不能解码 aac/m4a**（缺 good/bad/libav）；
  图片导入用 `file_selector`（GTK 原生对话框，不依赖 zenity）；**Linux 无应用内拍照**（camera 插件不支持）。
  选型结论：录音 ogg/Opus、播放 audioplayers、导入 file_selector。
- **JSON 全量写的性能上限**：每条变更全量序列化单笔记本文件。触发条件（单本条目过万 / 写入卡顿）出现时提前 M7，不为预防而提前。
- **旧原型数据**：`shared_preferences` 里的旧笔记为原型数据，M1 直接废弃不迁移；主题偏好重置为默认可接受。
- **写入并发**（M3 评审后已修）：`JsonFileStorage` 按路径串行化 + 唯一 tmp 名；修前实测并发写 120/120 轮 `PathNotFoundException`、300 轮中 1 轮静默丢数据，回归测试已固化（`json_storage_test.dart`）。
- **流渲染无虚拟化**：`SingleChildScrollView + Column` 全量构建，条目上千后需换 `ListView.builder`；与「JSON 全量写」同源，触发条件出现时一并处理。

## 5. 验收记录（§11 操作步数表，M5 + M6）

每行都对应一条自动化断言（媒体行随 M6 补齐）。一处例外：**换行行为在 widget 测试里无法真正验证**
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
| 清空 default（条目 + 媒体文件） | 3 | `test/ui/notebook_test.dart`「清空 default：确认文案含条数与媒体文件数，条目与媒体一并删除」 |
| 录一段音 | 2 | `test/ui/recording_test.dart`「点 🎤 进入录音态」「✓ 停止即保存」（1 步开录 + 1 步停止） |
| 查看/补录转写或摘要 | 2 + 输入 | `test/ui/media_menu_test.dart`（长按 → 菜单项 → 输入） |
| 相册导入一张 | 2–3 | `test/ui/photo_test.dart`「点 📷 选图 → 立即入流（成功路径，一次一张）」 |
| 拍一张照（应用内取景器） | — | Linux 无 camera 插件支持，随 Android（M8），N/A |

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

## 6.1 评审修复记录（M6）

| 编号 | 问题 | 修法 | 回归用例 |
|---|---|---|---|
| P1-1 | 录音态跨 State 销毁不被收尾（拖窗口跨 720 → 录音条消失、麦克风仍占用、临时文件成孤儿、可二次开录） | 录音会话上提为页面持有的 `RecordingSession` | `recording_test.dart`「录音中跨 720 布局切换…」「页面销毁时收尾…」 |
| P2-1 | 媒体菜单不符合 §8，且「编辑」写进永不显示的 `entry.text` | 菜单按类型给项 + 转写/摘要编辑弹层 + 摘要位点按即编辑 | `media_menu_test.dart`（5 项） |
| P2-2 | 并发点两条时「同一时刻只播一条」不成立且播放态标错行 | 意图同步落地 + 底层播放器操作串行化 | `playback_test.dart`「并发点两条…」 |
| P2-3 | 播放完成事件不区分条目，陈旧事件抹掉新起播条目的播放态 | 严格判定「完成事件只对真正装载的条目有效」 | `playback_test.dart`「陈旧的播放完成事件…」 |
| P3-1 | 不可播放时点按仍把行标成播放中 | `_handleTap` 校验 `available` 与文件存在 | 「不可播放时点按不会把行标成播放中」 |
| P3-2 | 播放中切笔记本：声音继续、界面无控件 | 切本时（帧后）`stopAll()` | 「播放中切笔记本：停止播放」 |
| P3-3 | 归档成功但写盘失败 → 孤儿文件 + 幽灵条目 + 清理指错路径 | `addMedia`/`importPhoto` 失败回滚（删文件、撤内存） | `media_test.dart`「归档成功但写盘失败…」 |
| P3-4 | 录音期间开录的笔记本被删 → 丢录音且内部 id 进文案 | 目标本不存在时落到当前本（同 §8 撤销回退语义） | `recording_test.dart`「录音期间开录的笔记本被删除…」 |
| P3-5 | `addMedia`/`importPhoto` 用 `putIfAbsent` 可能覆盖未加载笔记本的既有条目 | 改用 `_loadEntriesOf` | `media_test.dart`「写入未加载的笔记本不会覆盖其既有条目」 |
| P3-6 | `RecordingSession` 与录音器从不释放 | shutdown 后 dispose，并释放 recorder | 「页面销毁后录音器被释放」 |
| P3-7 | 导入时 `!mounted` 被当成「用户取消」，静默丢弃已选文件 | 导入不依赖 widget 存活（store 属于应用） | 成功路径用例 |
| P3-8 | 缩略图在 build 里做同步 stat | 存在性检查移入 State 缓存 | — |

M6 全段评审还列出 41 条文档漂移，已按「同一次提交内同步文档」的约定清零。

## 6.2 评审修复记录（M6 后：弹层路由归属）

M6 之后的整体复检（三路只读深审 + 探针实测）确认一类跨文件的 P1 导航竞态，
已修复并配「修复前会失败」的回归用例：

| 编号 | 问题 | 修法 | 回归用例 |
|---|---|---|---|
| P1-1 | `await` 之后 `Navigator.pop(sheetContext)` 只查 `mounted`：弹层若已因点遮罩 / 下滑 / Esc 进入退场动画，路由处于 `popping`——`mounted` 仍为 true，但它已不是 navigator 的 present 栈顶（Flutter 把 `popping` 明确列为 "routes that are not present"），`Navigator.pop` 于是选中**下面那条**路由，把 HomePage 弹掉 → 应用零路由、窗口空白；弹层若已整个销毁，还会抛「Looking up a deactivated widget's ancestor」 | 新增 `ui/sheet_nav.dart`：`sheetCloser(context)` 在 await **之前**捕获本弹层的路由，之后只在 `route.isCurrent` 时 pop。`notebook_list` 的 onDone（切换 / 新建 / 删除）与 `editor_sheet` 的三处保存 / 删除全部改走它 | `notebook_test.dart`「窄屏：切换写盘在途时关闭弹层，主界面不被弹掉」、`search_test.dart`「保存写盘在途时关闭弹层，主界面不被弹掉」 |

复现与验证记录（两处均实测）：

- 修复前：`pumpAndSettle()` 之后 `find.byType(HomePage)` 为 **0**（主界面被弹掉）；修复后为 1，且弹层仍正常关闭、切换/保存本身照常生效。
- 用 `GatedMemoryStorage`（`test/support/memory_storage.dart`）把「写盘在途」变成确定性窗口。
  刻意用 `Completer` 而不是 `Future.delayed`：widget 测试跑在 fake-async 区，真实 Timer
  不推进时钟就永不完成，`await store.xxx()` 这种不给 pump 的位置会直接**挂死**。
- 另一个测试写法坑（已记入 `AGENTS.md`）：断言「路由被弹掉」时 `pump(Duration(milliseconds: 400))`
  只走**一帧**，被 pop 的路由还没走完销毁、仍被 finder 找到 → **假绿**；必须用 `pumpAndSettle()`。
  本轮回归用例最初就是这么假绿的，改用 settle 后才在修复前如实变红。

## 6.3 评审修复记录（M6 后：跨 720 布局重建的 State 归属）

| 编号 | 问题 | 修法 | 回归用例 |
|---|---|---|---|
| P2-1 | 发送写盘在途时拖动窗口跨 720：InputBar 的 State 被重建，`_sending` 守卫归零，而新 State 从 `DraftStore` 读回**尚未清空的原文** → 输入框残留刚发出去的文字、➤ 重新可用，同一条文本入库两次（探针实测：写完 1 条，再点一次变 2 条） | 时间流与输入栏改为页面持有的 `GlobalKey`：跨宽窄时 Flutter 把元素**搬家**而不是重建，State 整体存活（发送/导入守卫、输入框内容、滚动位置、`_lastNotebookId/_lastCount` 基线） | `polish_test.dart`「写盘窗口内拖动窗口跨 720：草稿不残留、不重复入库」 |
| P2-2 | 跨 720 重建 StreamView：滚动位置与「已见基线」一起归零，新 State 首帧必判「切本了」而强制滚底——把窗口最大化 / 拉窄都会丢掉阅读位置（§4 只把「打开 / 发送 / 切本」列为滚底触发） | 同上（`_streamKey`） | `polish_test.dart`「跨 720 重建后滚动位置与按钮状态保持（不强制滚底）」 |

两条回归在修复前实测为红：滚动位置 `1632 → 2612`（= `maxScrollExtent`）、输入框残留 `'AAA'`。

写法备忘：「↓ 回到最新」按钮是**派生**状态（距底 > 一屏），视口变高后本就该隐藏——用例因此把
上翻距离取到 1200px，让这条判定在两套布局下都成立，而不是把派生值当不变量去断言；
另外「重建必须发生在写盘仍in-flight时」，所以跨 720 的那次 `pump()` **不能带时长**
（一带时长就把写盘计时器先跑完，竞态窗口消失、用例假绿）。

## 6.4 评审修复记录（M6 后：媒体渲染契约与解码尺寸）

| 编号 | 问题 | 修法 | 回归用例 |
|---|---|---|---|
| P2-1 | 录音文件丢失时音频行仍渲染成**可播放**（只判 `file != null`），点下去既没声音也没提示，违反 §10「音频行渲染为不可播放」 | 存在性判断收口到新增的 `Storage.mediaExists`（同步：文件型实现 stat、内存实现查登记表），`_AudioRow` 与点按路径都据此判定；结果缓存在 State，不在每帧 build 里查 | `playback_test.dart`「录音文件缺失：渲染为不可播放，点按不发起播放」 |
| P2-2 | 转写兜底只取首行**不截断**：一段没有换行的长转写会把整段铺进时间流，违背 §4「转写全文不进时间流」 | 只对**转写兜底**加 `maxLines: 2` + ellipsis；摘要（用户写的展示面）不截断 | `playback_test.dart`「转写兜底截断，摘要不截断（§4）」 |
| P2-3 | 缩略图 `Image.file` 未传 `cacheWidth` → 整幅解码原图（12MP ≈ 48MB 位图）；叠加「时间流无虚拟化」＝首帧为所有照片发起解码，ImageCache 反复淘汰重解码 | 按目标显示尺寸解码：`LayoutBuilder` 的约束（已是 60% 列宽）× dpr 作为 `cacheWidth` | `photo_test.dart`「缩略图按显示尺寸解码（cacheWidth），不整幅解码原图」 |

顺带统一口径：照片缩略图与全屏查看器也改走 `store.mediaExists`，UI 不再直接摸文件系统
（此前照片走 `dart:io`、录音完全不查：两套口径，且内存测试存储无法表达「文件在不在」）。

三条回归在修复前实测为红：`maxLines` 为 null、图标取 primary 色、provider 是 `FileImage` 而非 `ResizeImage`。

## 6.5 评审修复记录（M6 后：写盘失败的回滚与可见性）

| 编号 | 问题 | 修法 | 回归用例 |
|---|---|---|---|
| P2-1 | 写盘失败不回滚内存：`addText` / `_replaceEntry` / `deleteEntry` / `restoreEntry` 都是「先改内存再落盘」，失败后内存有、磁盘无 → 下一次任意通知「幽灵条目」就冒出来，重启又消失。`addMedia`/`importPhoto` 早有回滚（M6 P3-3），core 内两套口径 | core 统一走 `_mutateAndSave(notebookId, list, mutate)`：先备份、变更、落盘，失败**原地回滚**（clear + addAll，保持列表对象身份）后 rethrow；`createNotebook`/`renameNotebook` 同样失败回滚 | `store_test.dart`「addText 失败：抛错且不留在内存」「编辑与删除失败：内存回到改动前」 |
| P2-2 | 失败对用户不可见：`input_bar._send` 只有 `try/finally` 没有 catch，异常逃到 zone，输入框还留着原文——用户分不清「发出去了」还是「没发出去」，容易重复发 | 发送 / 编辑保存 / 删除条目 / 删除笔记本 / 新建重命名 / 主题设置全部补 catch + 可读 SnackBar；失败时**不关弹层、不清输入框**，内容留在原位可重试 | `polish_test.dart`「写盘失败：给可读提示并保住输入框原文」 |
| P2-3 | `deleteNotebook` 跨 5 处 await 改内存：中途失败会留下「条目已并、笔记本还在」或「内存已删、磁盘还在」的半状态 | 重排为「三份文件全部落盘成功后再改内存」；default 的条目列表改为**原地更新**，不再替换对象（顺带消掉 M6 评审 P3-1 里「撤销捕获旧列表对象」的隐患） | 既有删除笔记本用例 + §6.2 的撤销用例 |

三条回归在修复前实测为红：`entries` 里留着幽灵条目、文本变成了「改后」、找不到「保存失败」提示。

## 6.6 评审修复记录（M6 后：存储与启动兜底的健壮性）

| 编号 | 问题 | 修法 | 回归用例 |
|---|---|---|---|
| P2-1 | 启动扫描自身失败会拦下整个启动：`quarantineCorruptFiles` 的首个 `try` 只 catch `FormatException`，`readAsString` 的 EACCES/EIO 直接漏出；`loadStoreResilient` 里的扫描调用又在 `try` 之外——「数据目录里有一个读不了的文件」= 应用打不开（违反 §10） | 分层两道：逐文件兜底（单个文件读不了/改不了名只跳过，`dir.listSync` 失败直接返回空）+ `loadStoreResilient` 里扫描整体 try/catch（已加载的数据照常可用） | `startup_test.dart`「隔离自身抛错：照常以已加载数据启动」、`json_storage_test.dart`「单个文件读不了：跳过它继续扫」 |
| P2-2 | `deleteEntries` 绕过按路径写队列：删除会插到在飞的写入之前，写落地后 `nb_<id>.json` 又冒出来（僵尸文件，里面留着已并入 default 的条目） | 队列泛化为 `_enqueueFor(file, action)`，写与删排同一条队列 | `json_storage_test.dart`「删除与写入排同一条队列：写入在飞时删除不会被复活」 |
| P3-1 | 启动扫描对每个数据文件读两遍、`jsonDecode` 两遍 | 只读一次、解析一次，把结果传给结构校验分支 | 既有扫描用例 |

三条回归在修复前实测为红：`FileSystemException` 逃出启动路径、`nb_x.json` 被复活成 true、单文件读不了时扫描抛错。

## 6.7 复检补测（M6 后：三处语义空洞）

复检用变异实验找出三条「实现改坏、全套仍绿」的空洞，本批补齐（只动测试，不动行为）：

| 编号 | 空洞 | 补法 | 变异验证 |
|---|---|---|---|
| T-1 | 照片搜索命中面：旧断言用的查询词是**条目 id**，而 id 从来不是搜索字段——恒真，什么都没验到 | 给照片条目同时写入 `transcript` 与 `file`，断言转写、文件路径、id 都不命中，摘要命中 | 变异「照片也匹配转写」→ 用例红 |
| T-2 | 「撤销回**原**笔记本」没有用例（只有「原本已删 → 落当前本」） | 新增：A 删 → 建 B 切过去 → 撤销必须回 A，且不改变当前笔记本、归属落盘 | 变异「restoreEntry 恒落当前本」→ 用例红 |
| T-3 | 「退出搜索恢复滚动位置」用例进出之间没有任何 store 变更，位置本来就不会变 | 搜索期间删除一条（条目数变化会触发 §4 的滚底判定），再断言位置不变 | 变异「去掉搜索态滚底抑制」→ 本用例与兄弟用例一起红 |

## 6.8 功能变更（default 清空）

| 变更 | 说明 | 用例 |
|---|---|---|
| `default` 增加「清空」 | `default` 不可删除、不可重命名（§2 不变式），但它需要一条「推倒重来」的出口：菜单里只给「清空」。确认文案写明「N 条记录将被永久删除，M 个媒体文件也会一并删除。此操作不可撤销」，确认后条目与它们引用的媒体文件**一并删除**（顺手消掉一批未来会变成孤儿媒体的文件）。空笔记本时确认按钮置灰 | `notebook_test.dart`「default 的菜单只有「清空」…」「清空 default：确认文案含条数与媒体文件数，条目与媒体一并删除」（含「取消则什么都不动」与落盘断言） |

core 侧新增 `AppStore.clearNotebook`（先落盘空条目、成功后再逐个删媒体；条目落盘失败则回滚内存且一个文件都不删）
与 `mediaFileCountOf`（只数**仍然存在**的媒体文件，确认文案不说假话）。UI 只对 `default` 暴露清空：
其它笔记本用「删除笔记本」，语义是条目并入 default 而非销毁。

变异验证：去掉媒体删除循环 → 用例红（`media/….png` 仍留在登记表里）。

## 6.9 功能变更（设置改为独立整页）

| 变更 | 说明 | 用例 |
|---|---|---|
| 设置从底部弹层改为独立整页 | 弹层的扩展性差（导出、媒体清理、AI 接入都要放这里），改为 `Scaffold` 整页，宽窄屏一致；加分区只需往 `ListView` 里追加。页面自己持有 `CoreListenableBridge` 并在 `dispose` 释放，主题切换仍即时生效 | 新增 `settings_test.dart`：窄屏顶栏 ⚙ 打开 → 切「深色」→ 返回壳；宽屏侧栏「设置」打开 → 切「浅色」并断言落盘 |

顺带补上一直缺的设置页 widget 测试（复检指出「settings_view.dart 整体无测试」）。
入口不变（§11 步数不受影响：设置不在操作步数表里）。

## 7. 待办与开放问题（登记，勿遗忘）

- **无主媒体清理**：删除条目不删媒体文件（撤销窗口内仍需要它，见 `AppStore.deleteEntry`），
  因此长期使用会留下不再被任何条目引用的 `media/*.ogg|png`。需要一个「清理无主媒体」的
  入口或后台任务；`media/.tmp/*` 的孤儿同理（正常路径已清，异常退出可能残留）。
  另：「归档成功但写盘失败」的孤儿已由 `addMedia`/`importPhoto` 的失败回滚处理（删除已归档文件
  并回滚内存），但**进程被强杀**这类路径仍可能留文件。
- 真实 Linux IM 路径下的 Enter 发送（widget 测试走框架内 key 分发，不等于真实输入法）。
- 流渲染无虚拟化（`SingleChildScrollView + Column`），条目上千需换 `ListView.builder`。
- JSON 全量写的性能上限 → 触发时提前做 M7（SQLite）。
- 输入栏草稿仅内存（重启即失），如需持久化再定。
- **真机手动核对**：应用内完整链路（录音 → 播放；选图 → 缩略图 → 查看器）尚未在真机手点过；
  插件层已由 M6 spike 与构建验证，widget 层因 fake-async 限制不覆盖真实文件 I/O。
- **多实例无数据目录锁**（复检登记，未修）：写队列与唯一 tmp 名都是**进程内**的，
  两个实例同时开着会各自全量覆盖写，后写覆盖前写 → 一边新记的条目静默消失
  （`linux/runner/my_application.cc` 用的是 `G_APPLICATION_NON_UNIQUE`）。
  需要一次设计决策（第二实例转只读？给错误界面？聚焦已有窗口？），且 POSIX `fcntl`
  锁在**同进程内不互斥**，用本项目的测试方式无法覆盖，得靠子进程或真机手测。
  修之前：别同时开两个实例。

