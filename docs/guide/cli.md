# CLI 使用

NetProxy CLI 路径固定为：

```text
/data/adb/modules/netproxy/scripts/cli
```

通常通过 Root 调用：

```sh
su -c /data/adb/modules/netproxy/scripts/cli help
```

日常开关服务可以不用 CLI。模块默认开机自启；手动开关可在 KernelSU / Magisk / APatch 的模块页面点击 NetProxy 的“操作”按钮，KernelSU 用户也可以直接打开模块的 WebUI。

## 命令分组

```text
cli service {status|start|stop|restart|logs}
cli xray {config|show|test|apply|version}
cli geo {status|update}
cli conf {get|set}
```

## service

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service status'
su -c '/data/adb/modules/netproxy/scripts/cli service start'
su -c '/data/adb/modules/netproxy/scripts/cli service stop'
su -c '/data/adb/modules/netproxy/scripts/cli service restart'
```

`service status --json` 输出单行 JSON（WebUI 使用），包含运行状态、透明代理规则是否已加载以及透明代理相关设置。

查看日志：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service logs service 80'   # 模块日志
su -c '/data/adb/modules/netproxy/scripts/cli service logs error 80'     # Xray 错误日志（旧写法 xray 仍可用）
su -c '/data/adb/modules/netproxy/scripts/cli service logs access 80'    # Xray 访问日志
su -c '/data/adb/modules/netproxy/scripts/cli service logs --list'       # 当前生效的日志文件（JSON）
```

Xray 的日志文件由 `config.json` 中的 `log.error` 与 `log.access` 决定，详见 [module.conf 的日志说明](../config/module.md#日志文件)。

## xray

```sh
# 当前配置路径 / 内容
su -c '/data/adb/modules/netproxy/scripts/cli xray config'
su -c '/data/adb/modules/netproxy/scripts/cli xray show'

# 校验当前配置，或校验任意文件
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
su -c '/data/adb/modules/netproxy/scripts/cli xray test /sdcard/new.json'

# 校验通过后替换当前配置，上一版备份为 config.json.bak
su -c '/data/adb/modules/netproxy/scripts/cli xray apply /sdcard/new.json'

# 回滚到上一版（当前版本会与 .bak 互换）
su -c '/data/adb/modules/netproxy/scripts/cli xray apply /data/adb/modules/netproxy/config/xray/config.json.bak'

su -c '/data/adb/modules/netproxy/scripts/cli xray version'
```

`apply` 校验失败时不会修改当前配置。替换后需要重启服务才会生效。

## geo

```sh
su -c '/data/adb/modules/netproxy/scripts/cli geo status'          # 加 --json 输出单行 JSON（WebUI 使用）
su -c '/data/adb/modules/netproxy/scripts/cli geo update'          # 同时更新 geoip 和 geosite
su -c '/data/adb/modules/netproxy/scripts/cli geo update geosite'
```

## conf

读写 `module.conf` 中的 0/1 开关：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli conf get PROXY_IPV6'
su -c '/data/adb/modules/netproxy/scripts/cli conf set PROXY_IPV6 0'
```

可用的键：`AUTO_START`、`WATCHDOG_RESTART`、`PROXY_IPV6`、`PROXY_HOTSPOT`。分应用见下方 [app](#app)；端口等其他设置请直接编辑 `module.conf`，见 [module.conf](../config/module.md)。透明代理相关设置修改后需要重启服务。

## app

管理分应用代理（`APP_PROXY_MODE` / `APP_PROXY_LIST`）：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli app status'
su -c '/data/adb/modules/netproxy/scripts/cli app mode whitelist'
su -c '/data/adb/modules/netproxy/scripts/cli app add com.android.chrome 10:com.android.chrome'
su -c '/data/adb/modules/netproxy/scripts/cli app remove com.android.chrome'
su -c '/data/adb/modules/netproxy/scripts/cli app set blacklist com.tencent.mm'
su -c '/data/adb/modules/netproxy/scripts/cli app reload'
```

- `mode`：`off`、`blacklist` 或 `whitelist`。
- `add` / `remove` / `clear`：修改列表，每项为 `包名` 或 `用户ID:包名`。
- `set <模式> [包名...]`：一次性写入模式和完整列表（WebUI 使用此命令）。
- `packages [--json]`：列出主用户已安装的应用。
- `reload`：服务运行中时只重新加载透明代理规则，不重启 Xray；服务未运行时修改会在下次启动生效。

修改后需要执行 `cli app reload` 或重启服务才会生效。WebUI 的「分应用」页签提供搜索、全选、反选和黑 / 白名单切换。
