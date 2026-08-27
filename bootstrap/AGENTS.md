# Bootstrap

## Scope

本目录负责无需已编译 Harness 即可运行的作者态 Stage-0，并按宿主平台划分实现。Rule ID 前缀为 `BOOTSTRAP`。

## Accepted

- **BOOTSTRAP-001 — Bootstrap 按宿主平台归属。** 平台实现位于 `bootstrap/<platform>/`，目录名表达宿主平台而非脚本解释器；当前只建立 `windows`，未来按真实实现增加 `linux`、`macos`，不得预建空 `posix` 或抽象共享层。
- **BOOTSTRAP-002 — Bootstrap 迁移保真。** 旧 Bootstrap 的可观察功能与安全不变量必须先由行为审计和回归测试固定再迁移；任何有意删减都必须单列理由、影响与替代路径，并经确认后实施，不得在重写中静默降级。

## Open

无。

## Superseded

- **BOOT-006 — Bootstrap 按宿主平台归属。** 本规则曾使用中央 Bootstrap 序列；其原义由 `BOOTSTRAP-001` 继承。
- **BOOT-012 — Bootstrap 迁移保真。** 本规则曾使用中央 Bootstrap 序列；其原义由 `BOOTSTRAP-002` 继承。
