# 透明代理与分应用代理

透明代理层由 `scripts/network/tproxy.sh` 和 `config/tproxy/tproxy.conf` 驱动，负责把 Android 系统流量送入 Xray 的 `tproxy-in` 入站。

## 默认链路

```text
应用流量
  -> iptables / ip rule / ipset
  -> 127.0.0.1:1536 或本地 TProxy 端口
  -> Xray dokodemo-door 入站
  -> Xray routing
```

默认端口：

```text
PROXY_TCP_PORT="1536"
PROXY_UDP_PORT="1536"
DNS_PORT="1536"
```

Xray `config.json` 里的入站端口也必须是 `1536`，除非你同时修改这三项。

## TProxy 与 mark

默认透明代理模式：

```text
PROXY_MODE=1
```

Xray 入站默认：

```json
"sockopt": {
  "tproxy": "tproxy"
}
```

Xray 出站默认：

```json
"sockopt": {
  "mark": 2
}
```

`ROUTING_MARK="2"` 用于让 Xray 自己发出的外连绕过透明代理回环。不要只改一边。

## 分应用代理

查看配置：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli app list'
```

白名单模式：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli app mode whitelist'
su -c '/data/adb/modules/netproxy/scripts/cli app add com.example.app'
```

黑名单模式：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli app mode blacklist'
su -c '/data/adb/modules/netproxy/scripts/cli app add com.example.app'
```

在黑名单模式下，添加到列表里的应用会绕过代理；在白名单模式下，只有列表里的应用进入代理。

## QUIC 与中国 IP 绕过

```sh
su -c '/data/adb/modules/netproxy/scripts/cli tproxy quic on'
su -c '/data/adb/modules/netproxy/scripts/cli tproxy cnip on'
```

这些是透明代理层规则，不会自动修改 Xray routing。需要更细的域名或协议分流时，应写在 `config/xray/config.json`。
