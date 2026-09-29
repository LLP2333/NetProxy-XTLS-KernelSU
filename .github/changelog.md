## 版本 7.5.2

### 变更

* WebUI 日志页的下拉框只显示日志文件名（如 `service.log`、`xray.log`、`access.log`），日志类型改为选项的提示文字。

### 升级说明

* 可直接覆盖安装，配置与自定义文件都会保留。

## 版本 7.5.1

### 修复

* **从 WebUI 启动服务后，几分钟后整机断网或流量不走代理**：从 WebUI / 模块管理器启动服务时，Xray 与看门狗继承了管理器应用的 cgroup。管理器退到后台后系统（如小米 HyperOS）会冻结该 cgroup，Xray 随之冻结、不再处理连接；管理器被关闭时 Xray 也会被一起杀掉。现在启动服务时会将 Xray 与看门狗移入系统根 cgroup，不再受管理器应用状态影响。开机自启不受此问题影响。

### 升级说明

* 可直接覆盖安装，配置与自定义文件都会保留。
* 升级后如仍在运行旧版本启动的 Xray，在 WebUI 中重启一次服务即可。

## 版本 7.5.0

### 修复

* **7.4.0 在小米 HyperOS 等设备上开启代理后整机断网**：7.4.0 把策略路由优先级写死为 9000，部分 ROM 存在优先级更小的自有路由规则，代理流量被系统规则接走、到不了 Xray。现恢复 7.3.0 的行为，由内核把规则放在所有系统规则之前，并恢复开启 IPv4 转发。
* 日志所在目录不存在时，WebUI 保存配置（`xray run -test`）会校验失败。

### 变更

* **日志文件跟随 Xray 配置**：日志固定为模块日志 `service.log`，加上 Xray 配置中 `log.error` 与 `log.access` 指定的文件，最少 1 个、最多 3 个。
  * Xray 的启动输出与崩溃信息写入 error 日志；`log.error` 为空或 `none` 时写入 `logs/xray.log`。
  * WebUI 日志页与 `cli service logs` 按当前配置列出日志；新增 `cli service logs --list`，日志类型为 `service` / `error` / `access`（旧写法 `xray` 仍可用）。
* 不再生成 `.1` 备份日志：超过上限时就地截断，只保留后半部分（模块日志 1 MB、错误日志 2 MB、访问日志 5 MB），服务运行期间每 5 分钟检查一次。每次启动在错误日志中写入分隔行，崩溃前的日志保留在同一文件。
* 启动服务时删除 `logs/` 目录中不再使用的日志文件。
* 升级模块时保留运行日志；安装包不再附带空的占位日志文件。

### 升级说明

* 7.4.0 用户请尽快升级。已处于断网状态时，点击模块的「操作」按钮或执行 `su -c /data/adb/modules/netproxy/scripts/cli service stop` 即可恢复网络，再安装本版本。
* 可直接覆盖安装，配置与自定义文件都会保留。

## 版本 7.4.0

### 新增

* **看门狗**：Xray 意外退出时立即清理透明代理规则，避免整机断网，并自动重启服务（5 分钟内最多 3 次）。可在 WebUI 或 `module.conf` 的 `WATCHDOG_RESTART` 中关闭自动重启。
* **日志级别**：`module.conf` 新增 `LOG_LEVEL`，设为 `debug` 时记录完整的透明代理规则，便于排查问题。

### 优化

* 透明代理规则改为一次性原子提交，加载更快，失败时不会留下半套规则。
* 启动时检测透明代理端口进入监听即完成，不再固定等待；端口与配置不一致时给出明确提示。
* 开机不再等待内部存储，启用文件级加密的设备无需先解锁即可启动代理。
* 在线更新 geo 数据在没有 curl 的设备上自动改用 busybox wget，并限制等待时间。
* `xray.log` 保留上一次运行的日志（`xray.log.1`），`service.log` 超过 1 MB 自动轮转。
* WebUI 状态每次刷新不再重复启动 Xray 读取版本号。

### 修复

* 升级模块时会保留 `config/` 下用户自行添加的文件（如自定义规则 dat、`config.json.bak`），不再被移入回收站或在重启后丢失。
* `xray.log` 可能被两个写入者互相覆盖的问题。
* 模块文件权限：配置文件不再是可执行权限。

### 升级说明

* 可直接覆盖安装，`module.conf`、`config.json`、`bin/xray`、geo 数据及 `config/` 下的自定义文件都会保留。
* 旧的 `module.conf` 中没有新增的键，按默认值运行：自动重启开启、日志级别 info。

## 版本 7.3.0

### 新增

* **模块更新检查**：模块管理器（KernelSU / Magisk / APatch）现在可以检查并提示新版本，更新地址指向本项目的 GitHub Release。

### 变更

* 发布包只保留完整包与纯脚本包（mini），移除与完整包内容相同的 lite 包。
* README 增加对原项目 [NetProxy-Magisk](https://github.com/Fanju6/NetProxy-Magisk) 及作者 Fanju 的致谢。

### 升级说明

* 从 7.2.0 及更早版本升级需要手动安装一次本版本，之后的新版本即可在模块管理器中收到更新提示。
* 可直接覆盖安装，`module.conf`、`config.json`、`bin/xray` 与 geo 数据会保留。

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
