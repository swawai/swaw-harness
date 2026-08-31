# Core 领域规则

## Scope

本文件适用于 `core/` 目录，Rule ID 前缀为 `CORE`。

## Accepted

- **CORE-001 — 基础与派生资源空间。** Resource 按事实来源、生命周期与写入权限分属资源空间；基础资源空间包括作者（源代码）、运行（发布）、runs（logs）、export 与 context 模块专用上下文记录空间，领域或用户机制可通过自定义 facet 方式建立派生资源空间。两类资源空间均采用目录树寻址；新增派生资源空间不得修改 Core 协议。
- **CORE-002 — 目录树寻址。** `core/runtime.core.tree/` 协议样例及目标 `<EntryRoot>/core/` Runtime Core Tree 实例使用真实目录树声明运行 Resource 与 Facet；Resource 路径和 Facet 名称的每个目录段必须使用规范小写 ASCII 文件系统名称。访问 Resource 时必须使用树根下规范化的相对路径，不得另建 ResourceIdentity、ResourceRoute、Listing 或其他地址模型。
- **CORE-003 — Facet 只有操作。** Facet 是对已找到 Resource 执行的具名操作，协议不区分 `Operation` 与 `Projection`，Facet 也不得包含、枚举或投影其他资源空间的 Resource；跨空间访问必须切换资源空间、通过目录树寻址重新寻找，再执行 Facet。
- **CORE-004 — Core executable binding 有界授予执行权。** 只有目标 `<EntryRoot>/core/` Runtime Core Tree 实例的 Resource 目录中名为 `swaw-harness.executable.json` 的 Core executable binding 可以选择 executable；其 `releaseRoot` 必须位于同一 EntryRoot 的 `runtime/core/` 下，`releaseId` 必须选择一个已验证的不可变 Core module Release，`executable` 必须是该 Release 根下的安全文件名。其他可写 Resource 数据不得声明 executable、Facet 实现或平台能力；`core/runtime.core.tree/` 协议样例中的重复字符 ReleaseId 不代表已验证发布。
- **CORE-006 — 运行地址与实现目录解耦。** Runtime Core Tree 中 Resource、Facet 和 Core executable binding 的目录位置是运行地址与实现选择的事实来源；`core/modules/` 中 Rust package、模块和函数的源码层级不得被 Core 协议要求镜像该运行地址。执行一个 Facet 时从其 Resource 目录向 Runtime Core Tree 根逐级寻找最近的 Core executable binding，不得越过树根；Core dispatcher 与 module executable 的完整参数约定留待首个调用实现确定。

## Open

- **CORE-005 — 远端资源挂载。** 远端 Resource 通过显式 mount 进入派生资源空间后，应与本地 Resource 一样使用目录树寻址并执行 Facet，不另建远端专用的寻址与操作模型；mount 的物化、同步、离线、身份和凭据边界仍需由首个真实远端实现确定。

## Maintainer Notes

- 待办：迁移旧实现时 hard cut `Collection Facet`、`Operation`/`Projection` kind、`ResourceListing` 投影及逻辑 Route 模型，统一改为“选择资源空间 + 目录树寻址 + Facet 操作”；完成前不得声称旧实现已符合本规则。
- `core/runtime.core.tree/` 当前是由 `core/protocol` 验证的协议样例；其中 ReleaseId 尚未由 Bootstrap 物化，Entry launcher、Core dispatcher 与 Admin seed 也尚未读取或复制该树。
