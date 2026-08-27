# Entry Executable

## Scope

本目录拥有由 Windows Bootstrap 构建和发布的 Entry executable 产品适配器与当前运行边界。Rule ID 前缀为 `ENTRY-EXEC`。

## Accepted

- **ENTRY-EXEC-001 — Entry executable 运行启用门槛。** 在 Entry Manager 垂直样例确认运行布局前，`swaw-harness-entry.exe` 的验收范围只包括无 CRT 原生编译、大小约束与不可变发布，执行时必须显式失败；在新运行协议被接受前，不得迁入旧实现的寻址、manager、Bootstrap 或环境变量协议。

## Open

无。
