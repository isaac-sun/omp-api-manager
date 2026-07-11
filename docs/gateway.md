# Gateway design

Status: MVP foundation implemented. The app can start one explicitly selected Provider on a loopback-only listener; OMP rewiring and real-time SSE chunk forwarding remain the next Gateway increment.

The gateway binds to `127.0.0.1` only, chooses an unused port unless the user opts into a specific one, and authenticates each inbound request with a separately generated Keychain-stored bearer token. It obtains the upstream key from Keychain and forwards the method, path, safe headers, and body to one selected upstream Provider. It writes only sanitized timing, status, provider/model, and provider-reported token metadata to SQLite; prompt bodies, response bodies, API keys, and authorization headers are never stored.

The gateway distinguishes provider-reported token values from unavailable values. It must not bind `0.0.0.0`, reuse upstream credentials as local credentials, or log `Authorization` headers.
