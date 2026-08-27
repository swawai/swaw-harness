# Windows Candidate Build

## Scope

本目录拥有跨产品的不可变 Candidate 构建机制，不拥有产品编译适配器或 Release 发布。Rule ID 前缀为 `WIN-CANDIDATE`。

## Accepted

- **WIN-CANDIDATE-001 — Candidate 不可变。** Build 必须在释放构建锁前把产物固化为内容寻址、可独立验证的不可变 Candidate，Publish 不得引用仍可被后续 Cargo 构建覆盖的 target artifact 或共享 mutable `candidate.json`。

## Open

无。

## Superseded

- **BOOT-021 — Candidate 不可变。** 本规则曾使用中央 Bootstrap 序列；其原义由 `WIN-CANDIDATE-001` 继承。
