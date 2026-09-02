# Admin Core 技能图规则

## Scope

本文件适用于 `data/admin/map/core/` 目录，Rule ID 前缀为 `ADMIN-CORE-MAP`。

## Accepted

- **ADMIN-CORE-MAP-001 — Admin 当前 Core 技能图。** `data/admin/map/core/` 是仓库纳入 Git 的唯一默认 Core 技能图，也是 Admin 用户当前持有的实例；它不是资源空间，只保存技能描述、模块选择指针和寻址索引，不保存 Module Release 或 Resource 的事实数据，不得在源码空间另建第二棵默认模板。
- **ADMIN-CORE-MAP-002 — 目录直接声明 SkillPath。** Core 技能图根下每个目录的相对路径就是该节点的 SkillPath；目录包含 `skill.json` 时可调用，不包含时只是分类节点。可调用节点可以同时包含子节点，技能图根本身不得包含 `skill.json`；不得使用通用 `execute/` 后缀、`swaw-harness.resource.json`、`swaw-harness.executable.json` 或另一套逻辑地址声明。
- **ADMIN-CORE-MAP-003 — 技能声明直接选择模块。** 每个 `skill.json` 只包含精确字段 `schema`、`module`、`version`、`executable` 和 `arguments`；`schema` 固定为 `swaw.harness.skill/v1`，`module` 使用 `<Publisher>/<Group>/<Module>`，`version` 使用精确版本、`MAJOR.*` 或 `MAJOR.MINOR.*`，`executable` 是所选 Module Release 根下由模块清单验证的安全文件名，`arguments` 是 Core Host 放在调用方动态参数之前传给 executable 的固定参数数组。
- **ADMIN-CORE-MAP-004 — 模糊版本显式选择。** `MAJOR.*` 选择本机已验证的最高同 major 稳定版本，`MAJOR.MINOR.*` 选择最高同 major/minor 稳定版本；Core 技能图相同但本机已安装版本不同，解析结果可以不同。要求完全复现的技能声明必须写精确版本。
- **ADMIN-CORE-MAP-005 — 实例修改不承诺整图原子性。** Admin 可以修改自己持有的 Core 技能图；本协议不规定多份 `skill.json` 的整体原子切换、A/B 布局、并发编辑或自动回退。单个技能节点的新调用可在其 `skill.json` 被原子替换后选择新版本，已经运行的进程继续使用原版本。

## Open

- **ADMIN-CORE-MAP-006 — 资源参数与授权。** Core Host 已把用户 CLI 在 SkillPath 之后的参数作为动态参数原样追加；资源空间及 Resource 路径如何显式传递，以及普通 Harness 用户选择 Admin 安装技能时如何拒绝 Admin 专用操作，仍待真实样例确定。SkillPath 与 Resource 路径不要求相同，目录位置不得被当作授权凭据。
- **ADMIN-CORE-MAP-007 — 技能节点组合。** 相对依赖、技能图子树的模块发布与安装、按子树执行及运行记录，留待第一个真实组合样例确定，不得先用另一套 Playbook 目录或宽泛声明文件占位。

## Maintainer Notes

- `helloworld` 已形成用户 CLI → Core Host → Module Release 的批处理调用样例；计划中的 `dev/setup` 等涉及资源空间或管理副作用的节点必须逐项实现和验证后才能加入 Core 技能图，不得由 Helloworld 样例推断为已完成。
