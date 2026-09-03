# Core Host

## Scope

本文件适用于 `core/host/`，Rule ID 前缀为 `CORE-HOST`。

## Accepted

- **CORE-HOST-001 — Host 只组合稳定边界。** Core Host 自身是 Admin 用户共享的 `swaw/core/host` Module Release；同一不可变 executable 可以启动多个进程，但每个进程只服务启动参数指定的一个 Harness 用户。Core Host 只负责接收该用户的调用、解析该用户的 Core 技能图、验证共享 Module Release、监督模块进程和回传结果；模块领域行为仍由独立 Module Release 拥有。
- **CORE-HOST-002 — Windows v1 只支持批处理调用。** 一次命名管道连接只承载一次命令；模块 stdin 固定关闭，stdout、stderr 与退出码分别返回，不提供交互终端、PTY、HTTP 或 WebSocket。
- **CORE-HOST-003 — 调用只来自受信技能声明。** 调用方只提交 SkillPath 与动态参数，不得提交 executable 路径；Core Host 必须通过 `core/protocol` 验证目标 `skill.json` 和已安装 Module Release 后才可创建进程。
- **CORE-HOST-004 — 模块进程树受 Host 监督。** Windows Core Host 必须在恢复模块主线程前把进程加入启用 `KILL_ON_JOB_CLOSE` 的独立 Job Object；调用方断开或 Host 退出时不得遗留该调用的模块进程树。
- **CORE-HOST-006 — 普通用户启动受生命周期约束。** 固定 Admin 用户不使用 `user.json`；其他 UserId 的 Core Host 冷启动前必须读取该 UserHome 根下的严格 `swaw.harness.user/v1` 记录，并验证 `<DataHome>/<UserId>.exe` 是名称规范、非 reparse 且长度和 SHA-256 与记录一致，只有身份匹配且生命周期为 `active` 时才可建立命名管道。该检查只确认创建已提交，不构成 SkillPath、模块或管理操作授权。

## Open

- **CORE-HOST-005 — 运行记录与后台任务。** 本地持久运行记录、后台任务查询和跨 Host 重连尚未实现；首次真实长任务出现前不得扩展当前单次连接协议。
