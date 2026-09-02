# Admin 技能图根规则

## Scope

本文件适用于 `data/admin/map/` 目录，Rule ID 前缀为 `ADMIN-MAP-ROOT`。

## Accepted

- **ADMIN-MAP-ROOT-001 — 技能图根只容纳具名技能图。** `data/admin/map/` 是 Admin 用户的技能图根而不是一棵技能图；其每个直接子目录以 SkillMapId 命名并形成一棵独立技能图，不得把技能节点或技能声明直接放在本根目录。
- **ADMIN-MAP-ROOT-002 — Core 身份保留。** `data/admin/map/core/` 是当前唯一已建立且由 Core 协议解释的技能图；`core` 不得用于用户或领域自定义技能图。
- **ADMIN-MAP-ROOT-003 — 自定义图不自动继承 Core 语义。** 新的 SkillMapId 必须使用规范小写 ASCII 文件系统安全名称；自定义技能图的允许文件、验证器、解释器和与 Core 技能图的关系必须由首个真实实例确定，目录存在本身不授予 executable 调用能力。

## Open

- **ADMIN-MAP-ROOT-004 — 自定义技能图生命周期。** 自定义技能图由用户直接建立、由 Module Release 安装还是由 Admin 管理，以及不同技能图之间如何引用，留待第一棵真实自定义技能图确定；当前不创建示例或占位目录。
