# Swaw Harness 仓库规则

1. `docs/swaw-harness-spec.md` 是架构与协议的唯一事实源；`AGENTS.md` 只规定维护方式，`README.md` 只做人类入口。
2. 只有标记为 `Accepted` 的规则具有约束力；`Proposed` 不得被实现成既定协议，除非先完成决议并更新状态。
3. 架构变更必须同步更新规范；`Accepted` 规则的 ID 不得改义或复用，`Proposed` 可在接受前继续收敛，废弃的已接受规则应标为 `Superseded`。
4. 必须区分已确认事实、目标状态和推断，不得把尚未完成的迁移写成当前能力。
5. 本仓库必须能在任意目录独立构建、测试和打包，不得依赖其父目录恰好是 `swaw-kit`。
6. 遵循 KISS、YAGNI、AHA > DRY、Single Source of Truth、Core vs Context 和 Locality of Behavior；适度重复优于错误抽象。
7. 新主路径一旦启用，应 hard cut 旧路径；不得长期维护双协议、隐式 fallback 或无明确删除条件的兼容层。
8. 源码归属按最近的稳定领域边界确定，不按每个 CLI 叶节点机械拆 crate；调用意图应显式，禁止通过 mode、caller 或路径猜测行为。
9. 单文件或模块超过 400 行应考虑拆分，超过 500 行必须拆分。
10. `README.md` 由人类维护，Agent 不主动修改。
11. 修改任意路径前，必须读取从仓库根到目标路径沿途存在的全部 `AGENTS.md`；近目录规则只可补充或收紧上层规则，不得覆盖或放宽上层约束。

## Git 变更协议

12. 一个 commit 只承载一个语义目标和回退理由，并保持可构建、可验证；使行为成立的实现、测试与规范一起提交，无关或机械变化分开。
13. commit 标题使用英文 `type(scope): imperative summary`，基础类型限 `feat|fix|refactor|test|docs|build|ci|chore`，稳定的小写 ASCII scope 可省略，标题不超过 72 字符且不加句号；关联记录使用 `Refs: #<issue-id>`、`Spec: <rule-id>`，高风险取舍和 `BREAKING CHANGE:` 写入正文，不记录 AI 会话或工具宣传。
14. 普通 commit 以不超过 300 行手写变更和 10 个语义文件为目标；超过 500 行或 15 个语义文件必须拆分或在正文解释不可分割性。提交前检查 worktree、staged diff 和相称验证，只暂存本任务拥有的路径。
<!-- swaw.repository-change-governance:begin -->
15. 任何预期入库的变更开始前必须使用 `.agents/skills/govern-repository-change/SKILL.md` 建立或恢复受治理上下文；只读分析、解释和诊断除外。用户授权实施后，同一授权覆盖对应 Issue/分支、普通 commit、同名分支非强制 fast-forward push 和 Draft PR 创建或更新；不覆盖 amend、rebase、历史重写、force-push、其它分支或标签、Issue 关闭、Ready、控制平面或 merge。
16. 每项变更先建立 open GitHub Issue，再从最新 `main` 建一条 `<actor>/<issue-id>-<slug>` 分支；一个 Issue、分支和 PR 构成一个审计边界，禁止在 `main` 开发。Issue 按模板记录 Outcome、Reason、Scope、Non-goals、Invariants、Validation scope 和 Acceptance criteria，语义变化必须先更新 Issue；已通过 `Change policy` 后编辑、关闭或重开 Issue，必须以 PR 正文编辑或新 commit 触发重跑，旧结果失效。
17. 所有变更通过以 `main` 为目标的 PR；标题遵循 commit 标题，正文按模板记录结果、改动、验证、偏离与 review focus，并独立使用 `Refs: #<issue-id>` 对应分支编号。除受信 base 尚强制 closing reference 的一次性契约迁移外，主 Issue 禁用 GitHub closing keywords；PR 合并不代表 Issue 完成，只有仓库负责人在合并后审核并决定关闭或保留。
18. 工作分支保持线性，不得 merge `main` 或其它分支；同步 `main` 以及 amend、rebase、历史重写或 force-push 均需仓库负责人逐次明确授权，`main` 只接受线性合并方式。
19. 日常验证以 Issue Validation scope 指定的仓库内定向检查和独立本地 review 为主；GitHub 自动 required check 的目标状态只有受信 base 运行的 `Change policy`。产品与治理全量 workflow 仅在 Validation scope 要求、其自身信任根自测或仓库负责人显式请求时运行，并绑定准确 revision；Issue 要求的远端证据缺失时不得合并。
20. 独立 review 由仓库负责人显式发起，绑定准确 PR HEAD、Issue 语义、适用的 Accepted 规范、完整 PR 与 diff、验证范围和证据；任一输入变化都会使结果失效。Reviewer 全程只读，优先报告正确性、安全、恢复、协议、回归和测试缺口，有 actionable finding 时不得宣称可合并。
21. PR 只有在独立 review 无未解决 finding、实际 required checks 通过且 review conversations 清零后，才可由仓库负责人显式合并；Agent 不得标记 Ready、自动合并、合并或绕过 Issue、PR、检查与审查边界。
22. 若 diff 修改任一适用 `AGENTS.md`、Skill 的 review 路由、`references/review-handoff.md` 或策略枚举器，候选不得授权自身评审；必须使用 fetched base 的不可放宽规则，候选只能加严，并由负责人输入 `启动受保护评审` 后在固定 base/head SHA 的独立副本中派生全新只读 reviewer。无法取得完整策略快照、隔离副本或子代理时 fail closed；具体步骤读取 fetched base 的 review reference。
23. 版本库中的 workflow/ruleset 只是期望声明，不等于远端已生效；声称 enforcement 或 merge eligibility 前必须回读远端并报告缺失或漂移。任何控制平面变更另需明确授权；治理生命周期只管理专属 ruleset，不得接管 `protect-main` 或制造失去 provider 的 required context。
24. `.github/workflows/**`、policy 实际加载的 `governance.psm1` 及其传递加载的 `.github/rulesets/scripts/repository.psm1` 是 required-check 信任根；修改它们必须使用仓库负责人创建的 PR，并由负责人审阅最终 HEAD 后最后手动重新添加 `governance-migration` 标签。任何后续 commit 或 PR 正文修改都会使授权失效；Agent 不得操作该标签。
<!-- swaw.repository-change-governance:end -->
