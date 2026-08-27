# Windows Bootstrap Toolchain

## Scope

本目录拥有 Windows Stage-0 构建工具链的身份、载荷、安装、校验与受信执行入口；具体 Rust 与 MSVC 组装由各自子目录拥有。Rule ID 前缀为 `WIN-TOOLCHAIN`。

## Accepted

- **WIN-TOOLCHAIN-001 — Windows 物理路径有界。** 对仍受 `MAX_PATH` 约束的 MSVC/MSI 工具链，物理目录使用由完整身份确定的短 locator（工具链为 `tc-<128-bit hash prefix>`），完整 256-bit 身份仍由唯一 metadata 保存并校验；locator 冲突必须拒绝，不能误用已有内容。
- **WIN-TOOLCHAIN-002 — 外部载荷身份。** Contract 直接锚定的固定文件必须同时校验精确长度与 SHA-256；Microsoft 子载荷清单中的 `size` 只作为有界下载的声明值，实际身份以非空实际长度和清单 SHA-256 为准，并同时记录声明长度与实际长度。
- **WIN-TOOLCHAIN-003 — 工具链校验分层。** 安装时从完整文件树生成确定性摘要，但持久收据只保存该摘要、来源证明与少量关键文件记录；日常复用只执行快速收据检查，完整树遍历与 Hash 只能由显式 Full audit 触发，不得进入 Entry executable 或 Bootstrap 默认路径。
- **WIN-TOOLCHAIN-004 — 工具链由 Contract 选择。** Bootstrap 工具链是由平台 Contract、target 与安装 recipe 共同确定的不可变构建输入；不得再用 mutable `current.*` 或生成脚本中的硬编码 ToolchainId 建立第二选择源。
- **WIN-TOOLCHAIN-005 — 工具链入口与代码信任边界。** `toolchain-setup.ps1` 显式安装或修复 Contract 指定的工具链，`toolchain.ps1` 只从作者态 `bootstrap/windows` 解析并运行 `BootstrapWindowsRoot/toolchains` 中的已安装工具；两个 Windows Bootstrap 数据根都不得发布供用户执行的脚本。

## Open

无。

## Superseded

- **BOOT-016 — Windows 物理路径有界。** 本规则曾使用中央 Bootstrap 序列；其原义由 `WIN-TOOLCHAIN-001` 继承。
- **BOOT-017 — 外部载荷身份。** 本规则曾使用中央 Bootstrap 序列；其原义由 `WIN-TOOLCHAIN-002` 继承。
- **BOOT-019 — 工具链校验分层。** 本规则曾使用中央 Bootstrap 序列；其原义由 `WIN-TOOLCHAIN-003` 继承。
- **BOOT-022 — 工具链由 Contract 选择。** 本规则曾使用中央 Bootstrap 序列；其原义由 `WIN-TOOLCHAIN-004` 继承。
- **BOOT-044 — 工具链入口与代码信任边界。** 本规则曾使用中央 Bootstrap 序列；其原义由 `WIN-TOOLCHAIN-005` 继承。
