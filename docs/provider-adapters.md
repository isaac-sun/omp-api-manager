# Provider adapter guide

> Language: **English** | [简体中文](zh-CN/provider-adapters.md)

Implement `ProviderAdapter` for every provider protocol. An adapter owns endpoint validation, model-list parsing, a minimal authenticated connection test, outgoing gateway request translation, response usage parsing, and provider-specific errors. A view model may only depend on the protocol.

`OpenAICompatibleAdapter` validates HTTPS endpoints (or HTTP loopback endpoints), uses `GET /models`, and tests a selected model with `POST /chat/completions` using a one-token request. `AnthropicCompatibleAdapter` uses `GET /models` with the required Anthropic headers and tests a selected model through `POST /messages`. A no-model test performs discovery/authentication only.

All adapters map 401, 403, 404, 429, 5xx, timeouts, TLS failures, unreachable hosts, and malformed bodies into user-readable, provider-agnostic errors. They must not attach request bodies or authorization headers to the error. Tests use a `URLProtocol` mock rather than real provider endpoints.
