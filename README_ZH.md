# NetProxy

基于 **Xray-core** 的 Android 系统级透明代理模块。

通过 iptables TPROXY + dokodemo-door 入站实现全局流量劫持，支持 TCP、UDP、DNS 透明代理。

## 功能范围

- 内置 Xray-core Android arm64 二进制。
- 通过 iptables mangle 表 TPROXY 劫持全部 TCP/UDP 流量到 Xray。
- 内置 `geoip.dat` 和 `geosite.dat`，供 Xray 路由规则使用。
- CLI 支持服务启停、Xray 配置校验、日志查看。

## 模块结构

```text
src/module/
├─ META-INF/                   # Magisk/KernelSU/APatch 安装入口
├─ bin/
│  └─ xray                    # Xray-core Android arm64 二进制
├─ config/
│  ├─ module.conf             # 模块级配置
│  └─ xray/
│     ├─ config.json          # Xray 主配置（dokodemo-door 入站）
│     ├─ geoip.dat
│     └─ geosite.dat
├─ scripts/
│  ├─ cli                     # CLI 入口（service/xray 子命令）
│  ├─ core/
│  │  └─ service.sh           # 服务启停核心逻辑
│  ├─ network/
│  │  └─ tproxy.sh            # iptables TPROXY 规则管理
│  └─ utils/
│     ├─ common.sh            # 日志、路径等公共函数
│     └─ config.sh            # 配置读写工具
├─ logs/                       # 运行时日志（自动生成）
├─ action.sh                   # 模块管理器"操作"按钮脚本
├─ customize.sh                # 安装/升级脚本
├─ module.prop                 # 模块元信息（名称、版本等）
├─ post-fs-data.sh             # 开机早期初始化
└─ service.sh                  # 开机服务入口（AUTO_START）
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

4. 将默认的 `proxy` 出站（`freedom`）替换成自己的 Xray 出站，例如 VLESS、Trojan、VMess、Shadowsocks 或 SOCKS。**所有出站都必须保留 `"sockopt": { "mark": 255 }`**，否则会导致流量回环。
5. 校验配置：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
```

6. 重启服务生效：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
```

之后可以直接重启手机，模块默认 `AUTO_START=1`，开机会自动启动。需要手动开关时，打开 KernelSU / Magisk / APatch 的模块页面，点击 NetProxy 的"操作"按钮即可。

## TProxy 原理

模块使用 iptables mangle 表 TPROXY 目标将全部 TCP/UDP 流量重定向到 Xray 的 dokodemo-door 入站端口。

**启动流程：**

1. 启动 Xray 进程，监听 dokodemo-door 端口（默认 12345）
2. 配置 ip rule/route，将被标记的包路由到本地回环
3. 在 PREROUTING 链添加 TPROXY 规则，将流量重定向到 Xray
4. 在 OUTPUT 链标记本机发出的流量，触发 re-route 进入 TPROXY

**防回环机制：**

Xray 所有出站配置 `sockopt.mark: 255`，发出的包自带 fwmark。OUTPUT 链检测到此标记后直接放行，避免将 Xray 自身的流量再送回 TPROXY。

## 重要默认值

- Xray 配置：`/data/adb/modules/netproxy/config/xray/config.json`
- Xray 资源目录：`/data/adb/modules/netproxy/config/xray`
- 透明代理端口：`12345`（`module.conf` 中 `TPROXY_PORT`）
- 路由标记：`255`（`module.conf` 中 `FWMARK`，与 Xray `sockopt.mark` 一致）

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
- [Xray dokodemo-door 文档](https://xtls.github.io/config/inbounds/dokodemo.html)

## License

GPL-3.0
