# tproxy.conf

`tproxy.conf` 是 NetProxy 的透明代理主配置，位于：

```text
/data/adb/modules/netproxy/config/tproxy/tproxy.conf
```

它负责决定哪些 Android 系统流量进入 Xray，以及如何处理接口、DNS、分应用代理和 iptables 标记。

## 关键默认项

### 核心绕过

```text
CORE_USER_GROUP="root:net_admin"
ROUTING_MARK="2"
FORCE_MARK_BYPASS=0
```

Xray 以 `root:net_admin` 运行。透明代理脚本会优先通过 owner 规则绕过 Xray 自己发出的连接；`ROUTING_MARK="2"` 是 fallback，必须和 Xray 出站 `sockopt.mark` 一致。

### 监听端口

```text
PROXY_TCP_PORT="1536"
PROXY_UDP_PORT="1536"
DNS_PORT="1536"
```

这三项必须和 Xray `tproxy-in` 入站端口一致。

### 代理模式

```text
PROXY_MODE=1
```

含义：

- `0`：自动检测 TProxy，不支持时回退 REDIRECT。
- `1`：强制 TProxy。
- `2`：强制 REDIRECT。

默认强制 TProxy，因为默认 Xray 入站配置为 `"tproxy": "tproxy"`。

### DNS

```text
DNS_HIJACK_ENABLE=1
```

DNS 流量会进入 Xray，再由 Xray routing 送到 `dns-out`。

### 协议与接口

```text
PROXY_MOBILE=1
PROXY_WIFI=1
PROXY_HOTSPOT=0
PROXY_USB=0
PROXY_TCP=1
PROXY_UDP=1
PROXY_IPV6=0
```

IPv6 默认不代理，但不会强制关闭系统 IPv6 栈。

### 分应用代理

```text
APP_PROXY_ENABLE=1
APP_PROXY_MODE="blacklist"
PROXY_APPS_LIST=""
BYPASS_APPS_LIST=""
```

可以通过 CLI 修改。

### 其他控制

```text
BYPASS_CN_IP=0
BLOCK_QUIC=1
PERFORMANCE_MODE=0
LOG_TIMESTAMP=0
```

`BYPASS_CN_IP` 是透明代理层 IP 绕过，不等同于 Xray 的域名路由。更细的分流写在 `config/xray/config.json`。
