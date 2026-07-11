# Provider adapter guide

> Language: **English** | [简体中文](zh-CN/provider-adapters.md)

Implement `ProviderAdapter` for every provider protocol. An adapter owns endpoint validation, model-list parsing, a minimal authenticated connection test, outgoing gateway request translation, response usage parsing, and provider-specific errors. A view model may only depend on the protocol.

`OpenAICompatibleAdapter` validates HTTPS endpoints (or HTTP loopback endpoints), uses `GET /models`, and tests a selected model with `POST /chat/completions` using a one-token request. `AnthropicCompatibleAdapter` uses `GET /models` with the required Anthropic headers and tests a selected model through `POST /messages`. A no-model test performs discovery/authentication only.

All adapters map 401, 403, 404, 429, 5xx, timeouts, TLS failures, unreachable hosts, and malformed bodies into user-readable, provider-agnostic errors. They must not attach request bodies or authorization headers to the error. Tests use a `URLProtocol` mock rather than real provider endpoints.

## New API connection import

The Providers page can import a JSON object whose `_type` is `newapi_channel_conn`. The importer accepts `url` and `key`, treats it as a custom OpenAI-compatible provider, and adds `/v1` when the URL has no path. The source JSON is parsed in memory only; its key is saved to macOS Keychain and the raw JSON is never stored in provider metadata, diagnostics, or logs. Users can import a draft or import and apply it to supported OMP 16.x configuration.

## Model metadata

The provider form can define multiple models. For each model it writes `id`, optional `name`, `contextWindow`, `maxTokens`, `input` modalities (`text` and/or `image`), `reasoning`, and a `cost` mapping with `input`, `output`, `cacheRead`, and `cacheWrite` prices per million tokens. The form accepts ordinary decimals and scientific notation such as `5e-1` for a price. It validates positive token limits and non-negative prices before a configuration transaction is started.
