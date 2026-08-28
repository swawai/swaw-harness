# Entry Manager

## Scope

本目录拥有独立 Entry Manager executable，是 Entry 选择、命名、创建、删除与恢复的唯一领域所有者。Rule ID 前缀为 `ENTRY-MANAGEMENT`。

## Accepted

- **ENTRY-MANAGEMENT-001 — Entry 存储布局。** `<repository>/data` 是 DataRoot，独立的 `<repository>/data.entry` 保存 Entry；每个 Entry 由同级的 `data.entry/<EntryId>.exe` 与 `data.entry/<EntryId>/` 组成，后者是 EntryRoot，其 `entry.json` 保存受管身份与生命周期，文件和目录不承诺文件系统级原子出现。
- **ENTRY-MANAGEMENT-002 — EntryId 语法。** EntryId 必须是 1 至 48 字节的规范小写 ASCII 标识：首字符为 `a-z`，其余字符仅可为 `a-z`、`0-9` 或单个 `-`，末字符必须为字母或数字；不得静默转换大小写，不得包含连续 `--`，且不得使用 Windows 保留设备名 `con`、`prn`、`aux`、`nul`、`com1` 至 `com9`、`lpt1` 至 `lpt9`。
- **ENTRY-MANAGEMENT-003 — Entry 受管记录。** `data.entry/<EntryId>/entry.json` 必须使用 `swaw.harness.entry/v1` schema，只保存与路径一致的 `entryId` 以及 `provisioning`、`active`、`deleting` 之一的 `lifecycle`；未知 schema、字段、生命周期或不一致身份必须拒绝，不得从无效记录推断受管状态。

## Open

当前无。

## Maintainer Notes

- 待办：当前 Entry Manager executable 只实现独立构建并参与统一 Bootstrap Release，控制面板尚未实现；实现时补齐 Entry 生命周期门槛、状态提交与回读、互斥锁内的未完成操作恢复，以及对无有效 `entry.json` 孤立对象的冲突报告。
