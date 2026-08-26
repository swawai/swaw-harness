# GitHub Ruleset 维护规则

1. 本目录中的 JSON 是 GitHub Ruleset 的期望状态和创建/更新请求载荷；文件进入版本控制不会使规则自动生效。
2. 修改 JSON 后必须从仓库根依次使用 `ruleset.ps1 plan` 检查差异，并在获得 GitHub 控制平面变更授权后使用 `apply`；最后使用 `status` 验证远端为 `in_sync`。
3. 禁止通过 GitHub Actions 自动应用 Ruleset；控制平面变更必须由显式操作触发，结果不确定时不得盲目重试。
4. JSON 只保留 GitHub 创建或更新 Ruleset 所接受且本仓库决定管理的字段；不得复制远端响应中的 ID、来源、时间戳、链接或未纳管的服务端默认字段。
5. Required check 名称是本目录与 `.github/workflows/change-policy.yml`、`.github/workflows/validate.yml` 之间的外部契约；重命名、增删或改变职责时必须同步更新相关声明、测试和远端 Ruleset。
6. `protect-main` 同时是本地声明名和远端身份键，不得通过普通 `apply` 改名；改名必须作为显式迁移，在确认新规则生效后单独处置旧规则。
7. `Change policy` 必须由 `pull_request_target` 从 PR 的不可变 base SHA 加载，且不得检出或执行候选 head 代码；产品代码只能在低权限 `pull_request` 工作流中运行。
8. 首次安装时先把受信 policy workflow 合入默认分支，再启用 active ruleset；若顺序已反转，只能按根规则的一次性引导流程恢复，不能把临时放宽固化为常规 bypass。
9. Required status check 必须绑定 GitHub Actions 的 integration ID，避免同名外部 status 冒充；更换执行主体必须作为显式控制平面迁移。
10. required workflow 与其加载的 policy 模块属于信任根；日常 PR 不得修改，治理迁移必须满足根规则的 owner-authored PR 与人工标签门禁。

```powershell
& .\.agents\skills\govern-repository-change\scripts\ruleset.ps1 plan
& .\.agents\skills\govern-repository-change\scripts\ruleset.ps1 apply
& .\.agents\skills\govern-repository-change\scripts\ruleset.ps1 status
```
