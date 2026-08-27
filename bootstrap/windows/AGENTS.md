# Windows Bootstrap

## Scope

本目录拥有 Windows Stage-0 的平台 Contract、根编排入口与数据路径边界；`builder/`、`toolchain/` 和三个产品目录拥有各自的稳定子领域。Rule ID 前缀为 `WIN-BOOT`。

## Accepted

- **WIN-BOOT-001 — 平台 Contract 就近归属。** Windows 工具链版本、host target、下载来源与校验事实由 `bootstrap/windows/contract.json` 唯一声明；第二个平台出现真实共同字段前，不建立跨平台 contract 合并或继承体系。
- **WIN-BOOT-002 — Microsoft 许可非交互接受。** Windows Contract 必须固定 Microsoft Build Tools 许可地址与 `by-bootstrap-invocation` 接受方式；首次获取该工具链载荷前必须输出许可地址，调用 Bootstrap 即表示接受，不得弹出交互确认，MSI 必须显式禁止自动重启。
- **WIN-BOOT-003 — VS 产品线显式固定。** Windows Bootstrap v3 固定使用 VS 2026 stable 产品线及一个经长度与 SHA-256 锚定的精确 package manifest；不得在运行时解析 `latest`，升级必须同时修改 Contract、安装 recipe 与验收测试。
- **WIN-BOOT-004 — Windows 三产品自包含发布。** `bootstrap/windows/main.ps1` 每次调用都先构建 Core、Entry executable 与 Entry Manager 的全部 Candidate，再分别发布到各自 ReleaseRoot；已有 selector 不得跳过构建，内容未改变时复用 ReleaseId。三个产品的 Windows executable 均不得依赖用户另行安装的 C/C++ runtime；Windows 系统组件不属于该限制。

## Open

- **WIN-BOOT-005 — 三产品崩溃一致性。** 当前 target-scoped 锁只串行化协作发布者，三个 selector 仍是依次更新，进程崩溃不能保证三者形成原子 cohort；在消费者要求跨产品版本一致性前，必须决定采用单一 cohort selector 还是可恢复的发布 journal。
- **WIN-BOOT-006 — TargetId 编码。** TargetId 必须区分二进制不兼容目标，至少包含 OS 与 CPU architecture，并在必要时包含 ABI；采用 Rust target triple 还是稳定 Swaw `os-arch-abi` 名称，仍需由第一个 Windows publish 样例验证。

## Maintainer Notes

- 待办：消除 MSVC 链接时间等非确定性字节，使相同构建输入稳定产生相同 ReleaseId，避免创建和切换无实质内容变化的 Release；具体链接器与参数由真实原生依赖样例验证。
