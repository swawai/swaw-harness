# Swaw Harness 核心架构规范

本文是 Swaw Harness 架构与协议的唯一事实源。每条规则保持一至两句话；未来验收脚本只引用稳定规则 ID，不从散文推断要求。

状态：`Accepted` 表示设计或当前能力已确认并约束实现，但不自动表示目标能力已经交付；每条规则必须明确自己描述当前能力还是已接受的目标。`Proposed` 表示建议方案；`Open` 表示仍需决议；`Superseded` 表示已被新规则替代。

## Accepted

- **HAR-001 — 独立产品仓库。** `swaw-harness` 是 Swaw 品牌下的独立产品仓库，必须脱离 `swaw-kit` 的父目录和源码树独立构建、测试、打包与发布。
- **HAR-002 — 文档职责单一。** 本文件记录架构与协议，`AGENTS.md` 记录维护规则，`README.md` 只做人类入口；三者不得复制同一规范正文。
- **ARC-002 — 源码就近归属。** 实现应下沉到最近的稳定领域所有者；放在父领域 crate 可以接受，但必须按领域拆开，不能长期集中在总入口或总 dispatcher。
- **ARC-003 — 可独立执行。** 命令领域的核心实现应位于 library API，进程入口保持薄；因此模块可在确有发布或隔离需要时增加独立 executable，而无需重写业务逻辑。
- **ARC-004 — 边界按代价建立。** CLI 目录不等于 Cargo package 或进程边界；只有稳定领域、独立依赖、独立发布或故障隔离需求成立时才拆 crate/executable。
- **ARC-005 — 唯一生产路径。** 一个命令在一个发行档中只能有一个主执行模式；从 built-in 迁为 sidecar 时必须 hard cut 旧路径，不长期并存多种生产入口。
- **TPL-001 — 标准模块边界。** 标准 Rust 模块把领域行为放在 library API，并只用薄 executable 处理进程输入输出；模块必须可由 workspace 独立编译、测试和运行。
- **DEV-005 — 垂直样例驱动。** 新的 Core 或 Facet 协议必须先在 `core/templates/helloworld` 形成最小端到端实现与黑盒验收，通过后才扩展到其他模块。
- **DEV-006 — 单变量演进。** `core/templates/helloworld` 每次只引入一个待验证的外部协议能力，不为尚未出现的复用、类型或执行模式预建抽象。
- **TERM-001 — Entry 术语。** `Entry executable` 是 `bootstrap/windows/entry` 构建并由 Entry Manager 分发的可执行产品，`Entry` 是 `<entry-id>.exe + <entry-id>/` 受管实例；`Launcher` 只可出现在 Superseded 历史记录中。
- **ENTRY-002 — Entry 身份由 Manager 提交。** 合法的 Entry executable basename 与受管 descriptor 中的 EntryId 必须一致并共同确定唯一 EntryRoot；复制或重命名单个 Entry executable 文件不得创建合法 Entry。
- **DATA-ROOT-001 — Core 数据根。** `DataRoot` 是共享 Core 运行数据的可配置绝对根，仓库内默认值为 `<repository>/data`；`core`、`docs`、`bootstrap` 与 Entry 数据均不属于 DataRoot。
- **BOOTSTRAP-DATA-002 — Windows Bootstrap 数据空间。** `BootstrapWindowsRoot` 唯一映射为 `DataRoot/bootstrap.windows` 并保存 `toolchains/work/locks/logs`；`BootstrapWindowsCacheRoot` 唯一映射为 `DataRoot/bootstrap.windows.cache` 并保存 `downloads/build/cargo`，两者是独立受控写根。
- **CORE-RELEASE-002 — Core Release 空间。** `CoreReleaseRoot` 唯一映射为 `DataRoot/core.release`，直接保存共享 Core Release 与 target selector；点号分隔顶层 owner 与 kind，不增加无独立职责的中间层。
- **ENTRY-RELEASE-001 — Entry executable Release 空间。** `EntryReleaseRoot` 唯一映射为 `DataRoot/entry.release`，只保存内容寻址的 `swaw-harness-entry.exe` Release 与 target selector；它是 Entry Manager 的分发源，不是 Entry 实例数据。
- **ENTRY-MANAGER-RELEASE-001 — Entry Manager Release 空间。** `EntryManagerReleaseRoot` 唯一映射为 `DataRoot/entry.manager.release`，只保存内容寻址的独立 Entry Manager Release 与 target selector，不保存 Entry 实例数据。
- **DATA-LIFECYCLE-003 — 数据空间按所有者与生命周期分治。** 无 Bootstrap 进程运行时可以整体清理 `BootstrapWindowsCacheRoot`；删除 `BootstrapWindowsRoot` 属于工具链重置而非清 cache，`CoreReleaseRoot` 只允许显式 Release GC 与 selector 更新。
- **ENTRY-DATA-001 — Entry 数据空间。** 仓库内 EntryDataRoot 固定为 `<repository>/data.entry`，每个直接子目录唯一对应一个 EntryId；自定义位置协议留待 Entry executable 垂直样例确定。
- **ENTRY-LAYOUT-003 — Entry 文件与数据同名配对。** 一个 Entry 由同级的 `data.entry/<entry-id>.exe` 与 `data.entry/<entry-id>/` 组成；后者的 `entry.json` 是受管身份与生命周期 descriptor，二者不承诺文件系统级原子出现。
- **ENTRY-LIFECYCLE-001 — Entry 生命周期目标协议。** 实现 Entry 创建与启动时，descriptor 的状态只允许 `provisioning`、`active`、`deleting`；只有文件、目录、身份和运行引用全部核验通过的 `active` Entry 可启动，Manager 只有在状态提交并回读成功后才报告创建成功。
- **ENTRY-RECOVERY-001 — Entry Manager 恢复目标协议。** 实现控制面板时，Manager 是 Entry 创建、删除和状态迁移的唯一支持写入者，每次启动控制面板前必须在互斥锁内幂等恢复有效 descriptor 记录的未完成操作；无有效 descriptor 的孤立对象只报告冲突，不得推断所有权并静默删除。
- **ENTRY-CACHE-002 — Entry cache 所有者显式。** `EntryRoot/cache` 只保存 Entry-local cache；不得与 `BootstrapWindowsCacheRoot` 隐式 fallback、复制或同步。
- **CACHE-005 — 不预建全局 Cache。** 当前不存在 `DataRoot/cache`；只有第二个真实消费者出现并共同采用内容身份、原子发布、并发锁与 GC 协议后，才允许建立全局 Artifact Cache。
- **BOOT-034 — Stage-0 边界。** 根 `bootstrap/` 保存无需已编译 Harness 即可运行的作者态 Stage-0 实现，`core/` 是完整 Rust workspace 且不承担获取自身编译环境的职责。
- **BOOT-006 — Bootstrap 按宿主平台归属。** 平台实现位于 `bootstrap/<platform>/`，目录名表达宿主平台而非脚本解释器；当前只建立 `windows`，未来按真实实现增加 `linux`、`macos`，不得预建空 `posix` 或抽象共享层。
- **BOOT-008 — 平台 Contract 就近归属。** Windows 工具链版本、host target、下载来源与校验事实由 `bootstrap/windows/contract.json` 唯一声明；第二个平台出现真实共同字段前，不建立跨平台 contract 合并或继承体系。
- **BOOT-012 — Bootstrap 迁移保真。** 旧 Bootstrap 的可观察功能与安全不变量必须先由行为审计和回归测试固定再迁移；任何有意删减都必须单列理由、影响与替代路径，并经确认后实施，不得在重写中静默降级。
- **BOOT-013 — 冷启动依赖最小化。** Windows Stage-0 只获取构建当前 Rust 产品必需的 minimal Rust 与 MSVC 工具链，不获取 `rustfmt`、Bun 或内置 Pwsh；开发工具与脚本 Facet runtime 由出现真实消费者后的独立 setup 协议负责。
- **BOOT-016 — Windows 物理路径有界。** 对仍受 `MAX_PATH` 约束的 MSVC/MSI 工具链，物理目录使用由完整身份确定的短 locator（工具链为 `tc-<128-bit hash prefix>`），完整 256-bit 身份仍由唯一 metadata 保存并校验；locator 冲突必须拒绝，不能误用已有内容。
- **BOOT-017 — 外部载荷身份。** Contract 直接锚定的固定文件必须同时校验精确长度与 SHA-256；Microsoft 子载荷清单中的 `size` 只作为有界下载的声明值，实际身份以非空实际长度和清单 SHA-256 为准，并同时记录声明长度与实际长度。
- **BOOT-018 — 持久清单确定性。** 写入身份或完整性 metadata 的无序集合必须先按协议规定的、与文化和 PowerShell 版本无关的 ordinal 顺序规范化；Windows 路径先按 `OrdinalIgnoreCase`、再按 `Ordinal` 决胜，验证不得依赖文件系统枚举顺序或 `Sort-Object` 默认语义。
- **BOOT-019 — 工具链校验分层。** 安装时从完整文件树生成确定性摘要，但持久收据只保存该摘要、来源证明与少量关键文件记录；日常复用只执行快速收据检查，完整树遍历与 Hash 只能由显式 Full audit 触发，不得进入 Entry executable 或 Bootstrap 默认路径。
- **BOOT-021 — Candidate 不可变。** Build 必须在释放构建锁前把产物固化为内容寻址、可独立验证的不可变 Candidate，Publish 不得引用仍可被后续 Cargo 构建覆盖的 target artifact 或共享 mutable `candidate.json`。
- **BOOT-022 — 工具链由 Contract 选择。** Bootstrap 工具链是由平台 Contract、target 与安装 recipe 共同确定的不可变构建输入；不得再用 mutable `current.*` 或生成脚本中的硬编码 ToolchainId 建立第二选择源。
- **BOOT-024 — 构建环境属于子进程。** MSVC、SDK、Rust 与 Cargo 环境只注入实际工具子进程，不修改再恢复父 PowerShell 进程，也不生成需要 dot-source 的环境脚本；工具入口必须使用显式受支持的 executable 映射。
- **BOOT-025 — 内容寻址安装只前进发布。** Toolchain 与 Candidate 等内容寻址对象只允许从已验证 stage 原子移动到不存在的目标；损坏目标可在同一身份锁内移除后重建，不为不会被合法覆盖的旧对象维护通用 backup/rollback 协议。
- **BOOT-027 — Microsoft 许可非交互接受。** Windows Contract 必须固定 Microsoft Build Tools 许可地址与 `by-bootstrap-invocation` 接受方式；首次获取该工具链载荷前必须输出许可地址，调用 Bootstrap 即表示接受，不得弹出交互确认，MSI 必须显式禁止自动重启。
- **BOOT-028 — VS 产品线显式固定。** Windows Bootstrap v3 固定使用 VS 2026 stable 产品线及一个经长度与 SHA-256 锚定的精确 package manifest；不得在运行时解析 `latest`，升级必须同时修改 Contract、安装 recipe 与验收测试。
- **BOOT-045 — 仓库根 Windows 构建入口。** 根 `build.cmd` 是无业务逻辑的 Windows 适配器，只以 `<repository>/data` 调用 `bootstrap/windows/main.ps1` 并原样传播退出码；它不得复制 Entry executable、创建 Entry 或输出人工复制指引。
- **BOOT-050 — 显式 Bootstrap 发布三种产品。** `bootstrap/windows/main.ps1` 每次调用都先构建 Core、Entry executable 与 Entry Manager 的全部 Candidate，再分别发布到各自 ReleaseRoot；已有 selector 不得跳过构建，内容未改变时复用 ReleaseId。
- **BOOT-049 — Windows Stage-0 作者布局。** `bootstrap/windows/builder` 保存跨产品 Candidate、Release 与基础机制，`toolchain` 独占构建工具链领域，`core`、`entry` 与 `entry.manager` 分别拥有 Core、Entry executable 与 Entry Manager 产品适配器；`main.ps1` 是先构建全部 Candidate、再发布并核验 selector 的唯一多产品编排器。
- **BOOT-055 — 平台与产品 Contract 分治。** `bootstrap/windows/contract.json` v3 只声明 target、Rust 与 MSVC 平台事实；`core/contract.json`、`entry/contract.json`、`entry.manager/contract.json` 分别声明各自产物事实，不得由平台 Contract 的泛称 `product` 暗指 Core。
- **BOOT-056 — Windows Rust 产品静态 CRT。** Windows Core 与 Entry Manager 的产品 Contract 必须显式要求静态 CRT，构建必须把该要求投影为 Cargo/rustc 命令行配置；验收必须读取发布 PE 的 import table，并拒绝 `VCRUNTIME`、`UCRT` 或其他外部 C/C++ runtime 依赖。
- **BOOT-057 — 多产品发布串行边界。** `bootstrap/windows/publication.ps1` 是 `main.ps1` 使用的内部 target-scoped 发布边界，其锁覆盖三种产品的发布、selector 回读与本轮结果核验；产品目录内的 `publish.ps1` 只是适配器，不是受支持的并发多产品入口。
- **BOOT-044 — 工具链入口与代码信任边界。** `toolchain-setup.ps1` 显式安装或修复 Contract 指定的工具链，`toolchain.ps1` 只从作者态 `bootstrap/windows` 解析并运行 `BootstrapWindowsRoot/toolchains` 中的已安装工具；两个 Windows Bootstrap 数据根都不得发布供用户执行的脚本。
- **BOOT-042 — Windows 路径预算。** Windows Bootstrap v3 的规范化 DataRoot 最长 50 个 UTF-16 code unit，必须在下载或安装前拒绝超限路径；该上限与缩短后的物理布局共同保持原有最坏绝对路径预算不变。
- **ENTRY-EXEC-001 — Entry executable 运行协议暂缓。** 当前 `swaw-harness-entry.exe` 只验证无 CRT 原生编译、大小约束与不可变发布，执行时必须显式失败；在 Entry Manager 垂直样例确认运行布局前，不得迁入旧实现的寻址、manager、Bootstrap 或环境变量协议。
- **ENTRY-MANAGER-EXEC-001 — Entry Manager 控制面板暂缓。** 当前 Entry Manager executable 只验证独立构建、静态 CRT、大小约束与不可变发布，执行时必须以非零退出码和明确的未实现诊断失败；选择、命名、创建、删除与恢复是已接受的目标职责，不是当前已实现的控制面板能力。
- **ENTRY-MANAGER-002 — Entry 管理器独立。** Entry Manager 是作者项目 `bootstrap/windows/entry.manager` 产生的独立 executable，其目标职责是 Entry executable 的选择、命名、创建、删除与恢复，当前实施边界由 `ENTRY-MANAGER-EXEC-001` 界定；Entry executable 不自复制，根 `build.cmd` 也不创建 Entry。
- **RELEASE-011 — Core 发布池身份。** `DataRoot/core.release/<release-id>/` 是 Bootstrap 产生的共享不可变 Core 发布池；`release-id` 的 Hash 必须覆盖完整发布内容及含 target 的发布元数据，不能只散列源码 revision。
- **RELEASE-014 — Bootstrap Target Selector。** Core、Entry executable 与 Entry Manager 的 ReleaseRoot 都各自保存只含 Release 引用的 `current.<target-id>`；Publish 只原子更新本产品、本 target 的 selector，并验证所指 Release 的 target 兼容性。

## Proposed

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

## Open

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
- **ENTRY-ID-001 — EntryId 语法。** EntryId 的大小写归一、长度、可移植字符集与 Windows 保留名仍需确定；目录映射不得直接接受任意 Unicode basename。
- **TARGET-ID-001 — TargetId 编码。** TargetId 必须区分二进制不兼容目标，至少包含 OS 与 CPU architecture，并在必要时包含 ABI；采用 Rust target triple 还是稳定 Swaw `os-arch-abi` 名称，仍需由第一个 Windows publish 样例验证。
- **BUILD-REPRO-001 — Windows 可复现链接。** 当前 MSVC `link.exe` 的全新构建会把链接时间写入 PE，使同源码与同工具链仍可能产生字节不同但各自内容寻址正确的 Release；是否改用 `lld-link` 或建立更完整的 reproducible-build contract，必须在真实原生依赖样例出现后决议，不能仅追加 `/Brepro` 就宣称可复现。

## Superseded

- **LAUNCHER-RELEASE-002 — Launcher Release 空间。** 本规则曾使用 `LauncherReleaseRoot` 与 `DataRoot/launcher.release`；当前实体名、路径与产物名已由 `TERM-001`、`ENTRY-RELEASE-001` 取代。
- **LAUNCH-006 — Launcher 运行协议暂缓。** 本规则曾用旧产品名和 `template.harness.exe` 描述占位产物；当前名称与产物由 `ENTRY-EXEC-001` 取代。
- **RELEASE-013 — Bootstrap Target Selector。** 本规则曾以 Launcher 命名第二个发布产品；当前三产品 selector 术语由 `RELEASE-014` 取代。
- **ENTRY-001 — 启动器文件名是 Entry 身份。** 本规则曾允许复制或重命名 Launcher 形成新 Entry；Entry 创建权与双重身份核验已由 `ENTRY-002`、`ENTRY-LAYOUT-003` 和 `ENTRY-MANAGER-002` 取代。
- **LAUNCHER-RELEASE-001 — Launcher Release 空间。** 本规则曾把 Entry Manager 描述为未来组件；其职责先由 `LAUNCHER-RELEASE-002` 收敛，当前实体命名与独立发布由 `ENTRY-RELEASE-001`、`ENTRY-MANAGER-RELEASE-001` 取代。
- **BOOT-046 — 显式 Bootstrap 发布两种产品。** 本规则曾只发布 Core 与 Launcher；三产品构建发布边界已由 `BOOT-050` 取代。
- **BOOT-048 — Windows Stage-0 作者布局。** 本规则曾使用 `launcher` 作者目录且没有 Entry Manager 产品；当前布局已由 `BOOT-049` 取代。
- **ENTRY-MANAGER-001 — Entry 创建职责独立。** 本规则曾把 Entry Manager 预留在仓库根；当前独立作者项目与职责由 `ENTRY-MANAGER-002` 取代。
- **RELEASE-012 — Bootstrap Target Selector。** 本规则只覆盖 Core 与旧称 Launcher 的 selector；三产品 selector 协议先由 `RELEASE-013` 扩展，当前术语由 `RELEASE-014` 取代。
- **ENTRY-RUNTIME-001 — Entry 文件与数据同名配对。** 本规则曾把配对布局保留为候选；该布局及其非原子状态协议已由 `ENTRY-LAYOUT-003`、`ENTRY-LIFECYCLE-001` 和 `ENTRY-RECOVERY-001` 接受。
- **BOOT-047 — 产品构建分治、发布事务共享。** Core 与 Launcher 曾各自拥有编译脚本与 Contract，而 Candidate、Release 和工具链实现共同位于 `_lib`；该内部库先由 `BOOT-048` 拆分，当前布局继续由 `BOOT-049` 约束。
- **BOOT-035 — 仓库根 Windows 构建入口。** 根 `build.cmd` 曾只构建 Core 并把 Launcher 留待未来；当前入口边界已由 `BOOT-045`、`BOOT-050` 取代。
- **BOOT-036 — 显式 Bootstrap 发布共享 Core。** `main.ps1` 曾只发布 Core；当前三产品发布已由 `BOOT-050` 取代。
- **BOOT-043 — Windows Build 与 Publish 分离。** Core 曾独占 `BootstrapWindowsCacheRoot/build` 且共享层不得承担 Launcher 职责；两个真实产品出现后，产品缓存分治与共享发布事务已由 `BOOT-047` 取代。
- **LAUNCH-005 — Launcher 只读启动。** 旧称 Launcher 曾被约束为直接解析 `DataRoot/core.release/current.<target-id>`；该运行协议先由 `LAUNCH-006` 暂缓，当前由 `ENTRY-EXEC-001` 与 `ENTRY-LAYOUT-003` 约束。
- **LAUNCH-002 — 缺失 Release 显式失败。** Launcher 曾被要求提示运行根 `build.cmd`；缺失 Entry/Core 的修复职责现归 `ENTRY-MANAGER-002` 的独立 Manager。
- **RELEASE-009 — 共享 Core 内容寻址池。** 本规则曾进一步承诺所有 Entry 直接共享此池；当前只接受 Bootstrap 发布池本身，Entry 如何引用由 `RELEASE-011`、`ENTRY-CORE-001` 取代。
- **RELEASE-010 — Core Target Selector。** 本规则曾把 Bootstrap Core selector 直接规定为旧称 Launcher 的运行 selector；发布侧 selector 现由 `RELEASE-014` 保留，Entry 运行路径仍由 `ENTRY-EXEC-001` 暂缓。

- **CORE-RELEASE-001 — Core Release 空间。** `CoreReleaseRoot` 唯一映射为 `DataRoot/core_release`，直接保存共享 Core Release 与 target selector；不增加无独立职责的 `_core` 中间层。其顶层命名已由 `CORE-RELEASE-002` 的点号命名空间取代。
- **LAUNCH-004 — Launcher 只读启动。** Launcher 只解析并验证 `DataRoot/core_release/current.<target-id>` 指向的共享不可变 Core Release，不调用 Bootstrap、不联网、不构建，也不扫描 `core/target` 或比较源码时间。其 selector 路径已由 `LAUNCH-005` 取代。
- **RELEASE-007 — 共享 Core 内容寻址池。** 所有 Entry 与不同 target 共享 `DataRoot/core_release/<release-id>/` 中的不可变 Core Release；`release-id` 的 Hash 必须覆盖完整发布内容及含 target 的发布元数据，不能只散列源码 revision。其路径已由 `RELEASE-009` 取代。
- **RELEASE-008 — Core Target Selector。** `DataRoot/core_release/current.<target-id>` 是只含 Release 引用的普通 selector 文件，Publish 只原子更新本 target 的 selector，Launcher 必须同时校验所指 Release 的 target 兼容性。其路径已由 `RELEASE-010` 取代。
- **BOOTSTRAP-DATA-001 — Bootstrap 数据空间。** `BootstrapDataRoot` 唯一映射为 `DataRoot/bootstrap`，各平台只写 `BootstrapDataRoot/<platform>`；Windows 的受控写边界是 `DataRoot/bootstrap/windows`，不得覆盖其他平台数据。其嵌套平台根与单一生命周期已由 `BOOTSTRAP-DATA-002` 取代。
- **DATA-LIFECYCLE-002 — 数据空间按所有者分治。** `DataRoot/bootstrap` 保存可重建的 Bootstrap 状态，`DataRoot/core_release` 保存发布后不可变的 Release 与可原子替换的 selector；各 owner 只能修改自己的受控根，后者不得作为 cache 整体清理。Windows Bootstrap 的状态与 cache 已由 `DATA-LIFECYCLE-003` 分离。
- **ENTRY-CACHE-001 — Entry cache 所有者显式。** `EntryRoot/cache` 只保存 Entry-local cache；不得与 `BootstrapDataRoot` 隐式 fallback、复制或同步。旧 Bootstrap 根已由 `ENTRY-CACHE-002` 取代。
- **BOOT-040 — Windows Build 与 Publish 分离。** `bootstrap/windows/build.ps1` 只在 `DataRoot/bootstrap/windows/build` 产生 Candidate，`bootstrap/windows/publish.ps1` 只验证 Candidate、内容寻址发布到 `CoreReleaseRoot` 并原子更新 selector；二者都不得承担 Launcher 职责。其 Candidate 路径已由 `BOOT-043` 取代。
- **BOOT-041 — 工具链入口与代码信任边界。** `toolchain-setup.ps1` 显式安装或修复 Contract 指定的工具链，`toolchain.ps1` 只从作者态 `bootstrap/windows` 解析并运行已安装工具；`DataRoot/bootstrap/windows` 只保存数据与不可变载荷，不发布供用户执行的脚本。其数据根已由 `BOOT-044` 取代。
- **DATA-LIFECYCLE-001 — 同根不同生命周期。** 共处 CoreDataRoot 不表示共享写权限或删除策略：cache 可清理，Release 发布后不可变，各 owner 只能修改自己的受控子树。无职责的 CoreDataRoot 聚合已由 `DATA-LIFECYCLE-003` 的独立生命周期根取代。
- **CORE-DATA-001 — CoreDataRoot。** CoreDataRoot 唯一映射为 `DataRoot/_core`，当前只定义 `cache/` 与 `releases/` 两个子树；CoreDataRoot 本身不得被整体视为可清理 cache，也不得预建推测用途。该中间层已由 `BOOTSTRAP-DATA-002` 与 `CORE-RELEASE-002` 取代。
- **CACHE-004 — Cache 所有者显式。** `DataRoot/_core/cache` 只保存可跨 Entry 复用且可重建的 Core cache，`EntryRoot/cache` 只保存 Entry-local cache；调用方必须显式选择其一，不允许隐式 fallback 或复制同步。Bootstrap cache 与 Entry cache 已由 `DATA-LIFECYCLE-003`、`ENTRY-CACHE-002` 分别约束。
- **BOOT-037 — Windows Build 与 Publish 分离。** `bootstrap/windows/build.ps1` 只在 `DataRoot/_core/cache` 产生 Candidate，`bootstrap/windows/publish.ps1` 只验证 Candidate、内容寻址发布到共享 Core releases 并原子更新 selector；二者都不得承担 Launcher 职责。其路径已由 `BOOT-043` 取代。
- **BOOT-038 — 工具链入口与代码信任边界。** `toolchain-setup.ps1` 显式安装或修复 Contract 指定的工具链，`toolchain.ps1` 只从作者态 `bootstrap/windows` 解析并运行已安装工具；`DataRoot/_core/cache` 只保存数据与不可变载荷，不发布供用户执行的脚本。其数据路径已由 `BOOT-044` 取代。
- **BOOT-039 — Windows 路径预算。** Windows Bootstrap v2 的规范化 DataRoot 最长 38 个 UTF-16 code unit，必须在下载或安装前拒绝超限路径。缩短后的物理布局已由 `BOOT-042` 在相同最坏路径预算下放宽 DataRoot。
- **LAUNCH-003 — Launcher 只读启动。** Launcher 只解析并验证 `DataRoot/_core/releases/current.<target-id>` 指向的共享不可变 Core Release，不调用 Bootstrap、不联网、不构建，也不扫描 `core/target` 或比较源码时间。其路径已由 `LAUNCH-005` 取代。
- **RELEASE-005 — 共享 Core 内容寻址池。** 所有 Entry 与不同 target 共享 `DataRoot/_core/releases/<release-id>/` 中的不可变 Core Release；`release-id` 的 Hash 必须覆盖完整发布内容及含 target 的发布元数据，不能只散列源码 revision。其路径已由 `RELEASE-009` 取代。
- **RELEASE-006 — Core Target Selector。** `DataRoot/_core/releases/current.<target-id>` 是只含 Release 引用的普通 selector 文件，Publish 只原子更新本 target 的 selector，Launcher 必须同时校验所指 Release 的 target 兼容性。其路径已由 `RELEASE-010` 取代。
- **ARC-001 — 三种空间分离。** 源码/作者空间、不可变发布/执行空间、可变数据空间必须分离；逻辑地址可以映射它们，但不得把三者合并为同一棵可写目录树。该物理根限制已由 `VAR-002`、`VAR-003` 取代，生命周期与写权限分离仍然保留。
- **VAR-001 — 单一 VarRoot。** Harness 自写的 cache、Release、Run、Export 与领域状态必须位于一个用户可配置的绝对 `VarRoot` 下；`source` 与 `docs` 不属于 `VarRoot`，各运行目录只从该根确定性派生。该实体 `var/` 层级已由 `VAR-003`、`VAR-NAME-001` 的共同父目录与扁平 `var_*` 空间取代。
- **VAR-003 — 单一可配置父目录。** `VarRoot` 是用户只需配置一次的绝对父目录，Harness 自写根目录都由它确定性派生；默认布局可让 `source`、`docs` 与 `var_*` 共用父目录，但只有 `var_*` 属于 Harness 管理的运行数据。其共同父目录语义已由实体 `<repository>/var` 与 `VAR-004` 取代。
- **VAR-NAME-001 — 扁平 Var 空间命名。** Harness 管理的顶层运行目录使用保留的 `var_<kind>` snake_case 名称，当前定义 `var_cache` 与 `var_entry`。该扁平布局已由 `VAR-004`、`CORE-LAYOUT-001` 的 `var/_core/{cache,releases}` 取代。
- **CACHE-001 — Cache 所有者显式。** `VarRoot/cache` 只保存可跨 Entry 复用的共享 cache，`EntryRoot/cache` 只保存 Entry-local cache；调用方必须显式选择其一，不允许隐式 fallback 或复制同步。其物理路径已由 `CACHE-002` 取代。
- **CACHE-002 — Cache 所有者显式。** `VarRoot/var_cache` 只保存可跨 Entry 复用的共享 cache，`VarRoot/var_entry/<entry-id>/cache` 只保存 Entry-local cache。其 Core cache 物理路径已由 `CACHE-003` 取代。
- **ENTRY-LAYOUT-001 — EntryRoot。** EntryRoot 唯一映射为 `VarRoot/var_entry/<entry-id>`。共享 Core 迁入实体 `var/_core` 后，EntryRoot 物理布局已由 `ENTRY-LAYOUT-002` 重新开放，不能沿用本规则实现。
- **DEV-003 — 垂直样例驱动。** 新协议先在 `source/templates/helloworld` 形成端到端验收。其作者态路径已由 `DEV-005` 取代。
- **DEV-004 — 单变量演进。** `source/templates/helloworld` 每次只引入一个待验证的外部协议能力。其作者态路径已由 `DEV-006` 取代。
- **VAR-002 — 同根不同生命周期。** 共处 `VarRoot` 不表示共享写权限或删除策略。`VarRoot` 术语已由 `DATA-LIFECYCLE-001` 的 CoreDataRoot 取代。
- **VAR-004 — 单一可配置运行根。** `VarRoot` 默认映射为 `<repository>/var`。其命名与职责已由 `DATA-ROOT-001` 取代。
- **CORE-LAYOUT-001 — CoreRoot。** CoreRoot 映射为 `VarRoot/_core`。其无歧义名称与新根路径已由 `CORE-DATA-001` 取代。
- **CACHE-003 — Cache 所有者显式。** Core cache 位于 `VarRoot/_core/cache`。其新根路径已由 `CACHE-004` 取代。
- **ENTRY-LAYOUT-002 — EntryRoot 物理布局。** EntryRoot 在 VarRoot 下的位置曾保持开放。用户已确定仓库内独立 `data.entry` 空间，该问题由 `ENTRY-DATA-001` 取代。
- **DEV-001 — 垂直样例驱动。** 新的 Core 或 Facet 协议必须先在 `templates/helloworld` 形成最小端到端实现与黑盒验收，通过后才扩展到其他模块。其路径已由 `DEV-003` 取代。
- **DEV-002 — 单变量演进。** `templates/helloworld` 每次只引入一个待验证的外部协议能力，不为尚未出现的复用、类型或执行模式预建抽象。其路径已由 `DEV-004` 取代。
- **BOOT-002 — 唯一 Bootstrap 入口。** `bootstrap/main.ps1` 是 Launcher 和人工调用的唯一 Bootstrap 入口，由它持锁、重新检查 Release 并编排 build 与 publish；Launcher 不得直接调用内部脚本。其平台路径已由 `BOOT-006`、`BOOT-007` 取代。
- **BOOT-003 — Launcher 只认 Release。** Launcher 只验证 `var_entry/<entry-id>/releases/current` 选择的不可变 Release；没有可用 Release 时才调用 Bootstrap，绝不扫描 `source/target`、比较源码时间或执行 Cargo。其单一 selector 路径已由 `BOOT-010` 取代。
- **BOOT-004 — Build 与 Publish 分离。** `bootstrap/build.ps1` 只在 `var_cache` 中产生候选构建，`bootstrap/publish.ps1` 只负责验证候选、内容寻址发布到 Entry releases 并原子更新 selector；两者都不得承担 Launcher 职责。其 Windows 路径已由 `BOOT-009` 取代。
- **BOOT-005 — 发布后重新解析。** Bootstrap 成功返回后，Launcher 必须重新读取并验证 `current` 再执行 Release；Bootstrap 不直接启动产品，也不通过临时路径或 stdout 绕过已发布 selector。其 target-specific selector 语义已由 `BOOT-011` 取代。
- **BOOT-007 — Windows 唯一入口。** `bootstrap/windows/main.ps1` 是 Windows Launcher 和人工调用的唯一 Bootstrap 入口，由它持锁、重新检查 Release 并编排同目录的 `build.ps1` 与 `publish.ps1`；Launcher 不得直接调用内部脚本。其“已有 Release 时跳过显式构建”语义已由 `BOOT-020` 取代，Launcher 仍只调用 `main.ps1`，工具链维护入口由 `BOOT-023` 单独约束。
- **BOOT-009 — Windows Build 与 Publish 分离。** `bootstrap/windows/build.ps1` 只在 `var_cache` 中产生候选构建，`bootstrap/windows/publish.ps1` 发布到 Entry releases。其存储所有者与路径已由 `BOOT-031` 取代。
- **BOOT-010 — Launcher 只认目标 Release。** Launcher 验证 Entry-local Release，缺失时调用 Bootstrap。其 Entry-local 发布与可写启动语义已由 `LAUNCH-001`、`LAUNCH-002` 取代。
- **BOOT-011 — Bootstrap 后重新解析。** Bootstrap 成功后 Launcher 重新解析 selector。Launcher 不再调用 Bootstrap，该流程已由 `BOOT-029`、`LAUNCH-001`、`LAUNCH-002` 取代。
- **BOOT-020 — 显式 Bootstrap 总是发布当前构建。** Launcher 在 Release 缺失时调用 `main.ps1`，而显式 `main.ps1` 总是 Build 与 Publish。前一职责已删除，后一职责由 `BOOT-030` 取代。
- **BOOT-023 — 工具链入口与代码信任边界。** 作者态入口解析工具链，`var_cache` 只保存数据与载荷。其 cache 路径已由 `BOOT-032` 取代。
- **BOOT-026 — Windows 路径预算。** Windows Bootstrap v2 的规范化 `VarRoot` 最长 40 个 UTF-16 code unit。迁入更长的 `_core/cache` 后已由保持相同最坏路径长度的 `BOOT-033` 取代。
- **BOOT-001 — Stage-0 边界。** `source/` 是完整 Rust workspace。其作者态路径已由 `BOOT-034` 取代。
- **BOOT-029 — 仓库根 Windows 构建入口。** 根 `build.cmd` 以 `<repository>/var` 调用 Windows Bootstrap。其默认数据路径已由 `BOOT-035` 取代。
- **BOOT-030 — 显式 Bootstrap 发布共享 Core。** `main.ps1` 接收 VarRoot 并发布共享 Core。其参数术语已由 `BOOT-036` 取代。
- **BOOT-031 — Windows Build 与 Publish 分离。** Candidate 与 Release 位于 `VarRoot/_core`。其数据根路径已由 `BOOT-037` 取代。
- **BOOT-032 — 工具链入口与代码信任边界。** 工具链数据位于 `VarRoot/_core/cache`。其数据根路径已由 `BOOT-038` 取代。
- **BOOT-033 — Windows 路径预算。** Windows Bootstrap v2 的 VarRoot 最长 38 个 UTF-16 code unit。其参数术语已由 `BOOT-039` 取代。
- **LAUNCH-001 — Launcher 只读启动。** Launcher 从 `VarRoot/_core/releases` 启动且不扫描 `source/target`。其路径已由 `LAUNCH-003` 取代。
- **BOOT-014 — 工具链状态单一。** Bootstrap 只发布一个权威工具链完整性 metadata；构建环境在 Bootstrap 进程内应用并在退出时恢复，不生成重复的 `env.cmd`、`env.ps1`、`state.json` 与 `environment.json` 状态源。其父进程环境修改方式已由 `BOOT-024` 取代，单一 metadata 约束继续由 `BOOT-022` 保留。
- **BOOT-015 — 只恢复当前协议。** `swaw-harness` 只识别和恢复自身当前协议命名的安装 work、partial 与带时间戳 backup，不兼容不存在于新仓库历史中的 `swaw-kit` 或无序旧 backup 格式。通用 backup/rollback 已由 `BOOT-025` 的内容寻址只前进发布取代。
- **RELEASE-TARGET-001 — Release target 隔离。** 跨平台 VarRoot 中的 Release 与 `current` 必须按 host target 隔离；采用 Rust target triple、稳定 Swaw platform id 或其他目录形态仍需由第一个 Windows publish 样例验证。其目录形态已由 `RELEASE-001`、`RELEASE-002` 确定，剩余 TargetId 编码问题由 `TARGET-ID-001` 承接。
- **RELEASE-001 — Entry-local 内容寻址池。** 不同 target 的不可变 Release 共存于 `var_entry/<entry-id>/releases/<release-id>/`。其 Entry-local 所有权已由共享 Core 池 `RELEASE-003` 取代。
- **RELEASE-002 — Entry-local Target Selector。** `var_entry/<entry-id>/releases/current.<target-id>` 选择 Entry-local Release。其路径已由共享 Core selector `RELEASE-004` 取代。
- **RELEASE-003 — 共享 Core 内容寻址池。** 共享 Release 位于 `VarRoot/_core/releases/<release-id>`。其根路径已由 `RELEASE-005` 取代。
- **RELEASE-004 — Core Target Selector。** selector 位于 `VarRoot/_core/releases/current.<target-id>`。其根路径已由 `RELEASE-006` 取代。
