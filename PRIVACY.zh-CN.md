# 隐私政策

> 语言： [English](PRIVACY.md) | **简体中文**

OMP API Manager 是本地优先的软件。它不会向 OMP API Manager 服务器发送遥测数据、配置、API Key、提示词、响应或用量记录。

服务商模型发现、连接测试和网关转发必然会访问用户选择的服务商端点。API Key 保存在 macOS Keychain。本地网关仅保存[用量记录](docs/zh-CN/usage-tracking.md)中说明的元数据：服务商/模型标识、耗时、状态、可用时的 Token 数量和用量来源。提示词、响应、API Key 与授权头不会被持久化。
