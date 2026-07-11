# 参与贡献 OMP API Manager

感谢你帮助 OMP API Manager 变得更安全、更有用。欢迎代码、文档、测试、设计反馈和可复现的 Bug 报告。

> 语言： [English](CONTRIBUTING.md) | **简体中文**

## 开始前

- 阅读 [README](README.zh-CN.md)、[架构](docs/zh-CN/architecture.md)和[行为准则](CODE_OF_CONDUCT.zh-CN.md)。
- 创建 Issue 前先搜索已有讨论。
- 漏洞请遵循[安全政策](SECURITY.zh-CN.md)，不要公开报告潜在凭据或本地数据泄露。

## 开发环境

```sh
git clone https://github.com/isaac-sun/omp-api-manager.git
cd omp-api-manager
swift build -Xswiftc -warnings-as-errors
swift test
```

在 Xcode 中打开 `Package.swift` 即可运行 macOS 应用。最低支持 macOS 14，项目使用 Swift 6。

## Pull Request 检查表

1. 从 `main` 创建聚焦的分支。
2. 保持变更精简，并在 PR 说明中解释用户影响。
3. 修改配置事务、服务商解析、脱敏、网关或用量存储时，添加或更新测试。
4. 运行 `swift build -Xswiftc -warnings-as-errors` 与 `swift test`。
5. 行为变更时更新文档与 `CHANGELOG.md`。
6. 不要提交真实配置文件、私有本地路径、API Key、授权头、提示词或服务商响应。

## 兼容性与安全规则

- 不得默默为未经验证的 OMP 版本增加写入支持；未知主版本必须保持只读。
- 保持 YAML 事务保证：写入前解析、检测冲突、备份、验证，再原子替换。
- 服务商凭据必须保存在 macOS Keychain；模型、日志、诊断、导出和错误信息必须脱敏。
- 本地网关只能绑定 `127.0.0.1`，且本地令牌必须与上游服务商凭据不同。

## 报告 Bug 或提出功能建议

请使用 GitHub Issue 模板。一份好的报告应包含最小化且已脱敏的复现步骤、预期行为、实际行为、OMP 版本、macOS 版本和应用版本。不要包含秘密信息或私有配置内容。
