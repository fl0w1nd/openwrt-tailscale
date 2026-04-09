---
layout: home

hero:
  name: OpenWrt Tailscale
  text: Tailscale for Any OpenWrt Router
  tagline: One-command deployment — even on devices too old or too small for official packages.
  actions:
    - theme: brand
      text: Get Started
      link: /en/guide/installation
    - theme: alt
      text: View on GitHub
      link: https://github.com/fl0w1nd/openwrt-tailscale

features:
  - icon: 🚀
    title: One-Command Install
    details: A single wget command bootstraps the interactive installer. Dependencies, download, and service setup are handled automatically.
  - icon: 📦
    title: 8-10 MB Compressed Binary
    details: UPX-compressed Tailscale binary — 80% smaller than official packages. Runs on devices with as little as 8 MB free storage, or entirely from RAM.
  - icon: 🔄
    title: Self-Updating
    details: Built-in cron jobs keep the Tailscale binary and management scripts up to date. No opkg, no manual intervention.
  - icon: 🌐
    title: Subnet Routing
    details: One-click network interface and firewall configuration for accessing your LAN from any Tailscale device.
  - icon: ⚙️
    title: Full OpenWrt Integration
    details: UCI configuration, procd service management, and an optional LuCI web interface for status, control, and maintenance.
  - icon: 🛡️
    title: Broad Compatibility
    details: Works on OpenWrt 21.02+, busybox ash, without ucode or rpcd-mod-ucode. Falls back to userspace networking when kernel TUN is unavailable.
---
