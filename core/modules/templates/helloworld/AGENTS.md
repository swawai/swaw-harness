# Helloworld Template

## Scope

本目录是 Core 与技能调用外部协议能力的最小垂直样例和黑盒验收入口。Rule ID 前缀为 `HELLOWORLD`。

## Accepted

- **HELLOWORLD-001 — 垂直样例驱动。** 新的 Core 或技能调用协议必须先在 `core/modules/templates/helloworld` 形成最小端到端实现与黑盒验收，通过后才扩展到其他模块。
- **HELLOWORLD-002 — 单变量演进。** `core/modules/templates/helloworld` 每次只引入一个待验证的外部协议能力，不为尚未出现的复用、类型或执行模式预建抽象。

## Open

无。
