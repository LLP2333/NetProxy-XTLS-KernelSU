# NetProxy

基于 **Xray-core** TUN 模式的 Android 系统级透明代理模块。

通过 Xray 内建 TUN 接口接管系统流量，无需 iptables 规则，兼容性好、配置简单。

## 功能范围

- 内置 Xray-core Android arm64 二进制。
- 通过 Xray TUN 入站创建虚拟网卡，自动设置路由接管全部流量。
- 支持 TCP、UDP、DNS 透明代理。
- 内置 `geoip.dat` 和 `geosite.dat`，供 Xray 路由规则使用。
- CLI 支持服务启停、Xray 配置校验、日志查看。

## 模块结构

```text
src/module/
├─ bin/
│  └─ xray                    # Xray-core Android arm64 二进制
├─ config/
│  ├─ module.conf             # 模块级配置
│  └─ xray/
│     ├─ config.json          # Xray 主配置（TUN 入站）
│     ├─ geoip.dat
│     └─ geosite.dat
├─ scripts/
│  ├─ cli
│  ├─ core/service.sh
│  └─ utils/
│     ├─ common.sh
│     ├─ config.sh
│     └─ gms_fix.sh
└─ logs/
   ├─ service.log
   └─ xray.log
```

## 打包模块

在项目根目录执行：

```sh
cd src/module && zip -r ../../NetProxy.zip . && cd ../..
```

zip 内的文件必须在根目录层级（不能套一层文件夹），打包后的 `NetProxy.zip` 可直接在模块管理器中安装。

## 快速开始

1. 在 Magisk、KernelSU 或 APatch 中刷入模块。
2. 重启设备。
3. 编辑 Xray 配置：

```text
/data/adb/modules/netproxy/config/xray/config.json
```

4. 将默认的 `proxy` 出站（`freedom`）替换成自己的 Xray 出站，例如 VLESS、Trojan、VMess、Shadowsocks 或 SOCKS。
5. 校验配置：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
```

6. 重启服务生效：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
```

之后可以直接重启手机，模块默认 `AUTO_START=1`，开机会自动启动。需要手动开关时，打开 KernelSU / Magisk / APatch 的模块页面，点击 NetProxy 的"操作"按钮即可。

## TUN 模式说明

模块使用 Xray 内建 TUN 入站，关键配置：

```json
{
  "protocol": "tun",
  "settings": {
    "name": "xray0",
    "mtu": 1500,
    "gateway": ["10.0.0.1/16"],
    "dns": ["1.1.1.1"],
    "autoSystemRoutingTable": ["0.0.0.0/0"],
    "autoOutboundsInterface": "auto"
  }
}
```

- `autoSystemRoutingTable` — Xray 自动向系统路由表添加默认路由，将所有流量导向 TUN 接口。
- `autoOutboundsInterface` — Xray 自动检测物理网卡并绑定所有出站，防止流量回环。
- 出站无需设置 `sockopt.mark`，回环防护由接口绑定实现。
- 停止 Xray 后 TUN 接口和路由自动销毁，无需手动清理。

## 重要默认值

- Xray 配置：`/data/adb/modules/netproxy/config/xray/config.json`
- Xray 资源目录：`/data/adb/modules/netproxy/config/xray`
- TUN 接口名：`xray0`
- TUN 网关：`10.0.0.1/16`

默认配置里的 `proxy` 出站暂时是 `freedom`，目的是让模块在没有真实服务器配置时也能启动。真正走代理前，需要把这个出站替换成你的节点配置，并保留 tag 名称 `proxy`。

## CLI

日常启动和停止不必记 CLI。模块管理器里的"操作"按钮会在未运行时启动服务、运行时停止服务。

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service status'
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
su -c '/data/adb/modules/netproxy/scripts/cli service logs xray 80'
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
```

## 更新 Xray

本项目不在模块构建流程里编译 Xray-core。直接使用官方 release 资产：

```text
https://github.com/XTLS/Xray-core/releases
```

将压缩包里的文件放到模块对应位置：

- `xray` -> `src/module/bin/xray`
- `geoip.dat` -> `src/module/config/xray/geoip.dat`
- `geosite.dat` -> `src/module/config/xray/geosite.dat`

## 参考

- [Xray-core releases](https://github.com/XTLS/Xray-core/releases)
- [Xray TUN 入站文档](https://xtls.github.io/config/inbounds/tun.html)

## License

GPL-3.0
