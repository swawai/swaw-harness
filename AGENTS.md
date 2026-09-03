# Swaw Harness 仓库规则

## Scope

本文件适用于整个仓库，Rule ID 前缀为 `REPO`。

## 核心术语

- **HarnessRoot**：DataHome 的父目录；在源码检出中为仓库根，复制发布后为目标位置中 `data/` 的父目录。
- **DataHome**：Harness 面向用户且可独立复制运行的数据目录，固定位置为 `<HarnessRoot>/data`；保存用户 CLI executable、UserHome 及其发布运行资源，不保存仓库本地 Bootstrap 状态，也不得依赖 data.repo。
- **data.repo**：位于 `<repository>/data.repo`、仅属于源码仓库的 Bootstrap 数据目录；不随 DataHome 复制发布。
- **Admin Core module executable**：名为 `swaw-harness-admin.exe`、目标中拥有模块安装、Harness 用户创建与生命周期实现的独立 Core module executable；Windows Bootstrap 从完整且已验证的 Bootstrap Release 初始物化该 executable 的 Module Release，不再调用旧 `seed` 操作。当前已实现 `admin/user/create`，但尚未实现 Harness 用户授权；包括普通 Harness 用户在内的任何当前本机会话调用方只要其技能图选择该模块，均不会被模块特殊拒绝。
- **Harness 用户（Harness User）**：由 Admin Core module executable 创建和管理的 Harness 内部逻辑运行身份；它不是 Windows/Linux 用户账户或操作系统安全主体，同一操作系统用户可以拥有多个 Harness 用户。固定 Admin 用户是管理根，其他 Harness 用户均由 Admin Core module executable 创建；当前 Harness 用户之间没有访问权限隔离。
- **UserId**：Admin Core module executable 为一个普通 Harness 用户验证的文件系统名称，最多 16 个字符；目标中同时用作 `<DataHome>/<UserId>.exe` 的文件名和 `<DataHome>/<UserId>/` UserHome 的目录名。`admin` 固定属于 Admin 用户，不得作为普通 UserId。
- **UserHome**：与一个 Harness 用户唯一绑定的目录根，固定为 `<DataHome>/<UserId>/`。普通 Harness 用户的初始 UserHome 由 Admin Core module executable 建立，包含 `user.json`、创建时复制的 `map/core/` Core 技能图快照和 `host/` Core Host 版本指针根；基础资源空间仍按需建立。
- **Harness 用户记录**：普通 Harness 用户 UserHome 根下固定名为 `user.json` 的严格版本化 JSON 文件；当前 schema 为 `swaw.harness.user/v1`，绑定规范 UserId、用户 CLI executable 长度与 SHA-256，并以 `creating` 或 `active` 表示创建生命周期。未知 schema、未知字段、身份不匹配或非 `active` 状态不得作为已创建用户启动 Core Host。固定 Admin 用户由 Bootstrap 初始化，不使用该记录。
- **用户 CLI executable**：Bootstrap Release 中通用文件名为 `user.exe`、安装后位于 `<DataHome>/<UserId>.exe` 的小型 console executable；它从自身文件名确定 UserId，读取该用户的 Core Host 版本指针，冷启动 Admin 用户共享的 Core Host Module Release，并以本机命名管道转发一次批处理技能调用。它不解析技能图或模块清单；除固定身份 `swaw/core/host` 外不得选择或启动其他模块。Windows Bootstrap 把它初始安装为 `<DataHome>/admin.exe`，Admin Core module executable 在创建普通用户时以相同字节安装对应 `<UserId>.exe`。
- **Core Host executable**：名为 `swaw-harness-core.exe`、ModuleId 固定为 `swaw/core/host` 的独立 Module Release executable；同一不可变 executable 可由多个 Harness 用户共享，但每个运行中的 Core Host 进程只服务一个 Harness 用户。它从该用户的 Core 技能图解析 SkillPath、验证 Admin 用户共享的 Module Release、以批处理方式监督模块进程并返回 stdout、stderr 与退出码。固定 Admin 用户不需要 Harness 用户记录；普通 Harness 用户只有在 `user.json` 严格有效、生命周期为 `active` 且同名用户 CLI 匹配记录的长度和 SHA-256 时才可冷启动 Host。Windows v1 不监听 TCP/回环地址，只接受同一 Windows 登录会话通过本机命名管道发起的调用。
- **Core Host 版本指针**：位于 `<UserHome>/host/current.<PlatformTargetId>` 的普通 UTF-8 文本文件，只保存一个无预发布或构建后缀的精确 `MAJOR.MINOR.PATCH` 版本号并以换行结尾；它只选择同一 DataHome 中固定 ModuleId `swaw/core/host`、固定 PlatformTargetId 与固定 executable 名称的已验证 Module Release，不保存路径、不解析技能图、不允许模糊版本。原子替换该文件只影响后续冷启动，已经运行的 Core Host 进程继续使用启动时的版本。
- **批处理技能调用**：用户 CLI 向对应 Core Host 提交一个 SkillPath 与动态参数的一次性调用；一个命名管道连接只承载一个命令，模块 stdin 固定关闭，stdout、stderr 和退出码分别返回，不建立交互会话。
- **Admin 用户（Admin User）**：DataHome 中固定且最先存在的管理 Harness 用户；其 UserId 固定为 `admin`，UserHome 固定为 `<DataHome>/admin/`，当前直接包含 `map/` 技能图根、`modules/` 共享模块发布根、`host/` Core Host 版本指针根，并在管理其他 Harness 用户时使用 `user.lock`。Admin UserHome 持续存在，不得整体替换或删除。
- **Bootstrap**：无需已编译 Harness 即可运行，自动准备宿主平台声明的便携构建环境，并在无需用户预装、配置或交互干预的情况下编译出 Harness 核心的启动构建流程。
- **PlatformTargetId**：Bootstrap 平台目标的文件系统安全标识；当前 Windows Bootstrap 使用 Rust 平台目标三元组 `x86_64-pc-windows-msvc` 作为 PlatformTargetId。
- **Bootstrap Release**：Bootstrap 一次构建产生的配套 executable 发布单元；Windows 仓库内发布根为 `<repository>/data.repo/windows.release`，每个 `<ReleaseId>/` 不可变目录同时包含 Core Host executable、纳入该次启动构建的独立 Core module executable、用户 CLI executable 与 `manifest.json`，由一个 selector 选择当前版本。当前启动构建包含 Admin、Dev 与用于贯通验收的 Helloworld module executable；Helloworld 不构成未来生产启动集合必须永久携带的协议要求。
- **Runtime Release**：旧 seed 流程曾安装在 `<UserHome>/runtime/<ReleaseId>/` 的完整 executable 集合；改由 Core 技能图选择独立 Module Release 后，当前 Admin 用户初始化与普通 Harness 用户创建均不建立 Runtime Release。未来领域若出现独立运行发布需求，必须以新的具体实体和需求重新定义，不得恢复旧 seed 作为默认用户布局。
- **技能图根（Skill Map Root）**：一个 Harness 用户中固定在 `<UserHome>/map/`、容纳多棵具名技能图的目录；Admin 用户的技能图根固定为 `data/admin/map/`。技能图根本身不是一棵技能图，不保存 Module Release 或 Resource 的事实数据，也不属于资源空间。
- **SkillMapId**：技能图根下一个技能图的目录名；必须是规范小写 ASCII 文件系统安全名称。`core` 固定保留给 Core 技能图，其他 SkillMapId 留给用户或领域技能图。
- **技能图（Skill Map）**：固定在 `<UserHome>/map/<SkillMapId>/`、使用真实文件系统目录树保存技能描述、模块选择指针和寻址索引的可查看、可修改实例。当前只有 Core 技能图成为仓库实体；其他技能图的创建、协议和执行方式尚未实现。
- **Core 技能图**：SkillMapId 为 `core` 的内置技能图；仓库纳入 Git 的唯一默认实例及 Admin 用户当前实例固定为 `data/admin/map/core/`，普通 Harness 用户创建时把当时的 Admin Core 技能图完整复制为 `<UserHome>/map/core/` 独立快照，后续双方修改互不自动同步。当前只实现 SkillPath 到 Module Release executable 的绑定；节点依赖、子树安装与整树执行尚未实现。
- **SkillPath**：一个技能节点目录相对其技能图根的规范化文件系统路径；每个路径段必须是规范小写 ASCII 文件系统安全名称。SkillPath 独立于 ModuleId、模块作者目录与资源空间中的 Resource 路径。
- **技能节点（Skill Node）**：技能图中的一个真实目录；目录包含 `skill.toml` 时该 SkillPath 可调用，不包含时只是分类节点。可调用节点可以继续包含子节点，不要求位于叶目录；技能图根本身当前不得包含 `skill.toml`。
- **技能声明（Skill declaration）**：技能节点目录中规范名为 `skill.toml`、由人类维护的严格版本化 TOML 文件；当前 schema 为 `swaw.harness.skill/v2`，使用 `module`、`version`、`executable` 和 `arguments` 直接声明该节点的模块选择与固定命令参数，不使用 Resource 声明文件、Facet 层或可继承 executable binding。旧 `skill.json` 不构成技能声明，也不得与 `skill.toml` 共存。
- **ModuleId**：由规范小写文件系统名称 `<Publisher>/<Group>/<Module>` 组成的三段模块身份，例如 `swaw/core/admin`；它独立于源码仓库地址、Resource 路径和 executable 文件名。
- **Module Release**：安装在 `<DataHome>/admin/modules/<Publisher>/<Group>/<Module>/<PlatformTargetId>/<Version>/` 的模块平台发布目录；`Version` 是不含预发布或构建后缀的 `MAJOR.MINOR.PATCH` 语义化版本。当前 `swaw.harness.module/v1` 发布目录只允许包含一个不可变 executable 与 `swaw-harness.module.json`，不得放入未由清单声明和验证的私有运行文件；私有运行文件的清单字段、目录成员规则与完整性验证留待首个真实需求确定。Core Host 也以固定 ModuleId `swaw/core/host` 使用这一发布布局，不另建 Core Host 专用发布格式。Windows Bootstrap 负责从完整且已验证的 Bootstrap Release 初始物化本次构建的 Module Release；运行时安装目标由 Admin Core module executable 拥有。
- **Resource**：在一个资源空间内通过目录树寻址找到、由技能读取或写入的对象。
- **资源空间**：一个 Harness 用户中具有独立文件系统根、事实来源、生命周期与写入权限边界的一组 Resource；不得简称为含义过宽的 `Space`。资源空间保存被模块读取或写入的数据，不保存 executable 绑定；技能图根、技能图与 Module Release 根均不属于资源空间。
- **基础资源空间**：Core 协议保留规范名称 `author` 的作者（源代码）、`runtime` 的运行（发布）、`runs` 的 logs、`export` 和 `context` 模块专用上下文记录空间；对应根分别为 `<UserHome>/author/`、`<UserHome>/runtime/`、`<UserHome>/runs/`、`<UserHome>/export/` 和 `<UserHome>/context/`，需要时才建立。`map` 不是基础资源空间。
- **派生资源空间**：由领域或用户机制通过某技能建立的资源空间；它具有自己的文件系统根，并使用与基础资源空间相同的目录树寻址模型。
- **目录树寻址**：每个资源空间以其文件系统目录树作为 Resource 地址域，每棵技能图以自己的文件系统目录树作为 SkillPath 地址域；两者分别使用各自根下规范化的相对路径，不要求镜像，也不另建逻辑 Route 或其他地址模型。技能如何接收资源空间及 Resource 路径留待首次调用协议实现确定。
- **ReleaseId**：发布根下 `<ReleaseId>/` 不可变发布目录的名称，由发布目标与目录内全部发布物内容的哈希确定；发布目标与全部内容均相同时复用同一目录。
- **selector**：产品发布根下名为 `current.<PlatformTargetId>` 的普通文本文件；它是指向 `<ReleaseId>/` 的逻辑文件指针，以原子替换完成当前版本切换。

## Accepted

- **REPO-001 — 规则必须关联具体实体。** 规则必须直接说明约束哪个实体，以及该实体必须或不得做什么；存在对应代码、目录、产物或已定义术语时必须明确引用，不得用未定义缩写、抽象名词或内部黑话替代具体对象。例如，不得只把 selector 定义为“可原子替换的选择记录”，必须明确它是产品发布根下的 `current.<PlatformTargetId>` 普通文本文件，指向 `<ReleaseId>/` 并通过原子替换切换当前版本。确需引入新的高频概念时，必须先按 `REPO-007` 定义再使用。
- **REPO-002 — 小核心与领域自治。** 核心只保留跨领域稳定且必要的最小机制与薄协议；领域代码、规则、文档及其他资源由各自目录自治，领域间通过显式边界协作，不得把领域逻辑集中到核心或总调度器。新增或扩展领域不得修改核心协议，除非出现新的、稳定的跨领域共同约束。
- **REPO-003 — 规则就近归属。** 全仓规则写入根 `AGENTS.md`，领域规则写入最近领域目录的 `AGENTS.md`；修改路径时从根向下依次读取并叠加，不得在多个文件重复维护同一规则。
- **REPO-004 — 代码就近归属。** 代码应归入最近的稳定领域目录；允许父领域承载多个相关模块，但必须保持领域边界，不得长期堆积在总入口或总 dispatcher。
- **REPO-005 — DataHome 可独立复制运行。** DataHome 必须位于 `<HarnessRoot>/data`，其用户 CLI executable、Core Host 版本指针、Admin 用户、普通 Harness 用户、Module Release 及其他发布运行资源不得依赖 data.repo 的绝对路径；仓库本地 Bootstrap 工具链、构建、缓存与日志不得写入 DataHome，只有面向 DataHome 最终发布的同目录暂存可以在完成或失败后立即清理。`<DataHome>/admin/` 是持续存在的 Admin UserHome，不得整体替换；模块原子发布只作用于其 `modules/` 下具体 `<Version>/`，Core Host 版本切换只原子替换目标用户 `host/` 下的 Core Host 版本指针。
- **REPO-006 — Harness 用户由 Admin 模块创建。** 目标中只有 Admin Core module executable 可以实现普通 Harness 用户创建与生命周期写入；当前 `admin/user/create <UserId>` 不区分调用方 Harness 用户，授权另由 Issue #55 处理。创建必须在 `data/admin/user.lock` 协调下，先完整暂存并验证 `<DataHome>/<UserId>/`，再提交 `<DataHome>/<UserId>.exe`，最后以原子文件替换把 Harness 用户记录从 `creating` 切换为 `active`；中断状态可恢复但不得被 Core Host 视作已创建用户。用户 CLI executable 与 Core Host executable 均不得自行实现该生命周期。

- **REPO-007 — 核心术语统一。** 本文件的“核心术语”是全仓 `AGENTS.md` 的统一用语源；新增或改变核心高频术语必须先更新该段落，下级 `AGENTS.md` 不得自行创造同义词或改变既有含义。
- **REPO-008 — 不可变发布只前进。** Bootstrap Release 与 Runtime Release 使用 ReleaseId 内容身份发布；包括 Core Host 在内的 Module Release 使用 ModuleId、PlatformTargetId 与精确语义化版本定位。所有发布物必须先在暂存区完整生成并验证，再原子发布到尚不存在的不可变目标，不得覆盖或合并写入已发布目标。技能声明只允许选择已经验证的 Module Release；Core Host 版本指针只允许选择已经验证的 `swaw/core/host` Module Release。本规则不规定用户如何批量修改或切换 `<UserHome>/map/core/` Core 技能图实例。
- **REPO-009 — data.repo 仅属仓库。** data.repo 固定为 `<repository>/data.repo`，只保存不随 DataHome 复制发布的仓库本地数据；各宿主平台在其中使用明确的平台领域根，不得让 data.repo 成为运行时依赖。
- **REPO-010 — 普通 Harness 用户初始发布边界。** `admin/user/create` 为普通 Harness 用户安装与 Admin 用户 CLI 相同字节的 `<DataHome>/<UserId>.exe`，复制当时的 `data/admin/map/core/` 为独立 `<UserHome>/map/core/` 快照，并复制 Admin 用户的精确 Core Host 版本号为该用户自己的版本指针；它不复制共享 Module Release、不建立 Runtime Release 或基础资源空间。重复创建只验证完整 `active` 实例并成功返回，不同步后来变化的 Admin 技能图或用户 CLI。
- **REPO-012 — DataHome 结构化文档格式按维护者划分。** DataHome 中由 Harness 使用者直接维护的结构化声明使用 TOML，当前具体实体为 Core 技能图中的 `skill.toml`；未来权限或检查配置只有在定义为使用者维护声明时才沿用 TOML。由程序生成或持有的事实记录与发布清单继续使用 JSON，当前具体实体包括 `user.json`、`swaw-harness.module.json`、Bootstrap Release 的 `manifest.json` 与模块运行状态 JSON；不得为了统一扩展名而把程序事实改作使用者配置。源码仓库内部的 Bootstrap 构建 Contract 由对应平台领域决定格式，Markdown 等非结构化文档也不属于本规则。

## Open

- **REPO-011 — Harness 用户授权。** 当前 Harness 用户只是同一操作系统登录会话内的逻辑运行身份，Core Host 与 Admin Core module executable 不按调用方限制 SkillPath、ModuleId 或管理操作；不得把 UserId、UserHome 路径、技能图目录位置或 `user.json` 生命周期当作授权凭据。未来面向本机多用户、局域网或公网适配器的身份认证、命名权限动作、默认拒绝策略与 Admin 受管授权记录由 Issue #55 单独定义和实现。

## Maintainer Notes

- 待办：验证并实现 `swaw-harness` 脱离 `swaw-kit` 父目录和源码树后仍可独立构建、测试、打包与发布；完成前不得将其表述为当前能力。
- `data/admin.exe admin/user/create alice` 与随后 `data/alice.exe helloworld [recipient]` 已形成普通 Harness 用户创建及调用闭环；这只证明 UserHome、用户 CLI、Core Host 版本指针和 Core 技能图快照可被原子建立、恢复与执行。资源空间 Resource 验证、Harness 用户授权、模块安装、技能组合及用户删除、升级仍未实现，不得由该样例外推为完整系统。
- swaw-kit 中对应本项目的旧代码在： D:/2026.7/swaw-kit/_lib\proj，迁移注意参考

## Agent 工作约束

1. 修改仓库必须读取从仓库根到目标路径沿途的全部 `AGENTS.md`；近目录规则只可补充或收紧上层规则。
2. 必须区分已确认事实、目标状态和推断，不得把尚未完成的迁移写成当前能力。
3. 遵循 KISS、YAGNI、AHA > DRY、Single Source of Truth、Core vs Context 和 Locality of Behavior；适度重复优于错误抽象。
4. 单文件或模块超过 400 行应考虑拆分，超过 500 行必须拆分。
5. `README.md` 由人类维护，Agent 不主动修改。
6. 根与 `core/AGENTS.md` 当前不设 `Accepted`、`Open` 数量上限；新建或重构其他领域 `AGENTS.md` 时使用 `Scope`、`Accepted`、`Open`，仅在存在相应内容时增加 `Maintainer Notes`，且 `Accepted` 最多 5 条、`Open` 最多 3 条，若仍不足以说明，应先按重要性取舍并检查代码组织或架构边界。

## Git 变更协议

7. 预期入库的变更使用 `.agents/skills/govern-repository-change/SKILL.md`；只读分析、解释和诊断除外。
8. 默认流程是 `Issue → branch → PR → local test → review → human merge`，不得直接在 `main` 开发。
9. GitHub Issue、Issue-linked branch、PR 和 workflow 操作必须使用 PATH 解析到的 `ghswaw` 命令；当前 Windows 入口文件为 `ghswaw.cmd`。不得硬编码宿主绝对路径或绕过该入口直接调用底层 `gh`；PATH 中缺少该命令或身份检查失败时必须停止。
10. 创建 Issue-linked branch 前，本地当前分支必须是工作树干净的 `main`；获取 `origin/main` 后只允许以 fast-forward 更新本地 `main`，并必须验证两者指向同一 commit。存在本地独有 commit 或分叉时必须停止，不得自动 merge、rebase 或 reset 修复。
11. 测试范围写在 Issue 中，日常执行相称的本地测试。
12. PR 正文使用 `Refs: #<issue-id>` 提供不触发关闭的文本引用；GitHub Development 正式关联必须由 Issue-linked branch 或 PR 关联建立。
13. 仓库负责人确认 `Auto-close issues with merged linked pull requests` 已处于关闭状态；Agent 不得仅因 `ghswaw` 无法回读而重复询问。
