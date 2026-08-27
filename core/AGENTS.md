# Core 领域规则

## Scope

本文件适用于 `core/` 目录，Rule ID 前缀为 `CORE`。

## Accepted

- **CORE-001 — 资源空间分治。** Resource 按事实来源、生命周期与写入权限分属具有独立文件系统根的资源空间；内置资源空间包括作者（源代码）、运行（发布）、runs（logs）与 context 模块专用上下文记录空间。跨资源空间工作必须直接选择目标资源空间；领域或用户定义的 Facet 可派生新资源空间，但不得因此修改 Core 协议。
- **CORE-002 — 资源按路径寻找。** 寻找 Resource 时先选择资源空间根，再使用该根下规范化的相对文件系统路径；Resource 地址只由资源空间与相对路径组成，不得另建 ResourceIdentity、ResourceRoute 或 Listing 地址模型。
- **CORE-003 — Facet 只有操作。** Facet 是对已找到 Resource 执行的具名操作，协议不区分 `Operation` 与 `Projection`，Facet 也不得包含、枚举或投影其他资源空间的 Resource；跨空间访问必须切换资源空间、按路径重新寻找，再执行 Facet。
- **CORE-004 — 数据不授予执行权。** 可写资源空间中的 Resource 或数据不得自行声明 executable、Facet 实现或平台能力；执行权只能来自受信的不可变作者声明或 Release。

## Open

当前无。

## Maintainer Notes

- 待办：迁移旧实现时 hard cut `Collection Facet`、`Operation`/`Projection` kind、`ResourceListing` 投影及逻辑 Route 模型，统一改为“选择资源空间 + 文件系统路径 + Facet 操作”；完成前不得声称旧实现已符合本规则。
