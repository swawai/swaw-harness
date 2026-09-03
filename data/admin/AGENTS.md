# Admin 用户数据规则

## Scope

本文件适用于 `data/admin/` 目录，Rule ID 前缀为 `ADMIN-DATA`。

## Accepted

- **ADMIN-DATA-001 — 固定 Admin UserHome。** `data/admin/` 是 DataHome 中固定且保留的 Admin UserHome；它当前直接包含 `map/` 技能图根、`modules/` 共享 Module Release 根、`host/` Core Host 版本指针根，并在需要管理其他 Harness 用户时使用 `user.lock`。不得把该目录改作普通 Harness 用户、整体替换或删除。
- **ADMIN-DATA-002 — Admin 独占运行时写入。** 除 Windows Bootstrap 可以从已验证 Bootstrap Release 初始物化 Module Release、Admin Core Host 版本指针与 `data/admin.exe` 外，只有 Admin Core module executable 可以安装模块、创建 Harness 用户或写入 `data/admin/` 的其他受管状态；Core Host executable、其他 Module Release executable 与用户 CLI executable 不得直接写入这些实体。
- **ADMIN-DATA-003 — 技能图、模块与 Host 指针分离。** `data/admin/map/` 只容纳具名技能图，`data/admin/modules/` 只保存不可变 Module Release，`data/admin/host/` 只保存 Admin 用户的 Core Host 版本指针及其写入锁；Core Host executable 作为 `swaw/core/host` Module Release 存放在 `modules/`，不得复制到 `host/`。`data/admin/map/core/` Core 技能图的技能声明通过 ModuleId、Version 和 executable 选择普通技能模块，不得保存或推断指向 `data/admin/` 其他内容的文件系统路径。
- **ADMIN-DATA-004 — 普通 Harness 用户初始快照。** `admin/user/create` 把调用时完整且已验证的 `data/admin/map/core/` 复制为普通用户独立的 `<UserHome>/map/core/`，把 `data/admin/host/current.<PlatformTargetId>` 的精确版本复制为该用户自己的指针，并为其安装与当前 `data/admin.exe` 字节一致的用户 CLI；它共享 `data/admin/modules/`，不复制模块、不建立 Runtime Release 或基础资源空间，后续也不自动同步双方技能图。

## Open

- **ADMIN-DATA-005 — 其他技能图来源。** 普通 Harness 用户除 Core 技能图外的其他具名技能图是从默认实例复制、由技能生成还是由用户直接建立，留待第一棵自定义技能图出现后确定；当前创建流程不得预建空模板目录。

## Maintainer Notes

- `data/admin/map/core/` 已作为 Core 技能图实体存在；Windows Core Host 可以按技能声明执行已验证 Module Release，但资源空间参数、运行记录和技能组合仍未实现。
