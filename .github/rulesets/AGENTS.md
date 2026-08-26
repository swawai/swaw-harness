# GitHub Ruleset 维护规则

1. 本目录中的 JSON 是 GitHub Ruleset 的期望状态和创建/更新请求载荷；文件进入版本控制不会使规则自动生效。
2. `protect-main` 属于产品与通用主干保护；任何治理安装、停用或卸载都不得修改、停用、删除或接管它。
3. 修改产品基线后使用 `scripts/protect-main.ps1 plan/apply/status`；`scripts/` 是保留的产品能力，不随治理 Skill 卸载；`apply` 是控制平面变更，必须另获显式授权。
4. 禁止通过 GitHub Actions 自动应用 Ruleset；结果不确定时不得盲目重试，必须先回读状态并检查 GitHub。
5. JSON 只保留 GitHub 接受且本仓库决定管理的字段；不得复制远端响应中的 ID、来源、时间戳、链接或未纳管的服务端默认字段。
6. `Product validation` 只归 `protect-main`；产品工作流不得依赖治理专属源码。
7. `protect-main.json`、其中的声明名和远端身份键不得改名；改名必须作为显式迁移，不能由普通 reconcile 隐式完成。
8. Required status check 必须绑定 GitHub Actions 的 integration ID，避免同名外部 status 冒充；更换执行主体必须作为显式控制平面迁移。
9. required workflow 与其加载的 policy 模块属于信任根；迁移必须满足根规则的 owner-authored PR 与人工标签门禁。

```powershell
& .\.github\rulesets\scripts\protect-main.ps1 plan
& .\.github\rulesets\scripts\protect-main.ps1 apply
& .\.github\rulesets\scripts\protect-main.ps1 status
```

<!-- swaw.repository-change-governance:rulesets:begin -->
10. `swaw-change-governance` 是治理专属逻辑身份；manifest 的 128-bit 随机 token 会进入远端实体名，作为低碰撞的安装身份而非创建者的密码学证明；匹配 token 即表示该安装声明的实体。
11. 治理专属 Ruleset 只能使用 `lifecycle.ps1` 管理；禁止用产品 `protect-main.ps1 apply` 绕过碰撞、漂移、停用与卸载协议。
12. `Change policy` 必须由 `pull_request_target` 从 PR 的不可变 base SHA 加载，且不得检出或执行候选 head 代码；治理候选代码只能在低权限 `pull_request` 工作流中运行。
13. 安装治理时先合入受信 policy 与候选验证，再创建治理专属 active Ruleset；从旧组合规则迁移时必须先激活新规则，再从 `protect-main` 移除治理 checks。
14. `Change policy` 与 `Governance validation` 只归治理专属 Ruleset；停用与卸载不得影响 `Product validation`。
15. token 正常情况下保持稳定；若必须轮换，必须先用旧 manifest 停用并卸载旧实体，再通过受审 PR 同步修改 manifest 与期望 JSON，最后重新安装。任何同逻辑前缀的旧 token 实体都视为碰撞，脚本不得接管、覆盖或删除。
16. 卸载前必须先在治理专属 Ruleset 仍 active 时，将远端 `protect-main` 迁移并验证为与产品声明一致且不含治理 checks；生命周期脚本必须在该前置条件不成立时拒绝删除专属 Ruleset。

```powershell
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 status
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 plan-install
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 plan-disable
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 plan-uninstall
```
<!-- swaw.repository-change-governance:rulesets:end -->
