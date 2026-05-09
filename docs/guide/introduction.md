# 项目介绍

NetProxy 是一个面向 Android Root 环境的系统级透明代理模块，当前版本以 **Xray-core** 为代理核心。

模块做两件事：

1. 用 `scripts/network/tproxy.sh` 在 Android 上接管需要代理的 TCP、UDP 和 DNS 流量。
2. 用 `bin/xray run -config` 启动 Xray，并让 Xray 按 `config/xray/config.json` 处理入站、出站、DNS 和路由。

## 当前边界

当前版本只支持手写 Xray 配置文件：

```text
/data/adb/modules/netproxy/config/xray/config.json
```

不再提供以下运行能力：

- 节点链接导入
- 订阅更新
- 控制 API
- 内置网页面板
- 运行时代理组切换

这些行为都应回到 Xray 原生配置里表达。

## 适用环境

- Magisk
- KernelSU
- APatch

模块需要 root 权限和可用的 iptables/ipset 环境。TProxy、owner 匹配、mark 匹配等能力取决于设备内核。

## 关键目录

```text
/data/adb/modules/netproxy/bin/xray
/data/adb/modules/netproxy/config/module.conf
/data/adb/modules/netproxy/config/xray/config.json
/data/adb/modules/netproxy/config/xray/geoip.dat
/data/adb/modules/netproxy/config/xray/geosite.dat
/data/adb/modules/netproxy/config/tproxy/tproxy.conf
/data/adb/modules/netproxy/scripts/cli
/data/adb/modules/netproxy/logs/service.log
/data/adb/modules/netproxy/logs/xray.log
```

## 默认流量路径

```text
Android 应用
  -> tproxy.sh 创建的 iptables/ip rule
  -> Xray dokodemo-door 入站 tproxy-in:1536
  -> Xray routing
  -> proxy / direct / block / dns-out 出站
```

默认 `proxy` 出站是 `freedom` 占位，方便模块在没有服务器配置时启动。使用前需要把它替换成真实代理出站，并保留 tag `proxy`。
