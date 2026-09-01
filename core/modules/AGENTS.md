# Core Modules

## Scope

本文件适用于 `core/modules/` 目录，Rule ID 前缀为 `CORE-MODULE`。

## Accepted

- **CORE-MODULE-001 — 核心模块按作者目录归属。** `core/modules/<ModuleName>/` 是 Core 模块的作者目录；Core 模块身份由该目录归属确定，不依赖目录名前缀或 Resource 声明。
- **CORE-MODULE-002 — 作者目录不声明运行地址。** `core/modules/` 中 Rust package、模块、函数和资产目录只按作者代码职责组织，不得使用 `skill.json`、旧 `swaw-harness.resource.json`、旧 `swaw-harness.facet.json` 或目录位置声明技能图地址；SkillPath 与 ModuleId 选择只由 `data/admin/map/core/` Core 技能图声明。
- **CORE-MODULE-003 — Rust package 显式登记。** `core/modules/` 下具有 `Cargo.toml` 且参与 Core workspace 构建的 Rust package 必须在 `core/Cargo.toml` 的 `workspace.members` 中逐项登记；Core 模块身份不得由 Cargo workspace membership 推断。

## Open

无。
