# Windows Core Host Bootstrap Adapter

## Scope

本文件适用于 `bootstrap/windows/host/`，Rule ID 前缀为 `WIN-HOST`。

## Accepted

- **WIN-HOST-001 — 只适配 Windows 产品构建。** 本目录只拥有 `core/host/` 的 Windows Bootstrap 构建 Contract 与 Candidate 生成；通用 Module Release 初始物化和 Admin Core Host 版本指针初始化归 `bootstrap/windows/` 根编排，Core Host 运行行为归 `core/host/`。
- **WIN-HOST-002 — Core Host 模块身份固定。** `contract.json` 必须精确声明 ModuleId `swaw/core/host`、`MAJOR.MINOR.PATCH` 版本、PlatformTargetId 与 `swaw-harness-core.exe`；不得声明 Core Host 专用 ReleaseId 或另一套发布目录。
- **WIN-HOST-003 — Candidate 只运输 executable。** Core Host Candidate 只包含 `swaw-harness-core.exe`，与同次启动构建的其他 executable 一起进入 Bootstrap Release；`swaw-harness.module.json` 只在通用 Module Release 初始物化时生成。

## Open

- **WIN-HOST-004 — 活跃 Host 升级。** 当前只定义首次初始化及后续冷启动选择；运行中 Host 的排空、重启、回退和旧版本清理留待真实升级流程实现。
