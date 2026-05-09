# Xray 手写配置

Xray 主配置路径：

```text
/data/adb/modules/netproxy/config/xray/config.json
```

模块启动时执行：

```sh
bin/xray run -config /data/adb/modules/netproxy/config/xray/config.json
```

并设置：

```text
XRAY_LOCATION_ASSET=/data/adb/modules/netproxy/config/xray
XRAY_LOCATION_CONFIG=/data/adb/modules/netproxy/config/xray
```

因此 `geoip.dat` 和 `geosite.dat` 放在 `config/xray/` 下即可被 Xray 读取。

## 必须保留的入站

默认透明代理入口：

```json
{
  "tag": "tproxy-in",
  "port": 1536,
  "protocol": "dokodemo-door",
  "settings": {
    "allowedNetwork": "tcp,udp",
    "followRedirect": true
  },
  "streamSettings": {
    "sockopt": {
      "tproxy": "tproxy"
    }
  }
}
```

端口必须与 `tproxy.conf` 中的 `PROXY_TCP_PORT`、`PROXY_UDP_PORT` 和 `DNS_PORT` 保持一致。

## 替换 proxy 出站

默认 `proxy` 出站是 `freedom` 占位。把它替换成你的真实代理出站，保留：

- `tag: "proxy"`
- `streamSettings.sockopt.mark: 2`

示意：

```json
{
  "tag": "proxy",
  "protocol": "vless",
  "settings": {
    "vnext": []
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "sockopt": {
      "mark": 2
    }
  }
}
```

实际字段请按 Xray 文档和你的服务端配置填写。

## DNS 处理

透明代理层默认把 53 端口流量送入 Xray。默认路由规则将它转发到 `dns-out`：

```json
{
  "inboundTag": ["tproxy-in"],
  "port": 53,
  "outboundTag": "dns-out"
}
```

如果你要改 DNS 上游，优先改 `dns.servers` 和 `dns-out.settings`。

## REDIRECT 模式

默认配置使用 TProxy：

```json
"tproxy": "tproxy"
```

如果设备只能使用 REDIRECT，需要同时修改：

```text
PROXY_MODE=2
DNS_HIJACK_ENABLE=2
```

以及 Xray 入站：

```json
"sockopt": {
  "tproxy": "redirect"
}
```

REDIRECT 主要适合 TCP，UDP 透明代理能力不如 TProxy。
