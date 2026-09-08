# Notebase

本地优先的快速笔记本：打开即记，一条一档（文字 / 语音 / 拍照），按笔记本分组，完全离线。

> 当前阶段（初版）：只做**文本条目**的完整闭环——笔记本、时间流、本地搜索，仅 Linux 桌面端；UI 与核心分离，为多平台留好分层。多媒体与 AI 整体后置。
>
> 设计文档：[docs/ui-design.mdx](docs/ui-design.mdx)（交互设计与验收标准）· [docs/dev-plan.md](docs/dev-plan.md)（开发计划与里程碑）

## 技术栈

| 层 | 选型 | 说明 |
|----|------|------|
| UI | Flutter | Linux 桌面端先行；Android 工程已预留，多平台后置 |
| 核心 | 纯 Dart，零 Flutter 依赖 | 模型 / 存储 / 搜索 / 状态，全部在 `lib/core/`，可脱离 Flutter 测试与复用 |
| 存储 | JSON 文件（`Storage` 接口收口） | `notebooks.json` + `nb_<id>.json` + `prefs.json`；SQLite 迁移后置（M7） |
| 状态 | 自实现最小 `Listenable` | 不依赖 flutter/foundation，core 保持纯净 |
| 多媒体 | 后置（M6） | 录音 / 播放 / 拍照 / 相册导入，届时验证 Linux 插件成熟度 |
| 网络 / AI | 暂不引入 | 后置到 Phase 3；转写 / 摘要字段已预留，先支持手动编辑 |

## 阶段设计

### Phase 1 — 文本速记闭环（🚧 当前）

**目标：** Linux 桌面端交付可日常使用的纯文本快速笔记应用。

**包含：**

- 核心层：`Entry` / `Notebook` 模型（预留媒体字段）、JSON 持久化、包含匹配搜索
- 时间流：按天分组的追加式时间线 + 常驻底部输入栏，文本 2 步录入（宽屏 Enter 1 步）
- 笔记本：default 永存不可删；创建 / 切换 / 重命名 / 删除（条目并入 default）
- 搜索：当前笔记本内，原地过滤，命中正文
- 条目：编辑（底 sheet，无确认）、删除（确认 + 5s 撤销）
- 主题：跟随系统 / 浅色 / 深色

**不包含：** 拍照、录音、AI、同步、Android 构建。

### Phase 2 — 多媒体与存储升级

- 录音（record / 播放）、拍照 / 相册导入、媒体文件管理
- 转写 / 摘要的手动编辑（模型字段已预留）
- 存储迁移 SQLite（`sqflite` + `sqflite_common_ffi`）+ FTS5 全文检索
- 数据导出（JSON / Markdown）

### Phase 3 — AI 能力（远程 API）

- 录音自动转写 → 摘要，照片自动描述：异步生成、失败可重试，绝不阻塞录入；**用户编辑过的内容视为定稿**，不被自动生成覆盖
- 文本嵌入 + 语义搜索、全文与向量混排、自动标签
- OpenAI 兼容 endpoint（OpenAI / 智谱 / 硅基流动等）

### Phase 4+ — 本地模型 / 跨设备同步（远期）

- Ollama / ONNX 本地推理回退；CRDT 同步

## 架构决策

### UI 与核心分离

`core/` 纯 Dart，禁止 import 任何 `package:flutter/**`；`ui/ → core/` 单向依赖。收益：核心逻辑可用纯 Dart 测试（快、稳）；未来扩展平台（Android、其他前端）或替换 UI 框架时核心不动。平台能力（应用目录、权限）由 UI 层取得后注入 core。

### 零外部依赖起步

无网络调用、无 AI、无账号，完全离线。AI 后置但可插拔：搜索、摘要生成走统一接口，手动实现与自动实现可替换。

### 纯 Dart 先行，Rust 按需引入

业务逻辑全部 Dart；SQLite 经 `sqflite` 走 FFI。Rust 只在本地推理 / 媒体管线性能不足时再评估（flutter_rust_bridge），数据库永远留在 Dart 侧。

## 当前阶段待办（Phase 1）

- [x] M1 核心层：模型 / JSON 存储 / 搜索 + 纯 Dart 单测（替换旧 `store.dart`，废弃 `shared_preferences`）
- [x] M2 时间流 + 文本录入：宽 / 窄应用壳、按天分组、空态、自动滚底
- [ ] M3 笔记本管理：切换 / 新建 / 重命名 / 删除（条目并入 default）
- [ ] M4 搜索 + 条目编辑 / 删除（撤销）
- [ ] M5 打磨：回到最新、键盘行为、边界情况、release 自测
- [ ] 全量验收：analyze 0 issue + 测试绿 + 操作步数表核对

## 开发

### 环境要求

- Flutter SDK（stable）
- Linux 桌面构建需 GTK / Ninja 工具链（`flutter doctor` 自查）
- Android 后置（SDK 未装，工程已预留）

### 快速启动

```bash
flutter pub get
flutter run -d linux
flutter test          # core 层为纯 Dart 测试，不依赖桌面环境
```

### 项目结构

```
notebase/
├── lib/
│   ├── core/               # 纯 Dart：模型、状态、Storage 接口与 JSON 实现
│   └── ui/                 # Flutter：应用壳、时间流、输入栏、搜索、设置
├── docs/
│   ├── ui-design.mdx       # 交互设计（含 §11 操作步数验收表）
│   └── dev-plan.md         # 开发计划（里程碑 M1–M5，多媒体后置）
├── test/                   # 测试（core 单测不 pump widget）
├── android/                # Android 工程（后置，已预留）
├── linux/                  # Linux 桌面工程（windows / macos 已裁剪，需要时 flutter create 补回）
└── pubspec.yaml
```

> 注：`lib/main.dart` + `lib/store.dart` 是 Phase 0 的旧三 Tab 原型，M1/M2 期间按上述结构替换。

## License

MIT
