# Core 领域规则

## Scope

本文件适用于 `core/` 目录，Rule ID 前缀为 `CORE`。

## Accepted

- **CORE-001 — 资源空间保存事实数据。** Resource 按事实来源、生命周期与写入权限分属资源空间；基础资源空间包括 `author`、`runtime`、`runs`、`export` 与 `context`，领域或用户机制可通过自定义 facet 建立派生资源空间。两类资源空间均采用目录树寻址；`<EntryRoot>/config/` 配置根和 `<DataHome>/admin/modules/` Module Release 根不属于资源空间，也不得保存 Resource 事实数据。
- **CORE-002 — 资源地址与 Facet 绑定使用同一路径。** 选择资源空间后，以其根下规范化的相对文件系统路径寻找 Resource；`data/admin/config/core/` 唯一默认 Core 配置树及目标 `<EntryRoot>/config/core/` 实例在相同 Resource 路径下声明 Facet。一个包含 `swaw-harness.facet.json` 的叶目录是 Facet，其父目录相对 Core 配置树根的路径是 Resource 路径。各路径段必须使用规范小写 ASCII 文件系统名称，不得另建 ResourceIdentity、ResourceRoute、Listing 或其他地址模型。
- **CORE-003 — Facet 只有操作。** Facet 是对已找到 Resource 执行的具名操作，协议不区分 `Operation` 与 `Projection`，Facet 也不得包含、枚举或投影其他资源空间的 Resource；跨空间访问必须切换资源空间、通过目录树寻址重新寻找，再执行 Facet。
- **CORE-004 — Facet declaration 有界授予执行权。** 只有目标 `<EntryRoot>/config/core/` Core 配置树 Facet 叶目录中的 `swaw-harness.facet.json` 可以选择 Module Release executable；其 `module`、`version`、`executable` 和 `arguments` 必须精确通过协议验证，所选模块必须来自同一 DataHome 的 `<DataHome>/admin/modules/` 已验证发布目录，且 executable 必须由该 Module Release 的 `swaw-harness.module.json` 清单列出。其他配置树与可写 Resource 数据不得声明 executable、Facet 实现或平台能力；目录位于 `admin/` 下不构成调用授权。
- **CORE-006 — 运行地址与实现目录解耦。** Core 配置树中 Facet declaration 是运行地址与实现选择的事实来源；每个 Facet 直接声明 ModuleId 和版本选择，不继承祖先目录的 executable。`core/modules/` 中 Rust package、模块和函数的源码层级不得被 Core 协议要求镜像 Resource 或 Facet 运行地址；Core dispatcher 的动态参数约定留待首个调用实现确定。

## Open

- **CORE-005 — 远端资源挂载。** 远端 Resource 通过显式 mount 进入派生资源空间后，应与本地 Resource 一样使用目录树寻址并执行 Facet，不另建远端专用的寻址与操作模型；mount 的物化、同步、离线、身份和凭据边界仍需由首个真实远端实现确定。

## Maintainer Notes

- 待办：迁移旧实现时 hard cut `Collection Facet`、`Operation`/`Projection` kind、`ResourceListing` 投影及逻辑 Route 模型，统一改为“选择资源空间 + 目录树寻址 + Facet 操作”；完成前不得声称旧实现已符合本规则。
- `data/admin/config/core/` 当前由 `core/protocol` 验证目录和 Facet declaration；Core dispatcher、资源空间 Resource 验证、Module Release 选择与其他 Entry 的配置树复制尚未实现。
