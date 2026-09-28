# 透明代理与分应用代理

透明代理层由 `scripts/network/tproxy.sh` 实现，配置项在 `config/module.conf`，负责把 Android 系统流量送入 Xray 的透明代理入站。

## 链路

```text
本机应用
  -> mangle OUTPUT：跳过 Xray 自身、保留地址、不代理的应用，其余打 fwmark 20
  -> ip rule：fwmark 20 -> 路由表 100 -> local default dev lo
  -> mangle PREROUTING（入接口 lo）
  -> TPROXY -> Xray dokodemo-door 入站（TPROXY_PORT，默认 12345）
  -> Xray routing

热点 / USB 共享下游设备
  -> mangle PREROUTING（入接口在 HOTSPOT_INTERFACES 中）
  -> TPROXY -> Xray
```

IPv4 和 IPv6 各有一套结构相同的规则（`iptables` / `ip6tables`）。

## 端口

`module.conf` 里的 `TPROXY_PORT` 与 Xray 入站端口必须一致：

```text
TPROXY_PORT=12345
```

```json
{
  "tag": "tproxy-in",
  "protocol": "dokodemo-door",
  "port": 12345,
  "settings": { "network": "tcp,udp", "followRedirect": true },
  "streamSettings": { "sockopt": { "tproxy": "tproxy" } }
}
```

## DNS

发往任何非回环地址的 UDP 53 都会进入 Xray，包括 WiFi 下发往路由器（如 `192.168.1.1`）的 DNS。默认配置中的路由规则把它们交给 `dns-out`：

```json
{ "port": 53, "outboundTag": "dns-out" }
```

## 分应用代理

编辑 `module.conf`：

```text
# 只代理这两个应用
APP_PROXY_MODE=whitelist
APP_PROXY_LIST="com.google.android.youtube com.android.chrome"
```

```text
# 除微信外全部代理
APP_PROXY_MODE=blacklist
APP_PROXY_LIST="com.tencent.mm"
```

然后重启服务：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
```

更多说明见 [透明代理配置](../config/tproxy.md)。更细的域名或协议分流应写在 `config/xray/config.json` 的 routing 中。
