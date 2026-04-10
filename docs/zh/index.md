---
layout: home

hero:
  name: OpenWrt Tailscale
  text: 适用于任意 OpenWrt 路由器的 Tailscale
  tagline: 一条命令即可部署 —— 即使设备太旧或存储太小，无法使用官方包。
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
    details: 一条 wget 命令启动交互式安装器，自动检测并安装依赖、下载二进制、配置服务。
  - icon: 📦
    title: 5 MB 压缩二进制
    details: UPX 压缩后的 Tailscale 二进制，比官方包小 80%。最低仅需 8 MB 可用存储，也支持纯 RAM 运行模式。
  - icon: 🔄
    title: 自动更新
    details: 内置定时任务自动保持 Tailscale 二进制和管理脚本为最新版本。无需 opkg，无需手动操作。
  - icon: 🌐
    title: 子网路由
    details: 一键配置网络接口和防火墙规则，从任何 Tailscale 设备访问路由器背后的局域网。
  - icon: ⚙️
    title: 深度集成 OpenWrt
    details: UCI 配置、procd 服务管理，以及可选的 LuCI Web 管理界面，提供状态监控、服务控制和版本管理。
  - icon: 🛡️
    title: 广泛兼容
    details: 支持 OpenWrt 21.02+、busybox ash，不依赖 ucode 或 rpcd-mod-ucode。内核 TUN 不可用时自动切换到用户空间网络模式。
---
