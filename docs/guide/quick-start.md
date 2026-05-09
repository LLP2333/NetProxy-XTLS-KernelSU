# 快速开始

## 1. 编辑 Xray 配置

配置文件路径：

```text
/data/adb/modules/netproxy/config/xray/config.json
```

默认配置中有一个 tag 为 `proxy` 的 `freedom` 出站，它只是占位。把它替换成你的真实代理出站，保留 tag：

```json
{
  "tag": "proxy",
  "protocol": "vless",
  "settings": {},
  "streamSettings": {
    "sockopt": {
      "mark": 2
    }
  }
}
```

`settings` 和传输层字段按你的节点实际情况填写。

## 2. 保持端口一致

默认透明代理入站端口是 `1536`。Xray 入站和 `tproxy.conf` 需要一致：

```json
{
  "tag": "tproxy-in",
  "port": 1536,
  "protocol": "dokodemo-door"
}
```

```text
PROXY_TCP_PORT="1536"
PROXY_UDP_PORT="1536"
DNS_PORT="1536"
```

## 3. 校验配置

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
```

看到 `Configuration OK.` 后再启动。

## 4. 启动服务

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service start'
```

查看状态：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service status'
```

## 5. 查看日志

```sh
su -c '/data/adb/modules/netproxy/scripts/cli service logs service 80'
su -c '/data/adb/modules/netproxy/scripts/cli service logs xray 80'
```

## 6. 常用调整

开启分应用白名单模式：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli app mode whitelist'
su -c '/data/adb/modules/netproxy/scripts/cli app add com.example.app'
```

重载透明代理规则：

```sh
su -c '/data/adb/modules/netproxy/scripts/cli tproxy reload'
```
