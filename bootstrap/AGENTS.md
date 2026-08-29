# Bootstrap

## Scope

本目录负责无需已编译 Harness 即可运行的作者态 Stage-0，并按宿主平台划分实现。Rule ID 前缀为 `BOOTSTRAP`。

## Accepted

- **BOOTSTRAP-001 — Bootstrap 按宿主平台归属。** 平台实现位于 `bootstrap/<platform>/`，目录名表达宿主平台而非脚本解释器；当前只建立 `windows`，未来按真实实现增加 `linux`、`macos`，不得预建空 `posix` 或抽象共享层。
- **BOOTSTRAP-002 — 便携构建环境一键编译。** Bootstrap 必须自动获取并设置宿主平台声明的便携构建环境，无需用户预装、配置或交互干预，即可一键编译出 Core、Entry executable、Entry Manager executable 与 Harness GUI executable。
- **BOOTSTRAP-003 — 配套 executable 统一发布。** Bootstrap 必须把同次构建的 Core、Entry executable、Entry Manager executable 与 Harness GUI executable 完整验证后，作为一个 Bootstrap Release 原子发布到 data.repo 的宿主平台发布根；Windows 使用 `data.repo/windows.release/<ReleaseId>/`，再原子更新唯一的 `current.<PlatformTargetId>` selector，不得分别发布或选择这些 executable。

## Open

无。
