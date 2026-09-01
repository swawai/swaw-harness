# Swaw Harness 仓库规则

## Scope

本文件适用于整个仓库，Rule ID 前缀为 `REPO`。

## 核心术语

- **HarnessRoot**：DataHome 的父目录；在源码检出中为仓库根，复制发布后为目标位置中 `data/` 的父目录。
- **DataHome**：Harness 面向用户且可独立复制运行的数据目录，固定位置为 `<HarnessRoot>/data`；保存 Entry executable、EntryRoot 及其发布运行资源，不保存仓库本地 Bootstrap 状态，也不得依赖 data.repo。
- **data.repo**：位于 `<repository>/data.repo`、仅属于源码仓库的 Bootstrap 数据目录；不随 DataHome 复制发布。
- **Admin Core module executable**：名为 `swaw-harness-admin.exe`、目标中拥有模块安装、Entry 创建与生命周期实现的独立 Core module executable；Windows Bootstrap 从完整且已验证的 Bootstrap Release 初始物化该 executable 的 Module Release，不再调用旧 `seed` 操作。运行时管理操作必须通过 Admin Entry 上下文调用，当前尚未实现。
- **Entry Manager executable**：名为 `swaw-harness-cli.exe`、把人类发起的 Entry 操作委托给固定 Admin Entry 的独立 console frontend；它不拥有 Entry 布局或生命周期实现，也不得直接写入 DataHome。
- **Harness GUI executable**：名为 `swaw-harness.exe`、供人类操作的 Windows GUI executable；它通过同级 Entry Manager executable 执行 Entry 操作。
- **Entry**：由 Admin Core module executable 创建和管理的受管运行实体；固定 Admin Entry 是管理根，其他 Entry 均由它创建。
- **EntryId**：Admin Core module executable 为一个普通 Entry 验证的文件系统名称，最多 16 个字符；目标中同时用作 `data/<EntryId>.exe` 的文件名和 `data/<EntryId>/` EntryRoot 的目录名。`admin` 固定属于 Admin Entry，不得作为普通 EntryId。
- **EntryRoot**：与一个 Entry 唯一绑定、由 Admin Core module executable 在创建 Entry 时一并建立的目录根。
- **Admin Entry**：DataHome 中固定管理 Entry；其 EntryRoot 固定为 `<DataHome>/admin/`，当前直接包含 `map/` 技能图根、`modules/` 共享模块发布根，并在管理 Entry 时使用 `entry.lock`。Admin EntryRoot 持续存在，不得整体替换或删除。
- **Bootstrap**：无需已编译 Harness 即可运行，自动准备宿主平台声明的便携构建环境，并在无需用户预装、配置或交互干预的情况下编译出 Harness 核心的启动构建流程。
- **PlatformTargetId**：Bootstrap 平台目标的文件系统安全标识；当前 Windows Bootstrap 使用 Rust 平台目标三元组 `x86_64-pc-windows-msvc` 作为 PlatformTargetId。
- **Bootstrap Release**：Bootstrap 一次构建产生的配套 executable 发布单元；Windows 仓库内发布根为 `<repository>/data.repo/windows.release`，每个 `<ReleaseId>/` 不可变目录同时包含 Core、纳入该次构建的独立 Core 模块 executable、Entry executable、Entry Manager executable、Harness GUI executable 与 `manifest.json`，由一个 selector 选择当前版本。
- **Runtime Release**：旧 seed 流程曾安装在 `<EntryRoot>/runtime/<ReleaseId>/` 的完整 executable 集合；改由 Core 技能图选择独立 Module Release 后不再用于初始化 Admin Entry。普通 Entry 是否仍需保留 Runtime Release 及其内容边界属于 `REPO-010`。
- **技能图根（Skill Map Root）**：一个 Entry 中固定在 `<EntryRoot>/map/`、容纳多棵具名技能图的目录；Admin Entry 的技能图根固定为 `data/admin/map/`。技能图根本身不是一棵技能图，不保存 Module Release 或 Resource 的事实数据，也不属于资源空间。
- **SkillMapId**：技能图根下一个技能图的目录名；必须是规范小写 ASCII 文件系统安全名称。`core` 固定保留给 Core 技能图，其他 SkillMapId 留给用户或领域技能图。
- **技能图（Skill Map）**：固定在 `<EntryRoot>/map/<SkillMapId>/`、使用真实文件系统目录树保存技能描述、模块选择指针和寻址索引的可查看、可修改实例。当前只有 Core 技能图成为仓库实体；其他技能图的创建、协议和执行方式尚未实现。
- **Core 技能图**：SkillMapId 为 `core` 的内置技能图；仓库纳入 Git 的唯一默认实例及 Admin Entry 当前实例固定为 `data/admin/map/core/`，其他 Entry 的目标实例固定为 `<EntryRoot>/map/core/`。当前 v1 只实现 SkillPath 到 Module Release executable 的绑定；节点依赖、子树安装与整树执行尚未实现。
- **SkillPath**：一个技能节点目录相对其技能图根的规范化文件系统路径；每个路径段必须是规范小写 ASCII 文件系统安全名称。SkillPath 独立于 ModuleId、模块作者目录与资源空间中的 Resource 路径。
- **技能节点（Skill Node）**：技能图中的一个真实目录；目录包含 `skill.json` 时该 SkillPath 可调用，不包含时只是分类节点。可调用节点可以继续包含子节点，不要求位于叶目录；技能图根本身当前不得包含 `skill.json`。
- **技能声明（Skill declaration）**：技能节点目录中名为 `skill.json` 的版本化 JSON 文件；它使用 `module`、`version`、`executable` 和 `arguments` 直接声明该节点的模块选择与固定命令参数，不使用 Resource 声明文件、Facet 层或可继承 executable binding。
- **ModuleId**：由规范小写文件系统名称 `<Publisher>/<Group>/<Module>` 组成的三段模块身份，例如 `swaw/core/admin`；它独立于源码仓库地址、Resource 路径和 executable 文件名。
- **Module Release**：安装在 `<DataHome>/admin/modules/<Publisher>/<Group>/<Module>/<PlatformTargetId>/<Version>/`、包含一个模块在一个平台上的不可变 executable、私有运行文件及 `swaw-harness.module.json` 清单的发布目录；`Version` 是不含预发布或构建后缀的 `MAJOR.MINOR.PATCH` 语义化版本。Windows Bootstrap 负责从完整且已验证的 Bootstrap Release 初始物化本次构建的 Module Release；运行时安装目标由 Admin Core module executable 拥有。
- **Resource**：在一个资源空间内通过目录树寻址找到、由技能读取或写入的对象。
- **资源空间**：一个 Entry 中具有独立文件系统根、事实来源、生命周期与写入权限边界的一组 Resource；不得简称为含义过宽的 `Space`。资源空间保存被模块读取或写入的数据，不保存 executable 绑定；技能图根、技能图与 Module Release 根均不属于资源空间。
- **基础资源空间**：Core 协议保留规范名称 `author` 的作者（源代码）、`runtime` 的运行（发布）、`runs` 的 logs、`export` 和 `context` 模块专用上下文记录空间；对应根分别为 `<EntryRoot>/author/`、`<EntryRoot>/runtime/`、`<EntryRoot>/runs/`、`<EntryRoot>/export/` 和 `<EntryRoot>/context/`，需要时才建立。`map` 不是基础资源空间。
- **派生资源空间**：由领域或用户机制通过某技能建立的资源空间；它具有自己的文件系统根，并使用与基础资源空间相同的目录树寻址模型。
- **目录树寻址**：每个资源空间以其文件系统目录树作为 Resource 地址域，每棵技能图以自己的文件系统目录树作为 SkillPath 地址域；两者分别使用各自根下规范化的相对路径，不要求镜像，也不另建逻辑 Route 或其他地址模型。技能如何接收资源空间及 Resource 路径留待首次调用协议实现确定。
- **ReleaseId**：发布根下 `<ReleaseId>/` 不可变发布目录的名称，由发布目标与目录内全部发布物内容的哈希确定；发布目标与全部内容均相同时复用同一目录。
- **selector**：产品发布根下名为 `current.<PlatformTargetId>` 的普通文本文件；它是指向 `<ReleaseId>/` 的逻辑文件指针，以原子替换完成当前版本切换。

## Accepted

- **REPO-001 — 规则必须关联具体实体。** 规则必须直接说明约束哪个实体，以及该实体必须或不得做什么；存在对应代码、目录、产物或已定义术语时必须明确引用，不得用未定义缩写、抽象名词或内部黑话替代具体对象。例如，不得只把 selector 定义为“可原子替换的选择记录”，必须明确它是产品发布根下的 `current.<PlatformTargetId>` 普通文本文件，指向 `<ReleaseId>/` 并通过原子替换切换当前版本。确需引入新的高频概念时，必须先按 `REPO-007` 定义再使用。
- **REPO-002 — 小核心与领域自治。** 核心只保留跨领域稳定且必要的最小机制与薄协议；领域代码、规则、文档及其他资源由各自目录自治，领域间通过显式边界协作，不得把领域逻辑集中到核心或总调度器。新增或扩展领域不得修改核心协议，除非出现新的、稳定的跨领域共同约束。
- **REPO-003 — 规则就近归属。** 全仓规则写入根 `AGENTS.md`，领域规则写入最近领域目录的 `AGENTS.md`；修改路径时从根向下依次读取并叠加，不得在多个文件重复维护同一规则。
- **REPO-004 — 代码就近归属。** 代码应归入最近的稳定领域目录；允许父领域承载多个相关模块，但必须保持领域边界，不得长期堆积在总入口或总 dispatcher。
- **REPO-005 — DataHome 可独立复制运行。** DataHome 必须位于 `<HarnessRoot>/data`，其 Admin Entry、普通 Entry、Module Release 及其他发布运行资源不得依赖 data.repo 的绝对路径；仓库本地 Bootstrap 工具链、构建、暂存、缓存与日志不得写入 DataHome。`<DataHome>/admin/` 是持续存在的 Admin EntryRoot，不得整体替换；模块原子发布只作用于其 `modules/` 下具体的 `<Version>/`。

- **REPO-007 — 核心术语统一。** 本文件的“核心术语”是全仓 `AGENTS.md` 的统一用语源；新增或改变核心高频术语必须先更新该段落，下级 `AGENTS.md` 不得自行创造同义词或改变既有含义。
- **REPO-008 — 不可变发布只前进。** Bootstrap Release 与 Runtime Release 继续以 ReleaseId 内容身份发布；Module Release 使用 ModuleId、PlatformTargetId 与精确语义化版本定位。所有发布物必须先在暂存区完整生成并验证，再原子发布到尚不存在的不可变目标，不得覆盖或合并写入已发布目标。技能声明只允许选择已经验证的 Module Release；本规则不规定用户如何批量修改或切换 `<EntryRoot>/map/core/` Core 技能图实例。
- **REPO-009 — data.repo 仅属仓库。** data.repo 固定为 `<repository>/data.repo`，只保存不随 DataHome 复制发布的仓库本地数据；各宿主平台在其中使用明确的平台领域根，不得让 data.repo 成为运行时依赖。

## Open

- **REPO-010 — Runtime Release、Module Release 与前端 executable 的边界。** Admin Entry 初始化不再建立 Runtime Release；Windows Bootstrap 仍以 data.repo Bootstrap Release 验证和运输同次构建产物，再把 Core module executable 物化为独立 Module Release。普通 Entry 是否仍需 Runtime Release、Entry launcher 与两个前端 executable 最终如何进入 DataHome，以及 Bootstrap Release 是否继续运输 Core module executable，留待重新对齐 Issue #47 时确定。

## Maintainer Notes

- 待办：验证并实现 `swaw-harness` 脱离 `swaw-kit` 父目录和源码树后仍可独立构建、测试、打包与发布；完成前不得将其表述为当前能力。
- `data/admin/map/core/` 当前技能声明使用模糊模块版本；Windows Bootstrap 已实现本次构建 Module Release 的物化与清单验证，但 Core dispatcher、技能调用、资源空间 Resource 验证与其他 Entry 的技能图复制流程尚未实现，完成前不得将该图表述为可运行系统。
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
