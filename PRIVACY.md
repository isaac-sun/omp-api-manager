# Privacy

> Language: **English** | [简体中文](PRIVACY.zh-CN.md)

OMP API Manager is local-first. It does not send telemetry, configuration, API keys, prompts, responses, or usage records to an OMP API Manager server.

Provider model discovery, connection tests, and gateway forwarding necessarily contact the provider endpoint selected by the user. API keys belong in macOS Keychain. The local gateway stores only the metadata documented in [usage tracking](docs/usage-tracking.md): provider/model identifiers, timing, status, token counts when available, and the usage source. Prompts, responses, API keys, and authorization headers are not persisted.
