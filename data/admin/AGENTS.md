# Admin 用户数据规则

## Scope

本文件适用于 `data/admin/` 目录，Rule ID 前缀为 `ADMIN-DATA`。

## Accepted

- **ADMIN-DATA-001 — 固定 Admin UserHome。** `data/admin/` 是 DataHome 中固定且保留的 Admin UserHome；它当前直接包含 `map/` 技能图根、`modules/` 共享 Module Release 根、`host/` Core Host 版本指针根，并在需要管理其他 Harness 用户时使用 `user.lock`。不得把该目录改作普通 Harness 用户、整体替换或删除。
- **ADMIN-DATA-002 — Admin 独占运行时写入。** 除 Windows Bootstrap 可以从已验证 Bootstrap Release 初始物化 Module Release、Admin Core Host 版本指针与 `data/admin.exe` 外，只有 Admin Core module executable 可以安装模块、创建 Harness 用户或写入 `data/admin/` 的其他受管状态；Core Host executable、其他 Module Release executable 与用户 CLI executable 不得直接写入这些实体。
- **ADMIN-DATA-003 — 技能图、模块与 Host 指针分离。** `data/admin/map/` 只容纳具名技能图，`data/admin/modules/` 只保存不可变 Module Release，`data/admin/host/` 只保存 Admin 用户的 Core Host 版本指针及其写入锁；Core Host executable 作为 `swaw/core/host` Module Release 存放在 `modules/`，不得复制到 `host/`。`data/admin/map/core/` Core 技能图的技能声明通过 ModuleId、Version 和 executable 选择普通技能模块，不得保存或推断指向 `data/admin/` 其他内容的文件系统路径。

## Open

- **ADMIN-DATA-004 — 普通 Harness 用户派生。** Admin 创建普通 Harness 用户时必须建立该用户自己的用户 CLI 与 Core Host 版本指针，并共享 `data/admin/modules/` 中的 Core Host Module Release；Core 技能图是否复制 Admin 实例、还需建立哪些最小目录及如何记录受管身份，留待首个 `admin/user/create` 技能实现确定。
- **ADMIN-DATA-005 — 技能图来源。** 普通 Harness 用户的 Core 技能图以及其他具名技能图是从默认实例复制、由技能生成还是由用户直接建立，留待第二个真实 Harness 用户或第一棵自定义技能图出现后确定；当前不得预建空模板目录。

## Maintainer Notes

- `data/admin/map/core/` 已作为 Core 技能图实体存在；Windows Core Host 可以按技能声明执行已验证 Module Release，但资源空间参数、运行记录和技能组合仍未实现。
