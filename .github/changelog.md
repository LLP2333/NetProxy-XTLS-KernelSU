## 版本 7.1.0

### 核心更新

* 透明代理核心迁移为 **Xray-core v26.3.27**。
* 启动方式改为读取手写的 `/data/adb/modules/netproxy/config/xray/config.json`。
* 移除节点导入、订阅转换、控制 API 和内置面板相关运行链路。

### 主要变更

1. Xray 运行链路：
   * 使用 `bin/xray run -config` 启动。
   * `XRAY_LOCATION_ASSET` 指向模块内的 `geoip.dat` 与 `geosite.dat`。
   * 默认配置提供 `dokodemo-door` + TProxy 入站、DNS 出站、直连/阻断/代理标签。

2. 透明代理：
   * 保留原有 Android iptables/ipset 透明代理规则。
   * 默认强制 TProxy，并将 Xray 出站 `sockopt.mark` 与透明代理绕过标记保持一致。

3. CLI 与文档：
   * CLI 聚焦服务启停、Xray 配置校验、分应用代理和透明代理规则管理。
   * README 与文档已按 Xray 手写配置模式重写。
