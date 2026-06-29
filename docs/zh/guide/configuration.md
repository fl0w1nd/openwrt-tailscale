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
    option net_mode 'auto'          # 网络模式：auto | tun | userspace
    option proxy_listen 'localhost' # 代理监听：localhost | lan
    option auto_update '0'          # 自动更新：0 | 1
    option luci_enabled '0'         # 可选 LuCI 界面：0 | 1

    # 高级（可选）：自定义 procd 环境变量与 tailscaled 命令行参数
    # 这些 list 项不会被脚本升级覆盖
    list extra_env 'GOMIPS=softfloat'
    list extra_args '--socks5-server=192.168.10.1:1080'
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
| `bin_dir` | 路径 | `/opt/tailscale` | 二进制文件安装目录（安装时可通过 `--bin-dir` 参数或交互式提示自定义，适合外置挂载场景，详见[存储模式](/zh/guide/storage-modes#自定义二进制目录)） |
| `state_file` | 路径 | `/etc/config/tailscaled.state` | Tailscale 状态文件 |
| `statedir` | 路径 | `/etc/tailscale` | Tailscale 状态目录 |
| `fw_mode` | `nftables` / `iptables` | `nftables` | 防火墙后端 |
| `download_source` | `official` / `small` | `small` | 二进制下载源 |
| `net_mode` | `auto` / `tun` / `userspace` | `auto` | 网络模式 |
| `proxy_listen` | `localhost` / `lan` | `localhost` | 代理监听地址（仅用户空间模式） |
| `auto_update` | `0` / `1` | `0` | 启用每日自动更新定时任务 |
| `luci_enabled` | `0` / `1` | `0` | 标记可选 LuCI Web 界面是否跟随 `self-update` 刷新 |
| `extra_env` | `list KEY=VALUE` | 空 | 额外的 procd 环境变量，详见下方[高级：自定义 env 和 CLI 参数](#高级-自定义-env-和-cli-参数) |
| `extra_args` | `list --flag=...` | 空 | 额外的 `tailscaled` 命令行参数，详见下方[高级：自定义 env 和 CLI 参数](#高级-自定义-env-和-cli-参数) |

## 高级：自定义 env 和 CLI 参数

`/etc/init.d/tailscale` 由 `tailscale-manager` 维护，每次升级都会被覆盖，因此**不要直接修改 init 脚本**。需要为 `tailscaled` 注入额外的环境变量或启动参数时，请通过 UCI 的 `extra_env` / `extra_args` list 实现，这些条目在脚本升级时会被保留。

### 典型场景

- **MIPS 软浮点路由器**（如 TP-Link Archer C7、mips_24kc）：设置 `GOMIPS=softfloat` 避免硬件 FPU 缺失导致崩溃
- **低内存设备**：使用 `GOMEMLIMIT=24MiB` 或 `GODEBUG=asyncpreemptoff=1` 缓解 OOM
- **代理服务**：通过 `--socks5-server` / `--outbound-http-proxy-listen` 暴露 SOCKS5 / HTTP 代理给局域网

### 命令示例

```sh
# 注入环境变量
uci add_list tailscale.settings.extra_env='GOMIPS=softfloat'
uci add_list tailscale.settings.extra_env='GOMEMLIMIT=24MiB'

# 注入 tailscaled 命令行参数（每项作为独立参数）
uci add_list tailscale.settings.extra_args='--socks5-server=192.168.10.1:1080'
uci add_list tailscale.settings.extra_args='--outbound-http-proxy-listen=192.168.10.1:1081'

uci commit tailscale
/etc/init.d/tailscale restart
```

### 说明

- `extra_env` 的每一项必须是 `KEY=VALUE` 形式，原样传给 `procd_append_param env`
- `extra_args` 的每一项必须是独立参数（含 `=` 的长选项无需拆分），按顺序追加到 `tailscaled` 命令尾部
- 这两个选项不经任何转义或校验，错误的值会导致 `tailscaled` 启动失败；可用 `logread -e tailscale` 排查
- 用户空间模式下脚本默认会注入 `--socks5-server` / `--outbound-http-proxy-listen`（端口 1055/1056）；若 `extra_args` 已包含其中之一，脚本会跳过对应默认值，避免出现重复的 listener
- 若通过 `extra_env` 设置了 `TS_DEBUG_FIREWALL_MODE`，脚本会跳过自动检测的 `nftables`/`iptables`，保证你的覆盖生效
