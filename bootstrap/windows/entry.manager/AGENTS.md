# Entry Manager

## Scope

本目录拥有独立 Entry Manager executable 的产品适配器、当前控制面板边界和未来 Entry 管理职责。Rule ID 前缀为 `ENTRY-MANAGEMENT`。

## Accepted

- **ENTRY-MANAGEMENT-001 — Entry Manager 控制面板启用门槛。** 在选择、命名、创建、删除与恢复的控制面板能力交付前，Entry Manager executable 的验收范围只包括独立构建、静态 CRT、大小约束与不可变发布，执行时必须以非零退出码和明确的未实现诊断失败；这些控制面板能力是已接受的目标职责，不是当前能力。
- **ENTRY-MANAGEMENT-002 — Entry 管理器独立。** Entry Manager 是作者项目 `bootstrap/windows/entry.manager` 产生的独立 executable，其目标职责是 Entry executable 的选择、命名、创建、删除与恢复，当前实施边界由 `ENTRY-MANAGEMENT-001` 界定；Entry executable 不自复制，根 `build.cmd` 也不创建 Entry。
- **ENTRY-MANAGEMENT-004 — Entry 存储布局。** `<repository>/data` 是 DataRoot，独立的 `<repository>/data.entry` 保存 Entry；每个 Entry 由同级的 `data.entry/<entry-id>.exe` 与 `data.entry/<entry-id>/` 组成，后者是 EntryRoot，其 `entry.json` 保存受管身份与生命周期，文件和目录不承诺文件系统级原子出现。
- **ENTRY-MANAGEMENT-005 — Entry 状态门槛。** `bootstrap/windows/entry.manager/src/lib.rs` 的 `EntryLifecycleState` 只允许 `provisioning`、`active`、`deleting`；只有 executable、EntryRoot、身份和运行引用均验证通过的 `active` Entry 可以启动，Entry Manager 只有在状态提交并回读成功后才能报告创建成功。
- **ENTRY-MANAGEMENT-006 — Entry 管理操作可恢复。** Entry Manager 是 Entry 创建、删除和状态迁移的唯一写入者；控制面板启动前必须在互斥锁内幂等恢复有效 `entry.json` 记录的未完成操作，没有有效 `entry.json` 的孤立对象只能报告冲突，不得推断所有权或静默删除。

## Open

- **ENTRY-MANAGEMENT-003 — EntryId 语法。** EntryId 的大小写归一、长度、可移植字符集与 Windows 保留名仍需确定；目录映射不得直接接受任意 Unicode basename。
