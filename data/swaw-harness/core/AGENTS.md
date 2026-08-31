# Canonical Admin Entry Core 配置树规则

## Scope

本文件适用于 `data/swaw-harness/core/` 目录，Rule ID 前缀为 `ADMIN-CORE-TREE`。

## Accepted

- **ADMIN-CORE-TREE-001 — 唯一默认配置树。** `data/swaw-harness/core/` 是仓库纳入 Git 的唯一默认 Runtime Core Tree，同时是源码检出中 canonical Admin Entry 持有的实例；建立其他 Entry 时以它作为默认复制来源，但复制和升级流程尚未实现。不得在源码空间另建第二棵默认模板。
- **ADMIN-CORE-TREE-002 — 目录直接声明地址。** 一个包含 `swaw-harness.facet.json` 的叶目录声明一个 Facet，该目录名是 Facet 名称，其父目录相对本树根的路径是 Resource 路径；本树不得使用 `swaw-harness.resource.json`、`swaw-harness.executable.json` 或另一套逻辑地址声明。
- **ADMIN-CORE-TREE-003 — Facet 文件直接选择模块。** 每个 `swaw-harness.facet.json` 只包含精确字段 `schema`、`module`、`version`、`executable` 和 `arguments`；`module` 使用 `<Publisher>/<Group>/<Module>`，`version` 使用精确版本、`MAJOR.*` 或 `MAJOR.MINOR.*`，`executable` 是所选模块版本根下的安全文件名，`arguments` 是调用方动态参数之前传给 executable 的固定参数数组。
- **ADMIN-CORE-TREE-004 — 模糊版本显式选择。** `MAJOR.*` 选择本机已验证的最高同 major 稳定版本，`MAJOR.MINOR.*` 选择最高同 major/minor 稳定版本；配置相同但本机已安装版本不同，解析结果可以不同。要求完全复现的 Facet 必须写精确版本。
- **ADMIN-CORE-TREE-005 — 实例修改不承诺整树原子性。** 一个 Entry 可以修改自己持有的 Core 配置树；本协议不规定多份 Facet 文件的整体原子切换、A/B 布局、并发编辑或自动回退。单个 Facet 的新调用可在其文件被原子替换后选择新版本，已经运行的进程继续使用原版本。

## Open

- **ADMIN-CORE-TREE-006 — 动态参数约定。** Admin seed 的 HarnessRoot、Dev Bun mode 的可选 mode 等调用方动态参数如何统一传递，留待 Core dispatcher 首次实现时确定；当前 `arguments` 只记录现有 executable 的固定命令前缀。

## Maintainer Notes

- `dev/setup` Facet 当前只有目标配置，`swaw-harness-dev.exe` 尚未实现该 Resource；`data/modules/` 也尚无真实模块版本，因此本树当前不是可执行发布物。
