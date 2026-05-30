# 路线图

OpenWrt Tailscale Manager 的开发计划概览。

## ✅ 已完成

- 一键安装交互式菜单
- Small 小体积二进制（UPX 压缩，约 8-10 MB）
- 双下载源（官方 / Small）
- Tailscale 二进制自动更新（管理脚本仅支持手动更新）
- 持久化和 RAM 两种存储模式
- 用户空间网络回退
- UCI 配置 + procd 服务集成
- LuCI Web 管理界面（状态、配置、维护、日志）
- rpcd exec bridge（无需 ucode 依赖）

## 📋 计划中

本项目坚持"脚本为核心、LuCI 仅作高频低复杂度操作的便捷入口"的定位。LuCI 保持精简，不再扩张配置面，核心能力仍由 CLI 脚本承载。

### 诊断工具

- `tailscale-manager diagnose` 命令
- 一键生成系统报告，便于故障排查
