# Core 领域规则

## Scope

本文件适用于 `core/` 目录，Rule ID 前缀为 `CORE`。

## Accepted

- **CORE-001 — 基础与派生资源空间。** Resource 按事实来源、生命周期与写入权限分属资源空间；基础资源空间包括作者（源代码）、运行（发布）、runs（logs）与 context 模块专用上下文记录空间，领域或用户机制可通过 export、远端 mount 等方式建立派生资源空间。两类资源空间均采用目录树寻址；新增派生资源空间不得修改 Core 协议。
- **CORE-002 — 目录树寻址。** 访问 Resource 时必须先选择资源空间，再使用该空间文件系统目录树根下规范化的相对路径；不得另建 ResourceIdentity、ResourceRoute、Listing 或其他地址模型。
- **CORE-003 — Facet 只有操作。** Facet 是对已找到 Resource 执行的具名操作，协议不区分 `Operation` 与 `Projection`，Facet 也不得包含、枚举或投影其他资源空间的 Resource；跨空间访问必须切换资源空间、通过目录树寻址重新寻找，再执行 Facet。
- **CORE-004 — 数据不授予执行权。** 可写资源空间中的 Resource 或数据不得自行声明 executable、Facet 实现或平台能力；执行权只能来自受信的不可变作者声明或 Release。

## Open

- **CORE-005 — 远端资源挂载。** 远端 Resource 通过显式 mount 进入派生资源空间后，应与本地 Resource 一样使用目录树寻址并执行 Facet，不另建远端专用的寻址与操作模型；mount 的物化、同步、离线、身份和凭据边界仍需由首个真实远端实现确定。

## Maintainer Notes

- 待办：迁移旧实现时 hard cut `Collection Facet`、`Operation`/`Projection` kind、`ResourceListing` 投影及逻辑 Route 模型，统一改为“选择资源空间 + 目录树寻址 + Facet 操作”；完成前不得声称旧实现已符合本规则。
