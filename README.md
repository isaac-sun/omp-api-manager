<p align="center">
  <img src="Sources/OMPAPIManagerApp/Resources/AppIcon-master.png" width="112" alt="OMP API Manager app icon">
</p>

<h1 align="center">OMP API Manager</h1>

<p align="center">
  A native, local-first macOS app for safely managing custom OMP AI providers, running a loopback gateway, and inspecting sanitized usage.
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/isaac-sun/omp-api-manager">Project home</a> ·
  <a href="https://github.com/isaac-sun/omp-api-manager/releases">Download</a> ·
  <a href="#documentation">Documentation</a> ·
  <a href="https://github.com/isaac-sun/omp-api-manager/discussions">Discussions</a>
</p>

<p align="center">
  <a href="https://github.com/isaac-sun/omp-api-manager/actions/workflows/build.yml"><img src="https://github.com/isaac-sun/omp-api-manager/actions/workflows/build.yml/badge.svg" alt="Build status"></a>
  <a href="https://github.com/isaac-sun/omp-api-manager/actions/workflows/test.yml"><img src="https://github.com/isaac-sun/omp-api-manager/actions/workflows/test.yml/badge.svg" alt="Test status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="Apache 2.0 license"></a>
  <a href="https://github.com/isaac-sun/omp-api-manager/releases"><img src="https://img.shields.io/github/v/release/isaac-sun/omp-api-manager?display_name=tag" alt="Latest release"></a>
</p>

> **v0.3.0** adds a private, user-initiated **Check for Updates…** workflow. It safely checks the latest stable GitHub Release, explains rate limits and failures, and opens the official release page for manual installation. Download the Apple Silicon DMG from [Releases](https://github.com/isaac-sun/omp-api-manager/releases), or read the [v0.3.0 release notes](docs/releases/v0.3.0.md). The DMG is ad-hoc signed, not Developer ID notarized.

## Why OMP API Manager?

Custom AI providers are useful, but manually editing OMP configuration can risk exposing credentials or overwriting a working setup. OMP API Manager gives macOS users a focused local workspace for provider setup, safe configuration changes, a localhost-only gateway, and private usage visibility.

## Highlights

| Area | What it does |
| --- | --- |
| Safe OMP configuration | Detects OMP 16.x, semantically edits YAML, creates backups, checks for conflicts, and writes atomically. Unknown versions are read-only. |
| Provider management | Supports OpenAI-compatible and Anthropic-compatible endpoints, model discovery, connection testing, drafts, and secure apply. |
| New API import | Imports `newapi_channel_conn` JSON into an OpenAI-compatible provider, stores its key only in Keychain, and never persists the source JSON. |
| Credential protection | Stores provider keys in the macOS Keychain; no API key is saved in provider metadata or displayed by the advanced editor. |
| Local gateway | Starts a `127.0.0.1`-only gateway with a separate local token, substitutes upstream Keychain credentials, and forwards standard and SSE responses. |
| Private usage dashboard | Stores sanitized request metadata in SQLite and exports CSV or JSON. Prompts, responses, API keys, and authorization headers are never persisted. |
| Manual update checks | Checks the latest stable GitHub Release only when requested, then opens the official release page. It never downloads or installs an update automatically. |
| Native macOS UI | A SwiftUI workspace for environment status, providers, gateway controls, usage, and a redacted `models.yml` editor. |

## Requirements

- macOS 14 Sonoma or later
- Xcode with Swift 6, or a current Swift 6 toolchain
- OMP 16.x for configuration integration (the app can still open without OMP)

## Get started

### Run in Xcode

1. Clone this repository.
2. Open [`Package.swift`](Package.swift) in Xcode.
3. Select the `OMPAPIManager` executable scheme and press <kbd>⌘R</kbd>.
4. In **Providers**, add a compatible endpoint. The key is saved only in your macOS Keychain.

### Run from Terminal

```sh
git clone https://github.com/isaac-sun/omp-api-manager.git
cd omp-api-manager
swift run OMPAPIManager
```

To validate a checkout:

```sh
swift build -Xswiftc -warnings-as-errors
swift test
```

## Safety model

- Configuration writes are intentionally limited to documented OMP 16.x behavior.
- Each edit is parsed, protected by a fingerprint conflict check, backed up, and atomically replaced.
- The advanced editor redacts existing secret values and rejects plaintext secrets.
- The gateway binds only to localhost and never reuses the upstream provider key as its local token.
- No telemetry is sent by OMP API Manager. See [Privacy](PRIVACY.md) and [Configuration safety](docs/configuration-safety.md).

## Documentation

- [Architecture](docs/architecture.md)
- [OMP compatibility](docs/omp-compatibility.md)
- [Provider adapters](docs/provider-adapters.md)
- [Gateway design](docs/gateway.md)
- [Usage tracking and exports](docs/usage-tracking.md)
- [Configuration safety](docs/configuration-safety.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)

Chinese translations are available in [README.zh-CN.md](README.zh-CN.md) and [docs/zh-CN](docs/zh-CN/).

## Contributing

Contributions, bug reports, and documentation improvements are welcome. Please begin with [CONTRIBUTING.md](CONTRIBUTING.md), follow the [Code of Conduct](CODE_OF_CONDUCT.md), and use the issue templates when opening a discussion.

Never include API keys, authorization headers, prompts, responses, or real local configuration in an issue or pull request. For vulnerabilities, follow the private process in [SECURITY.md](SECURITY.md).

## License

Copyright © 2026 OMP API Manager contributors. Licensed under the [Apache License 2.0](LICENSE).
