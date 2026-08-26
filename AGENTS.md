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

12. 一个 commit 只承载一个语义目标和一个独立回退理由；实现、使该行为成立的测试与规范更新应一起提交，无关清理必须拆开。
13. 每个 commit 应保持仓库可构建、可验证；纯重命名、格式化、生成文件等机械变化应尽量与行为变化分开。
14. commit 标题采用英文 `type(scope): imperative summary`；允许的基础类型为 `feat`、`fix`、`refactor`、`test`、`docs`、`build`、`chore`；`scope` 只使用小写 ASCII 字母、数字、点、下划线或连字符并以字母或数字开头，summary 以小写 ASCII 字母或数字开头。
15. `scope` 使用稳定的实体或领域名，而不是临时文件名；没有明确主归属时省略，不得使用 `misc`、`other` 等模糊词。
16. 标题应描述结果，不得超过 72 个字符且不加句号；架构、协议、恢复、安全、兼容性或非显然取舍必须在正文解释原因与影响，不得只复述文件清单。
17. commit 有关联记录时使用 `Refs: #<issue-id>` 和 `Spec: <rule-id>`；`Closes #<issue-id>` 只写在完整解决该 Issue 的 PR 正文中，破坏性变化使用 `BREAKING CHANGE:`。
18. AI 的一次对话、一次执行或一次交接不是 commit 边界；commit message 必须依据 staged diff 编写，默认不记录 prompt、模型名或工具宣传信息。
19. 普通 commit 以不超过 300 行手写变更和 10 个语义文件为目标；超过 500 行或 15 个语义文件时必须拆分，或在正文说明其为何不可分割，机械迁移与生成内容不计入该预算。
20. 提交前必须检查 worktree、staged diff 并执行与变更相称的验证；只暂存本任务拥有的路径，不得混入用户或其它任务的修改。
21. Agent 只有在任务明确授权提交时才可创建 commit；未经明确授权不得 amend、rebase、重写历史或 push。
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
32. `.github/rulesets/protect-main.json` 是 `main` 保护规则的期望状态，必须通过 Skill 的 `scripts/ruleset.ps1` 显式核对和应用；`.github/workflows/change-policy.yml` 从受信 base 校验变更协议，`.github/workflows/validate.yml` 验证候选产品代码，二者都不会自动把检查设为 required。宣称治理已强制生效或 PR 可合并前，远端 ruleset 必须与该文件一致；缺失或漂移必须报告为治理阻塞，不得把仓库内软约束冒充 GitHub 硬约束。
33. 首次安装受信 `pull_request_target` 检查时，该检查必须先进入默认分支才能保护后续 PR；因此 active ruleset 只能在其合入后启用。若 ruleset 已提前启用，仓库负责人必须把临时放宽限定在这一个引导 PR，保留 Issue、产品验证和人工评审记录，并在合入后立即恢复期望 ruleset、核对 `in_sync`；该引导例外不得复用于后续变更。
34. `.github/workflows/**` 与 policy 实际加载的 `governance.psm1` 是 required checks 的信任根；修改它们必须使用仓库负责人创建的 PR，并由负责人在审阅 diff 后手动添加 `governance-migration` 标签。Agent 不得自行添加、移除或请求自动添加该标签；无信任根变更时该标签也不得保留。
