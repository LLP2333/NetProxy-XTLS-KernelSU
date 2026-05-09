# NetProxy

Android system-level transparent proxy module based on **Xray-core**.

This branch runs Xray with a hand-written JSON config. It does not import node links, update subscriptions, expose a Clash API, or bundle a web panel.

## Features

- Xray-core v26.3.27 for Android arm64.
- Transparent proxy through Android iptables/ipset rules.
- Default TProxy mode for TCP, UDP, and DNS traffic.
- Per-app proxy allowlist/blocklist support.
- Built-in `geoip.dat` and `geosite.dat` for Xray routing rules.
- CLI for service control, Xray config checks, logs, app rules, and tproxy rules.

## Module Layout

```text
src/module/
├─ bin/
│  ├─ xray                    # Xray-core Android arm64 binary
│  └─ ipset                   # optional ipset helper
├─ config/
│  ├─ module.conf             # module-level settings
│  ├─ tproxy/tproxy.conf      # transparent proxy rules
│  └─ xray/
│     ├─ config.json          # hand-written Xray config
│     ├─ geoip.dat
│     └─ geosite.dat
├─ scripts/
│  ├─ cli
│  ├─ core/service.sh
│  └─ network/tproxy.sh
└─ logs/
   ├─ service.log
   └─ xray.log
```

## Quick Start

1. Flash the module in Magisk, KernelSU, or APatch.
2. Reboot the device.
3. Edit the Xray config:

```text
/data/adb/modules/netproxy/config/xray/config.json
```

4. Replace the default `proxy` outbound with your own Xray outbound, such as VLESS, Trojan, VMess, Shadowsocks, or SOCKS.
5. Keep this outbound field unless you also change `tproxy.conf`:

```json
"streamSettings": {
  "sockopt": {
    "mark": 2
  }
}
```

6. Test and start:

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
su -c '/data/adb/modules/netproxy/scripts/cli service start'
```

## Important Defaults

- Xray config: `/data/adb/modules/netproxy/config/xray/config.json`
- Xray asset directory: `/data/adb/modules/netproxy/config/xray`
- Transparent proxy TCP port: `1536`
- Transparent proxy UDP port: `1536`
- DNS hijack port: `1536`
- Xray outbound mark: `2`
- TProxy route mark: `20` for IPv4, `25` for IPv6

The default Xray config intentionally keeps `proxy` as a `freedom` outbound so the module can start before you add a real server. Real proxying starts after you replace that outbound while keeping the tag name `proxy`.

## CLI

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service status'
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
su -c '/data/adb/modules/netproxy/scripts/cli service logs xray 80'
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
su -c '/data/adb/modules/netproxy/scripts/cli tproxy status'
su -c '/data/adb/modules/netproxy/scripts/cli app list'
```

## Updating Xray

This project does not build Xray-core locally. Replace the bundled files from the official release asset:

```text
https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-android-arm64-v8a.zip
```

Copy these files into the module:

- `xray` -> `src/module/bin/xray`
- `geoip.dat` -> `src/module/config/xray/geoip.dat`
- `geosite.dat` -> `src/module/config/xray/geosite.dat`

## References

- [Xray-core v26.3.27 release](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27)
- Xray config reference: `../Xray-docs-next`
- Xray source reference: `../Xray-core`

## License

GPL-3.0
