# Contributing to OMP API Manager

Thanks for helping make OMP API Manager safer and more useful. Contributions of code, documentation, tests, design feedback, and reproducible bug reports are welcome.

## Before you start

- Read the [README](README.md), [architecture](docs/architecture.md), and [Code of Conduct](CODE_OF_CONDUCT.md).
- Search existing issues before opening a new one.
- Use the security process in [SECURITY.md](SECURITY.md) for vulnerabilities; do not open a public issue for a potential credential or local-data exposure.

## Development setup

```sh
git clone https://github.com/isaac-sun/omp-api-manager.git
cd omp-api-manager
swift build -Xswiftc -warnings-as-errors
swift test
```

Open `Package.swift` in Xcode to run the macOS app. The minimum supported platform is macOS 14 and the package uses Swift 6.

## Pull request checklist

1. Create a focused branch from `main`.
2. Keep changes small and explain the user-facing impact in the PR description.
3. Add or update tests when changing configuration transactions, provider parsing, redaction, gateway behavior, or usage storage.
4. Run `swift build -Xswiftc -warnings-as-errors` and `swift test`.
5. Update documentation and `CHANGELOG.md` when behavior changes.
6. Never commit real configuration files, private local paths, API keys, authorization headers, prompts, or provider responses.

## Compatibility and safety rules

- Do not silently add write support for an unverified OMP version. Unknown major versions must remain read-only.
- Preserve semantic YAML transaction guarantees: parse before writing, detect conflicts, back up, validate, then atomically replace.
- Keep provider credentials in the macOS Keychain. Models, logs, diagnostics, exports, and errors must redact secrets.
- The local gateway must bind only to `127.0.0.1` and use a token distinct from the upstream provider credential.

## Reporting a bug or proposing a feature

Use the provided GitHub issue templates. A good report includes a minimal, sanitized reproduction, expected behavior, actual behavior, OMP version, macOS version, and app version. Do not include secrets or private configuration contents.
