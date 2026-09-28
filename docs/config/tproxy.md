# 透明代理配置

透明代理由 `scripts/network/tproxy.sh` 实现，配置项位于 [module.conf](./module.md)：

```text
/data/adb/modules/netproxy/config/module.conf
```

服务启动时加载规则，停止时清理。修改下列任何一项后都需要重启服务。

## 端口

```text
TPROXY_PORT=12345
```

流量被 TPROXY 送到这个端口，必须与 Xray 配置中 `dokodemo-door`（或 `tunnel`）入站的 `port` 一致，且该入站需要：

```json
"settings": { "network": "tcp,udp", "followRedirect": true },
"streamSettings": { "sockopt": { "tproxy": "tproxy" } }
```

WebUI 保存配置时会检查这一点。

## IPv6

```text
PROXY_IPV6=1
```

- `1`：同时用 ip6tables 接管 IPv6 的 TCP/UDP。内核不支持 IPv6 TPROXY 或缺少 `ip6tables` 时，会自动回滚 IPv6 规则、仅代理 IPv4，并在 `service.log` 中记录警告。
- `0`：IPv6 流量不经过 Xray，直接出网。

Xray 默认监听地址是双栈的，dokodemo-door 入站不需要额外修改即可接收 IPv6 流量。

## 热点与 USB 共享

```text
PROXY_HOTSPOT=1
HOTSPOT_INTERFACES="wlan2 ap+ swlan0 rndis+ ncm+"
```

`PROXY_HOTSPOT=1` 时，从这些下游接口进入的流量也会交给 Xray。接口名因设备而异，可以用 `ip addr` 查看开热点后新出现的接口；支持 iptables 通配符 `+`（如 `rndis+` 匹配 `rndis0`）。

只有本机回环（`lo`）和这里列出的接口会被劫持；移动数据、WiFi 等上游接口进入的入站连接不受影响。

## 分应用代理

```text
APP_PROXY_MODE=off
APP_PROXY_LIST=""
```

- `off`：所有应用都走代理。
- `blacklist`：列表内的应用不走代理。
- `whitelist`：只有列表内的应用走代理。

列表用空格或英文逗号分隔，每项为 `包名` 或 `用户ID:包名`：

```text
APP_PROXY_LIST="com.tencent.mm,10:com.android.chrome"
```

不写用户 ID 时表示主用户 `0`；工作资料、应用分身通常是 `10`、`999` 等。启动时通过 `/data/system/packages.list` 解析 UID，找不到的包名会在 `service.log` 中警告。应用重装后 UID 可能变化，需要重启服务。

分应用只作用于本机应用；热点下游设备不受影响。

## 固定行为

以下行为不提供开关：

- **防回环**：Xray 以 `root:net_admin` 运行，该 uid/gid 发出的流量不会被劫持。
- **保留地址绕过**：局域网、回环、链路本地、组播等地址不走代理。例外是发往这些地址的 **UDP 53**（例如 WiFi 下发往路由器的 DNS），它仍会进入 Xray，由路由规则交给 `dns-out`，避免 DNS 绕过代理。回环地址完全不处理。
- **标记与路由表**：fwmark `20`，路由表 `100`，IPv4 与 IPv6 共用。

排查时可查看当前规则：

```sh
su -c 'iptables -t mangle -S PROXY_OUTPUT; ip6tables -t mangle -S PROXY_OUTPUT; ip rule; ip -6 rule'
```
