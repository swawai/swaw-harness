# Windows Candidate Build

## Scope

本目录拥有跨产品的不可变 Candidate（候选发布物）构建机制，不拥有产品编译适配器或 Release 发布。

Candidate 是 Build 完成后固化在 `<repository>/data.repo/windows.build/<product>/candidates/<CandidateId>/` 中、已经验证且不可变的发布输入，目录内只保存该产品的 executable。CandidateId 是该目录的名称，由 Candidate 身份算法版本、Contract revision、PlatformTargetId、产物名称、产物长度与产物内容 SHA-256 共同确定，不另存重复的 Candidate metadata。

Rule ID 前缀为 `WIN-CANDIDATE`。

## Accepted

- **WIN-CANDIDATE-001 — Candidate 不可变。** Build 必须在释放构建锁前把唯一的产品 executable 固化到内容寻址的 `candidates/<CandidateId>/`，并根据产品 Contract 与 executable 内容验证所得 Candidate；Publish 不得引用仍可被后续构建覆盖的 target artifact。
- **WIN-CANDIDATE-002 — Candidate 随根 Bootstrap 发布清理。** Candidate Build、Publish 与 Windows 根 Bootstrap 必须协调同一 PlatformTargetId 的生命周期锁；Publish 必须在等待该锁前持有共享的 Candidate consumer lock，清理必须在同一锁文件上取得排他的 cleanup lock。Windows 根 Bootstrap 仅当完整 Release 已验证且 selector 已原子切换后，才清理 `core`、`user` 与 `frontend` 的 Candidate 目录；被活跃 Publish 占用或因其他原因清理失败时只报告警告，并由后续成功调用重试，发布失败不得执行成功清理。

## Open

无。
