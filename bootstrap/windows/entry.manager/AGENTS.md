# Entry Manager

## Scope

本目录拥有独立 Entry Manager executable，是 Entry 选择、命名、创建、删除与恢复的唯一领域所有者。Rule ID 前缀为 `ENTRY-MANAGEMENT`。

## Accepted

- **ENTRY-MANAGEMENT-001 — Entry 存储布局。** `<repository>/data` 是 DataRoot，独立的 `<repository>/data.entry` 保存 Entry；每个 Entry 由同级的 `data.entry/<entry-id>.exe` 与 `data.entry/<entry-id>/` 组成，后者是 EntryRoot，其 `entry.json` 保存受管身份与生命周期，文件和目录不承诺文件系统级原子出现。

## Open

- **ENTRY-MANAGEMENT-002 — EntryId 语法。** EntryId 的大小写归一、长度、可移植字符集与 Windows 保留名仍需确定；目录映射不得直接接受任意 Unicode basename。

## Maintainer Notes

- 待办：当前 Entry Manager executable 只实现独立构建与发布，控制面板尚未实现；实现时补齐 Entry 生命周期门槛、状态提交与回读、互斥锁内的未完成操作恢复，以及对无有效 `entry.json` 孤立对象的冲突报告。
