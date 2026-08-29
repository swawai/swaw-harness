# Windows Bootstrap

## Scope

本目录拥有 Windows Stage-0 的平台 Contract、根编排入口与数据路径边界；`builder/`、`toolchain/` 和三个产品目录拥有各自的稳定子领域。Rule ID 前缀为 `WIN-BOOT`。

## Accepted

- **WIN-BOOT-001 — 平台 Contract 就近归属。** Windows 工具链版本、host target、下载来源与校验事实由 `bootstrap/windows/contract.json` 唯一声明；第二个平台出现真实共同字段前，不建立跨平台 contract 合并或继承体系。
- **WIN-BOOT-002 — Microsoft 许可非交互接受。** Windows Contract 必须固定 Microsoft Build Tools 许可地址与 `by-bootstrap-invocation` 接受方式；首次获取该工具链载荷前必须输出许可地址，调用 Bootstrap 即表示接受，不得弹出交互确认，MSI 必须显式禁止自动重启。
- **WIN-BOOT-003 — Windows executable 运行时自包含。** Windows Bootstrap 发布的 Core、Entry executable 与 Entry Manager executable 均不得依赖用户另行安装的 C/C++ runtime；Windows 系统组件不属于该限制。
- **WIN-BOOT-004 — Windows 便携工具链与 native 路径预算。** Windows Bootstrap 必须自动下载并设置便携 Rust 与 MSVC 编译环境，无需用户预装、配置或交互干预，即可编译出 Harness 核心；绝对 HarnessRoot 或源码仓库根不得超过 60 字符，EntryId 最多 16 字符，交给 native 构建工具的路径不得超过 240 字符，不得通过盘符映射、reparse point、8.3 名称、环境变量替换或修改操作系统长路径设置来满足预算。
- **WIN-BOOT-005 — 构建环境只进入工具子进程。** `bootstrap/windows/toolchain/environment.ps1` 只生成环境计划，`bootstrap/windows/builder/process.ps1` 只把该计划注入实际工具子进程；不得修改后再恢复父 PowerShell 进程，也不得生成要求调用者 dot-source 的环境脚本，工具入口必须使用明确支持的 executable 路径。
- **WIN-BOOT-006 — Windows data.repo 扁平分域。** Windows Bootstrap 生产代码只使用 `<repository>/data.repo/windows.release`、`windows.build`、`windows.tool`、`windows.stage`、`windows.cache`、`windows.locks` 与 `windows.logs`；`bootstrap/windows/tests` 另将可整体删除的测试工作数据写入 `windows.test`，生产代码不得读写该测试根；`windows` 表示 Bootstrap 宿主平台，点号命名只分组同级领域根，不建立隐含层级。

## Open

当前无。
