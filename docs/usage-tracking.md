# Usage tracking

Status: sanitized SQLite persistence is implemented for Gateway records; aggregation dashboard and export are planned.

Each record contains provider/model identity, time, latency, HTTP status, input/output/total tokens when available, source, and error category. `providerReported` applies only where an upstream response supplies usage. Prompts, responses, API keys, and authorization headers are excluded from the schema.

Prices are user-configured per million tokens and tied to a recorded source/update time in the planned persistence layer. No prompt content, response content, API keys, or authorization headers belong in usage records.
