# Admin 模块发布规则

## Scope

本文件适用于 `data/admin/modules/` 目录，Rule ID 前缀为 `ADMIN-MODULE`。

## Accepted

- **ADMIN-MODULE-001 — 模块发布目录。** 一个模块版本的目标发布根固定为 `data/admin/modules/<Publisher>/<Group>/<Module>/<PlatformTargetId>/<Version>/`；`Publisher/Group/Module` 三个规范小写文件系统名称共同组成 ModuleId，例如 `swaw/core/admin`。ModuleId 不得从源码仓库地址、Resource 路径、executable 文件名或目录分片推断。
- **ADMIN-MODULE-002 — 精确版本目录。** `<Version>/` 必须使用不含预发布或构建后缀的 `MAJOR.MINOR.PATCH` 语义化版本；每个已发布版本目录不可变。同一 ModuleId、PlatformTargetId 与 Version 不得对应两套不同内容，任何内容变化都必须发布一个尚未使用的新版本。
- **ADMIN-MODULE-003 — 模块发布只前进。** 模块包必须先在 `data/admin/modules/.publish-<process-unique>.tmp/` 中完整生成并验证清单与 SHA-256，再原子改名到尚不存在的目标版本目录；不得覆盖、合并写入或就地修订已发布版本，完成或失败后必须清理该次暂存目录。
- **ADMIN-MODULE-004 — 本地版本选择。** Facet 的精确版本、`MAJOR.*` 或 `MAJOR.MINOR.*` 只在当前 DataHome、当前 PlatformTargetId 的已验证稳定版本中选择；模糊版本选择最高匹配版本，不联网下载、不选择预发布版本，也不允许对 major 0 使用模糊版本。
- **ADMIN-MODULE-005 — Git 只跟踪规则。** 仓库只跟踪 `data/admin/modules/AGENTS.md`；该目录下实际 Module Release、发布暂存和锁属于生成的 DataHome 运行资源，必须继续由 `.gitignore` 排除。

## Open

- **ADMIN-MODULE-006 — 版本保留。** 未再被任何 Entry Facet 选择的历史版本如何枚举、保留和清理，留待出现真实磁盘回收需求后确定。

## Maintainer Notes

- Windows Bootstrap 已实现本次构建 Module Release 的物化与清单验证；Core dispatcher 与 Admin 的运行时模块安装 Facet 尚未实现。
