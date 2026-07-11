# 用量记录

> 语言： [English](../usage-tracking.md) | **简体中文**

状态：网关记录的脱敏 SQLite 持久化、聚合仪表盘和 CSV/JSON 导出均已实现。

每条记录包含服务商/模型标识、时间、延迟、HTTP 状态、可用时的输入/输出/总 Token、来源和错误类别。只有上游响应提供用量时才会标记为 `providerReported`。Schema 排除提示词、响应、API Key 和授权头。

价格由用户按每百万 Token 配置，并与本地持久化层中记录的来源/更新时间关联。提示词内容、响应内容、API Key 或授权头均不属于用量记录。
