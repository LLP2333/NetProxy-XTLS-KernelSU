# 路由与 DNS

NetProxy 的路由分两层：

1. Android 透明代理层决定哪些系统流量进入 Xray。
2. Xray routing 决定进入后的流量走 `proxy`、`direct`、`block` 还是 `dns-out`。

## 透明代理层

配置文件：

```text
/data/adb/modules/netproxy/config/tproxy/tproxy.conf
```

这一层处理：

- 移动网络、WiFi、热点、USB 共享接口。
- TCP、UDP、DNS 是否接管。
- 分应用代理名单。
- 中国 IP 绕过和 QUIC 阻断。

## Xray 层

配置文件：

```text
/data/adb/modules/netproxy/config/xray/config.json
```

默认 routing：

- 53 端口流量发到 `dns-out`。
- 广告域名发到 `block`。
- 私有地址、中国域名、中国 IP 发到 `direct`。
- 其他 TCP/UDP 发到 `proxy`。

## DNS 默认路径

```text
应用 DNS 查询
  -> tproxy DNS 劫持
  -> Xray tproxy-in
  -> routing port 53
  -> dns-out
```

要改 DNS 上游，修改：

- `dns.servers`
- `outbounds` 中 tag 为 `dns-out` 的配置

## geodata

Xray 会从这里读取 `geoip.dat` 和 `geosite.dat`：

```text
/data/adb/modules/netproxy/config/xray/
```

服务脚本通过 `XRAY_LOCATION_ASSET` 指定该目录。

## 常见改法

全局代理：把最后一条 catch-all 保持为 `proxy`，并减少 `direct` 规则。

全局直连：把最后一条 catch-all 改为 `direct`。

自定义分流：在默认 catch-all 前添加更具体的 `domain`、`ip`、`port` 或 `protocol` 规则。
