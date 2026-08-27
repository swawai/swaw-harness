# Swaw Harness 仓库规则

1. 目录即协议：`AGENTS.md` 按目录承载其作用域内的规则；根文件记录全仓规则，稳定领域规则归最近的领域目录。`docs/swaw-harness-spec.md` 只记录全仓或跨领域的架构与协议，`README.md` 只做人类入口。
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

12. 一个 commit 只承载一个语义目标和一个独立回退理由；实现、使该行为成立的测试与规范更新应一起提交，无关清理必须拆开。
13. 每个 commit 应保持仓库可构建、可验证；纯重命名、格式化、生成文件等机械变化应尽量与行为变化分开。
14. commit 标题采用英文 `type(scope): imperative summary`；允许的基础类型为 `feat`、`fix`、`refactor`、`test`、`docs`、`build`、`ci`、`chore`；`scope` 只使用小写 ASCII 字母、数字、点、下划线或连字符并以字母或数字开头，summary 以小写 ASCII 字母或数字开头。
15. `scope` 使用稳定的实体或领域名，而不是临时文件名；没有明确主归属时省略，不得使用 `misc`、`other` 等模糊词。
16. 标题应描述结果，不得超过 72 个字符且不加句号；架构、协议、恢复、安全、兼容性或非显然取舍必须在正文解释原因与影响，不得只复述文件清单。
17. commit 有关联记录时使用 `Refs: #<issue-id>` 和 `Spec: <rule-id>`；`Closes #<issue-id>` 只写在完整解决该 Issue 的 PR 正文中，破坏性变化使用 `BREAKING CHANGE:`。
18. AI 的一次对话、一次执行或一次交接不是 commit 边界；commit message 必须依据 staged diff 编写，默认不记录 prompt、模型名或工具宣传信息。
19. 普通 commit 以不超过 300 行手写变更和 10 个语义文件为目标；超过 500 行或 15 个语义文件时必须拆分，或在正文说明其为何不可分割，机械迁移与生成内容不计入该预算。
20. 提交前必须检查 worktree、staged diff 并执行与变更相称的验证；只暂存本任务拥有的路径，不得混入用户或其它任务的修改。
<!-- swaw.repository-change-governance:begin -->
21. 用户授权实施一项拟进入版本控制的变更后，即授权 Agent 建立或恢复对应 Issue 与关联分支；Issue 达到就绪条件后，同一授权覆盖在该受治理分支内按语义边界创建普通 commit、向同名远端分支执行非强制的 fast-forward push，以及创建 Draft PR 或更新同一 PR，这些动作无需逐次请求授权。该常驻授权不包括 amend、rebase、历史重写、force-push、其它分支或标签、将 PR 标记为 ready、Ruleset 等控制平面变更及 merge。
22. 本协议合入后，任何预期进入版本控制的新增、修改或删除开始前，必须先建立 GitHub Issue，再从最新 `main` 建立关联工作分支；禁止直接在 `main` 上开发或提交。
23. Issue 必须明确 Outcome、Reason、Scope、Non-goals、Invariants 与 Acceptance criteria；发现目标、边界或验收条件变化时，必须先更新 Issue 再继续实现。
24. 工作分支使用 `<actor>/<issue-id>-<slug>`，例如 `codex/12-govern-change-workflow`；`actor` 以小写字母开头并只使用小写字母、数字和连字符，`slug` 由单个连字符分隔的小写字母或数字片段组成；一个分支只服务一个主 Issue，分支名中的 Issue 编号必须与 PR 正文独立一行的 `Closes #<issue-id>` 一致。
25. 所有变更必须通过以 `main` 为目标的 PR；PR 标题遵循第 14、16 条的 commit 标题格式，正文必须说明结果、实际改动、验证证据、偏离 Issue 之处与审查重点，并保持 diff 不含无关修改。
26. PR 评审必须对照 Issue 的目标、边界、不变量和验收条件检查完整 diff；格式校验或测试通过不能替代该语义审查。
27. PR 必须通过 required checks 且解决全部 review conversations 后才可合并；Agent 不得自行合并，最终合并由仓库负责人显式执行。
28. 禁止自动合并以及绕过 Issue、PR 或 required checks 的常规路径；紧急情况也必须留下可审计的 Issue、PR 与验证记录。
29. 工作分支保持线性，不得把 `main` 或其它分支 merge 进来；确需同步 `main` 时由仓库负责人显式授权 rebase，`main` 只接受保持线性历史的合并方式。
30. 关联 Issue 在 `Change policy` 通过后若被编辑、关闭或重开，必须通过编辑 PR 正文或推送新 commit 触发该检查重跑；不得沿用旧快照合并。
31. 任何将新增、修改或删除预期进入版本控制内容的任务，Agent 必须在变更前使用 `.agents/skills/govern-repository-change/SKILL.md` 创建或恢复受治理的变更上下文；只读分析、解释和诊断不触发该 Skill。该 Skill 只执行本协议，不得放宽第 21、27、28 条的授权与合并边界。
32. `.github/rulesets/protect-main.json` 是产品与通用主干保护的期望状态，不属于治理生命周期；`.github/rulesets/swaw-change-governance.json` 只承载治理 required checks，并由 Skill 的 `scripts/lifecycle.ps1` 管理。`.github/workflows/validate.yml` 只验证候选产品代码，`.github/workflows/change-policy.yml` 从受信 base 校验变更协议，`.github/workflows/validate-governance.yml` 验证候选治理代码。宣称任一保护已生效或 PR 可合并前，必须显式核对对应远端 ruleset；缺失或漂移必须报告，不得把仓库内声明冒充 GitHub 硬约束。
33. 首次安装治理时，受信 policy workflow 与治理候选验证必须先进入默认分支，之后才能激活治理专属 ruleset；停用或卸载只能操作治理专属 ruleset，不得停用、删除或接管 `protect-main`。若激活顺序错误，仓库负责人必须把临时放宽限定在一个引导 PR，保留 Issue、产品验证和人工评审记录，并在合入后立即恢复期望状态；该例外不得复用。
34. `.github/workflows/**`、policy 实际加载的 `governance.psm1` 及其传递加载的 `.github/rulesets/scripts/repository.psm1` 是 required checks 的信任根；修改它们必须使用仓库负责人创建的 PR，并由负责人在审阅当前 HEAD 后最后手动重新添加 `governance-migration` 标签。任何后续 commit 或 PR 正文修改都会使这次授权失效，负责人必须复审新的当前 HEAD 并再次移除、添加该标签。Agent 不得自行添加、移除或请求自动添加该标签；无信任根变更时该标签也不得保留。
35. 卸载治理时，必须先在治理仍 active 时把远端 `protect-main` 迁移并验证为不再包含治理 checks，再创建并完成源码移除 Draft PR 的 diff 与审查，然后将 PR 标为 Ready 并等待该事件完成；待 HEAD、正文、checks 与 conversations 最终确定后，由仓库负责人最后移除并重新添加 `governance-migration` 标签。随后从同步且干净的 `main` 另获授权执行 disable、uninstall 并回读远端确认为 absent，最后在不再修改 PR 的前提下立即由仓库负责人合并。禁止在 `protect-main` 仍引用治理 checks 或治理专属 Ruleset 仍 active 时先合并源码移除。

### Code Review Rules

- 独立评审由仓库负责人显式发起，并绑定被审查的准确 PR HEAD。此后若 HEAD、关联 Issue 的语义内容、适用的 Accepted 规范，或 PR 的验证与审查说明发生变化，原评审结果失效。
- Reviewer 必须读取关联 Issue、适用的 Accepted 规范、完整 diff、验证范围与证据，并优先报告行为正确性、安全、恢复、协议、回归和测试缺口；由自动化可靠处理的纯格式问题不作为人工评审重点。
- Reviewer 只读，不得修改 worktree 或分支、提交、push、修改 Issue 或 PR、标记 Ready、操作控制平面或合并。存在未解决的 actionable finding 时，不得宣称 PR 可合并。
- 若完整 diff 修改任一适用的 `AGENTS.md`、`.agents/skills/govern-repository-change/SKILL.md` 中的评审交接规则或其策略枚举器，候选分支不得成为自身评审策略的授权源。此类变更不得使用普通 `/review`；仓库负责人必须在主任务中显式输入 `启动受保护评审`，由主任务派生全新的只读 reviewer subagent，在固定准确 base 与 PR HEAD SHA 的一次性独立 clone 中执行评审。交接必须使用 fetched base 中的枚举器，从 base 与 head 两端枚举完整 diff 所适用的全部根级和嵌套 `AGENTS.md`，携带每个 base 版本以及 base 中的评审交接约束作为不可放宽规则；首次引导时必须独立读取两个 Git tree，不得以候选枚举器作为授权源。候选规则只能追加约束，无法建立完整策略快照、子代理或隔离副本时必须 fail closed。
- base 尚无上述规则的首次引导中，主任务必须先向仓库负责人展示将要授权的最低约束与准确 SHA，待负责人回复 `启动受保护评审` 后才能派生 reviewer。最低约束必须要求读取完整 Issue、适用的 Accepted 规范、完整 PR 正文、完整 diff、验证范围与证据；优先报告正确性、安全、恢复、协议、回归与测试缺口；全程只读，禁止修改仓库或 GitHub 状态、标记 Ready、操作控制平面或合并。
<!-- swaw.repository-change-governance:end -->
