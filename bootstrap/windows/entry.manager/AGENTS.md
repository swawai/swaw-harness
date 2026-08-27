# Entry Manager

## Scope

本目录拥有独立 Entry Manager executable 的产品适配器、当前控制面板边界和未来 Entry 管理职责。

## Accepted

- **ENTRY-MANAGER-EXEC-001 — Entry Manager 控制面板暂缓。** 当前 Entry Manager executable 只验证独立构建、静态 CRT、大小约束与不可变发布，执行时必须以非零退出码和明确的未实现诊断失败；选择、命名、创建、删除与恢复是已接受的目标职责，不是当前已实现的控制面板能力。
- **ENTRY-MANAGER-002 — Entry 管理器独立。** Entry Manager 是作者项目 `bootstrap/windows/entry.manager` 产生的独立 executable，其目标职责是 Entry executable 的选择、命名、创建、删除与恢复，当前实施边界由 `ENTRY-MANAGER-EXEC-001` 界定；Entry executable 不自复制，根 `build.cmd` 也不创建 Entry。

## Open

- **ENTRY-ID-001 — EntryId 语法。** EntryId 的大小写归一、长度、可移植字符集与 Windows 保留名仍需确定；目录映射不得直接接受任意 Unicode basename。
