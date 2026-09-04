# Admin Core Module

## Scope

本目录拥有 Admin Core module executable、UserId 验证以及 Harness 用户布局和生命周期实现。Rule ID 前缀为 `ADMIN`。

## Accepted

- **ADMIN-001 — 管理写入单点所有。** 目标中 Admin Core module executable 是运行时 Module Release 安装、UserId 验证、Harness 用户创建与生命周期写入的唯一实现所有者；Windows Bootstrap 只可从已验证 Bootstrap Release 初始物化本次构建的 Module Release、Admin 用户 CLI 与 Core Host 版本指针，用户 CLI executable 与其他模块不得维护替代实现。
- **ADMIN-002 — 固定 Admin 用户。** Admin UserHome 固定为 `data/admin/`，技能图根固定为 `data/admin/map/`，Core 技能图固定为 `data/admin/map/core/`，共享模块发布根固定为 `data/admin/modules/`，Core Host 版本指针根固定为 `data/admin/host/`，Harness 用户生命周期锁固定为 `data/admin/user.lock`；Admin 用户不使用旧 seed Runtime Release，不得整体替换或删除。
- **ADMIN-003 — 普通 UserId 语法。** 普通 UserId 必须是 1 至 16 字节的规范小写 ASCII 标识：首字符为 `a-z`，其余字符仅可为 `a-z`、`0-9` 或单个 `-`，末字符必须为字母或数字；不得静默转换大小写，不得包含连续 `--`，不得使用 Windows 保留设备名 `con`、`prn`、`aux`、`nul`、`com1` 至 `com9`、`lpt1` 至 `lpt9`，也不得使用固定 Admin 用户保留的 `admin`。
- **ADMIN-004 — 普通 Harness 用户创建。** `admin/user/create <UserId>` 必须在规范名称严格为 `data/admin/user.lock` 的生命周期锁下协调创建与恢复：暂存并验证绑定 UserId 且为 `creating` 的 `user.json`、Admin Core 技能图独立快照和 Admin 精确 Core Host 版本指针，提交 UserHome 后安装与当前 `data/admin.exe` 字节一致的用户 CLI，最后原子替换记录为 `active`。创建过程只保留 `<DataHome>/.user-<UserId>.tmp`、`<DataHome>/.<UserId>.exe.tmp` 与 `<UserHome>/.user.json.tmp` 三个固定暂存路径；`creating` 重试必须在持锁后清理名称精确、类型正确且非 reparse point 的对应残留，异常占位必须报告冲突；`active` 重复创建必须只验证三个保留路径均不存在，发现任何实体或大小写别名时不得清理而应报告冲突。所选 `swaw/core/host` 必须明确支持 `swaw.harness.user/v1` 启动门禁、`skill.toml`、技能帮助文档、技能调用目标、`/.help` 只读方法及单节点 Run；当前 Admin module 的已知兼容下界为 `1.0.10`，只接受 1.x 且不低于该下界。完整 `active` 用户的重复创建是只验证不写入的成功操作；单边实体、大小写别名等非规范名称、reparse point 或无效内容必须报告冲突。

## Open

- **ADMIN-005 — Admin 调用授权。** 当前 Admin Core module executable 不区分调用方 Harness 用户，普通用户通过自己的技能图调用 `admin/user/create` 不会被特殊拒绝；身份认证、命名权限动作和 Admin 受管授权记录由 Issue #55 单独定义。UserId、环境变量、`user.json` 生命周期和 `admin/` 文件系统路径均不得自行升级为授权凭据。
