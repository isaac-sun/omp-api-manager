# 更新日志

> 语言： [English](CHANGELOG.md) | **简体中文**

所有重要变更都会记录在此文档中。

## 未发布

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
