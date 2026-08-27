# Bootstrap

## Scope

本目录负责无需已编译 Harness 即可运行的作者态 Stage-0，并按宿主平台划分实现。Rule ID 前缀为 `BOOTSTRAP`。

## Accepted

- **BOOTSTRAP-001 — Bootstrap 按宿主平台归属。** 平台实现位于 `bootstrap/<platform>/`，目录名表达宿主平台而非脚本解释器；当前只建立 `windows`，未来按真实实现增加 `linux`、`macos`，不得预建空 `posix` 或抽象共享层。
- **BOOTSTRAP-002 — 便携工具链一键编译。** Bootstrap 必须自动下载并设置便携 Rust 与 MSVC 编译环境，无需用户预装、配置或交互干预，即可一键编译出 Harness 核心。
- **BOOTSTRAP-003 — 构建环境只进入工具子进程。** `bootstrap/windows/toolchain/environment.ps1` 只生成环境计划，`bootstrap/windows/builder/process.ps1` 只把该计划注入实际工具子进程；不得修改后再恢复父 PowerShell 进程，也不得生成要求调用者 dot-source 的环境脚本，工具入口必须使用明确支持的 executable 路径。

## Open

无。
