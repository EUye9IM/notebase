# Notebase

本地优先的多媒体笔记数据库，支持语义搜索与自动分类。

> 当前阶段聚焦应用框架：零外部依赖、完全离线的本地笔记应用，PC 桌面端 + Android 双端交付。

## 技术栈

| 层 | 选型 | 说明 |
|----|------|------|
| UI | Flutter | PC 桌面端（Windows / macOS / Linux）+ Android，一套代码 |
| 数据库 | SQLite（`sqlite3` 包） | Dart FFI 直连原生 SQLite，FTS5 / WAL / 扩展加载全支持，零依赖 |
| 状态管理 | Phase 1 内选型 | 框架搭建时确定（倾向 Riverpod） |
| 网络 / AI | 暂不引入 | 无任何网络调用与模型，整体后置，见阶段设计与架构决策 |

## 阶段设计

### Phase 1 — 应用框架与本地笔记（🚧 当前）

**目标：** 搭好双端应用框架，交付零外部依赖、完全离线可用的本地笔记应用。

**包含：**

- 项目骨架：一套 Flutter 代码同时构建 PC 桌面端（Windows / macOS / Linux）与 Android
- 应用框架：路由、导航骨架（宽屏侧边栏 / 窄屏底部导航）、主题、状态管理
- 本地 SQLite：笔记的创建、编辑、删除、列表（SQL 访问收口到 repository 层）
- 本地搜索：基于 SQL LIKE 的简单检索（FTS5 后置）
- 设置页：主题等本地偏好

**不包含：**

- 任何网络调用与 AI 模型（嵌入、语义搜索、自动分类、图片描述全部后置）
- 图片 / 音频 / 视频附件
- 标签管理
- 跨设备同步

### Phase 2 — 富内容与本地增强

- FTS5 全文检索（含中文分词方案）
- 标签管理
- 图片附件：导入、缩略图（纯本地处理）
- 拍照 / 相册导入（Android）
- 数据导出（Markdown / JSON）

### Phase 3 — AI 能力（远程 API）

- 远程 AI API 配置（OpenAI 兼容 endpoint，支持 OpenAI / 智谱 / 硅基流动等）
- 文本嵌入 + 余弦相似度语义搜索（brute-force 起步，升级 sqlite-vec）
- 全文检索与向量搜索混排
- 零样本自动标签 / 分类
- 图片描述（Vision API）→ 与文字统一搜索空间
- 嵌入模型版本管理、离线回填队列（local-first 核心约束）

### Phase 4 — 本地模型

- Ollama 后端（通过局域网连接本地算力）
- ONNX 小模型内置回退（离线可用）
- `Embedder` 抽象类多后端自动切换（Ollama 走 HTTP；本地 ONNX 优先评估 sherpa-onnx / onnxruntime 的 Flutter 插件）

### Phase 5 — 扩展媒体类型

- 音频：本地 Whisper 转录 → 文本嵌入
- 视频：关键帧抽取 → 图片嵌入（性能不足时按「架构决策」引入 Rust 模块）

### Phase 6 — 跨设备同步

- CRDT 数据同步
- 可选同步服务

## 架构决策

### 零外部依赖起步

当前阶段无任何网络调用、无 AI 模型、无第三方服务，无需账号与 API key，应用完全离线可用。AI 能力整体后置到 Phase 3，并保持可插拔：搜索走统一接口，LIKE 实现与未来的向量实现可替换。

### 纯 Dart 先行，Rust 按需引入

业务逻辑全部用 Dart 实现：SQLite 经 `sqlite3` 包 FFI 直连原生 C 库（与 rusqlite 同一底座），schema、FTS5、数据文件与任何未来 Rust 方案完全通用；SQL 访问收口在 repository 层。

Rust 不排除，但只为单一重负载模块引入（经 flutter_rust_bridge），命中以下任一条件时再评估：

1. 本地 ONNX / Whisper 推理在现有 Flutter 插件（sherpa-onnx、onnxruntime）下性能不足；
2. 视频 / 音频管线需要 Rust 级别的性能或内存控制；
3. 向量规模超过 10 万条且 sqlite-vec 扩展不够用，需要自研索引。

数据库永远留在 Dart 侧，引入 Rust 模块不需要迁移数据层。

## 当前阶段待办（Phase 1）

- [x] 项目脚手架：Flutter 模板，Linux 桌面端构建运行验证（Android 构建待装 SDK 后验证）
- [ ] 状态管理选型，搭建路由与导航骨架（宽屏侧边栏 / 窄屏底部导航）
- [ ] 数据库层：schema 与迁移、笔记 CRUD（SQL 访问收口到 repository 层）
- [ ] 核心页面：首页列表、笔记编辑器、搜索页（LIKE）、设置页
- [ ] 本地偏好存储：主题等应用设置

## 开发

### 环境要求

- Flutter SDK（建议当前 stable）
- Android 构建需 Android Studio / Android SDK

### 快速启动

```bash
flutter pub get
flutter run -d windows   # 或 macos / linux / android
```

### 项目结构

```
notebase/
├── lib/                    # Dart 应用
│   ├── db/                 # schema、迁移、repository 层（SQL 访问收口）
│   ├── models/             # 数据模型（Note 等）
│   ├── screens/            # 页面（列表、编辑器、搜索、设置）
│   ├── widgets/            # 组件
│   ├── services/           # 本地服务（偏好存储等）
│   └── main.dart           # 入口：主题、路由、导航骨架
├── android/                # Android 工程
├── windows/ macos/ linux/  # 桌面工程
├── pubspec.yaml            # Flutter 依赖配置
└── README.md
```

## License

MIT
