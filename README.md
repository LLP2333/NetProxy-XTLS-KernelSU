<div align="center">

<img src="image/logo.png" width="96" alt="NetProxy">

# NetProxy

An Android system-level transparent proxy module based on **Xray-core**, for KernelSU / Magisk / APatch

[中文](README_ZH.md) · [Download](https://github.com/LLP2333/NetProxy-XTLS-KernelSU/releases/latest)

</div>

> This project is derived from [NetProxy-Magisk](https://github.com/Fanju6/NetProxy-Magisk) by [Fanju](https://github.com/Fanju6), with the proxy core switched from sing-box to Xray-core.

## Features

- **Transparent proxy**: takes over local TCP / UDP / DNS traffic via iptables TPROXY, IPv4 and IPv6, and optionally hotspot / USB tethering clients.
- **Per-app proxy**: blacklist or whitelist mode, with multi-user support (work profile, app clones).
- **Native Xray config**: uses Xray's own `config.json` — outbounds, routing and DNS are written exactly as in Xray.
- **WebUI**: check status, start/stop the service, edit and validate the config, read logs and update geo data from the KernelSU manager.
- **Reliability**: a watchdog clears the rules immediately if Xray exits unexpectedly so the network keeps working, and can restart it; the service runs detached from the manager app, so it is not frozen or killed with the app.
- **Painless upgrades**: reinstalling keeps your config, custom rule files, logs, and any Xray or geo data you replaced; new versions show up as updates in the module manager.

## Installation & Quick Start

1. Download `NetProxy_<version>_<build>.zip` from [Releases](https://github.com/LLP2333/NetProxy-XTLS-KernelSU/releases/latest), install it in your module manager and reboot.
   - `_mini.zip` does not include the Xray binary or geo data; put your own `bin/xray` and `config/xray/geoip.dat` / `geosite.dat` in place.
2. Edit the Xray config at `/data/adb/modules/netproxy/config/xray/config.json` (also editable on the WebUI "配置" page):
   - Replace the default `proxy` outbound (a placeholder `freedom`) with your server, e.g. VLESS, Trojan, VMess or Shadowsocks, **keeping the tag `proxy`**.
   - Outbounds do **not** need `sockopt.mark`; the module lets Xray's own traffic through automatically.
   - The port of the `tproxy-in` inbound must match `TPROXY_PORT` in `module.conf` (default `12345`).
3. Save and restart the service. The WebUI validates with `xray run -test` before saving and never overwrites the config if validation fails.

The service starts on boot by default. For day-to-day toggling, use the module manager's "Action" button or the WebUI.

## Everyday Use

**WebUI** (tap the module's WebUI icon in the KernelSU manager)

| Page | What it does |
|---|---|
| Status | Service state, transparent proxy rules, watchdog; start / stop / restart; common switches; update geoip / geosite |
| Config | Edit `config.json`: format, validate, save, save & restart, restore the previous version |
| Logs | View `service.log` plus the error and access logs from your Xray config, with auto refresh |

**CLI**

```sh
CLI=/data/adb/modules/netproxy/scripts/cli
su -c "$CLI service status"          # show status
su -c "$CLI service restart"         # restart the service
su -c "$CLI service logs error 100"  # read logs: service / error / access
su -c "$CLI xray test"               # validate the current Xray config
su -c "$CLI geo update"              # update geoip / geosite online
su -c "$CLI help"                    # all commands
```

## Configuration

Module settings live in `/data/adb/modules/netproxy/config/module.conf`; restart the service after changing them:

| Key | Default | Description |
|---|---|---|
| `AUTO_START` | `1` | Start on boot |
| `WATCHDOG_RESTART` | `1` | Restart Xray if it exits unexpectedly (at most 3 times in 5 minutes); when off, only clears the rules and falls back to direct |
| `TPROXY_PORT` | `12345` | Transparent proxy port; must match the Xray inbound port |
| `PROXY_IPV6` | `1` | Proxy IPv6 traffic; when off, IPv6 goes direct |
| `PROXY_HOTSPOT` | `1` | Proxy hotspot / USB tethering clients on the interfaces in `HOTSPOT_INTERFACES` |
| `APP_PROXY_MODE` | `off` | Per-app proxy: `off` proxies everything, `blacklist` skips listed apps, `whitelist` proxies only listed apps |
| `APP_PROXY_LIST` | empty | Apps as `package` or `userId:package`, separated by spaces or commas |
| `LOG_LEVEL` | `info` | `debug` also logs the full transparent proxy rules |
| `GEO_UPDATE_*` | Loyalsoldier | Download URLs and timeout for geo data |

**Logs** are in `/data/adb/modules/netproxy/logs/`, at most three files: `service.log` (module log) plus the files set by `log.error` and `log.access` in your Xray config. They are trimmed automatically when they grow too large.

## FAQ

**No network after enabling — how do I recover?**
Tap the "Action" button in the module manager to stop the service, or run `su -c /data/adb/modules/netproxy/scripts/cli service stop`; the transparent proxy rules are removed. Then check `service.log` and the Xray error log.

**Traffic doesn't seem to go through the proxy?**
- Enable the Xray access log (set `log.access` to a file path) and check whether connections are routed to `proxy` or `direct`. Mainland China sites going direct is expected with the default rules.
- Check whether `PROXY_IPV6` is off: apps using IPv6 would bypass the proxy.

**Google Play downloads stay pending?**
Put the Google domain and IP rules before the `geosite:cn` / `geoip:cn` direct rules, and configure several independent DNS upstreams for non-China domains. Otherwise the Play download CDN may be routed direct, or a single DoH failure can make Android mark the network as unvalidated.

## Updating

- **Module**: the module manager shows new versions; you can also download from Releases and install over the existing one.
- **Geo data**: tap "更新 geoip / geosite" on the WebUI status page or run `cli geo update`. Downloads are sha256-verified before replacing, failures leave the existing files untouched, and changes apply after a service restart.
- **Xray binary**: download `Xray-android-arm64-v8a.zip` from [Xray-core Releases](https://github.com/XTLS/Xray-core/releases), replace `/data/adb/modules/netproxy/bin/xray` with the `xray` inside, and restart the service. Module upgrades keep your replacement; to go back to the bundled version, delete the file and reinstall the module.

## Development & Release

```text
src/module/
├─ config/module.conf          # module settings
├─ config/xray/                # Xray config and geo data
├─ scripts/cli                 # CLI
├─ scripts/core/               # service.sh (start/stop) · watchdog.sh · geo_update.sh
├─ scripts/network/tproxy.sh   # transparent proxy rules
├─ webroot/index.html          # WebUI
├─ customize.sh                # install and upgrade
├─ service.sh / action.sh      # boot entry · Action button
└─ module.prop                 # module metadata
```

- **Local build**: `cd src/module && zip -r ../../NetProxy.zip .` (files must sit at the zip root).
- **Release**: bump `version` in `module.prop`, add a section for the version at the top of `.github/changelog.md`, push to `main`, then create and push a tag starting with `V` (e.g. `V7.6.0`). CI builds the packages, generates `update.json` and publishes the release; `versionCode` is set to the commit count automatically.

How it works: the OUTPUT chain marks local traffic, policy routing sends it back through `lo` into PREROUTING, where TPROXY hands it to Xray's `dokodemo-door` inbound. Xray runs as `root:net_admin`, and its own traffic is let through by an owner match to avoid loops.

## Acknowledgements

Many thanks to [Fanju](https://github.com/Fanju6) and all contributors of [NetProxy-Magisk](https://github.com/Fanju6/NetProxy-Magisk). The module framework, install/upgrade scripts, transparent proxy approach and documentation structure of this project all come from NetProxy-Magisk — this project would not exist without it. If you use sing-box, the original project is recommended.

## License

[GPL-3.0](LICENSE)
