# Admin Entry 数据规则

## Scope

本文件适用于 `data/admin/` 目录，Rule ID 前缀为 `ADMIN-DATA`。

## Accepted

- **ADMIN-DATA-001 — 固定 Admin EntryRoot。** `data/admin/` 是 DataHome 中固定且保留的 Admin EntryRoot；它当前直接包含 `config/` 配置根、`modules/` 共享 Module Release 根，并在需要管理 Entry 时使用 `entry.lock`。不得把该目录改作普通 Entry、整体替换或删除。
- **ADMIN-DATA-002 — Admin 独占运行时写入。** 除 Windows Bootstrap 可以从已验证 Bootstrap Release 初始物化 Module Release 外，只有 Admin Core module executable 可以安装模块、创建 Entry 或写入 `data/admin/` 的受管状态；其他 Module Release executable、Entry Manager executable、Harness GUI executable 与 Entry launcher 不得直接写入这些实体。
- **ADMIN-DATA-003 — 配置与发布分离。** `data/admin/config/` 只保存可直接查看和修改的配置树，`data/admin/modules/` 只保存不可变 Module Release；Core 配置树的 Facet declaration 通过 ModuleId、Version 和 executable 选择模块，不得保存或推断指向 `data/admin/` 其他内容的文件系统路径。

## Open

- **ADMIN-DATA-004 — 普通 Entry 派生。** Admin 创建普通 Entry 时复制哪棵 Core 配置树、建立哪些最小目录及如何记录受管身份，留待首个 `admin/entry create` Facet 实现确定。
- **ADMIN-DATA-005 — 配置树来源。** 普通 Entry 的 Core 配置树及其他配置树是从模板复制、由 Facet 生成还是由用户直接建立，留待第二个真实 Entry 或第二种配置树出现后确定；当前不得预建空模板目录。

## Maintainer Notes

- `data/admin/config/core/` 已作为配置实体存在；Module Release 由 Bootstrap 物化后，仍需 Core dispatcher 才能按 Facet declaration 执行。
