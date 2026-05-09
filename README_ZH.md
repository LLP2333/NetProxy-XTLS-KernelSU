# NetProxy

基于 **Xray-core** 的 Android 系统级透明代理模块。

当前版本只考虑手写 Xray 配置文件的启动方式，不再提供节点链接导入、订阅更新、Clash API 或内置网页面板。

## 功能范围

- 内置 Xray-core v26.3.27 Android arm64 二进制。
- 通过 Android iptables/ipset 规则实现透明代理。
- 默认使用 TProxy 接管 TCP、UDP 和 DNS 流量。
- 支持分应用代理名单。
- 内置 `geoip.dat` 和 `geosite.dat`，供 Xray 路由规则使用。
- CLI 支持服务启停、Xray 配置校验、日志、分应用代理和透明代理规则管理。

## 模块结构

```text
src/module/
├─ bin/
│  ├─ xray                    # Xray-core Android arm64 二进制
│  └─ ipset                   # 可选 ipset 工具
├─ config/
│  ├─ module.conf             # 模块级配置
│  ├─ tproxy/tproxy.conf      # 透明代理配置
│  └─ xray/
│     ├─ config.json          # 手写 Xray 主配置
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

## 快速开始

1. 在 Magisk、KernelSU 或 APatch 中刷入模块。
2. 重启设备。
3. 编辑 Xray 配置：

```text
/data/adb/modules/netproxy/config/xray/config.json
```

4. 将默认的 `proxy` 出站替换成自己的 Xray 出站，例如 VLESS、Trojan、VMess、Shadowsocks 或 SOCKS。
5. 除非你同时修改 `tproxy.conf`，否则保留出站上的 mark：

```json
"streamSettings": {
  "sockopt": {
    "mark": 2
  }
}
```

6. 校验配置：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
```

之后可以直接重启手机，模块默认 `AUTO_START=1`，开机会自动启动。需要手动开关时，打开 KernelSU / Magisk / APatch 的模块页面，点击 NetProxy 的“操作”按钮即可。

## 重要默认值

- Xray 配置：`/data/adb/modules/netproxy/config/xray/config.json`
- Xray 资源目录：`/data/adb/modules/netproxy/config/xray`
- 透明代理 TCP 端口：`1536`
- 透明代理 UDP 端口：`1536`
- DNS 劫持端口：`1536`
- Xray 出站 mark：`2`
- TProxy 路由 mark：IPv4 为 `20`，IPv6 为 `25`

默认配置里的 `proxy` 出站暂时是 `freedom`，目的是让模块在没有真实服务器配置时也能启动。真正走代理前，需要把这个出站替换成你的节点配置，并保留 tag 名称 `proxy`。

## CLI

日常启动和停止不必记 CLI。模块管理器里的“操作”按钮会在未运行时启动服务、运行时停止服务。

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service status'
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
su -c '/data/adb/modules/netproxy/scripts/cli service logs xray 80'
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
su -c '/data/adb/modules/netproxy/scripts/cli tproxy status'
su -c '/data/adb/modules/netproxy/scripts/cli app list'
```

## 更新 Xray

本项目不在模块构建流程里编译 Xray-core。直接使用官方 release 资产：

```text
https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-android-arm64-v8a.zip
```

将压缩包里的文件放到模块对应位置：

- `xray` -> `src/module/bin/xray`
- `geoip.dat` -> `src/module/config/xray/geoip.dat`
- `geosite.dat` -> `src/module/config/xray/geosite.dat`

## 参考

- [Xray-core v26.3.27 release](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27)
- Xray 配置文档：`../Xray-docs-next`
- Xray 源码：`../Xray-core`

## License

GPL-3.0
