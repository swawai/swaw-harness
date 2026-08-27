# Swaw Harness 仓库规则

1. 目录即协议：`AGENTS.md` 按目录承载其作用域内的规则；根文件记录全仓规则，稳定领域规则归最近的领域目录。`docs/swaw-harness-spec.md` 只新增全仓或跨领域的架构与协议；尚未下沉的既有领域规则在完成单一来源迁移前继续由其中现有条目承载，`README.md` 只做人类入口。
2. 带状态的规则中，只有 `Accepted` 具有约束力；`Open` 或 `Proposed` 不得被实现成既定协议，除非先完成决议并更新状态。
3. 架构或协议变更必须同步更新其最近的事实源；全仓或跨领域变更更新中心规范。`Accepted` 规则的 ID 在全仓范围内不得改义、复用或重复；未接受的规则可继续收敛，废弃的已接受规则应标为 `Superseded`。
4. 必须区分已确认事实、目标状态和推断，不得把尚未完成的迁移写成当前能力。
5. 本仓库必须能在任意目录独立构建、测试和打包，不得依赖其父目录恰好是 `swaw-kit`。
6. 遵循 KISS、YAGNI、AHA > DRY、Single Source of Truth、Core vs Context 和 Locality of Behavior；适度重复优于错误抽象。
7. 新主路径一旦启用，应 hard cut 旧路径；不得长期维护双协议、隐式 fallback 或无明确删除条件的兼容层。
8. 源码归属按最近的稳定领域边界确定，不按每个 CLI 叶节点机械拆 crate；调用意图应显式，禁止通过 mode、caller 或路径猜测行为。
9. 单文件或模块超过 400 行应考虑拆分，超过 500 行必须拆分。
10. `README.md` 由人类维护，Agent 不主动修改。
11. 修改任意路径前，必须读取从仓库根到目标路径沿途存在的全部 `AGENTS.md`，规则按该顺序依次叠加；近目录规则只可补充或收紧上层规则，不得覆盖或放宽上层约束。新建或重构领域 `AGENTS.md` 时使用 `Scope`、`Accepted`、`Open` 和可选的 `Maintainer Notes`；`Accepted` 最多 5 条，`Open` 最多 3 条，若仍不足以说明，应先按重要性取舍并检查代码组织或架构边界。

## Git 变更协议

12. 预期入库的变更使用 `.agents/skills/govern-repository-change/SKILL.md`；只读分析、解释和诊断除外。
13. 默认流程是 `Issue → branch → PR → local test → review → human merge`，不得直接在 `main` 开发。
14. 测试范围写在 Issue 中，日常执行相称的本地测试。
15. PR 使用 `Refs: #<issue-id>` 关联 Issue，不自动关闭 Issue；只有仓库负责人决定合并与关闭 Issue。
