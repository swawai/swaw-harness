# Entry Manager

## Scope

本目录拥有独立 Entry Manager executable 的产品适配器、当前控制面板边界和未来 Entry 管理职责。Rule ID 前缀为 `ENTRY-MANAGEMENT`。

## Accepted

- **ENTRY-MANAGEMENT-001 — Entry Manager 控制面板启用门槛。** 在选择、命名、创建、删除与恢复的控制面板能力交付前，Entry Manager executable 的验收范围只包括独立构建、静态 CRT、大小约束与不可变发布，执行时必须以非零退出码和明确的未实现诊断失败；这些控制面板能力是已接受的目标职责，不是当前能力。
- **ENTRY-MANAGEMENT-002 — Entry 管理器独立。** Entry Manager 是作者项目 `bootstrap/windows/entry.manager` 产生的独立 executable，其目标职责是 Entry executable 的选择、命名、创建、删除与恢复，当前实施边界由 `ENTRY-MANAGEMENT-001` 界定；Entry executable 不自复制，根 `build.cmd` 也不创建 Entry。

## Open

- **ENTRY-MANAGEMENT-003 — EntryId 语法。** EntryId 的大小写归一、长度、可移植字符集与 Windows 保留名仍需确定；目录映射不得直接接受任意 Unicode basename。

## Superseded

- **ENTRY-MANAGER-EXEC-001 — Entry Manager 控制面板暂缓。** 本规则曾使用独立执行边界前缀；其原义由 `ENTRY-MANAGEMENT-001` 继承。
- **ENTRY-MANAGER-002 — Entry 管理器独立。** 本规则曾使用中央 Entry Manager 序列；其原义由 `ENTRY-MANAGEMENT-002` 继承。
- **ENTRY-ID-001 — EntryId 语法。** 本规则曾使用中央议题前缀；其未决问题由 `ENTRY-MANAGEMENT-003` 继承。
