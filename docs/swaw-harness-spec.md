# Swaw Harness 核心架构规范

本文记录 Swaw Harness 全仓及跨领域的架构与协议；稳定领域的新规则由最近目录的 `AGENTS.md` 记录并与上层规则依次叠加，尚未下沉的既有领域规则在完成单一来源迁移前继续由本文现有条目承载。每条规则保持一至两句话；未来验收脚本只引用稳定规则 ID，不从散文推断要求。

状态：`Accepted` 表示已经完成决议并形成当前可验证的实现约束，不要求永久不变，也不自动表示目标能力已经交付；过渡边界只有同时声明当前约束与明确退出条件时才可接受，纯进度事实属于 `Maintainer Notes`。`Open` 是唯一的未决规则状态且不具有实现约束；当前协议文件只保留这两种规则，Git 保存退出规则与基线前编号的历史。当前规范树中的完整 Rule ID 与领域前缀必须唯一，同一前缀的序列从 `001` 连续开始，新 ID 使用当前最大后缀加一。

## Accepted

- **CORE-RELEASE-001 — Core Release 空间。** `CoreReleaseRoot` 唯一映射为 `DataRoot/core.release`，直接保存共享 Core Release 与 target selector；点号分隔顶层 owner 与 kind，不增加无独立职责的中间层。
- **ENTRY-RELEASE-001 — Entry executable Release 空间。** `EntryReleaseRoot` 唯一映射为 `DataRoot/entry.release`，只保存内容寻址的 `swaw-harness-entry.exe` Release 与 target selector；它是 Entry Manager 的分发源，不是 Entry 实例数据。
- **ENTRY-MANAGER-RELEASE-001 — Entry Manager Release 空间。** `EntryManagerReleaseRoot` 唯一映射为 `DataRoot/entry.manager.release`，只保存内容寻址的独立 Entry Manager Release 与 target selector，不保存 Entry 实例数据。
- **DATA-LIFECYCLE-001 — 数据空间按所有者与生命周期分治。** 无 Bootstrap 进程运行时可以整体清理 `BootstrapWindowsCacheRoot`；删除 `BootstrapWindowsRoot` 属于工具链重置而非清 cache，`CoreReleaseRoot` 只允许显式 Release GC 与 selector 更新。
- **ENTRY-DATA-001 — Entry 数据空间。** 仓库内 EntryDataRoot 固定为 `<repository>/data.entry`，每个直接子目录唯一对应一个 EntryId；自定义位置协议留待 Entry executable 垂直样例确定。
- **ENTRY-LAYOUT-001 — Entry 文件与数据同名配对。** 一个 Entry 由同级的 `data.entry/<entry-id>.exe` 与 `data.entry/<entry-id>/` 组成；后者的 `entry.json` 是受管身份与生命周期 descriptor，二者不承诺文件系统级原子出现。
- **ENTRY-LIFECYCLE-001 — Entry 生命周期目标协议。** 实现 Entry 创建与启动时，descriptor 的状态只允许 `provisioning`、`active`、`deleting`；只有文件、目录、身份和运行引用全部核验通过的 `active` Entry 可启动，Manager 只有在状态提交并回读成功后才报告创建成功。
- **ENTRY-RECOVERY-001 — Entry Manager 恢复目标协议。** 实现控制面板时，Manager 是 Entry 创建、删除和状态迁移的唯一支持写入者，每次启动控制面板前必须在互斥锁内幂等恢复有效 descriptor 记录的未完成操作；无有效 descriptor 的孤立对象只报告冲突，不得推断所有权并静默删除。
- **ENTRY-CACHE-001 — Entry cache 所有者显式。** `EntryRoot/cache` 只保存 Entry-local cache；不得与 `BootstrapWindowsCacheRoot` 隐式 fallback、复制或同步。
- **CACHE-001 — 不预建全局 Cache。** 当前不存在 `DataRoot/cache`；只有第二个真实消费者出现并共同采用内容身份、原子发布、并发锁与 GC 协议后，才允许建立全局 Artifact Cache。
- **BOOT-002 — 冷启动依赖最小化。** Windows Stage-0 只获取构建当前 Rust 产品必需的 minimal Rust 与 MSVC 工具链，不获取 `rustfmt`、Bun 或内置 Pwsh；开发工具与脚本 Facet runtime 由出现真实消费者后的独立 setup 协议负责。
- **BOOT-003 — 持久清单确定性。** 写入身份或完整性 metadata 的无序集合必须先按协议规定的、与文化和 PowerShell 版本无关的 ordinal 顺序规范化；Windows 路径先按 `OrdinalIgnoreCase`、再按 `Ordinal` 决胜，验证不得依赖文件系统枚举顺序或 `Sort-Object` 默认语义。
- **BOOT-004 — 构建环境属于子进程。** MSVC、SDK、Rust 与 Cargo 环境只注入实际工具子进程，不修改再恢复父 PowerShell 进程，也不生成需要 dot-source 的环境脚本；工具入口必须使用显式受支持的 executable 映射。
- **BOOT-006 — 仓库根 Windows 构建入口。** 根 `build.cmd` 是无业务逻辑的 Windows 适配器，只以 `<repository>/data` 调用 `bootstrap/windows/main.ps1` 并原样传播退出码；它不得复制 Entry executable、创建 Entry 或输出人工复制指引。
- **BOOT-007 — Windows Stage-0 作者布局。** `bootstrap/windows/builder` 保存跨产品 Candidate、Release 与基础机制，`toolchain` 独占构建工具链领域，`core`、`entry` 与 `entry.manager` 分别拥有 Core、Entry executable 与 Entry Manager 产品适配器；`main.ps1` 是先构建全部 Candidate、再发布并核验 selector 的唯一多产品编排器。
- **BOOT-009 — Windows Rust 产品静态 CRT。** Windows Core 与 Entry Manager 的产品 Contract 必须显式要求静态 CRT，构建必须把该要求投影为 Cargo/rustc 命令行配置；验收必须读取发布 PE 的 import table，并拒绝 `VCRUNTIME`、`UCRT` 或其他外部 C/C++ runtime 依赖。
- **BOOT-011 — Windows 子领域依赖方向。** `toolchain/` 可依赖 `builder/` 的基础路径、文件和进程机制，产品适配器可依赖两者；`builder/build/` 不得依赖 `builder/release/`，两者只由产品适配器和根编排器显式组合，不得以 `common/`、`utils/`、总加载器或旧路径 shim 绕过依赖方向。
- **BOOT-012 — PowerShell 依赖显式。** Windows Bootstrap 的 PowerShell 文件必须自行 dot-source 足以加载所需函数的明确依赖链，不得依赖调用者预先加载。
- **RELEASE-001 — Core 发布池身份。** `DataRoot/core.release/<release-id>/` 是 Bootstrap 产生的共享不可变 Core 发布池；`release-id` 的 Hash 必须覆盖完整发布内容及含 target 的发布元数据，不能只散列源码 revision。
- **RELEASE-002 — Bootstrap Target Selector。** Core、Entry executable 与 Entry Manager 的 ReleaseRoot 都各自保存只含 Release 引用的 `current.<target-id>`；Publish 只原子更新本产品、本 target 的 selector，并验证所指 Release 的 target 兼容性。

## Open

- **ENTRY-CORE-001 — Entry selector 的引用形态。** `EntryRoot/releases` 应保存 Core Release 完整副本、硬链接，还是对 `DataRoot/core.release` 的受校验引用，尚未决议；选择必须同时满足 Entry 可搬移性、磁盘去重、原子更新与损坏隔离。

- **REMOTE-001 — 远端物化。** 远端查询不得在读取时隐式写入本地资源树；显式 `mount/import` 创建只含 provider、稳定 remote ID、revision 与状态的本地 descriptor，cache 与凭据不属于 Resource identity。
- **BUILD-REPRO-001 — Windows 可复现链接。** 当前 MSVC `link.exe` 的全新构建会把链接时间写入 PE，使同源码与同工具链仍可能产生字节不同但各自内容寻址正确的 Release；是否改用 `lld-link` 或建立更完整的 reproducible-build contract，必须在真实原生依赖样例出现后决议，不能仅追加 `/Brepro` 就宣称可复现。
