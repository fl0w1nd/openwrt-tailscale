# UCI 配置

所有设置均以 UCI 格式存储在 `/etc/config/tailscale`。

## 完整配置参考

```ini
config tailscale 'settings'
    option enabled '1'              # 启用/禁用服务
    option port '41641'             # Tailscale UDP 端口
    option storage_mode 'persistent' # persistent | ram
    option bin_dir '/opt/tailscale'  # 二进制文件目录
    option state_file '/etc/config/tailscaled.state' # 状态文件路径
    option statedir '/etc/tailscale' # 状态目录
    option fw_mode 'nftables'       # 防火墙模式：nftables | iptables
    option download_source 'small'  # 下载源：official | small
    option tun_mode 'auto'          # TUN 模式：auto | tun | userspace
    option proxy_listen 'localhost' # 代理监听：localhost | lan
    option auto_update '1'          # 自动更新：0 | 1
```

## 修改配置

### 通过 UCI 命令

```sh
uci set tailscale.settings.port=12345
uci commit tailscale
/etc/init.d/tailscale restart
```

### 通过 LuCI

如已安装 [LuCI 界面](/zh/guide/luci)，可在 **服务 → Tailscale → 配置** 中设置。

## 选项参考

| 选项 | 可选值 | 默认值 | 说明 |
|------|--------|--------|------|
| `enabled` | `0` / `1` | `1` | 启用或禁用 Tailscale 服务 |
| `port` | 整数 | `41641` | Tailscale WireGuard 流量的 UDP 端口 |
| `storage_mode` | `persistent` / `ram` | `persistent` | 二进制文件存储位置 |
| `bin_dir` | 路径 | `/opt/tailscale` | 二进制文件安装目录 |
| `state_file` | 路径 | `/etc/config/tailscaled.state` | Tailscale 状态文件 |
| `statedir` | 路径 | `/etc/tailscale` | Tailscale 状态目录 |
| `fw_mode` | `nftables` / `iptables` | `nftables` | 防火墙后端 |
| `download_source` | `official` / `small` | `small` | 二进制下载源 |
| `tun_mode` | `auto` / `tun` / `userspace` | `auto` | 网络模式 |
| `proxy_listen` | `localhost` / `lan` | `localhost` | 代理监听地址（仅用户空间模式） |
| `auto_update` | `0` / `1` | `1` | 启用每日自动更新定时任务 |
