# DataHome 模块发布规则

## Scope

本文件适用于 `data/.harness/modules/` 目录，Rule ID 前缀为 `DATA-MODULE`。

## Accepted

- **DATA-MODULE-001 — 模块发布目录。** 一个模块版本的目标发布根固定为 `data/.harness/modules/<Publisher>/<Group>/<Module>/<PlatformTargetId>/<Version>/`；`Publisher/Group/Module` 三个规范小写文件系统名称共同组成模块身份，例如 `swaw/core/admin`。模块身份不得从源码仓库地址、Resource 路径、executable 文件名或目录分片推断。
- **DATA-MODULE-002 — 精确版本目录。** `<Version>/` 必须使用不含预发布或构建后缀的 `MAJOR.MINOR.PATCH` 语义化版本；每个已发布版本目录不可变。同一模块、平台与版本不得对应两套不同内容，任何内容变化都必须发布一个尚未使用的新版本，并按兼容性分别增加 major、minor 或 patch。
- **DATA-MODULE-003 — 模块发布只前进。** 模块包必须先在同一 DataHome 的 `data/.harness/modules/.publish-<process-unique>.tmp/` 中完整生成，再校验模块身份、平台、版本、文件清单和 SHA-256，最后原子改名到尚不存在的目标版本目录；不得覆盖、合并写入或就地修订已发布版本，完成或失败后必须清理该次暂存目录。
- **DATA-MODULE-004 — 本地版本选择。** Facet 的精确版本、`MAJOR.*` 或 `MAJOR.MINOR.*` 只在当前 DataHome、当前 PlatformTargetId 的已验证稳定版本中选择；模糊版本选择最高匹配版本，不联网下载、不选择预发布版本，也不允许对 major 0 使用模糊版本。
- **DATA-MODULE-005 — Git 只跟踪规则。** 仓库只跟踪 `data/.harness/modules/AGENTS.md`；`data/.harness/modules/` 下实际模块发布物属于生成的 DataHome 运行资源，必须继续由 `.gitignore` 排除。`data/.harness/` 是持续存在且含可变状态的 DataHome control root，不得随任一模块版本整体替换。

## Open

- **DATA-MODULE-006 — 模块清单实体。** 每个模块版本根中的 `swaw-harness.module.json` 需要记录哪些文件字段、SHA-256、模块入口和可选来源信息，留待首个模块发布实现确定；确定前不得声称模块包已完成验证。
- **DATA-MODULE-007 — 版本保留。** 未再被任何 Entry Facet 选择的历史版本如何枚举、保留和清理，留待出现真实磁盘回收需求后确定。

## Maintainer Notes

- 当前仓库尚未在 `data/.harness/modules/` 发布任何模块版本；本文件记录的是目标布局与发布边界。
