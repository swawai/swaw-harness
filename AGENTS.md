# Swaw Harness 仓库规则

## Scope

本文件适用于整个仓库，Rule ID 前缀为 `REPO`。

## 核心术语

- **DataRoot**：仓库通用的数据目录空间，用于各领域的运行时工作、数据产出和持久保存；仓库内位置为 `<repository>/data`。
- **Entry Manager executable**：负责创建和管理 Entry 的独立可执行程序。
- **Entry**：由 Entry Manager executable 创建的受管运行实体。
- **EntryRoot**：与一个 Entry 唯一绑定的目录根，由 Entry Manager executable 在创建 Entry 时一并建立。
- **Bootstrap**：自动下载并设置便携 Rust 与 MSVC 编译环境，并在无需用户干预的情况下编译出 Harness 核心的启动构建流程。
- **Resource**：在一个资源空间内按文件系统路径寻找并执行操作的对象。
- **Facet**：对已找到 Resource 执行的具名操作。
- **资源空间**：具有独立文件系统根、事实来源、生命周期与写入权限边界的一组 Resource；不得简称为含义过宽的 `Space`。
- **ReleaseId**：由固定 Release schema、TargetId、发布物文件名、字节长度和发布物 SHA-256 共同计算出的 64 字符小写十六进制 SHA-256；它直接作为产品发布根下的不可变目录名，例如 `<repository>/data/core.release/<ReleaseId>/`，相同字段必须得到并复用相同 ReleaseId。
- **selector**：产品发布根下名为 `current.<TargetId>` 的普通文本文件，内容严格为 64 字符 ReleaseId 加一个 LF（共 65 个 ASCII 字节）；它是指向 `<ReleaseId>/` 的逻辑文件指针，以原子替换完成当前版本切换，不是符号链接且不包含发布物。

## Accepted

- **REPO-001 — 小核心与领域自治。** 核心只保留跨领域稳定且必要的最小机制与薄协议；领域代码、规则、文档及其他资源由各自目录自治，领域间通过显式边界协作，不得把领域逻辑集中到核心或总调度器。新增或扩展领域不得修改核心协议，除非出现新的、稳定的跨领域共同约束。
- **REPO-002 — 规则就近归属。** 全仓规则写入根 `AGENTS.md`，领域规则写入最近领域目录的 `AGENTS.md`；修改路径时从根向下依次读取并叠加，不得在多个文件重复维护同一规则。
- **REPO-003 — 代码就近归属。** 代码应归入最近的稳定领域目录；允许父领域承载多个相关模块，但必须保持领域边界，不得长期堆积在总入口或总 dispatcher。
- **REPO-004 — DataRoot 通用数据空间。** 各领域使用 DataRoot 时必须遵循核心术语定义的用途与仓库内位置，不得将其重新解释为“共享 Core 数据根”或“可配置绝对根”。
- **REPO-005 — Entry 创建流程。** Entry Manager executable 是创建 Entry 的唯一入口；创建时必须同时建立该 Entry 及与其唯一绑定的 EntryRoot。
- **REPO-006 — 核心术语统一。** 本文件的“核心术语”是全仓 `AGENTS.md` 的统一用语源；新增或改变核心高频术语必须先更新该段落，下级 `AGENTS.md` 不得自行创造同义词或改变既有含义。
- **REPO-007 — 内容寻址发布只前进。** 所有模块的发布物必须先在暂存区完整生成并验证，再以内容身份原子发布到尚不存在的不可变目标；需要切换当前版本时，只允许在新目标验证完成后原子更新 selector。不得覆盖已发布目标或为其维护通用 backup/rollback 副本；损坏目标仅可在同一身份锁内删除并按原内容身份重建。
- **REPO-008 — 规则关联具体实体。** 规则必须直接说明约束哪个实体，以及该实体必须或不得做什么；存在对应代码、目录、产物或已定义术语时必须明确引用，不得用未定义缩写、抽象名词或内部黑话替代具体对象。确需引入新的高频概念时，必须先按 `REPO-006` 定义再使用。

## Open

当前无。

## Maintainer Notes

- 待办（原 `HAR-001`）：验证并实现 `swaw-harness` 脱离 `swaw-kit` 父目录和源码树后仍可独立构建、测试、打包与发布；完成前不得将其表述为当前能力。

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
10. PR 使用 `Refs: #<issue-id>` 关联 Issue，不自动关闭 Issue；只有仓库负责人决定合并与关闭 Issue。
