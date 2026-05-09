# Xray 配置

主目录：

```text
/data/adb/modules/netproxy/config/xray/
```

文件：

```text
config.json
geoip.dat
geosite.dat
```

## 启动方式

服务脚本会设置：

```text
XRAY_LOCATION_ASSET=/data/adb/modules/netproxy/config/xray
XRAY_LOCATION_CONFIG=/data/adb/modules/netproxy/config/xray
```

然后启动：

```sh
/data/adb/modules/netproxy/bin/xray run -config /data/adb/modules/netproxy/config/xray/config.json
```

## 默认入站

默认入站是透明代理入口：

```json
{
  "tag": "tproxy-in",
  "port": 1536,
  "protocol": "dokodemo-door",
  "settings": {
    "allowedNetwork": "tcp,udp",
    "followRedirect": true
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"]
  },
  "streamSettings": {
    "sockopt": {
      "tproxy": "tproxy"
    }
  }
}
```

## 默认出站

默认出站包括：

- `proxy`：代理出站占位，使用前需要替换。
- `direct`：直连出站。
- `block`：阻断出站。
- `dns-out`：DNS 出站。

所有会发起外连的出站都应保留：

```json
"sockopt": {
  "mark": 2
}
```

这个 mark 与 `tproxy.conf` 的 `ROUTING_MARK="2"` 对应。

## 校验配置

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
```

配置通过后再重启：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
```
