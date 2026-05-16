# Notebase

本地优先的多媒体笔记数据库，支持语义搜索与自动分类。

## 技术栈

| 层 | 选型 | 说明 |
|----|------|------|
| UI | Flutter | iOS / Android / macOS / Windows / Linux |
| 核心引擎 | Rust | 数据库、AI 调用、媒体处理 |
| FFI 桥接 | flutter_rust_bridge v2 | Rust ↔ Dart 类型安全绑定 |
| 数据库 | SQLite (rusqlite) | 零依赖，本地存储 |
| AI 模型 | 远程 API（OpenAI 兼容协议） | 文本嵌入、图片描述、自动分类 |
| 向量搜索 | 余弦相似度 brute-force | 初版够用，后续升级 HNSW |

## 阶段设计

### Phase 1 — 原型：核心笔记 + 远程 AI（🚧 当前）

**目标：** 验证整体技术路线，交付最小可用版本。

**包含：**

- 文本笔记的创建、编辑、删除、列表
- 配置远程 AI API（OpenAI 兼容 endpoint，支持 OpenAI / 智谱 / 硅基流动等）
- 通过远程 API 生成文本嵌入，自动存储到 embeddings 表
- 基于余弦相似度的语义向量搜索
- 零样本自动标签/分类（候选标签文本嵌入匹配）
- 图片附件（Vision API 生成图片描述 → 文本嵌入，图片与文字统一搜索空间）
- 缩略图生成
- SQLite FTS5 全文检索
- 桌面端 Flutter UI（macOS / Windows / Linux）

**不包含：**

- 本地模型（Ollama / ONNX）
- 移动端完整适配
- 跨设备同步
- 音频 / 视频
- 插件系统

### Phase 2 — 移动端适配

- 响应式 UI 适配手机 / 平板
- 拍照 / 相册导入
- 离线降级策略（无 API 时的功能限制提示）

### Phase 3 — 本地模型

- Ollama 后端（通过局域网连接本地算力）
- ONNX 小模型内置回退（离线可用）
- `Embedder` trait 多后端自动切换

### Phase 4 — 扩展媒体类型

- 音频：本地 Whisper 转录 → 文本嵌入
- 视频：关键帧抽取 → 图片嵌入

### Phase 5 — 跨设备同步

- CRDT 数据同步
- 可选同步服务

## 原型阶段待办

- [ ] 项目脚手架：Flutter + Rust 项目模板，bridge 编译验证
- [ ] 数据库层：schema 迁移、笔记 CRUD、标签管理、媒体记录
- [ ] 远程 API 嵌入层：`Embedder` trait + `RemoteEmbedder`（文本嵌入、Vision 描述、零样本分类）
- [ ] 配置管理：API endpoint / key / model 的读写
- [ ] 搜索：FTS5 全文检索 + 向量余弦相似度 + 混排
- [ ] 图片管理：导入、缩略图、AI 描述嵌入
- [ ] Flutter UI：首页列表、笔记编辑器、搜索页、标签管理、设置页、首次启动向导

## 开发

### 环境要求

- Flutter SDK >= 3.22
- Rust >= 1.85
- `flutter_rust_bridge_codegen`

### 快速启动

```bash
# 安装代码生成器
cargo install flutter_rust_bridge_codegen

# 生成 Rust ↔ Dart FFI 绑定
flutter_rust_bridge_codegen generate

# 运行桌面端
flutter run -d macos    # 或 linux / windows
```

### 项目结构

```
notebase/
├── rust/                 # Rust 核心库
│   └── src/
│       ├── db/           # SQLite schema 与迁移
│       ├── embedder/     # Embedder trait + 远端 API 实现
│       ├── media/        # 图片存储、缩略图
│       └── api/          # flutter_rust_bridge 暴露的公开 API
├── lib/                  # Flutter/Dart UI
│   ├── screens/          # 页面
│   ├── widgets/          # 组件
│   └── services/         # Rust FFI 调用封装
├── pubspec.yaml          # Flutter 依赖配置
└── README.md
```

## License

MIT
