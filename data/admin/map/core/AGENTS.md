# Admin Core 技能图规则

## Scope

本文件适用于 `data/admin/map/core/` 目录，Rule ID 前缀为 `ADMIN-CORE-MAP`。

## Accepted

- **ADMIN-CORE-MAP-001 — Admin 当前 Core 技能图。** `data/admin/map/core/` 是仓库纳入 Git 的唯一默认 Core 技能图，也是 Admin 用户当前持有的实例；它不是资源空间，只保存技能描述、模块选择指针和寻址索引，不保存 Module Release 或 Resource 的事实数据，不得在源码空间另建第二棵默认模板。
- **ADMIN-CORE-MAP-002 — 目录直接声明 SkillPath。** Core 技能图根下每个目录的相对路径就是该节点的 SkillPath；目录包含规范 `skill.toml` 时可调用，不包含时只是分类节点。可调用节点可以同时包含子节点，目录父子关系默认只表达分类、SkillPath 包含和技能子树选择范围，不自动产生执行顺序或显式依赖；技能图根本身不得包含 `skill.toml`，旧 `skill.json` 不受支持且不得共存，也不得使用通用 `execute/` 后缀、`.node-facet`、任何真实点号目录、`swaw-harness.resource.json`、`swaw-harness.executable.json` 或另一套逻辑地址声明。技能调用目标中的 NodeMethod 只由 Core Host 解释，不是本技能图的目录成员。
- **ADMIN-CORE-MAP-003 — 技能声明直接选择模块。** 每个 `skill.toml` 是人类维护的严格 TOML 声明，只包含精确字段 `schema`、`module`、`version`、`executable` 和 `arguments`；`schema` 固定为 `swaw.harness.skill/v2`，`module` 使用 `<Publisher>/<Group>/<Module>`，`version` 使用精确版本、`MAJOR.*` 或 `MAJOR.MINOR.*`，`executable` 是所选 Module Release 根下由模块清单验证的安全文件名，`arguments` 是 Core Host 放在调用方动态参数之前传给 executable 的固定参数数组。
- **ADMIN-CORE-MAP-004 — 模糊版本显式选择。** `MAJOR.*` 选择本机已验证的最高同 major 稳定版本，`MAJOR.MINOR.*` 选择最高同 major/minor 稳定版本；Core 技能图相同但本机已安装版本不同，解析结果可以不同。要求完全复现的技能声明必须写精确版本。
- **ADMIN-CORE-MAP-005 — 实例修改不承诺整图原子性。** Admin 可以修改自己持有的 Core 技能图；本协议不规定多份 `skill.toml` 的整体原子切换、A/B 布局、并发编辑或自动回退。单个技能节点的新调用可在其 `skill.toml` 被原子替换后选择新版本，已经运行的进程继续使用原版本。

## Open

- **ADMIN-CORE-MAP-006 — 资源参数与授权。** Core Host 已把用户 CLI 在技能调用目标之后的参数作为动态参数原样追加；资源空间及 Resource 路径如何显式传递仍待真实样例确定。当前普通 Harness 用户复制的 Core 技能图包含 SkillPath `admin/user/create`，调用目标 `core/admin/user/create` 不会被特殊拒绝；未来授权由 Issue #55 处理，SkillPath 和目录位置不得被当作授权凭据。
- **ADMIN-CORE-MAP-007 — 分类与编排共用技能图。** `data/admin/map/core/` 可以同时容纳普通分类子树和声明执行关系的编排子树；两者继续使用同一 SkillPath、技能节点和 Module Release 选择机制，不得为 Playbook 另建目录根、节点类型或发布格式。Core Host 已保留 `/.tree`、`/.tree.parent-success` 和 `/.tree.no-structure` 虚拟选择器，但当前实例尚无子树执行策略或依赖声明实体且 Host 尚未执行这些方法；显式依赖和技能子树发布由 Issue #59 和首个真实样例继续确定，不得先增加空目录或宽泛占位文件。

## Maintainer Notes

- `core/helloworld` 已形成用户 CLI → Core Host → 单节点 Run → Module Release 的批处理调用样例，`core/admin/user/create` 已形成普通 Harness 用户创建样例；计划中的节点方法、其他管理操作及涉及资源空间的节点必须逐项实现和验证后才能加入 Core 技能图，不得由现有样例推断为已完成。
