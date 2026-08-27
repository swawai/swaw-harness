# Windows MSVC Bootstrap 维护规则

## Scope

本目录负责从父级 Windows Contract 选择、验证并组装 Swaw Harness 使用的便携 MSVC 与 Windows SDK；不负责通用工具链生命周期、产品构建或 Release 发布。

## Structure

允许：

- manifest 与安装 recipe 选择
- 外部 payload 校验与展开
- 便携工具链组装与安装
- inventory 与 receipt 验证
- 本领域的 `AGENTS.md` 与 `SPEC.md`

禁止：

- 平台或产品 Contract
- 通用下载缓存与工具链生命周期
- Candidate、Release 或 selector 实现
- Core、Entry 或 Entry Manager 产品适配器
- 无真实消费者的兼容脚本或旧路径 shim

## Maintenance

1. **所有权：** MSVC 实现可依赖父级 `toolchain/` 与 `builder/` 基础机制，不得反向拥有它们的协议。
2. **变更：** manifest 选择与便携组装主要参考 https://gist.github.com/mmozeiko/7f3162ec2988e81e56d5c4e22cde9977；修改相关算法时必须对比当前上游、同步本目录 `SPEC.md`，但只迁入本产品有真实消费者的能力。
3. **验证：** 修改来源、recipe、payload、安装或 inventory 时，运行对应 MSVC 测试及受影响的工具链端到端测试。
