# 服务商适配器指南

> 语言： [English](../provider-adapters.md) | **简体中文**

每种服务商协议都应实现 `ProviderAdapter`。适配器负责端点验证、模型列表解析、最小化的认证连接测试、出站网关请求转换、响应中的用量解析和服务商专属错误。视图模型只能依赖该协议。

`OpenAICompatibleAdapter` 验证 HTTPS 端点（或 HTTP 回环端点），使用 `GET /models`，并通过向 `POST /chat/completions` 发送单 Token 请求来测试选定模型。`AnthropicCompatibleAdapter` 使用带必需 Anthropic 请求头的 `GET /models`，并通过 `POST /messages` 测试选定模型。没有模型的测试只执行发现/认证。

所有适配器都会将 401、403、404、429、5xx、超时、TLS 失败、主机不可达和格式错误的响应映射为用户可读、服务商无关的错误。错误中不得附带请求正文或授权头。测试使用 `URLProtocol` Mock，不会请求真实服务商端点。

## New API 连接导入

Providers 页面可导入 `_type` 为 `newapi_channel_conn` 的 JSON 对象。导入器读取 `url` 与 `key`，将其视为自定义 OpenAI 兼容服务商；当 URL 没有路径时自动添加 `/v1`。源 JSON 仅在内存中解析；其密钥保存至 macOS Keychain，原始 JSON 不会写入服务商元数据、诊断信息或日志。用户可选择只导入草稿，或导入后应用到受支持的 OMP 16.x 配置。

## 模型元数据

服务商表单可定义多个模型。每个模型会写入 `id`、可选的 `name`、`contextWindow`、`maxTokens`、输入模态 `input`（`text` 和/或 `image`）、`reasoning`，以及每百万 Token 价格的 `cost` 映射：`input`、`output`、`cacheRead` 和 `cacheWrite`。表单接受普通小数和 `5e-1` 这样的科学计数法价格；在启动配置事务前会验证 Token 限制为正数、价格为非负数。
