# Admin Core Module

## Scope

本目录拥有 Admin Core module executable、UserId 验证以及 Harness 用户布局和生命周期实现。Rule ID 前缀为 `ADMIN`。

## Accepted

- **ADMIN-001 — 管理写入单点所有。** 目标中 Admin Core module executable 是运行时 Module Release 安装、UserId 验证、Harness 用户创建与生命周期写入的唯一实现所有者；Windows Bootstrap 只可从已验证 Bootstrap Release 初始物化本次构建的 Module Release，Harness 管理 CLI executable、Harness GUI executable、用户 CLI executable 与其他模块不得维护替代实现。
- **ADMIN-002 — 固定 Admin 用户。** Admin UserHome 固定为 `data/admin/`，技能图根固定为 `data/admin/map/`，Core 技能图固定为 `data/admin/map/core/`，共享模块发布根固定为 `data/admin/modules/`，Harness 用户生命周期锁固定为 `data/admin/user.lock`；Admin 用户不使用旧 seed Runtime Release，不得整体替换或删除。
- **ADMIN-003 — 普通 UserId 语法。** 普通 UserId 必须是 1 至 16 字节的规范小写 ASCII 标识：首字符为 `a-z`，其余字符仅可为 `a-z`、`0-9` 或单个 `-`，末字符必须为字母或数字；不得静默转换大小写，不得包含连续 `--`，不得使用 Windows 保留设备名 `con`、`prn`、`aux`、`nul`、`com1` 至 `com9`、`lpt1` 至 `lpt9`，也不得使用固定 Admin 用户保留的 `admin`。

## Open

- **ADMIN-004 — 普通 Harness 用户创建。** 普通 Harness 用户的最小目录、受管记录、技能图来源、用户 CLI 安装与恢复流程，留待首个 `admin/user/create` 技能实现确定；旧 seed 专用实现不得作为当前能力保留。
- **ADMIN-005 — Admin 调用授权。** Core dispatcher 如何证明调用来自 Admin 用户，以及普通 Harness 用户如何被禁止调用 Admin 专用操作，留待 dispatcher 首次实现确定；UserId、环境变量和 `admin/` 文件系统路径均不得单独作为授权凭据。
