# Privacy

OMP API Manager is local-first. The current implementation does not send telemetry, configuration, API keys, prompts, responses, or usage records to an OMP API Manager server.

Provider model discovery and connection tests necessarily contact the provider endpoint selected by the user. API keys belong in macOS Keychain. Future gateway and analytics features will store only the metadata explicitly documented in `docs/usage-tracking.md`, with an opt-in control for any expanded collection.
