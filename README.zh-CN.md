<p align="center">
  <img src="Sources/OMPAPIManagerApp/Resources/AppIcon-master.png" width="112" alt="OMP API Manager 应用图标">
</p>

<h1 align="center">OMP API Manager</h1>

<p align="center">
  一个原生、本地优先的 macOS 应用：安全管理 OMP 自定义 AI 服务商、运行本机网关，并查看经过脱敏的用量。
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <a href="https://github.com/isaac-sun/omp-api-manager">项目主页</a> ·
  <a href="https://github.com/isaac-sun/omp-api-manager/releases">下载</a> ·
  <a href="#文档">文档</a> ·
  <a href="https://github.com/isaac-sun/omp-api-manager/discussions">讨论区</a>
</p>

<p align="center">
  <a href="https://github.com/isaac-sun/omp-api-manager/actions/workflows/build.yml"><img src="https://github.com/isaac-sun/omp-api-manager/actions/workflows/build.yml/badge.svg" alt="构建状态"></a>
  <a href="https://github.com/isaac-sun/omp-api-manager/actions/workflows/test.yml"><img src="https://github.com/isaac-sun/omp-api-manager/actions/workflows/test.yml/badge.svg" alt="测试状态"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="Apache 2.0 许可证"></a>
  <a href="https://github.com/isaac-sun/omp-api-manager/releases"><img src="https://img.shields.io/github/v/release/isaac-sun/omp-api-manager?display_name=tag" alt="最新版本"></a>
</p>

> **v0.3.0** 新增私密、由用户主动触发的 **检查更新…** 流程：安全检查 GitHub 最新正式 Release，明确说明限流和失败原因，并跳转至官方 Release 页面手动安装。可从 [Releases](https://github.com/isaac-sun/omp-api-manager/releases) 下载 Apple Silicon DMG，或阅读 [v0.3.0 发布说明](docs/zh-CN/releases/v0.3.0.md)。DMG 使用 ad-hoc 签名，尚未经过 Developer ID 公证。

## 为什么使用 OMP API Manager？

自定义 AI 服务商很有价值，但手工修改 OMP 配置可能泄露凭据或覆盖已有的可用配置。OMP API Manager 在 macOS 上提供专注的本地工作区，用于服务商设置、安全配置变更、仅本机可访问的网关和私密用量查看。

## 主要功能

| 模块 | 能力 |
| --- | --- |
| 安全 OMP 配置 | 检测 OMP 16.x，语义化编辑 YAML，创建备份、检查冲突并原子写入。未知版本仅可读。 |
| 服务商管理 | 支持 OpenAI 兼容和 Anthropic 兼容端点、模型发现、连接测试、草稿和安全应用。 |
| New API 导入 | 将 `newapi_channel_conn` JSON 导入为 OpenAI 兼容服务商；密钥只保存到 Keychain，原始 JSON 不会持久化。 |
| 凭据保护 | 服务商密钥保存在 macOS Keychain；服务商元数据和高级编辑器均不会显示 API Key。 |
| 本地网关 | 在 `127.0.0.1` 启动独立本地令牌的网关，从 Keychain 替换上游凭据，并转发普通响应与 SSE。 |
| 私密用量面板 | 在 SQLite 保存脱敏请求元数据，并支持 CSV/JSON 导出；不会持久化提示词、响应、API Key 或授权头。 |
| 手动检查更新 | 只在用户主动请求时检查 GitHub 最新正式 Release，并打开官方 Release 页面；不会自动下载或安装更新。 |
| 原生 macOS 界面 | 提供环境状态、服务商、网关控制、用量和脱敏 `models.yml` 编辑器。 |

## 系统要求

- macOS 14 Sonoma 或更高版本
- Xcode 和 Swift 6，或当前 Swift 6 工具链
- OMP 16.x 用于配置集成（未安装 OMP 时应用仍可打开）

## 快速开始

### 在 Xcode 中运行

1. 克隆本仓库。
2. 在 Xcode 中打开 [`Package.swift`](Package.swift)。
3. 选择 `OMPAPIManager` 可执行 Scheme，按 <kbd>⌘R</kbd>。
4. 在 **Providers** 中添加兼容端点。密钥仅保存到 macOS Keychain。

### 在终端中运行

```sh
git clone https://github.com/isaac-sun/omp-api-manager.git
cd omp-api-manager
swift run OMPAPIManager
```

验证代码：

```sh
swift build -Xswiftc -warnings-as-errors
swift test
```

## 安全模型

- 配置写入仅限已记录的 OMP 16.x 行为。
- 每次编辑都会解析、使用指纹检查冲突、创建备份，并原子替换文件。
- 高级编辑器会脱敏既有密钥，并拒绝明文密钥。
- 网关只绑定到 localhost，绝不将上游服务商密钥复用为本地令牌。
- OMP API Manager 不发送遥测数据。详见[隐私政策](PRIVACY.zh-CN.md)和[配置安全](docs/zh-CN/configuration-safety.md)。

## 文档

- [架构](docs/zh-CN/architecture.md)
- [OMP 兼容性](docs/zh-CN/omp-compatibility.md)
- [服务商适配器](docs/zh-CN/provider-adapters.md)
- [网关设计](docs/zh-CN/gateway.md)
- [用量记录与导出](docs/zh-CN/usage-tracking.md)
- [配置安全](docs/zh-CN/configuration-safety.md)
- [路线图](ROADMAP.zh-CN.md)
- [更新日志](CHANGELOG.zh-CN.md)

## 参与贡献

欢迎提交代码、文档、Bug 报告和设计反馈。请先阅读[贡献指南](CONTRIBUTING.zh-CN.md)、遵循[行为准则](CODE_OF_CONDUCT.zh-CN.md)，并使用 Issue 模板发起讨论。

请勿在 Issue 或 PR 中包含 API Key、授权头、提示词、响应或真实本地配置。安全漏洞请遵循[安全政策](SECURITY.zh-CN.md)中的私密报告流程。

## 许可证

Copyright © 2026 OMP API Manager contributors。项目采用 [Apache License 2.0](LICENSE) 授权。
