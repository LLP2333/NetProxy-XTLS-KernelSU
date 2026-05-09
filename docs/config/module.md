# module.conf

模块级配置位于：

```text
/data/adb/modules/netproxy/config/module.conf
```

## 默认配置

```text
AUTO_START=1
GMS_FIX=0
XRAY_CONFIG="/data/adb/modules/netproxy/config/xray/config.json"
```

## AUTO_START

```text
AUTO_START=1
```

- `1`：开机后自动启动 NetProxy 服务。
- `0`：开机不自动启动，需要手动执行 `cli service start`。

## GMS_FIX

```text
GMS_FIX=0
```

用于执行模块内的设备兼容性修复脚本。默认关闭。

## XRAY_CONFIG

```text
XRAY_CONFIG="/data/adb/modules/netproxy/config/xray/config.json"
```

Xray 主配置文件路径。服务启动时会执行：

```sh
bin/xray run -config "$XRAY_CONFIG"
```

如果你把配置放到其他位置，确保：

- 文件对 root 可读。
- 配置中的日志路径存在或可创建。
- `geoip.dat` 和 `geosite.dat` 仍位于 `config/xray/`，或你同步修改了 Xray asset 路径相关启动脚本。
