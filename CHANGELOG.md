# Changelog

> Language: **English** | [简体中文](CHANGELOG.zh-CN.md)

All notable changes to this project will be documented here.

## Unreleased

## [0.3.0] - 2026-07-11

### Added

- A standard macOS **Check for Updates…** command and Software Update settings for manually checking the latest stable GitHub Release.
- Strict semantic-version comparison with support for development builds, ETag reuse, request cooldowns, and clear update/error states.

### Security

- Update checks use an unauthenticated HTTPS request to a fixed GitHub API endpoint and never send OMP configuration, provider data, API keys, usage records, or a device identifier.
- Release URLs are constructed locally from a validated stable tag; the app does not automatically download, mount, install, or execute updates while builds remain ad-hoc signed and unnotarized.
- Release packaging no longer overwrites an existing asset with the same name.

## [0.2.1] - 2026-07-11

### Fixed

- Fixed the downloadable app crashing immediately at launch by loading the packaged icon from the standard app resources directory instead of invoking an unavailable SwiftPM `Bundle.module` path.
- Redesigned provider and model form inputs with full-width editable controls, muted example text, per-field guidance, and visible row dividers.
- Release packaging now starts the finished `.app` as a smoke test before creating the DMG.

## [0.2.0] - 2026-07-11

### Added

- Safe import for `newapi_channel_conn` JSON connections, including OpenAI `/v1` base URL normalization and Keychain-only API key storage.
- A detailed multi-model provider form with model names, context and output token limits, text/image input capabilities, reasoning support, and per-million-token pricing.
- Selectable OMP API modes for OpenAI completions, OpenAI responses, Codex responses, Azure OpenAI responses, and Anthropic messages.
- Provider duplication that copies endpoint and model settings without copying credentials.
- Model token presets, decimal and scientific-notation pricing, and API-key visibility controls for faster provider setup.

### Security

- Imported connection JSON is parsed only in memory and is never saved to provider metadata, diagnostics, or logs.
- Duplicated providers require their own API key, preventing credentials from being carried into a new provider accidentally.

### Fixed

- Release checksum files now use a portable relative DMG filename and can be verified directly with `shasum -a 256 -c`.

## [0.1.0] - 2026-07-11

### Added

- Native macOS SwiftUI workspace for OMP status, providers, usage, and configuration.
- OMP 16.x discovery plus safe semantic YAML updates with backups, conflict detection, and atomic replacement.
- Keychain-backed provider drafts, OpenAI-compatible and Anthropic-compatible model discovery, and connection testing.
- Localhost-only gateway with a separate local token, upstream Keychain substitution, and SSE byte-stream forwarding.
- Sanitized SQLite usage storage, dashboard metrics, and CSV/JSON export.
- Redacted `models.yml` editor with provider-copy support and plaintext-secret rejection.
- Build and test GitHub Actions workflows, security and privacy documentation, and contributor guidance.

### Security

- Provider API keys remain in the macOS Keychain and are excluded from provider metadata.
- Gateway usage records exclude prompts, responses, API keys, and authorization headers.
