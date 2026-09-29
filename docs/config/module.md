# module.conf

模块级配置位于：

```text
/data/adb/modules/netproxy/config/module.conf
```

升级模块时会保留该文件。旧版本升级后文件里可能没有新增的键，缺失的键会使用下方默认值。

## 默认配置

```text
AUTO_START=1
WATCHDOG_RESTART=1
LOG_LEVEL=info

TPROXY_PORT=12345
PROXY_IPV6=1
PROXY_HOTSPOT=1
HOTSPOT_INTERFACES="wlan2 ap+ swlan0 rndis+ ncm+"
APP_PROXY_MODE=off
APP_PROXY_LIST=""

XRAY_CONFIG="/data/adb/modules/netproxy/config/xray/config.json"

GEO_UPDATE_GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
GEO_UPDATE_GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
GEO_UPDATE_TIMEOUT=60
```

## AUTO_START

- `1`：开机后自动启动 NetProxy 服务。
- `0`：开机不自动启动，需要手动执行 `cli service start`。

## WATCHDOG_RESTART

服务运行期间，看门狗每 5 秒检查一次 Xray 进程。Xray 意外退出时，看门狗会先清理透明代理规则，避免流量被送往无人监听的端口导致整机断网，然后：

- `1`：自动重启服务。5 分钟内最多自动重启 3 次，超过后停止重试，网络保持直连，需查看 `xray.log` 排查原因。
- `0`：不自动重启，网络保持直连。

主动停止服务时会先停止看门狗，不会被误判为崩溃。

## LOG_LEVEL

- `info`：常规日志。
- `debug`：额外记录 iptables 命令与完整的透明代理规则，排查规则问题时使用。

`service.log` 超过 1 MB 时会在下次启动服务时轮转为 `service.log.1`；上一次运行的 `xray.log` 会保留为 `xray.log.1`。

## 透明代理

`TPROXY_PORT`、`PROXY_IPV6`、`PROXY_HOTSPOT`、`HOTSPOT_INTERFACES`、`APP_PROXY_MODE`、`APP_PROXY_LIST` 控制哪些流量进入 Xray，详见 [透明代理](./tproxy.md)。修改后需要重启服务。

## XRAY_CONFIG

Xray 主配置文件路径。服务启动时会执行：

```sh
bin/xray run -config "$XRAY_CONFIG"
```

如果你把配置放到其他位置，确保：

- 文件对 root 可读。
- 配置中的日志路径存在或可创建。
- `geoip.dat` 和 `geosite.dat` 仍位于 `config/xray/`。

## geo 数据更新

- `GEO_UPDATE_GEOIP_URL` / `GEO_UPDATE_GEOSITE_URL`：下载地址。
- `GEO_UPDATE_TIMEOUT`：单个文件的下载超时（秒）。

在 WebUI 状态页点击「更新 geoip / geosite」，或执行 `cli geo update` 手动更新；更新后重启服务生效。
