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
