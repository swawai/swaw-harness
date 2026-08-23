# Windows Bootstrap 内部库规则

1. `_lib` 根只保留至少被两个领域使用的 Stage-0 基础机制；领域实现分别归入 `toolchain/`、`build/` 与 `release/`，不得建立 `common/`、`utils/` 或总加载器。
2. `toolchain/` 管理工具链定义、下载、安装、完整性与子进程环境；`build/` 管理 Candidate；`release/` 管理不可变 Release 与 selector。
3. 领域可依赖自身内部实现与 `_lib` 根基础机制；跨领域只允许 `release/` 读取 Candidate，`build/` 不得依赖 `release/`，两者由 `main.ps1`、`publish.ps1` 等入口编排。
4. PowerShell 文件必须自行 dot-source 足以加载所需函数的明确依赖链，不依赖调用者预先加载，也不建立总加载器或旧路径 shim。
