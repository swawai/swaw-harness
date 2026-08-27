# Windows MSVC Bootstrap 规范

## Scope

本目录拥有 Windows Bootstrap 所需 MSVC 与 Windows SDK 的来源选择、许可、payload 验证和便携组装协议；平台 target 与版本输入由父级 Contract 拥有，通用工具链发布由父级 `toolchain/` 拥有。

## Accepted

- **BOOT-027 — Microsoft 许可非交互接受。** Windows Contract 必须固定 Microsoft Build Tools 许可地址与 `by-bootstrap-invocation` 接受方式；首次获取该工具链载荷前必须输出许可地址，调用 Bootstrap 即表示接受，不得弹出交互确认，MSI 必须显式禁止自动重启。
- **BOOT-028 — VS 产品线显式固定。** Windows Bootstrap v3 固定使用 VS 2026 stable 产品线及一个经长度与 SHA-256 锚定的精确 package manifest；不得在运行时解析 `latest`，升级必须同时修改 Contract、安装 recipe 与验收测试。

## Open

无。
