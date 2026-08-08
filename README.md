# NetProxy

Android system-level transparent proxy module based on **Xray-core**.

Intercepts all traffic via iptables TPROXY + dokodemo-door inbound, supporting TCP, UDP, and DNS transparent proxying.

## Features

- Bundled Xray-core Android arm64 binary.
- Hijacks all TCP/UDP traffic to Xray through iptables mangle table TPROXY.
- Built-in `geoip.dat` / `geosite.dat`, with optional online refresh before Xray is stopped.
- Xray version is logged to `service.log` on start; `xray.log` tail is appended on startup failure for easy debugging.
- Module upgrades **preserve** existing `bin/xray`, `geoip.dat`, and `geosite.dat` if you've replaced them manually.
- CLI for service control, Xray config validation, log viewing, and geo data updates.

## Module Layout

```text
src/module/
├─ META-INF/                   # Magisk/KernelSU/APatch install entry
├─ bin/
│  └─ xray                    # Xray-core Android arm64 binary
├─ config/
│  ├─ module.conf             # Module-level settings
│  └─ xray/
│     ├─ config.json          # Xray main config (dokodemo-door inbound)
│     ├─ geoip.dat
│     └─ geosite.dat
├─ scripts/
│  ├─ cli                     # CLI entry (service/xray subcommands)
│  ├─ core/
│  │  └─ service.sh           # Service start/stop core logic
│  ├─ network/
│  │  └─ tproxy.sh            # iptables TPROXY rule management
│  └─ utils/
│     ├─ common.sh            # Logging, path, and common utilities
│     └─ config.sh            # Config read/write helpers
├─ logs/                       # Runtime logs (auto-generated)
├─ action.sh                   # Module manager "Action" button script
├─ customize.sh                # Install/upgrade script
├─ module.prop                 # Module metadata (name, version, etc.)
├─ post-fs-data.sh             # Early boot initialization
└─ service.sh                  # Boot service entry (AUTO_START)
```

## Building the Module

From the project root:

```sh
cd src/module && zip -r ../../NetProxy.zip . && cd ../..
```

Files inside the zip must be at the root level (no extra wrapper folder). The resulting `NetProxy.zip` can be installed directly via a module manager.

## Quick Start

1. Flash the module in Magisk, KernelSU, or APatch.
2. Reboot the device.
3. Edit the Xray config:

```text
/data/adb/modules/netproxy/config/xray/config.json
```

4. Replace the default `proxy` outbound (`freedom`) with your own Xray outbound, such as VLESS, Trojan, VMess, Shadowsocks, or SOCKS. You do **not** need to set `sockopt.mark` on the outbound — the module prevents routing loops via owner match.
5. Validate the config:

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
```

6. Restart the service:

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
```

### Google Play downloads

Keep Google domain and IP rules before `geosite:cn` / `geoip:cn` direct rules.
Otherwise Android connectivity checks or Play download CDN traffic can be
classified as direct traffic even though the Play Store UI itself works.

Use independent DNS fallbacks for non-CN domains. A single DoH upstream failure
can make Android mark the network as unvalidated and leave Play downloads
pending.

Module upgrades preserve the installed Xray config. After changing the bundled
template, update `/data/adb/modules/netproxy/config/xray/config.json` explicitly
and restart the service.

After that you can simply reboot — the module defaults to `AUTO_START=1` and will start automatically on boot. To manually toggle the service, open the module page in KernelSU / Magisk / APatch and tap the NetProxy "Action" button.

## TProxy Overview

The module uses iptables mangle table TPROXY to redirect all TCP/UDP traffic to Xray's dokodemo-door inbound port.

**Startup flow:**

1. Start the Xray process, listening on the dokodemo-door port (default `12345`)
2. Configure ip rule/route so that marked packets are routed to local loopback
3. Add TPROXY rules in PREROUTING to redirect traffic to Xray
4. Mark locally originated traffic in OUTPUT to trigger re-route into TPROXY

**Loop prevention:**

Xray runs as `root:net_admin`. The OUTPUT chain uses iptables `-m owner --uid-owner root --gid-owner net_admin` to match and bypass traffic from the proxy process itself, eliminating the need for `sockopt.mark`. Users do **not** need to add `sockopt.mark` to their Xray outbound config.

## Important Defaults

- Xray config: `/data/adb/modules/netproxy/config/xray/config.json`
- Xray asset directory: `/data/adb/modules/netproxy/config/xray`
- Transparent proxy port: `12345` (`TPROXY_PORT` in `module.conf`)

The default `proxy` outbound is set to `freedom` so the module can start even without a real server config. To actually proxy traffic, replace this outbound with your node configuration while keeping the tag name `proxy`.

## CLI

Day-to-day start/stop doesn't require the CLI — the "Action" button in the module manager will start the service when stopped and stop it when running.

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service status'
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
su -c '/data/adb/modules/netproxy/scripts/cli service logs xray 80'
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
su -c '/data/adb/modules/netproxy/scripts/cli geo status'
su -c '/data/adb/modules/netproxy/scripts/cli geo update'
```

## Updating geoip / geosite

- **Auto refresh before stop**: When the service is stopped or restarted, it first downloads the latest `geoip.dat` / `geosite.dat` while the proxy is still active (better connectivity). Download → sha256 verification → atomic replace is handled in one script. Failures only print a warning and never block the stop flow.
- **Manual**: `cli geo update` or `cli geo update geoip` / `cli geo update geosite`.
- **Disable auto refresh**: set `GEO_UPDATE_ON_STOP=0` in `module.conf`.
- **Change source**: edit `GEO_UPDATE_GEOIP_URL` / `GEO_UPDATE_GEOSITE_URL` in `module.conf`. Defaults to [`Loyalsoldier/v2ray-rules-dat`](https://github.com/Loyalsoldier/v2ray-rules-dat), same as the official Xray-install.

## Updating Xray

This project does not build Xray-core during the module build process. Use the official release assets directly:

```text
https://github.com/XTLS/Xray-core/releases
```

Place the files from the release archive into the corresponding module paths:

- `xray` -> `src/module/bin/xray`
- `geoip.dat` -> `src/module/config/xray/geoip.dat`
- `geosite.dat` -> `src/module/config/xray/geosite.dat`

> Tip: if you manually replace `/data/adb/modules/netproxy/bin/xray` on an installed device, re-flashing the module **will not** overwrite that file (same for `geoip.dat` / `geosite.dat`). Delete the file before re-flashing if you want the module-bundled version back.

## References

- [Xray-core releases](https://github.com/XTLS/Xray-core/releases)
- [Xray dokodemo-door documentation](https://xtls.github.io/config/inbounds/dokodemo.html)

## License

GPL-3.0
