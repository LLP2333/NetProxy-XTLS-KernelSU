# 安装与升级

## 安装前准备

- 设备已具备 Root 环境。
- 已安装 Magisk、KernelSU 或 APatch。
- 已准备可用的 Xray 出站配置。

当前版本不处理订阅或分享链接。请先把你的节点转换为 Xray 原生 JSON 出站配置。

## 安装模块

1. 从 [NetProxy Releases](https://github.com/Fanju6/NetProxy-Magisk/releases) 下载模块 ZIP。
2. 在 Magisk、KernelSU 或 APatch 中刷入模块。
3. 重启设备。
4. 编辑 `/data/adb/modules/netproxy/config/xray/config.json`。
5. 执行配置校验。

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
```

配置通过后可以重启手机让模块自动启动，也可以在模块管理器中点击 NetProxy 的“操作”按钮手动启动。

## 安装后检查

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service status'
su -c '/data/adb/modules/netproxy/scripts/cli tproxy status'
su -c '/data/adb/modules/netproxy/scripts/cli service logs xray 80'
```

如果 `xray test` 失败，先修正 `config.json`，再启动服务。

## Android 管理器

如果你需要图形化管理，可安装 Android 管理器：

- 下载地址：[`NetProxy - Google Play`](https://play.google.com/store/apps/details?id=com.fanjv.netproxy)
- 应用包名：`com.fanjv.netproxy`

当前模块的核心配置仍以手写 Xray JSON 为准。图形化入口适合查看状态、日志和常用透明代理项。

## 从旧版本升级

升级到 Xray 版本后，旧的节点目录、订阅目录、控制接口和面板不再使用。请重点检查：

- `/data/adb/modules/netproxy/config/xray/config.json` 是否存在。
- `config.json` 内是否有 tag 为 `proxy` 的可用出站。
- 所有需要发起外连的出站是否设置 `streamSettings.sockopt.mark=2`。
- `config/tproxy/tproxy.conf` 是否保留 `ROUTING_MARK="2"`。

旧配置不会自动转换成 Xray 配置。
