---
layout: home

hero:
  name: OpenWrt Tailscale
  text: Tailscale Manager for OpenWrt
  tagline: Install, update, and manage Tailscale on your OpenWrt router with a single script.
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
    details: Download, install, and start the interactive menu with a single command. Handles dependencies automatically.
  - icon: 📦
    title: Small Binary Support
    details: Compressed binaries (~5 MB) via UPX — 80% smaller than official packages, perfect for embedded devices.
  - icon: 🔄
    title: Auto-Updates
    details: Daily cron job keeps Tailscale and the manager script up to date automatically.
  - icon: 🌐
    title: Subnet Routing
    details: Automatic network interface and firewall configuration for accessing your LAN from any Tailscale device.
  - icon: ⚙️
    title: Full OpenWrt Integration
    details: UCI configuration, procd service management, and optional LuCI web interface.
  - icon: 🛡️
    title: Userspace Fallback
    details: Automatically falls back to userspace networking when kernel TUN is unavailable.
---
