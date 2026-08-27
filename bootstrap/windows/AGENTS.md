# Windows Bootstrap

## Scope

本目录拥有 Windows Stage-0 的平台 Contract、根编排入口与数据路径边界；`builder/`、`toolchain/` 和三个产品目录拥有各自的稳定子领域。Rule ID 前缀为 `WIN-BOOT`。

## Accepted

- **WIN-BOOT-001 — 平台 Contract 就近归属。** Windows 工具链版本、host target、下载来源与校验事实由 `bootstrap/windows/contract.json` 唯一声明；第二个平台出现真实共同字段前，不建立跨平台 contract 合并或继承体系。
- **WIN-BOOT-002 — Microsoft 许可非交互接受。** Windows Contract 必须固定 Microsoft Build Tools 许可地址与 `by-bootstrap-invocation` 接受方式；首次获取该工具链载荷前必须输出许可地址，调用 Bootstrap 即表示接受，不得弹出交互确认，MSI 必须显式禁止自动重启。
- **WIN-BOOT-003 — Windows executable 运行时自包含。** Windows Bootstrap 发布的 Core、Entry executable 与 Entry Manager executable 均不得依赖用户另行安装的 C/C++ runtime；Windows 系统组件不属于该限制。
- **WIN-BOOT-004 — Windows 便携工具链。** Windows Bootstrap 必须自动下载并设置便携 Rust 与 MSVC 编译环境，无需用户预装、配置或交互干预，即可编译出 Harness 核心。

## Open

当前无。

## Maintainer Notes

- 待办：消除 MSVC 链接时间等非确定性字节，使相同构建输入稳定产生相同 ReleaseId，避免创建和切换无实质内容变化的 Release；具体链接器与参数由真实原生依赖样例验证。
