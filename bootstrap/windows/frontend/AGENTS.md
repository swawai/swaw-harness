# Windows 管理前端

## Scope

本目录拥有 Harness 管理 CLI executable、Harness GUI executable 及其共享 Rust frontend library；两个 frontend 都不拥有 UserHome 布局或 Harness 用户生命周期实现，Harness 管理 CLI executable 必须把用户管理操作委托给固定 Admin 用户，Harness GUI executable 必须委托同级 Harness 管理 CLI executable。Rule ID 前缀为 `FRONTEND`。

## Accepted

- **FRONTEND-001 — Frontend 不写 DataHome。** Harness 管理 CLI executable 与 Harness GUI executable 不得创建、修改或删除用户 CLI executable、UserHome、Runtime Release、selector 或 Harness 用户受管记录，也不得复制 Admin Core module executable 的用户生命周期实现。
- **FRONTEND-002 — GUI 委托 console frontend。** Harness GUI executable 必须通过同级 `swaw-harness-cli.exe` 请求 Harness 用户管理操作，不得直接启动 Admin Core module executable 或把 UserId、环境变量当作授权凭据。

## Open

当前无。

## Maintainer Notes

- 待办：当前 Harness 管理 CLI executable 与 Harness GUI executable 只实现独立界面占位、共享 library 构建并参与统一 Bootstrap Release；在固定 Admin 用户运行链路完成前，不得表述为已经能够委托 Harness 用户管理操作。
