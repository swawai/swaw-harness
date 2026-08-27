# Helloworld Template

## Scope

本目录是 Core 与 Facet 外部协议能力的最小垂直样例和黑盒验收入口。

## Accepted

- **DEV-005 — 垂直样例驱动。** 新的 Core 或 Facet 协议必须先在 `core/templates/helloworld` 形成最小端到端实现与黑盒验收，通过后才扩展到其他模块。
- **DEV-006 — 单变量演进。** `core/templates/helloworld` 每次只引入一个待验证的外部协议能力，不为尚未出现的复用、类型或执行模式预建抽象。

## Open

无。
