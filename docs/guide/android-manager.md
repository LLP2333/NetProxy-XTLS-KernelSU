# Android 管理器

NetProxy 的 Android 管理器可用于日常查看状态、日志和常用配置项。

- 下载地址：[`NetProxy - Google Play`](https://play.google.com/store/apps/details?id=com.fanjv.netproxy)
- 应用包名：`com.fanjv.netproxy`

## 当前版本的配置边界

Xray 主配置仍以文件为准：

```text
/data/adb/modules/netproxy/config/xray/config.json
```

如果管理器里的功能与当前 Xray 版本不一致，以模块内的 CLI 和配置文件为准。

## 推荐使用方式

- 用管理器查看服务状态和日志。
- 用管理器调整分应用代理、基础开关等透明代理项。
- 用文本编辑器或 adb 手动维护 `config/xray/config.json`。
- 用 CLI 执行 Xray 配置校验。

```sh
su -c '/data/adb/modules/netproxy/scripts/cli xray test'
```
