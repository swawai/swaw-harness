# Core Templates

## Scope

本目录拥有标准 Rust 模块模板的作者态结构与可独立执行边界。Rule ID 前缀为 `CORE-TEMPLATE`。

## Accepted

- **CORE-TEMPLATE-001 — 标准模块边界。** 标准 Rust 模块把领域行为放在 library API，并只用薄 executable 处理进程输入输出；模块必须可由 workspace 独立编译、测试和运行。

## Open

无。

## Superseded

- **TPL-001 — 标准模块边界。** 本规则曾使用中央模板序列；其原义由 `CORE-TEMPLATE-001` 继承。
