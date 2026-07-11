# 更新日志

> 语言： [English](CHANGELOG.md) | **简体中文**

所有重要变更都会记录在此文档中。

## 未发布

### 新增

- 标准 macOS **检查更新…** 菜单和“软件更新”设置页，用于手动检查 GitHub 最新正式 Release。
- 严格的语义版本比较，支持开发版本识别、ETag 复用、请求冷却以及明确的更新/错误状态。

### 安全

- 更新检查只会向固定 GitHub API 端点发送未认证的 HTTPS 请求，不会发送 OMP 配置、服务商数据、API Key、用量记录或设备标识。
- Release URL 根据经过验证的正式标签在本地构造；在应用仍为 ad-hoc 签名且未公证时，不会自动下载、挂载、安装或执行更新。
- Release 打包不再覆盖同名的既有资产。

## [0.2.0] - 2026-07-11

### 新增

- 安全导入 `newapi_channel_conn` JSON 连接：规范化 OpenAI `/v1` 基础 URL，API Key 仅保存到 Keychain。
- 更详细的多模型服务商表单：支持模型名称、上下文与最大输出 Token、文本/图像输入能力、推理能力以及每百万 Token 价格。
- 可选择的 OMP API 模式：OpenAI Completions、OpenAI Responses、Codex Responses、Azure OpenAI Responses 和 Anthropic Messages。
- 服务商复制功能：复制端点和模型设置，但不复制凭据。
- 模型 Token 快速预设、普通小数与科学计数法价格，以及 API Key 显示/隐藏控制，可更快完成服务商配置。

### 安全

- 导入的连接 JSON 仅在内存中解析，不会保存到服务商元数据、诊断信息或日志。
- 复制后的服务商必须使用自己的 API Key，避免凭据意外带入新的服务商。

### 修复

- Release 校验文件现在使用可移植的 DMG 相对文件名，可直接通过 `shasum -a 256 -c` 验证。

## [0.1.0] - 2026-07-11

### 新增

- 用于 OMP 状态、服务商、用量和配置的原生 macOS SwiftUI 工作区。
- OMP 16.x 发现与安全的语义 YAML 更新：备份、冲突检测和原子替换。
- Keychain 支持的服务商草稿、OpenAI/Anthropic 兼容模型发现和连接测试。
- 仅 localhost 的网关：独立本地令牌、上游 Keychain 凭据替换与 SSE 字节流转发。
- 经过脱敏的 SQLite 用量存储、仪表盘指标与 CSV/JSON 导出。
- 脱敏的 `models.yml` 编辑器，支持复制服务商并拒绝明文密钥。
- Build/Test GitHub Actions、安全与隐私文档以及贡献者指南。

### 安全

- 服务商 API Key 保留在 macOS Keychain 中，不会进入服务商元数据。
- 网关用量记录不包含提示词、响应、API Key 或授权头。
