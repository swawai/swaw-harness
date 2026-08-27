# Windows Candidate Build

## Scope

本目录拥有跨产品的不可变 Candidate 构建机制，不拥有产品编译适配器或 Release 发布。

## Accepted

- **BOOT-021 — Candidate 不可变。** Build 必须在释放构建锁前把产物固化为内容寻址、可独立验证的不可变 Candidate，Publish 不得引用仍可被后续 Cargo 构建覆盖的 target artifact 或共享 mutable `candidate.json`。

## Open

无。
