# 模块理念

NetProxy 现在把职责拆得更清楚：

1. Android 透明代理层只负责把系统流量送进 Xray。
2. Xray 只读取用户手写的 `config.json`，不再由模块生成节点、订阅或代理组。
3. CLI 只保留运维动作，不参与代理配置转换。

## 为什么这样做

Xray 的协议、传输层、DNS 和路由能力已经足够完整。模块继续实现订阅转换和运行时代理组，会让透明代理脚本、配置生成器和核心本身形成三套状态，排障成本很高。

当前版本把状态收敛为两个文件：

- `config/xray/config.json`：Xray 自己的代理、DNS、路由配置。
- `config/tproxy/tproxy.conf`：Android 透明代理、接口、分应用代理配置。

## 配置原则

- 代理协议写在 Xray 出站里。
- 国内外分流写在 Xray routing 里。
- DNS 劫持先由 tproxy 层接管，再交给 Xray 的 `dns-out` 出站。
- 应用名单写在 `tproxy.conf`，因为这是 Android 系统层行为。
- 出站 `sockopt.mark` 必须和 `tproxy.conf` 的 `ROUTING_MARK` 保持一致，默认都是 `2`。

## 默认选择

默认使用 TProxy，而不是自动回退：

```text
PROXY_MODE=1
```

原因是 Xray 入站需要明确配置 `sockopt.tproxy`。默认 `config.json` 使用 `"tproxy"`，所以透明代理脚本也默认强制 TProxy。如果设备只能使用 REDIRECT，需要同时改 `tproxy.conf` 和 Xray 入站配置。
