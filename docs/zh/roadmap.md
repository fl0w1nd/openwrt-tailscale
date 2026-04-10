# 路线图

OpenWrt Tailscale Manager 的开发计划概览。

## ✅ 已完成

- 一键安装交互式菜单
- Small 小体积二进制（UPX 压缩，约 5 MB）
- 双下载源（官方 / Small）
- Tailscale 二进制和管理脚本自动更新
- 持久化和 RAM 两种存储模式
- 用户空间网络回退
- UCI 配置 + procd 服务集成
- LuCI Web 管理界面（状态、配置、维护、日志）
- rpcd exec bridge（无需 ucode 依赖）

## 🚧 进行中

### LuCI Tailscale 设置

在 LuCI 界面中添加 `tailscale set` 配置项，无需 SSH 即可管理常用设置：

- 接受路由 (Accept Routes)
- 通告为出口节点 (Advertise Exit Node)
- 通告子网路由 (Advertise Routes)
- MagicDNS 开关
- Tailscale SSH
- Web 管理界面
- Shields Up（拒绝入站连接）
- 子网路由 SNAT
- 自定义主机名

## 📋 计划中

### Headscale 与登录流程

- 自定义 login server（Headscale）支持
- Auth key 预填
- LuCI 中提供登录 / 登出按钮

### Exit Node 选择器

- 在 LuCI 中通过下拉菜单选择出口节点
- 从在线设备列表动态获取候选项

### 状态页增强

- 显示 DERP relay 信息（直连 / 中继连接）
- 健康检查警告
- 设备列表排序

### 多语言支持

- LuCI 界面中英文翻译

### 诊断工具

- `tailscale-manager diagnose` 命令
- 一键生成系统报告，便于故障排查
