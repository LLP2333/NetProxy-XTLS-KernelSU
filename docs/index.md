---
layout: home

hero:
  name: NetProxy
  text: Android Xray 透明代理模块
  tagline: 基于 Xray-core，使用手写 config.json 启动的 Android 系统级透明代理模块。
  image:
    src: /logo.png
    alt: NetProxy Logo
  actions:
    - theme: brand
      text: 快速开始
      link: /guide/quick-start
    - theme: alt
      text: 安装与升级
      link: /guide/installation
    - theme: alt
      text: GitHub
      link: https://github.com/Fanju6/NetProxy-Magisk

features:
  - title: Xray-core
    details: 内置 Xray-core v26.3.27 Android arm64 二进制，模块启动时直接读取手写配置文件。
  - title: 手写配置
    details: 主配置位于 config/xray/config.json，节点、路由、DNS 都由 Xray 原生 JSON 配置表达。
  - title: TProxy 透明代理
    details: 透明代理层保留 Android iptables/ipset 规则，默认接管 TCP、UDP 和 DNS 流量。
  - title: 分应用代理
    details: 继续通过 tproxy.conf 控制应用名单，可用 CLI 快速启用、添加或移除包名。
  - title: CLI 运维
    details: 命令行覆盖服务启停、Xray 配置校验、日志查看和透明代理规则重载。
  - title: 精简运行链路
    details: 不内置订阅转换、控制 API 或网页面板，运行时行为由 Xray 配置和透明代理规则共同决定。
---
