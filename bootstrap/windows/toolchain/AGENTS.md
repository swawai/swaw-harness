# Windows Bootstrap Toolchain

## Scope

本目录拥有 Windows Stage-0 构建工具链的身份、载荷、安装、校验与受信执行入口；具体 Rust 与 MSVC 组装由各自子目录拥有。Rule ID 前缀为 `WIN-TOOLCHAIN`。

## Accepted

- **WIN-TOOLCHAIN-001 — 外部下载必须校验。** `bootstrap/windows/contract.json` 直接声明的下载必须校验其中记录的长度与 SHA-256；Microsoft 清单引用的子载荷必须受清单声明的大小约束，并以清单记录的 SHA-256 校验内容。
- **WIN-TOOLCHAIN-002 — 已安装工具链分层校验。** `<repository>/data/bootstrap.windows/toolchains/<toolchain-directory>/toolchain.json` 必须保存 Rust 与 MSVC 安装的完整文件树摘要和关键文件记录；普通复用校验关键文件，完整文件树扫描只由显式维护或测试入口触发。
- **WIN-TOOLCHAIN-003 — 工具链数据不得成为脚本来源。** `toolchain-setup.ps1` 与 `toolchain.ps1` 只能从作者目录 `bootstrap/windows` 加载脚本；`<repository>/data/bootstrap.windows` 与 `<repository>/data/bootstrap.windows.cache` 只保存下载物、已安装工具和构建数据，不得保存供用户或 Bootstrap 加载执行的脚本。

## Open

无。
