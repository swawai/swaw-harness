# Windows Candidate Build

## Scope

本目录拥有跨产品的不可变 Candidate（候选发布物）构建机制，不拥有产品编译适配器或 Release 发布。Rule ID 前缀为 `WIN-CANDIDATE`。

## Accepted

- **WIN-CANDIDATE-001 — Candidate 不可变。** Build 必须在释放构建锁前把产物和 `candidate.json` 固化到内容寻址的 `candidates/<CandidateId>/`，并验证所得 Candidate；Publish 不得引用仍可被后续 Cargo 构建覆盖的 target artifact 或共享 mutable `candidate.json`。

## Open

无。
