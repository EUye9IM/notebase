# notebase

一个Rust实现的基于Rag技术的笔记库，提供基本的文本/图片管理与自然语言检索。

---

## 设计概览

### 架构
- **单进程 + 后台守护进程（daemon）**：前台CLI接受命令后立即退出，向量计算、模型推理等耗时操作由后台daemon异步处理。
- **进程间通信（IPC）**：
  - Unix（Linux/macOS）：Unix domain sockets（`/tmp/notebase.sock`）
  - Windows：Named pipes（`\\.\pipe\notebase`）
  - 使用 `interprocess` 库实现跨平台抽象，统一为双工字节流协议。
- **通信协议**：简单的二进制协议（长度前缀 + JSON/MessagePack），支持请求‑响应与异步通知。

### 模型与嵌入
- **初期实现**：依赖外部API（如OpenAI Embeddings、Ollama），便于快速验证。
- **可插拔设计**：定义 `Embedding` 与 `Chat` trait，未来可接入本地模型（`llm`、`candle`、`sentence‑transformers` 等）。
- **图片处理**：使用多模态模型（如Qwen‑VL）生成文本描述，再对描述进行嵌入。若资源受限，可降级为CLIP嵌入或仅存储图片路径。
- **长文本处理**：超过阈值（如512 token）的文本先经聊天模型（如Qwen3.5‑0.8B）生成摘要，再对摘要嵌入。支持分块嵌入作为备选方案。

### 检索算法
- **向量相似度**：使用余弦相似度计算查询向量与存储向量的匹配度。
- **阈值策略**：动态阈值 = 平均相似度 + α × 标准差（α可配置），同时返回top‑k结果（k可配置）。
- **索引**：初期使用线性扫描，后续可引入ANN索引（如HNSW、FAISS）提升性能。

### 数据存储
- **SQLite**：存储元数据（ID、路径、类型、创建时间等）和向量（BLOB）。
- **向量表**：`embeddings (id, note_id, vector BLOB, ...)`。
- **笔记表**：`notes (id, content_type, raw_content, processed_content, ...)`。
- **支持增量更新与版本迁移**。

### 配置与错误处理
- **配置文件**：`~/.config/notebase/config.toml`，定义模型端点、API密钥、阈值参数、IPC路径等。
- **错误处理**：daemon崩溃后自动重启，客户端重连机制，操作幂等性保证。
- **资源限制**：可配置并发请求数、内存上限、队列长度。

### 命令设计
```
nb add <path|text>        # 添加笔记（文件或直接文本）
nb list [--limit N]       # 列出最近笔记
nb find <query> [--top-k] # 自然语言检索
nb show <id>              # 显示笔记详情
nb mod <id> <new_content> # 修改笔记
nb delete <id>            # 删除笔记
nb serve                  # 启动后台daemon（若未运行）
nb status                 # 查看daemon状态
nb stop                   # 停止daemon
```

### 移动端部署考虑
- 目标平台：iOS / Android（通过 `flutter_rust_bridge` 编译Rust核心库）。
- 资源适配：模型需量化（GGUF），嵌入向量尺寸压缩，SQLite作为本地存储。
- 网络降级：移动端优先使用本地模型，无网络时仍可检索。

---

## TODO（优先级排序）

1. **IPC基础**：实现跨平台的进程间通信层（`interprocess`），定义简单协议。
2. **daemon框架**：构建后台守护进程，支持任务队列、状态管理。
3. **外部API集成**：接入OpenAI Embeddings（或Ollama）进行文本嵌入。
4. **SQLite存储**：设计数据库表结构，实现笔记与向量的CRUD。
5. **CLI命令**：实现 `add`、`list`、`find` 等基本命令。
6. **图片处理**：集成多模态模型（Qwen‑VL）生成描述，或使用CLIP嵌入。
7. **长文本摘要**：接入聊天模型（Qwen3.5‑0.8B）进行摘要生成。
8. **检索优化**：实现动态阈值策略，引入ANN索引。
9. **配置管理**：读取/写入TOML配置，支持环境变量覆盖。
10. **错误恢复**：daemon崩溃重启、客户端重连、操作幂等。
11. **移动端桥接**：研究 `flutter_rust_bridge`，编译核心库到移动平台。

---

## 注意事项
- **跨平台兼容性**：IPC路径、文件锁、信号处理需在不同OS上测试。
- **模型依赖**：外部API需网络，离线场景需降级到本地模型（后续实现）。
- **性能监控**：daemon应记录请求耗时、队列长度等指标，便于调优。
- **安全**：IPC通信本地仅限，但若暴露网络接口需加密认证。



