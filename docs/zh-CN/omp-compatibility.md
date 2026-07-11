# OMP 兼容性

> 语言： [English](../omp-compatibility.md) | **简体中文**

状态：已于 2026-07-11 在 macOS 上针对 OMP `16.4.2` 验证，并参考下方列出的上游 `main` 文档与源文件。这是一份兼容性记录，不代表未经测试的 OMP 版本可写入。

## OMP 16.x 的文件与用途

| 文件 | 观察到的用途 | OMP API Manager 行为 |
| --- | --- | --- |
| `~/.omp/agent/config.yml` | Agent 设置，包括 `modelRoles.default` | 仅读取和更新已记录的 `modelRoles.default` 路径。 |
| `~/.omp/agent/models.yml` | 自定义服务商定义、自定义模型、服务商覆盖和可选等价映射 | 仅读取和更新 `providers` 下指定服务商映射。 |

本地 OMP 安装位于 `/opt/homebrew/bin/omp`；`omp --version` 返回 `omp/16.4.2`。既有本地配置使用 `config.yml` 存储 `modelRoles.default`，使用 `models.yml` 存储 `providers`。密钥从未复制到本仓库或本文档。

## 发现规则

OMP API Manager 按以下顺序解析位置：

1. 用户确认的位置（计划中的偏好设置）。
2. `PI_CODING_AGENT_DIR`：精确 Agent 目录；其中包含 `config.yml` 与 `models.yml`。
3. `PI_CONFIG_DIR`：配置根目录；Agent 文件位于 `<root>/agent`。
4. 默认位置 `~/.omp/agent`。

上游环境变量文档指出，OMP 在加载 `.env` 时也会尊重这些值。`PI_CODING_AGENT_DIR` 被记录为会话存储，因此两个变量同时存在时将它视为更具体的覆盖。OMP `.env` 中的 `OMP_*` 变量由 OMP 自身镜像为 `PI_*` 值。

## MVP 使用的 `models.yml` Schema

官方上游文档说明根结构为：

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

对于完整的自定义服务商，OMP 16.x 要求 `baseUrl`、`apiKey`（除非 `auth: none`）以及服务商或每个模型上的 `api`。当前支持的 API 值为 `openai-completions`、`openai-responses`、`openai-codex-responses`、`azure-openai-responses`、`anthropic-messages`、`google-generative-ai`、`google-gemini-cli` 和 `google-vertex`。

模型需要 `id`；若出现，`contextWindow` 与 `maxTokens` 必须为正数。OMP 依次合并内置模型、服务商覆盖、`modelOverrides`、自定义模型和发现的模型。自定义模型若与现有服务商/id 相同会替换对应模型，因此应用会在写入前警告。

OMP 允许以 `!` 开头的命令解析秘密字段。初始适配器写入 Keychain 支持的 `security find-generic-password` 命令引用，而不是实际 API Key。这与 OMP 的命令密钥行为兼容，但在用户选定服务商上验证前不应视为生产就绪。

## 配置验证与重载

`omp config` 提供 `list`、`get`、`set`、`reset`、`path` 和 `init-xdg`；`omp models` 提供列表、搜索和刷新。OMP 16.4.2 没有记录独立的 YAML 验证或重载命令。因此 MVP 会在原子替换前使用 Yams 解析精确的临时 YAML，并在之后再次解析。它不声称 OMP 已重载运行中的进程；需重启或新建 OMP 调用才能观察到变更。

## 安全兼容性政策

当前只有 OMP 主版本 16 可写。其他版本可以被发现，但必须显示为只读；UI 应提供可导出的 YAML 补丁和兼容性 Issue 链接。适配器会语义化保留未知 YAML 数据，但 Yams 不能保证保留注释、空白、锚点或原始引号。每次写入前必须创建带时间戳的备份。

## 来源

- OMP 16.4.2 本地 CLI 帮助：`omp --help`、`omp config --help` 和 `omp models --help`。
- [上游模型/服务商配置](https://github.com/can1357/oh-my-pi/blob/main/docs/models.md)，获取于 2026-07-11。
- [上游环境变量](https://github.com/can1357/oh-my-pi/blob/main/docs/environment-variables.md)，获取于 2026-07-11。
- [上游设置 Schema](https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/config/settings-schema.ts)，获取于 2026-07-11。
