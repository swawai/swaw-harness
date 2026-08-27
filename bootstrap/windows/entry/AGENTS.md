# Entry Executable

## Scope

本目录拥有由 Windows Bootstrap 构建和发布的 Entry executable 产品适配器与当前运行边界。

## Accepted

- **ENTRY-EXEC-001 — Entry executable 运行协议暂缓。** 当前 `swaw-harness-entry.exe` 只验证无 CRT 原生编译、大小约束与不可变发布，执行时必须显式失败；在 Entry Manager 垂直样例确认运行布局前，不得迁入旧实现的寻址、manager、Bootstrap 或环境变量协议。

## Open

无。
