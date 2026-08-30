# Core Modules

## Scope

本文件适用于 `core/modules/` 目录，Rule ID 前缀为 `CORE-MODULE`。

## Accepted

- **CORE-MODULE-001 — 核心模块按作者目录归属。** `core/modules/<ModuleName>/` 是 Core 模块的作者目录；Core 模块身份由该目录归属确定，不依赖目录名前缀或 Resource 声明。
- **CORE-MODULE-002 — Resource 必须显式声明。** Core 模块作者目录及其子目录只有在该目录包含 `swaw-harness.resource.json` 时才是 Resource；`src`、`assets` 等普通目录名不得产生 Resource 语义。
- **CORE-MODULE-003 — Rust package 显式登记。** `core/modules/` 下具有 `Cargo.toml` 且参与 Core workspace 构建的 Rust package 必须在 `core/Cargo.toml` 的 `workspace.members` 中逐项登记；Core 模块身份不得由 Cargo workspace membership 推断。

## Open

无。
