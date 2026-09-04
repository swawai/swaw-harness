# Core Host

## Scope

本文件适用于 `core/host/`，Rule ID 前缀为 `CORE-HOST`。

## Accepted

- **CORE-HOST-001 — Host 只组合稳定边界。** Core Host 自身是 Admin 用户共享的 `swaw/core/host` Module Release；同一不可变 executable 可以启动多个进程，但每个进程只服务启动参数指定的一个 Harness 用户。Core Host 只负责接收该用户的调用、解析技能调用目标和该用户的 Core 技能图、为 `/.help` 生成只读完整技能路径列表，或为普通节点验证共享 Module Release、建立 Run、监督模块进程和回传结果；模块领域行为仍由独立 Module Release 拥有。
- **CORE-HOST-002 — 当前 Windows 实现只支持批处理调用。** 一次命名管道连接只承载一次命令；模块 stdin 固定关闭，调用 stdout、UTF-8 文本 stdout、调用 stderr、退出码以及已建立 Run 才具有的 RunId 元数据使用不同响应帧返回，不提供交互终端、PTY、HTTP 或 WebSocket。当前包含 UTF-8 文本 stdout 的不兼容响应帧集合使用 v3 管道和互斥体端点，避免新版用户 CLI 误连仍驻留的 v1 或 v2 Core Host。
- **CORE-HOST-003 — 调用只来自受信技能声明。** 调用方只提交技能调用目标与动态参数，不得提交 executable 路径；Core Host 必须通过 `core/protocol` 分离 SkillMapId、可选 SkillPath 和 NodeMethod。省略显式选择器的 `node` 方法必须验证非空 SkillPath、目标 `skill.toml` 和已安装 Module Release 后才能建立 Run 与进程；`/.help` 只可读取有界技能树描述，不得选择 Module Release、建立 Run 或创建进程。未知点号选择器必须拒绝，`/.tree`、`/.tree.parent-success`、`/.tree.no-structure` 与 `/.plan` 必须明确报告尚未实现，不得把它们退化为真实 SkillPath。
- **CORE-HOST-004 — 模块进程树受 Host 监督。** Windows Core Host 必须在恢复模块主线程前把进程加入启用 `KILL_ON_JOB_CLOSE` 的独立 Job Object；调用方断开或 Host 退出时不得遗留该调用的模块进程树。
- **CORE-HOST-006 — 普通用户启动受生命周期约束。** 固定 Admin 用户不使用 `user.json`；其他 UserId 的 Core Host 冷启动前必须读取该 UserHome 根下的严格 `swaw.harness.user/v1` 记录，并验证 `<DataHome>/<UserId>.exe` 是名称规范、非 reparse 且长度和 SHA-256 与记录一致，只有身份匹配且生命周期为 `active` 时才可建立命名管道。该检查只确认创建已提交，不构成 SkillPath、模块或管理操作授权。
- **CORE-HOST-007 — Host 拥有单节点 Run 生命周期。** Core Host 必须为每次通过验证的单节点执行生成新的小写 32 位十六进制 UUIDv7 RunId，排他建立 `<UserHome>/runs/<RunId>/`，先写 `swaw.harness.run/v1` 的 `run.json` 和 `<SkillMapId>/<SkillPath>/` 运行节点目录，再通过独立响应帧返回同一个 RunId，最后把该节点目录作为模块进程工作目录。`run.json` 的初始 `running` 结果和最终 `completed` 或 `failed` 结果必须以完整 JSON 保存，最终结果通过同目录暂存文件原子替换；不得把 RunId 交给模块自行生成，也不得把结构化日志协议混入 stdout/stderr 转发。

## Open

- **CORE-HOST-005 — 后台任务与历史运行操作。** 当前只为前台单节点执行保存 `run.json` 和运行节点目录；后台任务查询、跨 Host 重连、历史 Run 选择、重播、重试和保留清理尚未实现，首次真实长任务或历史运行操作出现前不得扩展当前单次连接协议。
