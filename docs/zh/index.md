---
layout: home

hero:
  name: OpenWrt Tailscale
  text: OpenWrt 的 Tailscale 管理器
  tagline: 一条命令即可在 OpenWrt 路由器上安装、更新和管理 Tailscale。
  actions:
    - theme: brand
      text: 快速开始
      link: /zh/guide/installation
    - theme: alt
      text: 在 GitHub 查看
      link: https://github.com/fl0w1nd/openwrt-tailscale

features:
  - icon: 🚀
    title: 一键安装
    details: 单条命令完成下载、安装和启动交互菜单，自动处理依赖。
  - icon: 📦
    title: 小体积二进制
    details: 通过 UPX 压缩至约 5 MB，比官方包体积缩小 80%，专为嵌入式设备优化。
  - icon: 🔄
    title: 自动更新
    details: 每日定时任务自动保持 Tailscale 和管理脚本为最新版本。
  - icon: 🌐
    title: 子网路由
    details: 自动配置网络接口和防火墙，从任何 Tailscale 设备访问本地局域网。
  - icon: ⚙️
    title: 深度集成 OpenWrt
    details: UCI 配置、procd 服务管理，以及可选的 LuCI Web 管理界面。
  - icon: 🛡️
    title: 用户空间回退
    details: 内核 TUN 模块不可用时自动切换到用户空间网络模式。
---
