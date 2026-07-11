# OMP compatibility

> Language: **English** | [简体中文](zh-CN/omp-compatibility.md)

Status: verified against OMP `16.4.2` on macOS on 2026-07-11, plus the upstream `main` documentation and source files listed below. This is a compatibility record, not a promise that an untested OMP release is writable.

## What OMP 16.x stores where

| File | Observed role | OMP API Manager behavior |
| --- | --- | --- |
| `~/.omp/agent/config.yml` | Agent settings, including `modelRoles.default` | Read and update only the documented `modelRoles.default` path. |
| `~/.omp/agent/models.yml` | Custom provider definitions, custom models, provider overrides, and optional equivalence mapping | Read and update only a named provider mapping under `providers`. |

The local OMP installation was found at `/opt/homebrew/bin/omp`; `omp --version` returned `omp/16.4.2`. The existing local configuration uses `config.yml` for `modelRoles.default` and `models.yml` for `providers`. Secrets were never copied into this repository or this document.

## Discovery rules

OMP API Manager resolves locations in this order:

1. A user-confirmed location (planned preference storage).
2. `PI_CODING_AGENT_DIR`: exact agent directory; `config.yml` and `models.yml` live there.
3. `PI_CONFIG_DIR`: configuration root; agent files live in `<root>/agent`.
4. Default `~/.omp/agent`.

The upstream environment reference states that OMP also respects these values when loading `.env` files. `PI_CODING_AGENT_DIR` is documented as session storage; it is treated as the more specific override when both variables are present. `OMP_*` variables in OMP `.env` files are mirrored to `PI_*` values by OMP itself.

## `models.yml` schema used by the MVP

The official upstream document states that the root shape is:

```yaml
providers:
  provider-id:
    baseUrl: https://api.example.com/v1
    apiKey: ENV_NAME_OR_COMMAND
    api: openai-completions
    headers: {}
    models: []
equivalence:
  overrides: {}
  exclude: []
```

For a full custom provider, OMP 16.x requires `baseUrl`, `apiKey` unless `auth: none`, and `api` on either the provider or every model. Current supported API values are `openai-completions`, `openai-responses`, `openai-codex-responses`, `azure-openai-responses`, `anthropic-messages`, `google-generative-ai`, `google-gemini-cli`, and `google-vertex`.

Models require `id`; `contextWindow` and `maxTokens` must be positive when present. OMP merges built-ins, provider overrides, `modelOverrides`, custom models, and discovered models in that order. A custom model with an existing provider/id replaces the matching model, so the app warns before doing so.

OMP allows command-resolved secret fields beginning with `!`. The initial adapter writes a Keychain-backed `security find-generic-password` command reference rather than the actual API key. This is compatible with OMP's documented command-secret behavior, but must be exercised against a user-selected provider before being considered production-ready.

## Configuration validation and reload

`omp config` exposes `list`, `get`, `set`, `reset`, `path`, and `init-xdg`; `omp models` exposes listing, searching, and refresh. OMP 16.4.2 does not document a standalone YAML validation or reload command. The MVP therefore validates by parsing the exact temporary YAML with Yams before an atomic replacement and parses it again afterward. It does not claim that OMP has reloaded a running process; a restart/new OMP invocation is required to observe changes.

## Safe compatibility policy

Only OMP major version 16 is currently writable. Any other version is discovered but must be shown as read-only; the UI should offer an exportable YAML patch and compatibility issue link. The adapter preserves unknown YAML data semantically, but Yams cannot guarantee preservation of comments, whitespace, anchors, or original quoting. A timestamped backup is mandatory before every write.

## Sources

- OMP 16.4.2 local CLI help: `omp --help`, `omp config --help`, and `omp models --help`.
- [Upstream model/provider configuration](https://github.com/can1357/oh-my-pi/blob/main/docs/models.md), retrieved 2026-07-11.
- [Upstream environment variables](https://github.com/can1357/oh-my-pi/blob/main/docs/environment-variables.md), retrieved 2026-07-11.
- [Upstream settings schema](https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/config/settings-schema.ts), retrieved 2026-07-11.
