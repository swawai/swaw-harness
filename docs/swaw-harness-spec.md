# Swaw Harness 核心架构规范

本文是 Swaw Harness 架构与协议的唯一事实源。每条规则保持一至两句话；未来验收脚本只引用稳定规则 ID，不从散文推断要求。

状态：`Accepted` 表示已确认并约束实现；`Proposed` 表示建议方案；`Open` 表示仍需决议；`Superseded` 表示已被新规则替代。

## Accepted

- **HAR-001 — 独立产品仓库。** `swaw-harness` 是 Swaw 品牌下的独立产品仓库，必须脱离 `swaw-kit` 的父目录和源码树独立构建、测试、打包与发布。
- **HAR-002 — 文档职责单一。** 本文件记录架构与协议，`AGENTS.md` 记录维护规则，`README.md` 只做人类入口；三者不得复制同一规范正文。
- **ARC-002 — 源码就近归属。** 实现应下沉到最近的稳定领域所有者；放在父领域 crate 可以接受，但必须按领域拆开，不能长期集中在总入口或总 dispatcher。
- **ARC-003 — 可独立执行。** 命令领域的核心实现应位于 library API，进程入口保持薄；因此模块可在确有发布或隔离需要时增加独立 executable，而无需重写业务逻辑。
- **ARC-004 — 边界按代价建立。** CLI 目录不等于 Cargo package 或进程边界；只有稳定领域、独立依赖、独立发布或故障隔离需求成立时才拆 crate/executable。
- **ARC-005 — 唯一生产路径。** 一个命令在一个发行档中只能有一个主执行模式；从 built-in 迁为 sidecar 时必须 hard cut 旧路径，不长期并存多种生产入口。
- **TPL-001 — 标准模块边界。** 标准 Rust 模块把领域行为放在 library API，并只用薄 executable 处理进程输入输出；模块必须可由 workspace 独立编译、测试和运行。
- **DEV-003 — 垂直样例驱动。** 新的 Core 或 Facet 协议必须先在 `source/templates/helloworld` 形成最小端到端实现与黑盒验收，通过后才扩展到其他模块。
- **DEV-004 — 单变量演进。** `source/templates/helloworld` 每次只引入一个待验证的外部协议能力，不为尚未出现的复用、类型或执行模式预建抽象。
- **VAR-002 — 同根不同生命周期。** 共处 `VarRoot` 不表示共享写权限或删除策略：cache 可清理，Release 发布后不可变，Run 与领域状态必须持久，各 owner 只能修改自己的受控子树。
- **ENTRY-001 — 启动器文件名是 Entry 身份。** 合法的 launcher basename 确定 EntryId 与唯一 EntryRoot；替换同名 launcher 保留 EntryRoot，复制或重命名为另一 basename 必须选择隔离的 EntryRoot。
- **VAR-003 — 单一可配置父目录。** `VarRoot` 是用户只需配置一次的绝对父目录，Harness 自写根目录都由它确定性派生；默认布局可让 `source`、`docs` 与 `var_*` 共用父目录，但只有 `var_*` 属于 Harness 管理的运行数据。
- **VAR-NAME-001 — 扁平 Var 空间命名。** Harness 管理的顶层运行目录使用保留的 `var_<kind>` snake_case 名称，`kind` 使用单数资源种类而非集合语法；当前定义 `var_cache` 与 `var_entry`，不得因推测未来空间而预建更多目录。
- **ENTRY-LAYOUT-001 — EntryRoot。** EntryRoot 唯一映射为 `VarRoot/var_entry/<entry-id>`；`var_entry` 只容纳 EntryId，不与平台保留目录或其他资源种类混排。
- **CACHE-002 — Cache 所有者显式。** `VarRoot/var_cache` 只保存可跨 Entry 复用的共享 cache，`VarRoot/var_entry/<entry-id>/cache` 只保存 Entry-local cache；调用方必须显式选择其一，不允许隐式 fallback 或复制同步。
- **BOOT-001 — Stage-0 边界。** 根 `bootstrap/` 保存无需已编译 Harness 即可运行的作者态 Stage-0 实现，`source/` 是完整 Rust workspace 且不承担获取自身编译环境的职责。
- **BOOT-006 — Bootstrap 按宿主平台归属。** 平台实现位于 `bootstrap/<platform>/`，目录名表达宿主平台而非脚本解释器；当前只建立 `windows`，未来按真实实现增加 `linux`、`macos`，不得预建空 `posix` 或抽象共享层。
- **BOOT-008 — 平台 Contract 就近归属。** Windows 工具链版本、host target、下载来源与校验事实由 `bootstrap/windows/contract.json` 唯一声明；第二个平台出现真实共同字段前，不建立跨平台 contract 合并或继承体系。
- **BOOT-009 — Windows Build 与 Publish 分离。** `bootstrap/windows/build.ps1` 只在 `var_cache` 中产生候选构建，`bootstrap/windows/publish.ps1` 只负责验证候选、内容寻址发布到 Entry releases 并原子更新 selector；两者都不得承担 Launcher 职责。
- **BOOT-010 — Launcher 只认目标 Release。** Launcher 只验证 `var_entry/<entry-id>/releases/current.<target-id>` 指向的不可变 Release；没有兼容 Release 时才调用 Bootstrap，绝不扫描 `source/target`、比较源码时间或执行 Cargo。
- **BOOT-011 — Bootstrap 后重新解析。** Bootstrap 成功返回后，Launcher 必须重新读取并验证本机的 `current.<target-id>` 再执行 Release；Bootstrap 不直接启动产品，也不通过临时路径或 stdout 绕过已发布 selector。
- **BOOT-012 — Bootstrap 迁移保真。** 旧 Bootstrap 的可观察功能与安全不变量必须先由行为审计和回归测试固定再迁移；任何有意删减都必须单列理由、影响与替代路径，并经确认后实施，不得在重写中静默降级。
- **BOOT-013 — 冷启动依赖最小化。** Windows Stage-0 只获取构建当前 Rust 产品必需的 minimal Rust 与 MSVC 工具链，不获取 `rustfmt`、Bun 或内置 Pwsh；开发工具与脚本 Facet runtime 由出现真实消费者后的独立 setup 协议负责。
- **BOOT-016 — Windows 物理路径有界。** 对仍受 `MAX_PATH` 约束的 MSVC/MSI 工具链，物理目录使用由完整身份确定的短 locator（工具链为 `tc-<128-bit hash prefix>`），完整 256-bit 身份仍由唯一 metadata 保存并校验；locator 冲突必须拒绝，不能误用已有内容。
- **BOOT-017 — 外部载荷身份。** Contract 直接锚定的固定文件必须同时校验精确长度与 SHA-256；Microsoft 子载荷清单中的 `size` 只作为有界下载的声明值，实际身份以非空实际长度和清单 SHA-256 为准，并同时记录声明长度与实际长度。
- **BOOT-018 — 持久清单确定性。** 写入身份或完整性 metadata 的无序集合必须先按协议规定的、与文化和 PowerShell 版本无关的 ordinal 顺序规范化；Windows 路径先按 `OrdinalIgnoreCase`、再按 `Ordinal` 决胜，验证不得依赖文件系统枚举顺序或 `Sort-Object` 默认语义。
- **BOOT-019 — 工具链校验分层。** 安装时从完整文件树生成确定性摘要，但持久收据只保存该摘要、来源证明与少量关键文件记录；日常复用只执行快速收据检查，完整树遍历与 Hash 只能由显式 Full audit 触发，不得进入 Launcher 或 Bootstrap 默认路径。
- **BOOT-020 — 显式 Bootstrap 总是发布当前构建。** Launcher 只在没有有效目标 Release 时调用 `main.ps1`，但 `main.ps1` 一旦被显式调用就必须执行 Build 与 Publish，不得因已有 selector 而跳过当前源码构建；产物内容未改变时复用同一 ReleaseId 仍属于一次幂等发布。
- **BOOT-021 — Candidate 不可变。** Build 必须在释放构建锁前把产物固化为内容寻址、可独立验证的不可变 Candidate，Publish 不得引用仍可被后续 Cargo 构建覆盖的 target artifact 或共享 mutable `candidate.json`。
- **BOOT-022 — 工具链由 Contract 选择。** Bootstrap 工具链是由平台 Contract、target 与安装 recipe 共同确定的不可变构建输入；不得再用 mutable `current.*` 或生成脚本中的硬编码 ToolchainId 建立第二选择源。
- **BOOT-023 — 工具链入口与代码信任边界。** `toolchain-setup.ps1` 显式安装或修复 Contract 指定的工具链，`toolchain.ps1` 只从作者态 `bootstrap/windows` 解析并运行已安装工具；`var_cache` 只保存数据与不可变载荷，不发布供用户执行的脚本。
- **BOOT-024 — 构建环境属于子进程。** MSVC、SDK、Rust 与 Cargo 环境只注入实际工具子进程，不修改再恢复父 PowerShell 进程，也不生成需要 dot-source 的环境脚本；工具入口必须使用显式受支持的 executable 映射。
- **BOOT-025 — 内容寻址安装只前进发布。** Toolchain 与 Candidate 等内容寻址对象只允许从已验证 stage 原子移动到不存在的目标；损坏目标可在同一身份锁内移除后重建，不为不会被合法覆盖的旧对象维护通用 backup/rollback 协议。
- **BOOT-026 — Windows 路径预算。** Windows Bootstrap v2 的规范化 `VarRoot` 最长 40 个 UTF-16 code unit，必须在下载或安装前拒绝超限路径；同一 ToolchainId 的安装 work 已由独占锁串行，固定使用短 `p`、`m` child，不再追加无意义 GUID。
- **BOOT-027 — Microsoft 许可非交互接受。** Windows Contract 必须固定 Microsoft Build Tools 许可地址与 `by-bootstrap-invocation` 接受方式；首次获取该工具链载荷前必须输出许可地址，调用 Bootstrap 即表示接受，不得弹出交互确认，MSI 必须显式禁止自动重启。
- **BOOT-028 — VS 产品线显式固定。** Windows Bootstrap v2 固定使用 VS 2026 stable 产品线及一个经长度与 SHA-256 锚定的精确 package manifest；不得在运行时解析 `latest`，升级必须同时修改 Contract、安装 recipe 与验收测试。
- **RELEASE-001 — Release 共享内容寻址池。** 不同 target 的不可变 Release 共存于 `var_entry/<entry-id>/releases/<release-id>/`；`release-id` 的 Hash 必须覆盖完整发布内容及含 target 的发布元数据，不能只散列源码 revision。
- **RELEASE-002 — Target Selector。** `var_entry/<entry-id>/releases/current.<target-id>` 是只含 Release 引用的普通 selector 文件，Publish 只原子更新本 target 的 selector，Launcher 必须同时校验 selector 所指 Release 的 target 兼容性。

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

- **ARC-001 — 三种空间分离。** 源码/作者空间、不可变发布/执行空间、可变数据空间必须分离；逻辑地址可以映射它们，但不得把三者合并为同一棵可写目录树。该物理根限制已由 `VAR-002`、`VAR-003` 取代，生命周期与写权限分离仍然保留。
- **VAR-001 — 单一 VarRoot。** Harness 自写的 cache、Release、Run、Export 与领域状态必须位于一个用户可配置的绝对 `VarRoot` 下；`source` 与 `docs` 不属于 `VarRoot`，各运行目录只从该根确定性派生。该实体 `var/` 层级已由 `VAR-003`、`VAR-NAME-001` 的共同父目录与扁平 `var_*` 空间取代。
- **CACHE-001 — Cache 所有者显式。** `VarRoot/cache` 只保存可跨 Entry 复用的共享 cache，`EntryRoot/cache` 只保存 Entry-local cache；调用方必须显式选择其一，不允许隐式 fallback 或复制同步。其物理路径已由 `CACHE-002` 取代。
- **DEV-001 — 垂直样例驱动。** 新的 Core 或 Facet 协议必须先在 `templates/helloworld` 形成最小端到端实现与黑盒验收，通过后才扩展到其他模块。其路径已由 `DEV-003` 取代。
- **DEV-002 — 单变量演进。** `templates/helloworld` 每次只引入一个待验证的外部协议能力，不为尚未出现的复用、类型或执行模式预建抽象。其路径已由 `DEV-004` 取代。
- **BOOT-002 — 唯一 Bootstrap 入口。** `bootstrap/main.ps1` 是 Launcher 和人工调用的唯一 Bootstrap 入口，由它持锁、重新检查 Release 并编排 build 与 publish；Launcher 不得直接调用内部脚本。其平台路径已由 `BOOT-006`、`BOOT-007` 取代。
- **BOOT-003 — Launcher 只认 Release。** Launcher 只验证 `var_entry/<entry-id>/releases/current` 选择的不可变 Release；没有可用 Release 时才调用 Bootstrap，绝不扫描 `source/target`、比较源码时间或执行 Cargo。其单一 selector 路径已由 `BOOT-010` 取代。
- **BOOT-004 — Build 与 Publish 分离。** `bootstrap/build.ps1` 只在 `var_cache` 中产生候选构建，`bootstrap/publish.ps1` 只负责验证候选、内容寻址发布到 Entry releases 并原子更新 selector；两者都不得承担 Launcher 职责。其 Windows 路径已由 `BOOT-009` 取代。
- **BOOT-005 — 发布后重新解析。** Bootstrap 成功返回后，Launcher 必须重新读取并验证 `current` 再执行 Release；Bootstrap 不直接启动产品，也不通过临时路径或 stdout 绕过已发布 selector。其 target-specific selector 语义已由 `BOOT-011` 取代。
- **BOOT-007 — Windows 唯一入口。** `bootstrap/windows/main.ps1` 是 Windows Launcher 和人工调用的唯一 Bootstrap 入口，由它持锁、重新检查 Release 并编排同目录的 `build.ps1` 与 `publish.ps1`；Launcher 不得直接调用内部脚本。其“已有 Release 时跳过显式构建”语义已由 `BOOT-020` 取代，Launcher 仍只调用 `main.ps1`，工具链维护入口由 `BOOT-023` 单独约束。
- **BOOT-014 — 工具链状态单一。** Bootstrap 只发布一个权威工具链完整性 metadata；构建环境在 Bootstrap 进程内应用并在退出时恢复，不生成重复的 `env.cmd`、`env.ps1`、`state.json` 与 `environment.json` 状态源。其父进程环境修改方式已由 `BOOT-024` 取代，单一 metadata 约束继续由 `BOOT-022` 保留。
- **BOOT-015 — 只恢复当前协议。** `swaw-harness` 只识别和恢复自身当前协议命名的安装 work、partial 与带时间戳 backup，不兼容不存在于新仓库历史中的 `swaw-kit` 或无序旧 backup 格式。通用 backup/rollback 已由 `BOOT-025` 的内容寻址只前进发布取代。
- **RELEASE-TARGET-001 — Release target 隔离。** 跨平台 VarRoot 中的 Release 与 `current` 必须按 host target 隔离；采用 Rust target triple、稳定 Swaw platform id 或其他目录形态仍需由第一个 Windows publish 样例验证。其目录形态已由 `RELEASE-001`、`RELEASE-002` 确定，剩余 TargetId 编码问题由 `TARGET-ID-001` 承接。
