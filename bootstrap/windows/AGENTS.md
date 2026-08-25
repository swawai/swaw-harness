# Windows Bootstrap 维护规则

1. `builder/` 保存 Windows Stage-0 的跨产品构建与发布基础机制；`toolchain/` 管理构建工具链，`core/`、`entry/` 与 `entry.manager/` 分别拥有各自的产品适配器。
2. `builder/build/` 管理不可变 Candidate，`builder/release/` 管理不可变 Release 与 selector；不得建立 `common/`、`utils/`、总加载器或旧路径 shim。
3. `toolchain/` 可依赖 `builder/` 的基础路径、文件和进程机制；产品适配器可依赖两者。`builder/build/` 不得依赖 `builder/release/`，两者只由产品适配器和 `main.ps1` 显式编排。
4. PowerShell 文件必须自行 dot-source 足以加载所需函数的明确依赖链，不依赖调用者预先加载。
5. `main.ps1` 是多产品总编排器：必须先完成 Core、Entry 与 Entry Manager 的所有 Candidate 构建，再推进任何产品 selector，并在返回前重新解析和核验本轮发布结果。
6. `publication.ps1` 是 `main.ps1` 使用的 target-scoped 串行发布边界；各产品 `publish.ps1` 只是内部适配器，不单独承诺多产品 selector 一致性。
