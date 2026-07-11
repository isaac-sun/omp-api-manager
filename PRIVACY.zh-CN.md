# 隐私政策

> 语言： [English](PRIVACY.md) | **简体中文**

OMP API Manager 是本地优先的软件。它不会向 OMP API Manager 服务器发送遥测数据、配置、API Key、提示词、响应或用量记录。

服务商模型发现、连接测试和网关转发必然会访问用户选择的服务商端点。API Key 保存在 macOS Keychain。本地网关仅保存[用量记录](docs/zh-CN/usage-tracking.md)中说明的元数据：服务商/模型标识、耗时、状态、可用时的 Token 数量和用量来源。提示词、响应、API Key 与授权头不会被持久化。

应用只会在用户选择 **检查更新…** 时检查新版本。该操作会向 GitHub 发送标准的未认证 HTTPS 请求，其中包含应用版本以及 IP 地址、请求时间等正常网络元数据；不会发送设备标识、OMP 配置、服务商/模型信息、API Key、Keychain 内容或用量记录。GitHub 会按照其自身的隐私政策处理该请求。
