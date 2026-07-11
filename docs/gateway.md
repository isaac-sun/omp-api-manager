# Gateway design

Status: MVP Gateway implemented. The app can start one explicitly selected Provider on a loopback-only listener and forward ordinary responses or SSE byte chunks in real time; automatic OMP rewiring remains a follow-up.

The gateway binds to `127.0.0.1` only, chooses an unused port unless the user opts into a specific one, and authenticates each inbound request with a separately generated Keychain-stored bearer token. It obtains the upstream key from Keychain and forwards the method, path, safe headers, and body to one selected upstream Provider. Response headers and bytes, including SSE chunks, are forwarded without persistence. It writes only sanitized timing, status, provider/model, and provider-reported token metadata to SQLite; prompt bodies, response bodies, API keys, and authorization headers are never stored.

The gateway distinguishes provider-reported token values from unavailable values. It must not bind `0.0.0.0`, reuse upstream credentials as local credentials, or log `Authorization` headers.
