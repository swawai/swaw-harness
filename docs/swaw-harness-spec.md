# Swaw Harness 核心架构规范

本文记录 Swaw Harness 全仓及跨领域的架构与协议；稳定领域的新规则由最近目录的 `AGENTS.md` 记录并与上层规则依次叠加，尚未下沉的既有领域规则在完成单一来源迁移前继续由本文现有条目承载。每条规则保持一至两句话；未来验收脚本只引用稳定规则 ID，不从散文推断要求。

状态：`Accepted` 表示已经完成决议并形成当前可验证的实现约束，不要求永久不变，也不自动表示目标能力已经交付；过渡边界只有同时声明当前约束与明确退出条件时才可接受，纯进度事实属于 `Maintainer Notes`。`Open` 是唯一的未决规则状态且不具有实现约束；当前协议文件只保留这两种规则，Git 保存退出规则与基线前编号的历史。当前规范树中的完整 Rule ID 与领域前缀必须唯一，同一前缀的序列从 `001` 连续开始，新 ID 使用当前最大后缀加一。

## Accepted

- **ARC-002 — 可独立执行。** 命令领域的核心实现应位于 library API，进程入口保持薄；因此模块可在确有发布或隔离需要时增加独立 executable，而无需重写业务逻辑。
- **TERM-001 — Entry 术语。** `Entry executable` 是 `bootstrap/windows/entry` 构建并由 Entry Manager 分发的可执行产品，`Entry` 是 `<entry-id>.exe + <entry-id>/` 受管实例；`Launcher` 只可出现在 Git 保存的基线前历史中。
- **ENTRY-001 — Entry 身份由 Manager 提交。** 合法的 Entry executable basename 与受管 descriptor 中的 EntryId 必须一致并共同确定唯一 EntryRoot；复制或重命名单个 Entry executable 文件不得创建合法 Entry。
- **DATA-ROOT-001 — Core 数据根。** `DataRoot` 是共享 Core 运行数据的可配置绝对根，仓库内默认值为 `<repository>/data`；`core`、`docs`、`bootstrap` 与 Entry 数据均不属于 DataRoot。
- **BOOTSTRAP-DATA-001 — Windows Bootstrap 数据空间。** `BootstrapWindowsRoot` 唯一映射为 `DataRoot/bootstrap.windows` 并保存 `toolchains/work/locks/logs`；`BootstrapWindowsCacheRoot` 唯一映射为 `DataRoot/bootstrap.windows.cache` 并保存 `downloads/build/cargo`，两者是独立受控写根。
- **CORE-RELEASE-001 — Core Release 空间。** `CoreReleaseRoot` 唯一映射为 `DataRoot/core.release`，直接保存共享 Core Release 与 target selector；点号分隔顶层 owner 与 kind，不增加无独立职责的中间层。
- **ENTRY-RELEASE-001 — Entry executable Release 空间。** `EntryReleaseRoot` 唯一映射为 `DataRoot/entry.release`，只保存内容寻址的 `swaw-harness-entry.exe` Release 与 target selector；它是 Entry Manager 的分发源，不是 Entry 实例数据。
- **ENTRY-MANAGER-RELEASE-001 — Entry Manager Release 空间。** `EntryManagerReleaseRoot` 唯一映射为 `DataRoot/entry.manager.release`，只保存内容寻址的独立 Entry Manager Release 与 target selector，不保存 Entry 实例数据。
- **DATA-LIFECYCLE-001 — 数据空间按所有者与生命周期分治。** 无 Bootstrap 进程运行时可以整体清理 `BootstrapWindowsCacheRoot`；删除 `BootstrapWindowsRoot` 属于工具链重置而非清 cache，`CoreReleaseRoot` 只允许显式 Release GC 与 selector 更新。
- **ENTRY-DATA-001 — Entry 数据空间。** 仓库内 EntryDataRoot 固定为 `<repository>/data.entry`，每个直接子目录唯一对应一个 EntryId；自定义位置协议留待 Entry executable 垂直样例确定。
- **ENTRY-LAYOUT-001 — Entry 文件与数据同名配对。** 一个 Entry 由同级的 `data.entry/<entry-id>.exe` 与 `data.entry/<entry-id>/` 组成；后者的 `entry.json` 是受管身份与生命周期 descriptor，二者不承诺文件系统级原子出现。
- **ENTRY-LIFECYCLE-001 — Entry 生命周期目标协议。** 实现 Entry 创建与启动时，descriptor 的状态只允许 `provisioning`、`active`、`deleting`；只有文件、目录、身份和运行引用全部核验通过的 `active` Entry 可启动，Manager 只有在状态提交并回读成功后才报告创建成功。
- **ENTRY-RECOVERY-001 — Entry Manager 恢复目标协议。** 实现控制面板时，Manager 是 Entry 创建、删除和状态迁移的唯一支持写入者，每次启动控制面板前必须在互斥锁内幂等恢复有效 descriptor 记录的未完成操作；无有效 descriptor 的孤立对象只报告冲突，不得推断所有权并静默删除。
- **ENTRY-CACHE-001 — Entry cache 所有者显式。** `EntryRoot/cache` 只保存 Entry-local cache；不得与 `BootstrapWindowsCacheRoot` 隐式 fallback、复制或同步。
- **CACHE-001 — 不预建全局 Cache。** 当前不存在 `DataRoot/cache`；只有第二个真实消费者出现并共同采用内容身份、原子发布、并发锁与 GC 协议后，才允许建立全局 Artifact Cache。
- **BOOT-001 — Stage-0 边界。** 根 `bootstrap/` 保存无需已编译 Harness 即可运行的作者态 Stage-0 实现，`core/` 是完整 Rust workspace 且不承担获取自身编译环境的职责。
- **BOOT-002 — 冷启动依赖最小化。** Windows Stage-0 只获取构建当前 Rust 产品必需的 minimal Rust 与 MSVC 工具链，不获取 `rustfmt`、Bun 或内置 Pwsh；开发工具与脚本 Facet runtime 由出现真实消费者后的独立 setup 协议负责。
- **BOOT-003 — 持久清单确定性。** 写入身份或完整性 metadata 的无序集合必须先按协议规定的、与文化和 PowerShell 版本无关的 ordinal 顺序规范化；Windows 路径先按 `OrdinalIgnoreCase`、再按 `Ordinal` 决胜，验证不得依赖文件系统枚举顺序或 `Sort-Object` 默认语义。
- **BOOT-004 — 构建环境属于子进程。** MSVC、SDK、Rust 与 Cargo 环境只注入实际工具子进程，不修改再恢复父 PowerShell 进程，也不生成需要 dot-source 的环境脚本；工具入口必须使用显式受支持的 executable 映射。
- **BOOT-005 — 内容寻址安装只前进发布。** Toolchain 与 Candidate 等内容寻址对象只允许从已验证 stage 原子移动到不存在的目标；损坏目标可在同一身份锁内移除后重建，不为不会被合法覆盖的旧对象维护通用 backup/rollback 协议。
- **BOOT-006 — 仓库根 Windows 构建入口。** 根 `build.cmd` 是无业务逻辑的 Windows 适配器，只以 `<repository>/data` 调用 `bootstrap/windows/main.ps1` 并原样传播退出码；它不得复制 Entry executable、创建 Entry 或输出人工复制指引。
- **BOOT-007 — Windows Stage-0 作者布局。** `bootstrap/windows/builder` 保存跨产品 Candidate、Release 与基础机制，`toolchain` 独占构建工具链领域，`core`、`entry` 与 `entry.manager` 分别拥有 Core、Entry executable 与 Entry Manager 产品适配器；`main.ps1` 是先构建全部 Candidate、再发布并核验 selector 的唯一多产品编排器。
- **BOOT-008 — 平台与产品 Contract 分治。** `bootstrap/windows/contract.json` v3 只声明 target、Rust 与 MSVC 平台事实；`core/contract.json`、`entry/contract.json`、`entry.manager/contract.json` 分别声明各自产物事实，不得由平台 Contract 的泛称 `product` 暗指 Core。
- **BOOT-009 — Windows Rust 产品静态 CRT。** Windows Core 与 Entry Manager 的产品 Contract 必须显式要求静态 CRT，构建必须把该要求投影为 Cargo/rustc 命令行配置；验收必须读取发布 PE 的 import table，并拒绝 `VCRUNTIME`、`UCRT` 或其他外部 C/C++ runtime 依赖。
- **BOOT-010 — 多产品发布串行边界。** `bootstrap/windows/publication.ps1` 是 `main.ps1` 使用的内部 target-scoped 发布边界，其锁覆盖三种产品的发布、selector 回读与本轮结果核验；产品目录内的 `publish.ps1` 只是适配器，不是受支持的并发多产品入口。
- **BOOT-011 — Windows 子领域依赖方向。** `toolchain/` 可依赖 `builder/` 的基础路径、文件和进程机制，产品适配器可依赖两者；`builder/build/` 不得依赖 `builder/release/`，两者只由产品适配器和根编排器显式组合，不得以 `common/`、`utils/`、总加载器或旧路径 shim 绕过依赖方向。
- **BOOT-012 — PowerShell 依赖显式。** Windows Bootstrap 的 PowerShell 文件必须自行 dot-source 足以加载所需函数的明确依赖链，不得依赖调用者预先加载。
- **RELEASE-001 — Core 发布池身份。** `DataRoot/core.release/<release-id>/` 是 Bootstrap 产生的共享不可变 Core 发布池；`release-id` 的 Hash 必须覆盖完整发布内容及含 target 的发布元数据，不能只散列源码 revision。
- **RELEASE-002 — Bootstrap Target Selector。** Core、Entry executable 与 Entry Manager 的 ReleaseRoot 都各自保存只含 Release 引用的 `current.<target-id>`；Publish 只原子更新本产品、本 target 的 selector，并验证所指 Release 的 target 兼容性。

## Open

- **RF-001 — Resource。** Resource 是具有稳定身份、可被寻址的 subject；它可以由本地或外部事实源提供，不等同于目录、文件或某次返回的数据。
- **RF-002 — Facet。** Facet 是绑定到 Resource 的原子命名行为，不是类；`operation` 与 `projection` 分别表达有副作用的动作和只读投影，子 Resource 遍历不再作为 Facet 类型。
- **RF-003 — 最小运行时模型。** Core 只需要 Resource、Facet 与 ResourceRef/Listing；Space 是“可解析直接子 Resource 的 Resource”这一结构角色，不是额外的 nominal ResourceType。
- **RF-004 — 组合通过 Resource。** Facet 不任意嵌套，任何继续遍历都必须进入下一级 Resource；ResourcePath 只通过 Space child resolver 逐段解析，不再引入 Collection Facet 路由。
- **RF-005 — Listing 是访问边快照。** ResourceListing 携带 identity、route、space-local selector 与本次 `facetIds` 授权，它是一次查询产生的临时表示，不是 Resource 本体或可长期缓存的执行票据。
- **RF-006 — 动态 Resource 可重解析。** 动态 Resource 必须跨进程、跨调用重新解析，identity 必须不可变且不可复用；本地 descriptor 是首选实现，只存在于一次查询中的外部计算值只能作为 Projection 值。
- **RF-007 — 使用点重新验证。** 对动态 Resource 的操作必须重新验证当前 Space membership、Facet grant 与权威对象状态；列表之后对象消失应安全返回 NotFound，而不是依赖旧内存列表继续执行。
- **RF-008 — 数据不授予代码权力。** 可写 DataRoot 中的目录或文件不能自行声明 executable、Facet 实现或平台能力；执行权只能来自受信的不可变作者声明与 Release。
- **RF-009 — 文件系统只是 provider。** Core 不隐式扫描任意 CommandDataRoot；file-backed Space 必须被显式声明，并只在受控子树内完成校验、原子发布、边界限制与 ResourceList 投影。
- **RF-010 — 语法必须自解释。** Resource 选择与 Facet 调用必须在语法上无歧义，parser 不得查询 Catalog 或扫描磁盘猜测某一段的角色；错误层级的协议 marker 必须产生诊断。
- **RF-011 — 静态子命令也是 Resource。** `.dev/setup` 若拥有自己的 help、runs、execute 或子命令，就必须是 Resource，不能把 `setup` 同时解释为 Facet。
- **RF-012 — 地址分层。** 短 CLI CommandAddress、完整 Resource/Facet Route、领域存储路径是三种不同标识；它们可以确定性映射，但不得要求字符串或物理路径完全相同。
- **RF-013 — 统一 marker 后派发。** Facet id 只来自目录名，发现层只精确查找通用 `facet.json` marker；读取 manifest 后按封闭的 `kind`，必要时再按显式、带版本的 `contract` 派发，不按 `help/runs/execute` 扩张 marker 文件名。
- **RF-014 — 定义不执行。** Facet、可选 Shape/FacetSet 与 contract 只描述结构和语义，Facet binding 才选择 core、built-in 或 sidecar 实现；定义本身不得因“语法糖”获得可执行身份。
- **RF-015 — 保留 Facet 单调产生。** `/execute`、`/help`、`/subcommands`、`/runs` 等保留 Facet 只能由同一 Resource 辖区内的明确事实单调产生且不可 override，例如存在执行实现才有 `/execute`，明确采用 Journal contract 才有 `/runs`。
- **RF-016 — Space 与成员 Facet 分离。** Space 自己的 concrete Facets 与直接成员的 sealed `memberFacets` 必须分开声明；`memberFacets` 可内嵌于 Space definition，不必成为独立 InstanceFacetSet，跨 Space 复用时才允许 exact ref。
- **RF-017 — 禁止命令类型继承。** 静态 Command Resource 直接拥有或由局部事实确定性产生 concrete Facets；不得建立 `CommandType + extends + override/merge` 体系来减少声明文件。
- **RF-018 — 术语单义。** `kind` 只表达 Facet 的行为类别；静态 command backing、Space member contract 和领域数据 schema 必须使用各自独立的名称。
- **RF-019 — 核心抽象有边界。** Resource–Facet 统一产品可见的寻址、能力、依赖与编排语义，但不替代 Rust crate 图、进程边界、存储事务或发布拓扑。
- **RF-020 — 定义不制造类型层级。** ResourceDefinition 描述静态 Resource 或 Space，FacetDefinition 描述调用契约与 binding，Space 的 `memberFacets` 描述直接成员能力；这些作者态定义不得演化为 runtime inheritance/override/merge 体系。

- **ENTRY-CORE-001 — Entry selector 的引用形态。** `EntryRoot/releases` 应保存 Core Release 完整副本、硬链接，还是对 `DataRoot/core.release` 的受校验引用，尚未决议；选择必须同时满足 Entry 可搬移性、磁盘去重、原子更新与损坏隔离。

- **LIFE-001 — 本地 descriptor。** 若采用 Materialized Resource Space，当前建议 v1 要求每个可寻址 Resource 拥有本地 descriptor，但不要求 payload 本地化；未 mount/import 的远端搜索结果仍是 Projection 值。
- **ROUTE-001 — ResourcePath 与 Facet 调用。** 若路径只寻址 Resource，推荐用独立参数表达 Facet，例如 `swaw .contexts/add show` 与 `swaw .contexts add new-id`，从而删除 `::` 且允许 Resource id 为 `add`；若 Facet 继续进入同一条路径，则必须保留 `::` 或另一个显式分隔符。
- **SPACE-001 — Materialized Resource Space。** 候选主模型是“Space 为有直接子 Resource 的 Resource；直接 child resolve 是寻址结构，`list/find` 是 Space Projection，`add/mount` 是 Space Operation，`show/delete` 是成员 Facet”；Core 只理解空间解析与可信绑定，不理解领域动作。
- **SHAPE-001 — 成员模板。** 当前倾向删除 named ResourceType 和独立 InstanceFacetSet，由每个 Space definition 直接拥有 sealed `memberFacets`；只有出现真实跨 Space 复用时才抽出 exact-ref FacetSet。
- **REMOTE-001 — 远端物化。** 远端查询不得在读取时隐式写入本地资源树；显式 `mount/import` 创建只含 provider、稳定 remote ID、revision 与状态的本地 descriptor，cache 与凭据不属于 Resource identity。
- **LINEAGE-001 — 派生关系。** Source、Release、Run 与 Export 是不同生命周期的 Resource；Operation 在目标 Space 中创建 Resource 并返回 ResourceRef，Space 本身不“派生另一个 Space”，`derivedFrom/producedBy` 等 lineage 必须显式记录。
- **ROOT-001 — 空间根是 mount。** `.sources`、`.releases`、`.runs`、`.exports` 与 `.contexts` 可以形成一棵统一逻辑观察树，但必须分别挂载作者、不可变发布、审计与可变数据事实源，不能因此合并为一个写权限域。
- **NAME-001 — 空间用名词，动作作 Facet。** 执行产物空间应命名为 `.releases` 或 `.executables`，`execute` 保留为 Operation；不得用 `.execute` 同时表示空间和动作。
- **TEMPLATE-001 — Facet template marker。** 待真实约束证明后，再决定模板是否从通用 `facet.json` 分离为 `facet-template.json`；当前不因命名偏好增加协议类型。
- **RUNS-001 — Runs Space。** 若采用 Space 模型，`.runs/<owner>/<run-id>` 应成为 Run Resource 的唯一规范路径，命令详情中的 Runs 只是对该 Resource 的查询或引用，不再制造第二份 route identity。
- **BUILD-REPRO-001 — Windows 可复现链接。** 当前 MSVC `link.exe` 的全新构建会把链接时间写入 PE，使同源码与同工具链仍可能产生字节不同但各自内容寻址正确的 Release；是否改用 `lld-link` 或建立更完整的 reproducible-build contract，必须在真实原生依赖样例出现后决议，不能仅追加 `/Brepro` 就宣称可复现。
