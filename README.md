# Portal Loginer

OpenWrt / KWrt 的校园网 Portal 自动认证插件，提供 LuCI 面板、守护进程和命令行。
适配本项目使用的 `login.php → ack_auth.php`、AES-128-ECB 校园认证协议，不是通用校园网账号客户端。

**1.4.0** 的检查证据、真实验收和未验证边界见 [REVIEW.md](REVIEW.md)。安装包和升级助手见 [Releases](https://github.com/Small-SaltedFish/Portal_Loginer/releases)。

## 工作方式

1. 从 netifd 获取实际 WAN IPv4 地址，等待地址与出口路由稳定约 10 秒。
2. 优先请求设置页中的主探针；未确认时依次请求华为、vivo 备用探针。
3. 收到 HTTP 204，表示此次直连探测成功。301/302/303/307/308 跳转必须通过认证参数校验，才触发登录。
4. 无 WAN 地址、无路由、超时、HTTP 200/5xx 和普通网页跳转分别处理，不使用缓存盲目反复登录。
5. 登录 API、确认 API、实际联网分别检查。认证已提交但联网未确认时显示“等待联网确认”。

探针失败不能单独证明校园账号已过期。节点失效也不应触发校园登出。必要时界面显示“未确认”，保留会话并继续检查。

## 三个探针

| 顺序 | 地址 | 用途 |
|---|---|---|
| 1 | 设置页的主探针；默认 `http://connect.rom.miui.com/generate_204` | 正常情况下只请求它 |
| 2 | `http://connectivitycheck.platform.hicloud.com/generate_204` | 主探针未确认时回退 |
| 3 | `http://wifi.vivo.com.cn/generate_204` | 前两个未确认时回退 |

它们按顺序检查，不是每轮并发请求三个。确认在线或发现有效认证跳转后立即结束本轮。
自定义主探针应为成功返回 **204** 的纯 HTTP 地址；HTTP 用于让 AC 可以返回认证跳转，不能直接替换为普通返回 200 的网站。

## 安装、升级和回退

需要 `busybox`（含 flock）、`curl`、`openssl-util`、`libopenssl3`、`jsonfilter`、`jshn`、`luci-base` 和 `rpcd`。
主程序会检查 flock 等运行命令。部分固件的 BusyBox 未启用 flock，需从该固件的软件源安装对应工具，不能省略互斥保护。

构建：

```sh
sh build.sh
```

首次安装使用构建出的 ipk，并在 LuCI“服务 → Portal 自动登录”填写账号。
启用插件和启动项后，启动守护进程。密码保存在路由器 UCI 配置，文件权限为 600；不要把现场配置或日志提交仓库。

**从 1.3 升级请使用升级助手。** 旧包没有 conffiles，并可能在升级时关闭启动项。助手在安装前保存账号配置、自启动和运行状态，安装后恢复：

```sh
sh install-upgrade.sh /path/to/luci-app-portal-login_VERSION_all.ipk
```

助手打印 root 私有备份目录。请保留原版 ipk 和该目录，验证后再清理。配置文件不同而产生 `portal_login-opkg` 提示时，保留现有配置是预期行为。
助手会核对包名及实际安装版本；包管理器跳过安装时不会空报成功。仅明确要降级时使用 `--allow-downgrade`，例如从本次临时 rc 包切换到正式包。
回退应先保存现场配置，再用相应固件的包管理器降级到原包，并恢复原配置和启动项；不要删除配置后重新填写密码。

## 与 OpenClash 共存

PortalLogin 检查校园网出口，不能把代理节点的健康状况当作校园账号状态。
单独使用 `--noproxy` 或 Mihomo `DIRECT` 规则不能保证绕过透明代理，尤其要验证全局模式。

推荐使用 OpenClash **原生**设置保护探针直连。逐项填写、验证和撤销方法见 **[OpenClash 共存配置详解](docs/OPENCLASH.md)**：

1. 插件设置 → DNS：开启第二 DNS，三个探针域名使用独立上游，例如 `223.5.5.5`。普通浏览域名不加入此列表。
2. 将这个 DNS 上游 IP 加入本机流量的绕过地址，防止 dnsmasq 的上游请求又进入代理。
3. 插件设置页面底部 → 来源流量访问控制：增加一条 `user=0`、`dscp=42`、`proto=both`、`family=ipv4`、`src_port=0-65535`、`target=RETURN`、启用的规则，备注使用 `PortalLogin_Direct_42`。接口和来源地址留空。
4. PortalLogin 的兼容配置设为 `direct_tos=168`，使自身 curl 请求携带对应 DSCP 标记。需要 curl 8.9.0 或以上。
5. 重载 OpenClash 并检查实际规则命中后，重启 PortalLogin。设置页会在检测到 OpenClash 时显示兼容提醒和详细文档链接。此后可以开启路由器本机代理。

```sh
uci set portal_login.main.direct_tos='168'
uci commit portal_login
/etc/init.d/portal-login restart
```

标记和原生 RETURN 规则必须配套。插件发现规则不正确时会显示未确认，避免通过代理探测。没有 OpenClash 时直接使用系统网络，不显示兼容提醒。
开启兼容设置后，自定义主探针域名须先加入第二 DNS 列表，否则面板拒绝保存并说明原因；不能让它解析成 Fake-IP 再进入核心。
这不是安全访问控制边界：其他 root 程序如主动使用相同标记，也会匹配这条绕过规则。

第二 DNS 的 UDP/TCP 53 查询属于明确保留的运维例外，**不是所有 DNS 均加密**。普通域名的加密解析和分流由 OpenClash 独立配置，不应为了探针而放开所有域名。

参考：[OpenClash 来源流量控制 §10.3](https://raw.githubusercontent.com/vernesong/OpenClash/dev/.github/skills/openclash-user-guide/10-settings-geo-misc-src.md)、[DNS §9.1](https://raw.githubusercontent.com/vernesong/OpenClash/dev/.github/skills/openclash-user-guide/09-settings-dns-ac-ipv6.md)、[curl --ip-tos](https://curl.se/docs/manpage.html#--ip-tos)。

## 设置与操作

| 设置 | 范围 / 行为 |
|---|---|
| 主探针 URL | 优先检查；失败后仍有两个固定备用 |
| 检查间隔 | 5–600 秒，默认 30 |
| 首次失败重试间隔 | 3–300 秒，默认 10；连续失败倍增，最高 300 秒 |
| 每日重登录小时 | -1 禁用，或 0–23；已有配置升级时保留 |
| 日志行数 | 50–5000，默认 500 |
| 启用及开机自启 | 保存后同步启动项；运行配置重启守护进程生效 |
| 详细日志 | 默认关闭，不输出明文密码 |

“重启”只重载守护进程，不主动登出。“立即登录”在明确需要认证时登录；在线且参数有效时会尝试重新认证，可能短暂断网。状态不明时不主动登出。

```sh
portal-login status
portal-login probe
portal-login logs 100
/etc/init.d/portal-login restart
```

`probe` 会更新经过验证的门户参数，但不会执行登录。并发操作只允许一个认证事务，忙碌时返回 75。

## 故障排查与验证

先看界面的状态、错误说明和日志：等待 DHCP、等待路由、探测未确认、接口失败分别处理。
冷启动期间会定期记录 WAN、DHCP 和路由诊断，不会自动重启路由器或反复重拨 WAN。

设备端隔离回归：

```sh
sh tests/core.sh
sh tests/rpc.sh
sh tests/locking.sh
sh tests/daemon.sh
sh tests/package.sh
```

模拟测试不会真实登录或修改 WAN。真实校园注销、光猫与 KWrt 同时启动、代理不可用和普通 LAN 设备联网仍须现场验收。
详细状态机、文件、接口及参数见 [TECHNICAL.md](TECHNICAL.md)，变更见 [CHANGELOG.md](CHANGELOG.md)。
