# Changelog

All notable changes to this project will be documented here.

## Unreleased

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
