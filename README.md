# OMP API Manager

Native macOS tooling for safely managing OMP custom AI providers and inspecting locally captured usage.

> Status: pre-release foundation. The current codebase builds a macOS SwiftUI shell and implements safe OMP 16.x configuration primitives. Provider persistence, gateway forwarding, usage storage, dashboard, and exports are planned; do not use this version to manage production credentials yet.

## What is implemented

- OMP 16.x installation and directory discovery (`PI_CODING_AGENT_DIR`, `PI_CONFIG_DIR`, then `~/.omp/agent`).
- Read-only display of the detected OMP executable/version, configuration paths, YAML state, configured providers, default model, and diagnostics. Unknown OMP versions are read-only.
- Semantic parsing of `config.yml` and `models.yml` using Yams.
- OMP 16.x provider mutation with conflict detection, a backup, temporary-file validation, and atomic replacement.
- Keychain service wrapper; no API key persistence in app models.
- Provider draft service with validation and Keychain-backed secret storage; provider metadata is stored separately without the secret.
- OMP 16.x `saveAndApply` service path; unsupported OMP versions retain a draft but reject configuration writes.
- Advanced, redacted `models.yml` editor service: edits are parsed and transactionally saved; existing secret values are never displayed or replaced by redaction markers.
- OpenAI-compatible and Anthropic-compatible model discovery plus selected-model connection tests, with local mock coverage and classified provider errors.
- Loopback Gateway core that accepts a separate local token, retrieves upstream credentials from Keychain, forwards requests to one selected provider, and records sanitized usage metadata in SQLite.
- Initial OpenAI-compatible endpoint validation and model-list request.
- Separate provider-reported vs locally-estimated usage source model and pure cost calculation.
- SwiftUI application shell and core tests.

## Safety and privacy

API keys are designed to live in the macOS Keychain. The config adapter emits a Keychain command reference, not the secret. Do not paste secrets in issues, logs, or test fixtures. The current release does not upload telemetry or usage.

OMP configuration compatibility is deliberately narrow. Only OMP 16.x is writable; other major versions must be read-only. See [OMP compatibility](docs/omp-compatibility.md) and [configuration safety](docs/configuration-safety.md).

## Requirements

- macOS 14 or later
- Xcode with Swift 6 (for an app build), or current Swift toolchain for the package tests
- OMP 16.x is optional for opening the app, but required for configuration integration

## Build and test

```sh
swift build
swift test
```

Open `Package.swift` in Xcode to run the SwiftUI application. A packaged `.xcodeproj`, signing, notarization, DMG, and Homebrew cask are planned.

## Roadmap

See [ROADMAP.md](ROADMAP.md). Gateway forwarding, SQLite analytics, model dashboard, CSV/JSON export, and release automation are not yet implemented.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing changes. Please report vulnerabilities through the private process in [SECURITY.md](SECURITY.md), not public issues.

## License

Licensed under the [Apache License 2.0](LICENSE).
