# Core 领域规则

## Scope

本文件适用于 `core/` 目录，Rule ID 前缀为 `CORE`。

## Accepted

- **CORE-001 — 资源空间保存事实数据。** Resource 按事实来源、生命周期与写入权限分属资源空间；基础资源空间包括 `author`、`runtime`、`runs`、`export` 与 `context`，领域或用户机制可通过技能建立派生资源空间。两类资源空间均采用目录树寻址；`<UserHome>/map/` 技能图根、其中的具名技能图和 `<DataHome>/admin/modules/` Module Release 根不属于资源空间，也不得保存 Resource 事实数据。
- **CORE-002 — Resource 路径与 SkillPath 各自寻址。** 资源空间以其根下规范化的相对路径寻找 Resource，技能图以其根下规范化的 SkillPath 寻找技能节点；两者不要求相同或镜像。`data/admin/map/core/` 是唯一默认 Core 技能图，其他 Harness 用户的实例位于 `<UserHome>/map/core/`；不得另建 ResourceIdentity、ResourceRoute、Listing 或其他地址模型。
- **CORE-003 — 技能节点即调用地址。** Core 技能图中一个目录就是一个技能节点；包含 `skill.toml` 时该 SkillPath 可调用，不包含时只是分类节点。可调用节点可以继续包含子节点，目录父子关系默认只表达分类、SkillPath 包含和技能子树范围，不自动产生执行顺序、显式依赖或失败传播；不得通过通用 `execute/` 子目录重复表达可执行性，也不区分 `Operation` 与 `Projection` 两种节点类型。技能调用目标末尾由 Core Host 识别的 `/.tree`、`/.tree.parent-success`、`/.tree.no-structure`、`/.help` 和 `/.plan` 是虚拟节点方法，不属于 SkillPath，不得在技能图中创建对应点号目录或 `.node-facet`。
- **CORE-004 — 技能声明有界授予执行权。** 对普通技能调用，只有目标 `<UserHome>/map/core/` Core 技能图技能节点中的规范 `skill.toml` 可以选择 Module Release executable；其 TOML `schema`、`module`、`version`、`executable` 和 `arguments` 必须精确通过协议验证，旧 `skill.json` 不受支持且不得共存。所选模块必须来自同一 DataHome 的 `<DataHome>/admin/modules/` 已验证发布目录，且 executable 必须由该 Module Release 的 `swaw-harness.module.json` 清单列出。Core Host 版本指针是启动边界的唯一例外，只能选择固定 ModuleId `swaw/core/host`、当前 PlatformTargetId、固定 executable 名称与精确版本，不能授予普通技能调用权。其他技能图、其他文件与可写 Resource 数据不得声明 executable、技能实现或平台能力；目录位于 `admin/` 下不构成调用授权。
- **CORE-006 — SkillPath 与实现目录解耦。** Core 技能图中的技能声明是 SkillPath 与实现选择的事实来源；每个技能节点直接声明 ModuleId 和版本选择，不继承祖先目录的 executable。`core/modules/` 中 Rust package、模块和函数的源码层级不得被 Core 协议要求镜像 SkillPath；Core Host 把技能声明的固定 `arguments` 放在调用方动态参数之前传给模块，资源空间和 Resource 路径的显式传递约定仍留待首个真实样例确定。
- **CORE-009 — 单节点 Run 使用独立工作目录。** 当前 Core Host 对每次隐式 `node` 方法执行生成一个 RunId，先把调用目标、解析后的 Module Release、Windows UTF-16 参数和 `running` 结果固化到 `<UserHome>/runs/<RunId>/run.json`，再以 `<UserHome>/runs/<RunId>/<SkillMapId>/<SkillPath>/` 作为模块进程当前工作目录；模块退出后必须原子记录 `completed` 与退出码，Host 监督失败必须原子记录 `failed` 与错误。一次执行不得复用其他 Run 的目录，Module Release 根不得继续充当模块工作目录，stdout/stderr 也不得冒充尚未定义的结构化日志。

## Open

- **CORE-005 — 远端资源挂载。** 远端 Resource 通过显式 mount 进入派生资源空间后，应与本地 Resource 一样使用资源空间目录树寻址，不另建远端专用地址模型；技能如何接收和操作远端 Resource，以及 mount 的物化、同步、离线、身份和凭据边界，仍需由首个真实远端实现确定。
- **CORE-007 — 技能执行范围与子树模式。** 当前 Core Host 只实现技能调用目标 `<SkillMapId>/<SkillPath>` 的节点执行；已保留但尚未实现的 `/.tree`、`/.tree.parent-success` 和 `/.tree.no-structure` 分别选择普通、强父子顺序和无父子顺序子树模式。普通模式只采用技能子树中明确声明的父子顺序，未声明区域中的父节点失败不得阻断没有依赖它的子节点；强父子顺序模式为所选范围加入可调用父节点成功后后代才可运行的结构顺序；无父子顺序模式忽略选中范围内普通或已声明的结构顺序。分类节点没有 executable 动作，只参与范围和层级组织；所有模式都必须保留显式依赖，影响正确性的前置条件不得只依赖可被忽略的结构顺序。声明文件和 schema 尚未实现，必须由首个真实分类批量执行与编排样例共同确定。
- **CORE-008 — 技能子树执行计划。** 目标中的 Core Host 必须在子树执行启动任何 Module Release 前固定参与节点，合并执行模式产生的结构顺序与节点声明的显式依赖，拒绝缺失引用、自我依赖和循环关系，再按有界并发调度；一个节点失败只阻断依赖图中受影响的后续节点，不得阻断无关分支，最终汇总各节点的成功、失败、阻断与跳过状态。显式依赖可以只要求前置节点在本次运行中成功，也可以进一步绑定其特定产物；未来拓扑渲染器必须复用同一执行计划，不能另行解释技能图。同一次子树执行必须只生成一个 RunId，并在其 Run 根中展开全部节点目录；相对依赖、运行产物身份、状态检查、跨图引用和技能子树发布仍未实现。

## Maintainer Notes

- 待办：迁移旧实现时 hard cut `Collection Facet`、`Operation`/`Projection` kind、`ResourceListing` 投影及逻辑 Route 模型，统一改为“资源空间目录树寻址 + SkillPath 调用”；完成前不得声称旧实现已符合本规则。
- `core/host/` 已通过 Windows 命名管道接收一次批处理调用，并由 `core/protocol` 验证普通 Harness 用户的 `active user.json`、技能调用目标、SkillPath、技能声明和同一 DataHome 的已安装 Module Release；当前单节点执行会建立 Run 记录和节点工作目录，`admin/user/create` 已复制普通用户的独立 Core 技能图快照。结构化日志、重播、技能子树执行和资源空间 Resource 验证尚未实现。
