# Swaw Harness 仓库规则

## Scope

本文件适用于整个仓库，Rule ID 前缀为 `REPO`。

## 核心术语

- **HarnessRoot**：DataHome 的父目录；在源码检出中为仓库根，复制发布后为目标位置中 `data/` 的父目录。
- **DataHome**：Harness 面向用户且可独立复制运行的数据目录，固定位置为 `<HarnessRoot>/data`；保存 Entry executable、EntryRoot 及其发布运行资源，不保存仓库本地 Bootstrap 状态，也不得依赖 data.repo。
- **data.repo**：位于 `<repository>/data.repo`、仅属于源码仓库的 Bootstrap 数据目录；不随 DataHome 复制发布。
- **Entry Manager executable**：负责创建和管理 Entry 的独立可执行程序。
- **Entry**：由 Entry Manager executable 创建的受管运行实体。
- **EntryId**：Entry Manager 为一个 Entry 确定的文件系统名称，最多 16 个字符；它同时用作 `data/<EntryId>.exe` 的文件名和 `data/<EntryId>/` EntryRoot 的目录名。
- **EntryRoot**：与一个 Entry 唯一绑定的目录根，由 Entry Manager executable 在创建 Entry 时一并建立。
- **Bootstrap**：无需已编译 Harness 即可运行，自动准备宿主平台声明的便携构建环境，并在无需用户预装、配置或交互干预的情况下编译出 Harness 核心的启动构建流程。
- **PlatformTargetId**：Bootstrap 平台目标的文件系统安全标识；当前 Windows Bootstrap 使用 Rust 平台目标三元组 `x86_64-pc-windows-msvc` 作为 PlatformTargetId。
- **Bootstrap Release**：Bootstrap 一次构建产生的配套 executable 发布单元；Windows 仓库内发布根为 `<repository>/data.repo/windows.release`，每个 `<ReleaseId>/` 不可变目录同时包含 Core、Entry executable、Entry Manager executable 与 `manifest.json`，由一个 selector 选择当前版本。
- **Resource**：在一个资源空间内通过目录树寻址找到并执行操作的对象。
- **Facet**：对已找到 Resource 执行的具名操作。
- **资源空间**：具有独立文件系统根、事实来源、生命周期与写入权限边界的一组 Resource；不得简称为含义过宽的 `Space`。
- **基础资源空间**：无需通过 Facet、export 或 mount 建立即可直接选择的资源空间；当前包括作者（源代码）、运行（发布）、runs（logs）和 context 模块专用上下文记录空间。
- **派生资源空间**：由领域或用户机制通过 export、远端 mount 等方式建立的资源空间；它具有自己的文件系统根，并使用与基础资源空间相同的目录树寻址与 Facet 操作模型。
- **目录树寻址**：每个资源空间以其文件系统目录树作为地址域；选择资源空间后，使用该目录树根下规范化的相对文件系统路径寻找 Resource，不另建逻辑 Route 或其他地址模型。
- **ReleaseId**：发布根下 `<ReleaseId>/` 不可变发布目录的名称，由发布目标与目录内全部发布物内容的哈希确定；发布目标与全部内容均相同时复用同一目录。
- **selector**：产品发布根下名为 `current.<PlatformTargetId>` 的普通文本文件；它是指向 `<ReleaseId>/` 的逻辑文件指针，以原子替换完成当前版本切换。

## Accepted

- **REPO-001 — 规则必须关联具体实体。** 规则必须直接说明约束哪个实体，以及该实体必须或不得做什么；存在对应代码、目录、产物或已定义术语时必须明确引用，不得用未定义缩写、抽象名词或内部黑话替代具体对象。例如，不得只把 selector 定义为“可原子替换的选择记录”，必须明确它是产品发布根下的 `current.<PlatformTargetId>` 普通文本文件，指向 `<ReleaseId>/` 并通过原子替换切换当前版本。确需引入新的高频概念时，必须先按 `REPO-007` 定义再使用。
- **REPO-002 — 小核心与领域自治。** 核心只保留跨领域稳定且必要的最小机制与薄协议；领域代码、规则、文档及其他资源由各自目录自治，领域间通过显式边界协作，不得把领域逻辑集中到核心或总调度器。新增或扩展领域不得修改核心协议，除非出现新的、稳定的跨领域共同约束。
- **REPO-003 — 规则就近归属。** 全仓规则写入根 `AGENTS.md`，领域规则写入最近领域目录的 `AGENTS.md`；修改路径时从根向下依次读取并叠加，不得在多个文件重复维护同一规则。
- **REPO-004 — 代码就近归属。** 代码应归入最近的稳定领域目录；允许父领域承载多个相关模块，但必须保持领域边界，不得长期堆积在总入口或总 dispatcher。
- **REPO-005 — DataHome 可独立复制运行。** DataHome 必须位于 `<HarnessRoot>/data`，其 Entry executable、EntryRoot 及发布运行资源不得依赖 data.repo 的绝对路径；仓库本地 Bootstrap 工具链、构建、暂存、缓存、锁与日志不得写入 DataHome。
- **REPO-006 — Entry 创建流程。** Entry Manager executable 是创建 Entry 的唯一入口；创建时必须同时建立该 Entry 及与其唯一绑定的 EntryRoot。
- **REPO-007 — 核心术语统一。** 本文件的“核心术语”是全仓 `AGENTS.md` 的统一用语源；新增或改变核心高频术语必须先更新该段落，下级 `AGENTS.md` 不得自行创造同义词或改变既有含义。
- **REPO-008 — 内容寻址发布只前进。** 所有模块的发布物必须先在暂存区完整生成并验证，再以内容身份原子发布到尚不存在的不可变目标；需要切换当前版本时，只允许在新目标验证完成后原子更新 selector。不得覆盖已发布目标或为其维护通用 backup/rollback 副本；损坏目标仅可在同一身份锁内删除并按原内容身份重建。
- **REPO-009 — data.repo 仅属仓库。** data.repo 固定为 `<repository>/data.repo`，只保存不随 DataHome 复制发布的仓库本地数据；各宿主平台在其中使用明确的平台领域根，不得让 data.repo 成为运行时依赖。

## Open

当前无。

## Maintainer Notes

- 待办：验证并实现 `swaw-harness` 脱离 `swaw-kit` 父目录和源码树后仍可独立构建、测试、打包与发布；完成前不得将其表述为当前能力。

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
9. 测试范围写在 Issue 中，日常执行相称的本地测试。
10. PR 正文使用 `Refs: #<issue-id>` 提供不触发关闭的文本引用；GitHub Development 正式关联必须由 Issue-linked branch 或 PR 关联建立。仓库的 `Auto-close issues with merged linked pull requests` 设置保持关闭，只有仓库负责人决定合并与关闭 Issue。
