# Admin 配置根规则

## Scope

本文件适用于 `data/admin/config/` 目录，Rule ID 前缀为 `ADMIN-CONFIG`。

## Accepted

- **ADMIN-CONFIG-001 — 配置根不是资源空间。** `data/admin/config/` 是 Admin Entry 的配置根，只容纳具有具体协议和所有者的配置树；它不是 Resource 的事实目录，也不得作为 `author`、`runtime`、`runs`、`export` 或 `context` 资源空间的替代根。
- **ADMIN-CONFIG-002 — 配置树分别定义。** 配置根下每种配置树必须由自己的规则明确根目录、声明文件、验证器与解释器；当前只有 `data/admin/config/core/` Core 配置树成为仓库实体。未知目录和普通 JSON 文件不得自动获得 Core 配置树语义。
- **ADMIN-CONFIG-003 — executable 绑定只属 Core 配置树。** 只有 `data/admin/config/core/` 中通过验证的 `swaw-harness.facet.json` 可以选择 Module Release executable；其他配置树即使采用目录层级，也只能引用已解析的 Resource 与 Facet，不得自行声明 ModuleId、版本或 executable 来绕过 Core dispatcher。
- **ADMIN-CONFIG-004 — 编排配置树复用调用心智。** 每个编排配置树实例固定在 `<EntryRoot>/config/playbooks/<PlaybookId>/`；执行步骤只选择资源空间、Resource 路径与 Facet 并提供调用参数，由当前 Entry 的 Core 配置树完成模块选择，不得在编排步骤中重复 Facet declaration。

## Open

- **ADMIN-CONFIG-005 — 编排顺序与依赖。** 数字前缀和目录层级只能定义稳定的有序执行树，不能单独表达一个节点依赖多个前置节点的有向无环图；步骤声明格式、失败策略、并行度和显式依赖边留待首个真实编排样例确定，当前不创建空目录或占位 schema。
- **ADMIN-CONFIG-006 — 其他自定义配置树。** 第二种非 Core 配置树出现时再确定其目录种类、身份和 schema；不得让一个含义宽泛的通用配置文件解释所有自定义树。
