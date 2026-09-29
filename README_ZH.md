<div align="center">

<img src="image/logo.png" width="96" alt="NetProxy">

# NetProxy

基于 **Xray-core** 的 Android 系统级透明代理模块，支持 KernelSU / Magisk / APatch

[English](README.md) · [下载](https://github.com/LLP2333/NetProxy-XTLS-KernelSU/releases/latest)

</div>

> 本项目基于 [Fanju](https://github.com/Fanju6) 的 [NetProxy-Magisk](https://github.com/Fanju6/NetProxy-Magisk) 修改而来，将代理核心从 sing-box 替换为 Xray-core。

## 功能

- **透明代理**：通过 iptables TPROXY 接管本机 TCP / UDP / DNS 流量，支持 IPv4 与 IPv6，可选接管热点、USB 共享下游设备。
- **分应用代理**：黑名单或白名单模式，支持多用户（工作资料、应用分身）。
- **原生 Xray 配置**：直接使用 Xray 的 `config.json`，节点、路由、DNS 全部按 Xray 原生写法配置。
- **WebUI**：在 KernelSU 管理器中查看状态、启停服务、编辑并校验配置、查看日志、更新 geo 数据。
- **稳定性**：看门狗在 Xray 意外退出时立即清理规则避免断网，并可自动重启；服务脱离管理器应用运行，不会随应用被冻结或关闭。
- **升级无忧**：覆盖安装会保留配置、自定义规则文件、日志以及自行替换的 Xray 与 geo 数据；模块管理器中可直接收到新版本提示。

## 安装与快速开始

1. 从 [Releases](https://github.com/LLP2333/NetProxy-XTLS-KernelSU/releases/latest) 下载 `NetProxy_<版本>_<编号>.zip`，在模块管理器中安装后重启手机。
   - `_mini.zip` 不含 Xray 程序与 geo 数据，需要自行放入 `bin/xray` 与 `config/xray/geoip.dat`、`geosite.dat`。
2. 编辑 Xray 配置 `/data/adb/modules/netproxy/config/xray/config.json`，可在 WebUI 的「配置」页直接编辑：
   - 把默认的 `proxy` 出站（占位用的 `freedom`）替换成你的节点，例如 VLESS、Trojan、VMess、Shadowsocks，**保留 tag `proxy`**。
   - 出站**不需要**设置 `sockopt.mark`，模块会自动放行 Xray 自身的流量。
   - 透明代理入站 `tproxy-in` 的端口需与 `module.conf` 中的 `TPROXY_PORT`（默认 `12345`）一致。
3. 保存并重启服务。WebUI 保存时会先用 `xray run -test` 校验，校验失败不会覆盖原配置。

服务默认开机自启。之后日常开关可以使用模块管理器中的「操作」按钮或 WebUI。

## 日常使用

**WebUI**（KernelSU 管理器中点击模块的 WebUI 图标）

| 页面 | 功能 |
|---|---|
| 状态 | 运行状态、透明代理规则、看门狗；启动 / 停止 / 重启；常用开关；更新 geoip / geosite |
| 配置 | 编辑 `config.json`，格式化、校验、保存、保存并重启、恢复上一版 |
| 日志 | 查看 `service.log` 与 Xray 配置中的错误日志、访问日志，支持自动刷新 |

**CLI**

```sh
CLI=/data/adb/modules/netproxy/scripts/cli
su -c "$CLI service status"          # 查看状态
su -c "$CLI service restart"         # 重启服务
su -c "$CLI service logs error 100"  # 查看日志：service / error / access
su -c "$CLI xray test"               # 校验当前 Xray 配置
su -c "$CLI geo update"              # 在线更新 geoip / geosite
su -c "$CLI help"                    # 全部命令
```

## 配置

模块设置位于 `/data/adb/modules/netproxy/config/module.conf`，修改后重启服务生效：

| 键 | 默认值 | 说明 |
|---|---|---|
| `AUTO_START` | `1` | 开机自动启动 |
| `WATCHDOG_RESTART` | `1` | Xray 意外退出后自动重启（5 分钟内最多 3 次）；关闭时只清理规则、恢复直连 |
| `TPROXY_PORT` | `12345` | 透明代理端口，需与 Xray 入站端口一致 |
| `PROXY_IPV6` | `1` | 代理 IPv6 流量；关闭时 IPv6 流量直连 |
| `PROXY_HOTSPOT` | `1` | 代理热点 / USB 共享下游设备，接口由 `HOTSPOT_INTERFACES` 指定 |
| `APP_PROXY_MODE` | `off` | 分应用代理：`off` 全部代理，`blacklist` 列表内不代理，`whitelist` 只代理列表内 |
| `APP_PROXY_LIST` | 空 | 应用列表，`包名` 或 `用户ID:包名`，用空格或英文逗号分隔 |
| `LOG_LEVEL` | `info` | 设为 `debug` 时记录完整的透明代理规则 |
| `GEO_UPDATE_*` | Loyalsoldier | geo 数据的下载地址与超时 |

**日志**位于 `/data/adb/modules/netproxy/logs/`，最多 3 个：`service.log`（模块日志），以及 Xray 配置中 `log.error`、`log.access` 指定的文件。超过大小上限时自动截断。

## 常见问题

**开启后无法上网怎么恢复？**
点击模块管理器中的「操作」按钮停止服务，或执行 `su -c /data/adb/modules/netproxy/scripts/cli service stop`，透明代理规则会被清除。然后查看 `service.log` 与 Xray 错误日志排查原因。

**感觉流量没有走代理？**
- 查看 Xray 访问日志（在配置中设置 `log.access` 为文件路径），确认连接被路由到了 `proxy` 还是 `direct`。国内网站按默认规则直连属于正常现象。
- 检查 `PROXY_IPV6` 是否被关闭：应用走 IPv6 时会绕过代理。

**Google Play 下载一直等待中？**
将 Google 相关的域名和 IP 规则放在 `geosite:cn` / `geoip:cn` 直连规则之前，并为非中国大陆域名配置多个独立的 DNS 上游。否则 Play 下载 CDN 可能被判定为直连，或单个 DoH 失败导致系统判定网络不可用。

## 更新

- **模块**：模块管理器会提示新版本，也可以从 Releases 下载后覆盖安装。
- **geo 数据**：WebUI 状态页点击「更新 geoip / geosite」，或执行 `cli geo update`；下载后校验 sha256 再替换，失败不影响现有文件，重启服务后生效。
- **Xray 程序**：从 [Xray-core Releases](https://github.com/XTLS/Xray-core/releases) 下载 `Xray-android-arm64-v8a.zip`，将其中的 `xray` 替换 `/data/adb/modules/netproxy/bin/xray` 后重启服务。升级模块时会保留你替换的版本；想恢复模块自带版本，删除该文件后重新安装模块。

## 开发与发布

```text
src/module/
├─ config/module.conf          # 模块设置
├─ config/xray/                # Xray 配置与 geo 数据
├─ scripts/cli                 # CLI
├─ scripts/core/               # service.sh 服务启停 · watchdog.sh 看门狗 · geo_update.sh
├─ scripts/network/tproxy.sh   # 透明代理规则
├─ webroot/index.html          # WebUI
├─ customize.sh                # 安装与升级
├─ service.sh / action.sh      # 开机入口 · 操作按钮
└─ module.prop                 # 模块信息
```

- **本地打包**：`cd src/module && zip -r ../../NetProxy.zip .`（文件需位于 zip 根目录）。
- **发布**：修改 `module.prop` 中的 `version`，在 `.github/changelog.md` 顶部新增该版本的更新日志，推送到 `main` 后打 `V` 开头的标签（如 `V7.6.0`）并推送。CI 会打包、生成 `update.json` 并发布 Release，`versionCode` 自动取提交数。

透明代理原理：OUTPUT 链为本机流量打标记，经策略路由送回 `lo` 进入 PREROUTING，再由 TPROXY 交给 Xray 的 `dokodemo-door` 入站；Xray 以 `root:net_admin` 运行，其自身流量通过 owner 匹配放行以避免回环。

## 致谢

感谢 [Fanju](https://github.com/Fanju6) 及 [NetProxy-Magisk](https://github.com/Fanju6/NetProxy-Magisk) 项目的全体贡献者。本项目的模块框架、安装与升级脚本、透明代理方案和文档结构都源自 NetProxy-Magisk，没有原项目的工作就没有本项目。如果你使用 sing-box，推荐直接使用原项目。

## 许可证

[GPL-3.0](LICENSE)
