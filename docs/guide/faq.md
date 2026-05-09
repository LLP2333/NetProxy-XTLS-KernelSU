# 常见问题

## 服务启动失败

先看日志：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service logs service 120'
su -c '/data/adb/modules/netproxy/scripts/cli service logs xray 120'
```

再校验 Xray 配置：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
```

常见原因：

- `config/xray/config.json` JSON 语法错误。
- `proxy` 出站字段不符合 Xray 配置规范。
- 出站缺少 `sockopt.mark=2`，导致透明代理回环。
- `geoip.dat` 或 `geosite.dat` 不在 `config/xray/` 下。

## 启动后无法联网

重点检查：

- `proxy` 出站是否仍是默认 `freedom` 占位。
- 服务端地址、端口、UUID、Reality/TLS 等参数是否正确。
- 代理协议是否需要 UDP，而设备是否支持当前 TProxy 模式。
- 是否启用了分应用白名单但没有添加目标应用。

## DNS 不正常

默认配置把 53 端口流量送入 Xray 的 `dns-out`。检查：

- `DNS_HIJACK_ENABLE=1`
- `DNS_PORT="1536"`
- Xray routing 里有 `port: 53 -> dns-out`
- `dns-out.settings.rewriteAddress` 是可用 DNS 服务器

## 设备不支持 TProxy

默认配置强制 TProxy。如果内核不支持，需要改为 REDIRECT：

```text
PROXY_MODE=2
DNS_HIJACK_ENABLE=2
```

并把 Xray 入站改成：

```json
"sockopt": {
  "tproxy": "redirect"
}
```

REDIRECT 对 UDP 的覆盖能力有限，优先尝试修复 TProxy 支持。

## 如何更新 Xray

下载官方 Android arm64 release 包，替换：

```text
bin/xray
config/xray/geoip.dat
config/xray/geosite.dat
```

替换后执行：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray version'
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
```
