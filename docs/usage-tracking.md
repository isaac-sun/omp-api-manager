# Usage tracking

> Language: **English** | [简体中文](zh-CN/usage-tracking.md)

Status: sanitized SQLite persistence, the aggregation dashboard, and CSV/JSON export are implemented for Gateway records.

Each record contains provider/model identity, time, latency, HTTP status, input/output/total tokens when available, source, and error category. `providerReported` applies only where an upstream response supplies usage. Prompts, responses, API keys, and authorization headers are excluded from the schema.

Prices are user-configured per million tokens and tied to a recorded source/update time in the local persistence layer. No prompt content, response content, API keys, or authorization headers belong in usage records.
