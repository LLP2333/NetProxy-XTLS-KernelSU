# CLI 使用

NetProxy CLI 路径固定为：

```text
/data/adb/modules/netproxy/scripts/cli
```

通常通过 Root 调用：

```sh
su -c /data/adb/modules/netproxy/scripts/cli help
```

## 命令分组

```text
cli service {status|start|stop|restart|logs}
cli xray {config|show|test|version}
cli app {list|mode|add|remove|enable|disable}
cli tproxy {status|reload|quic|cnip}
```

## service

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service status'
su -c '/data/adb/modules/netproxy/scripts/cli service start'
su -c '/data/adb/modules/netproxy/scripts/cli service stop'
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
```

查看日志：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service logs service 80'
su -c '/data/adb/modules/netproxy/scripts/cli service logs xray 80'
```

## xray

查看当前配置路径：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray config'
```

输出配置内容：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray show'
```

校验配置：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
```

查看版本：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray version'
```

## app

```sh
su -c '/data/adb/modules/netproxy/scripts/cli app list'
su -c '/data/adb/modules/netproxy/scripts/cli app mode whitelist'
su -c '/data/adb/modules/netproxy/scripts/cli app add com.example.app'
su -c '/data/adb/modules/netproxy/scripts/cli app remove com.example.app'
su -c '/data/adb/modules/netproxy/scripts/cli app enable'
su -c '/data/adb/modules/netproxy/scripts/cli app disable'
```

`blacklist` 模式表示列表里的应用绕过代理；`whitelist` 模式表示只有列表里的应用进入代理。

## tproxy

```sh
su -c '/data/adb/modules/netproxy/scripts/cli tproxy status'
su -c '/data/adb/modules/netproxy/scripts/cli tproxy reload'
su -c '/data/adb/modules/netproxy/scripts/cli tproxy quic off'
su -c '/data/adb/modules/netproxy/scripts/cli tproxy cnip on'
```

`tproxy reload` 只重载透明代理规则，不会修改 Xray 配置。如果你改了 `config.json`，请重启服务。
