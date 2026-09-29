## 版本 7.2.0

### 新增

* **WebUI**：在 KernelSU 管理器中打开模块即可管理服务。
  * 状态页：运行状态、透明代理规则、启动 / 停止 / 重启，常用开关，一键更新 geoip / geosite。
  * 配置页：在线编辑 `config.json`，保存前经 `xray run -test` 校验，支持恢复上一版。
  * 日志页：查看 `service.log` / `xray.log`，支持自动刷新与自动换行。
* **透明代理**：
  * 支持 IPv6（`PROXY_IPV6`），内核不支持时自动回退为仅 IPv4。
  * 支持分应用代理（`APP_PROXY_MODE` / `APP_PROXY_LIST`，黑名单或白名单）。
  * 支持热点 / USB 共享下游设备代理（`PROXY_HOTSPOT` / `HOTSPOT_INTERFACES`）。
* **CLI**：新增 `xray apply`、`conf get/set`，`service status` 与 `geo status` 支持 `--json`。

### 变更与修复

* WiFi 下发往路由器的 DNS 不再绕过 Xray。
* 透明代理端口改为读取 `module.conf` 的 `TPROXY_PORT`。
* 只劫持本机与共享网络接口的流量，上游接口的入站连接不再被误劫持。
* 移除"停止服务前自动更新 geo 数据"，改为 WebUI 按钮或 `cli geo update` 手动更新。
* 移除指向原项目的更新地址；模式文案统一为 TPROXY。

### 升级说明

* 可直接覆盖安装，`module.conf`、`config.json`、`bin/xray` 与 geo 数据会保留。
* 旧的 `module.conf` 中没有新增的键，按默认值运行：IPv6 与热点代理开启，分应用代理关闭。

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
