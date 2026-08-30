# Admin Core Module

## Scope

本目录拥有 Admin Core module executable、`admin/entry` Resource 及 Entry 布局和生命周期实现。Rule ID 前缀为 `ADMIN`。

## Accepted

- **ADMIN-001 — Entry 生命周期单点所有。** Admin Core module executable 是 EntryId 验证、Entry 布局、受管记录、生命周期转换、staging、互斥锁、恢复与激活的唯一实现所有者；Bootstrap、Entry Manager executable、Harness GUI executable、Entry launcher 与测试不得维护替代实现。
- **ADMIN-002 — Entry 与 Runtime Release 布局。** 每个 Entry 由同级 `data/<EntryId>.exe` 与 `data/<EntryId>/` EntryRoot 组成；`<EntryRoot>/entry.json` 保存受管身份与生命周期，`<EntryRoot>/runtime/<ReleaseId>/` 保存完整不可变 Runtime Release，`<EntryRoot>/runtime/current.<PlatformTargetId>` selector 选择当前 Release；DataHome 的 Entry 生命周期锁固定为 `data/.entry.lock`，新 Entry 的 staging 只可临时使用 `data/.<EntryId>.<Facet>-<process-unique>.tmp/`，已有 Entry 的 Runtime Release staging 只可临时使用 `<EntryRoot>/runtime/.release-<process-unique>.tmp/`，完成或失败后必须清理且不得建立持久 staging 目录。
- **ADMIN-003 — EntryId 语法。** EntryId 必须是 1 至 16 字节的规范小写 ASCII 标识：首字符为 `a-z`，其余字符仅可为 `a-z`、`0-9` 或单个 `-`，末字符必须为字母或数字；不得静默转换大小写，不得包含连续 `--`，且不得使用 Windows 保留设备名 `con`、`prn`、`aux`、`nul`、`com1` 至 `com9`、`lpt1` 至 `lpt9`。
- **ADMIN-004 — Entry 受管记录。** `<EntryRoot>/entry.json` 必须使用 `swaw.harness.entry/v1` schema，只保存与路径一致的 `entryId` 以及 `provisioning`、`active`、`deleting` 之一的 `lifecycle`；未知 schema、字段、生命周期或不一致身份必须拒绝，不得从无效记录推断受管状态。
- **ADMIN-005 — seed 固定来源与目标。** `admin/entry/swaw-harness seed` 只可把包含当前 Admin Core module executable 的一个完整已验证 Release 播种为 canonical `swaw-harness` Entry；它必须接受显式绝对 HarnessRoot、固定 EntryId、复制而非 hard-link 全部 Runtime Release 文件，并在同一生命周期锁内恢复未完成 provisioning，且不得覆盖或升级已 active 的另一 Release。

## Open

无。
