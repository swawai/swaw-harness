# Swaw Harness 仓库规则

1. 在中心规范逐步迁回目录规则并退场前，修改仓库必须先读取 `docs/swaw-harness-spec.md`，再读取从仓库根到目标路径沿途的全部 `AGENTS.md`；近目录规则只可补充或收紧上层规则。
2. 必须区分已确认事实、目标状态和推断，不得把尚未完成的迁移写成当前能力。
3. 遵循 KISS、YAGNI、AHA > DRY、Single Source of Truth、Core vs Context 和 Locality of Behavior；适度重复优于错误抽象。
4. 单文件或模块超过 400 行应考虑拆分，超过 500 行必须拆分。
5. `README.md` 由人类维护，Agent 不主动修改。
6. 新建或重构领域 `AGENTS.md` 时使用 `Scope`、`Accepted`、`Open`，仅在存在相应内容时增加 `Maintainer Notes`；`Accepted` 最多 5 条，`Open` 最多 3 条，若仍不足以说明，应先按重要性取舍并检查代码组织或架构边界。

## Git 变更协议

7. 预期入库的变更使用 `.agents/skills/govern-repository-change/SKILL.md`；只读分析、解释和诊断除外。
8. 默认流程是 `Issue → branch → PR → local test → review → human merge`，不得直接在 `main` 开发。
9. 测试范围写在 Issue 中，日常执行相称的本地测试。
10. PR 使用 `Refs: #<issue-id>` 关联 Issue，不自动关闭 Issue；只有仓库负责人决定合并与关闭 Issue。
