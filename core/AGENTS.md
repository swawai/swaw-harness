# Core 领域规则

## Scope

本文件适用于 `core/` 目录，Rule ID 前缀为 `CORE`。

## Accepted

- **CORE-001 — 资源空间保存事实数据。** Resource 按事实来源、生命周期与写入权限分属资源空间；基础资源空间包括 `author`、`runtime`、`runs`、`export` 与 `context`，领域或用户机制可通过技能建立派生资源空间。两类资源空间均采用目录树寻址；`<EntryRoot>/map/` 技能图根、其中的具名技能图和 `<DataHome>/admin/modules/` Module Release 根不属于资源空间，也不得保存 Resource 事实数据。
- **CORE-002 — Resource 路径与 SkillPath 各自寻址。** 资源空间以其根下规范化的相对路径寻找 Resource，技能图以其根下规范化的 SkillPath 寻找技能节点；两者不要求相同或镜像。`data/admin/map/core/` 是唯一默认 Core 技能图，其他 Entry 的实例位于 `<EntryRoot>/map/core/`；不得另建 ResourceIdentity、ResourceRoute、Listing 或其他地址模型。
- **CORE-003 — 技能节点即调用地址。** Core 技能图中一个目录就是一个技能节点；包含 `skill.json` 时该 SkillPath 可调用，不包含时只是分类节点。可调用节点可以继续包含子节点，不得通过通用 `execute/` 子目录重复表达可执行性，也不区分 `Operation` 与 `Projection` 两种节点类型。
- **CORE-004 — 技能声明有界授予执行权。** 只有目标 `<EntryRoot>/map/core/` Core 技能图技能节点中的 `skill.json` 可以选择 Module Release executable；其 `schema`、`module`、`version`、`executable` 和 `arguments` 必须精确通过协议验证，所选模块必须来自同一 DataHome 的 `<DataHome>/admin/modules/` 已验证发布目录，且 executable 必须由该 Module Release 的 `swaw-harness.module.json` 清单列出。其他技能图、其他文件与可写 Resource 数据不得声明 executable、技能实现或平台能力；目录位于 `admin/` 下不构成调用授权。
- **CORE-006 — SkillPath 与实现目录解耦。** Core 技能图中的技能声明是 SkillPath 与实现选择的事实来源；每个技能节点直接声明 ModuleId 和版本选择，不继承祖先目录的 executable。`core/modules/` 中 Rust package、模块和函数的源码层级不得被 Core 协议要求镜像 SkillPath；Core dispatcher 的动态参数、资源空间和 Resource 路径传递约定留待首个调用实现确定。

## Open

- **CORE-005 — 远端资源挂载。** 远端 Resource 通过显式 mount 进入派生资源空间后，应与本地 Resource 一样使用资源空间目录树寻址，不另建远端专用地址模型；技能如何接收和操作远端 Resource，以及 mount 的物化、同步、离线、身份和凭据边界，仍需由首个真实远端实现确定。
- **CORE-007 — 技能图组合与执行。** 可调用父节点和子节点已经共享同一目录树；相对依赖的语法、无环验证、跨图引用、技能图子树发布、单节点与整棵子树执行、状态检查和运行记录尚未实现，必须由首个真实组合样例共同确定。

## Maintainer Notes

- 待办：迁移旧实现时 hard cut `Collection Facet`、`Operation`/`Projection` kind、`ResourceListing` 投影及逻辑 Route 模型，统一改为“资源空间目录树寻址 + SkillPath 调用”；完成前不得声称旧实现已符合本规则。
- `data/admin/map/core/` 当前由 `core/protocol` 验证 SkillPath 和技能声明，并从同一 DataHome 的已安装模块中选择和校验 Module Release；Core dispatcher、资源空间 Resource 验证与其他 Entry 的技能图复制尚未实现。
