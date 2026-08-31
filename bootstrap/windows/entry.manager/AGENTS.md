# Entry Manager

## Scope

本目录拥有 Entry Manager executable、Harness GUI executable 及其共享 Rust frontend library；两个 frontend 都不拥有 Entry 布局或生命周期实现，Entry Manager executable 必须把 Entry 操作委托给固定 Admin Entry，Harness GUI executable 必须委托同级 Entry Manager executable。Rule ID 前缀为 `ENTRY-MANAGEMENT`。

## Accepted

- **ENTRY-MANAGEMENT-001 — Frontend 不写 DataHome。** Entry Manager executable 与 Harness GUI executable 不得创建、修改或删除 Entry executable、EntryRoot、Runtime Release、selector 或 Entry 受管记录，也不得复制 Admin Core module executable 的 Entry 生命周期实现。
- **ENTRY-MANAGEMENT-002 — GUI 委托 console frontend。** Harness GUI executable 必须通过同级 `swaw-harness-cli.exe` 请求 Entry 操作，不得直接启动 Admin Core module executable 或把 EntryId、环境变量当作授权凭据。

## Open

当前无。

## Maintainer Notes

- 待办：当前 Entry Manager executable 与 Harness GUI executable 只实现独立界面占位、共享 library 构建并参与统一 Bootstrap Release；在固定 Admin Entry 运行链路完成前，不得表述为已经能够委托 Entry 操作。
