# 服务商适配器指南

> 语言： [English](../provider-adapters.md) | **简体中文**

每种服务商协议都应实现 `ProviderAdapter`。适配器负责端点验证、模型列表解析、最小化的认证连接测试、出站网关请求转换、响应中的用量解析和服务商专属错误。视图模型只能依赖该协议。

`OpenAICompatibleAdapter` 验证 HTTPS 端点（或 HTTP 回环端点），使用 `GET /models`，并通过向 `POST /chat/completions` 发送单 Token 请求来测试选定模型。`AnthropicCompatibleAdapter` 使用带必需 Anthropic 请求头的 `GET /models`，并通过 `POST /messages` 测试选定模型。没有模型的测试只执行发现/认证。

所有适配器都会将 401、403、404、429、5xx、超时、TLS 失败、主机不可达和格式错误的响应映射为用户可读、服务商无关的错误。错误中不得附带请求正文或授权头。测试使用 `URLProtocol` Mock，不会请求真实服务商端点。
