# Contributing

Thanks for contributing to OMP API Manager. Keep changes small, tested, and free of API keys, real configuration files, and private paths.

## Development loop

1. Use OMP fixture files only in temporary test directories.
2. Run `swift build` and `swift test`.
3. Add tests for configuration transaction, provider parsing, or redaction changes.
4. Explain OMP schema evidence and version impact in the pull request.

Configuration adapters may never silently support an unverified OMP version. Provider adapters must redact all credentials from diagnostics.
