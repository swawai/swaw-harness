# Windows Candidate Build

## Scope

本目录拥有跨产品的不可变 Candidate（候选发布物）构建机制，不拥有产品编译适配器或 Release 发布。

Candidate 是 Build 完成后固化在 `<repository>/data.repo/windows.build/<product>/candidates/<CandidateId>/` 中、已经验证且不可变的发布输入，目录内只保存该产品的 executable。CandidateId 是该目录的名称，由 Candidate 身份算法版本、Contract revision、PlatformTargetId、产物名称、产物长度与产物内容 SHA-256 共同确定，不另存重复的 Candidate metadata。

Rule ID 前缀为 `WIN-CANDIDATE`。

## Accepted

- **WIN-CANDIDATE-001 — Candidate 不可变。** Build 必须在释放构建锁前把唯一的产品 executable 固化到内容寻址的 `candidates/<CandidateId>/`，并根据产品 Contract 与 executable 内容验证所得 Candidate；Publish 不得引用仍可被后续构建覆盖的 target artifact。
- **WIN-CANDIDATE-002 — Candidate 随根 Bootstrap 发布清理。** Windows 根 Bootstrap 必须在同一 PlatformTargetId 的生命周期锁内完成全部 Candidate 构建、Bootstrap Release 发布与 Candidate 清理；仅当完整 Release 已验证且 selector 已原子切换后，才清理 `core`、`entry` 与 `manager` 的 Candidate 目录。发布失败不得执行成功清理；已成功切换 selector 后的清理失败只报告警告，并由后续成功调用重试。

## Open

无。
