# luci-app-portal-login 技术文档

> 版本: 1.3 | 最后更新: 2026-03-11
> 本文档记录所有实现细节，可作为 Claude AI 对话上下文恢复参考。

---

## 1. 项目概览

### 1.1 目标

在 OpenWrt 路由器上自动完成校园网 Portal 认证，实现：
- 开机自动登录
- session 过期自动重连
- 每日定时重认证
- LuCI 面板管理

### 1.2 约束

- 纯 POSIX Shell（兼容 busybox ash）
- 不依赖 Python / Node / Lua
- 运行时仅需 `curl` + `openssl`（`libopenssl`）
- 与 Clash / passwall 等代理插件零冲突
- 目标设备：Cudy TR3000 (256MB Flash / 512MB RAM / aarch64 / KWrt)

### 1.3 包信息

- 包名：`luci-app-portal-login`
- 版本：`1.3`
- 架构：`all`（纯脚本，架构无关）
- 大小：约 21KB
- 依赖：`curl`, `libopenssl3`, `openssl-util`, `luci-base`, `rpcd`

---

## 2. Portal 认证机制

### 2.1 核心发现

校园网 AC (Access Controller) 的所有动态参数**全部来自 HTTP 302 重定向的 Location URL**，不能硬编码，必须每次登录前实时获取。

### 2.2 302 重定向示例

当用户未认证时，访问任意 HTTP 地址会被 AC 拦截并 302 重定向：

```
GET http://connecttest.com/
↓ AC 拦截
302 Location: http://192.168.199.200/index.html
    ?bras=hn
    &wlanuserip=10.17.231.135
    &clientip=10.17.231.135
    &wlanacname=hn
    &clientmac=d8:bb:c1:9e:7b:1b
    &paip=172.16.100.200
    &vlan=1407.1051
    &iarmdst=140.143.144.103:8082/
```

### 2.3 参数说明

| 参数 | 含义 | 来源 |
|------|------|------|
| `bras` | 接入服务器标识 | AC 分配 |
| `clientip` / `wlanuserip` | 客户端 IP | DHCP 分配 |
| `wlanacname` | AC 名称 | AC 配置 |
| `clientmac` | 客户端 MAC | AC 检测 |
| `paip` | Portal 认证 IP | AC 配置 |
| `vlan` | VLAN 标识 | AC 检测 |
| Location host | Portal 服务器地址 | AC 配置 |

### 2.4 登录 API

```
POST {portal_host}/api/login.php?bras=X&clientip=X&...
Body: user=账号&pass=AES加密密码&authmode=0&pool=0&isp_id=0&pyacct=0
Response: {"ret":0} = 成功

POST {portal_host}/api/ack_auth.php?bras=X&clientip=X&...
Body: user=账号&pass=AES加密密码&authmode=0&pool=0&isp_id=0&pyacct=0
Response: {"ret":0} = 确认

POST {portal_host}/api/logoff.php?bras=X&clientip=X&clientmac=X-X-X&vlan=X
Response: {"ret":0} = 登出成功
```

### 2.5 返回值

| ret | 含义 |
|-----|------|
| 0 | 成功 |
| 121 | 成功（已在线） |
| 122 | 成功（重复认证） |
| 3 | 成功（某些版本） |
| -1 | 密码错误 |
| 其他 | 失败，读 `msg` 字段 |

### 2.6 密码加密

AES-128-ECB，格式：`4字节随机前缀 + 明文密码 + 零填充到16字节倍数`

```sh
# key 示例: "5a3b9f207411a8ed"（16位 ASCII）
# key 转 hex: 3561336239663230373431316138656
# 使用 openssl:
openssl enc -aes-128-ecb -nosalt -nopad -K {keyhex} -in plaintext -out ciphertext
# 密文转 hex 输出
```

密钥可能变更，程序自动从 portal JS 文件（如 `/assets/js/raas.js`）提取 16 位 ASCII 字符串。

---

## 3. 文件清单与职责

### 3.1 安装文件

| 路径 | 行数 | 职责 |
|------|------|------|
| `/usr/bin/portal-login` | 760 | 主程序守护进程 |
| `/usr/libexec/rpcd/portal-login` | 195 | rpcd 接口（LuCI JS ↔ Shell 后端） |
| `/etc/init.d/portal-login` | 34 | procd 服务（START=95） |
| `/etc/hotplug.d/iface/99-portal-login` | 45 | WAN ifup 触发器 |
| `/etc/config/portal_login` | 11 | UCI 配置文件 |
| `/usr/share/luci/menu.d/luci-app-portal-login.json` | 20 | LuCI 菜单注册 |
| `/usr/share/rpcd/acl.d/luci-app-portal-login.json` | 22 | rpcd ACL 权限 |
| `/www/luci-static/resources/view/portal-login.js` | 520 | LuCI 前端界面 |

### 3.2 运行时文件（tmpfs，重启清空）

| 路径 | 用途 |
|------|------|
| `/tmp/portal-login.status` | 状态 key=value 文件 |
| `/tmp/portal-login.log` | 运行日志（最多 500 行滚动） |
| `/tmp/portal-login.cookies` | curl session cookie |
| `/var/run/portal-login.pid` | PID 文件 |
| `/var/lock/portal-login.lock` | 防重复启动锁 |

---

## 4. 主程序架构 (`/usr/bin/portal-login`)

### 4.1 函数列表

| 函数 | 用途 |
|------|------|
| `load_cfg()` | 从 UCI 读取配置到全局变量 |
| `_save_params_uci()` | portal 参数持久化到 UCI（重启可恢复） |
| `_restore_params_uci()` | daemon 启动时从 UCI 恢复参数 |
| `_get_wan_ip()` | 获取 WAN 接口 IP（判断是否连接） |
| `_refresh_wan_params()` | 从 WAN 接口刷新 clientip/mac |
| `_restore_saved_params()` | 从 status 文件恢复参数 + WAN 刷新 |
| `probe_portal()` | 核心探测（返回 0/1/2） |
| `_parse_portal_url()` | 解析 302 Location URL |
| `detect_key()` | 从 portal JS 文件自动检测 AES 密钥 |
| `encrypt_pass()` | AES-128-ECB 密码加密 |
| `do_logout()` | 调用 logoff API |
| `do_login()` | 完整登录流程 |
| `run_daemon()` | 主循环 |
| `main()` | CLI 入口 |

### 4.2 probe_portal() 返回值

| 返回值 | 含义 | 后续动作 |
|--------|------|---------|
| 0 | 需要登录（P_* 已填充） | detect_key → do_login |
| 1 | 已在线 | sleep check_interval |
| 2 | WAN 未连接或无法探测 | sleep retry_interval |

### 4.3 probe 超时处理链

```
curl connecttest.com → 超时 (000)
    ↓
检查 WAN IP（ip addr show）
    ├─ 无 IP → return 2（WAN 未连接）
    └─ 有 IP → 备用 IP 探测
         ↓
    curl http://1.1.1.1/（纯 IP，绕 DNS）
         ├─ 200 → return 1（在线）
         ├─ 302 + portal 参数 → _parse_portal_url → return 0
         └─ 也超时 → 直连 portal 内网
              ↓
         curl http://192.168.199.200/index.html
              ├─ 可达 → _restore_saved_params → return 0
              └─ 不可达 → return 2
```

### 4.4 主循环状态机

```
IDLE → probe
  ├─ 0 (需登录) → LOGGING_IN → do_login
  │    ├─ 成功 → LOGGED_IN → sleep 30s
  │    └─ 失败 → FAILED → sleep 10s → probe
  ├─ 1 (在线) → LOGGED_IN → sleep 30s → probe
  └─ 2 (断网) → OFFLINE → sleep 10s → probe

每日 relogin_hour:00 → do_logout → IDLE（下一轮 probe 自动重登录）
```

### 4.5 在线日志汇总

为避免日志过于冗长，在线状态的日志采用汇总策略：
- 首次在线：输出 `探测 → 在线`
- 之后每 10 次探测（约 5 分钟）：输出 `在线 ×10 (5m)`
- debug 模式下每次都输出

### 4.6 UCI 持久化参数

登录成功后，portal 参数存入 UCI（不是 tmpfs），重启后可用于 fallback：

```
portal_login.main.last_host='http://192.168.199.200'
portal_login.main.last_bras='hn'
portal_login.main.last_clientip='10.17.231.135'
portal_login.main.last_clientmac='d8:bb:c1:9e:7b:1b'
portal_login.main.last_paip='172.16.100.200'
portal_login.main.last_vlan='1407.1051'
```

### 4.7 busybox ash 兼容性注意

- 不使用嵌套函数定义（busybox ash 对 local function 支持不一致）
- `load_cfg()` 中直接调用 `uci -q get` 而非封装子函数
- `_log()` 输出到 stderr（`>&2`），避免污染 `$()` 命令替换的 stdout
- `_sleep()` 用 while 循环而非 `sleep $s`（便于信号响应）

---

## 5. 自启动机制

### 5.1 procd 服务 (`/etc/init.d/portal-login`)

```sh
USE_PROCD=1
START=95          # 网络(20) uhttpd(80) 之后
procd_set_param respawn 30 5 0   # 崩溃后 30s 重启，永不放弃
procd_add_reload_trigger "portal_login"  # UCI 变更自动 reload
```

### 5.2 hotplug 触发器 (`/etc/hotplug.d/iface/99-portal-login`)

- 仅响应 `wan` 和 `pppoe-wan` 的 `ifup` 事件（不响应 `wan6`）
- 60 秒防抖锁（防止短时间重复触发）
- 检查 procd 服务状态 + PID 文件兜底
- 守护进程已在运行则跳过（主循环会自动 probe）

### 5.3 启动时序

```
上电
 ├─ procd START=95 → portal-login daemon
 │    └─ _restore_params_uci() → 恢复缓存参数
 │    └─ run_daemon() → 主循环 → probe → login
 └─ WAN ifup → hotplug 99-portal-login
      └─ sleep 5 → 检查 daemon → 已运行则跳过
```

---

## 6. rpcd 接口 (`/usr/libexec/rpcd/portal-login`)

### 6.1 方法签名

| 方法 | 参数 | 说明 |
|------|------|------|
| `get_status` | 无 | 返回状态、portal 参数、在线时长等 |
| `get_logs` | `lines: int` | 返回最近 N 行日志 |
| `get_config` | 无 | 返回 UCI 配置（密码不回传，仅返回 has_pass） |
| `set_config` | 所有配置字段 | 写入 UCI 并 commit |
| `do_action` | `action: string` | 执行操作 |

### 6.2 do_action 支持的操作

| action | 实际执行 |
|--------|---------|
| `start` | `/etc/init.d/portal-login start` |
| `stop` | `/etc/init.d/portal-login stop` |
| `restart` | `/etc/init.d/portal-login restart` |
| `login` | `portal-login login &`（后台） |
| `relogin` | `portal-login relogin &`（后台） |
| `probe` | `portal-login probe &`（后台） |
| `logs_clear` | `> /tmp/portal-login.log` |

### 6.3 JSON 输入解析

使用 OpenWrt 内置的 `jsonfilter` 解析 stdin JSON，每个字段单独调用（避免嵌套函数兼容问题）。

---

## 7. LuCI 前端 (`portal-login.js`)

### 7.1 技术栈

- LuCI 原生 JS API：`rpc.declare()` + `view.extend()` + `poll.add()`
- 纯手写 DOM（无框架），CSS-in-JS（变量+暗色主题）
- 2 秒轮询状态和日志

### 7.2 界面结构

| 卡片 | 内容 |
|------|------|
| 📡 连接状态 | 状态指示灯、在线时长、失败次数、portal 参数、上次登录/检查时间、错误信息 |
| ⚙️ 操作控制 | 立即登录、启动、停止、重启 |
| 📋 配置 | 账号密码、探测URL、AES密钥、定时策略、开机自启、调试开关 |
| 📄 运行日志 | 带颜色高亮的实时日志，可选行数，清空/刷新 |

### 7.3 状态映射

| 后端 STATE | 前端显示 | 指示灯 |
|-----------|---------|--------|
| LOGGED_IN | 已登录 ✓ | 绿色脉冲 |
| LOGGING_IN | 登录中... | 黄色 |
| FAILED | 登录失败 | 红色 |
| OFFLINE | 网络离线 | 灰色 |
| STOPPED | 服务停止 | 灰色 |
| IDLE | IDLE | 默认 |

### 7.4 暗色主题

自动检测三种暗色模式：
1. `body.classList.contains('dark')`
2. `body.getAttribute('data-theme') === 'dark'`
3. `window.matchMedia('(prefers-color-scheme:dark)')`

通过 `MutationObserver` 监听 body 属性变化实时切换。

---

## 8. UCI 配置项

```
config portal-login 'main'
    option enabled        '1'       # 是否启用
    option user           ''        # 校园网账号
    option pass           ''        # 密码（明文）
    option key            '5a3b9f207411a8ed'  # AES-128-ECB 密钥（16位ASCII）
    option probe_url      'http://connecttest.com/'  # 触发302的HTTP地址
    option check_interval '30'      # 在线检测间隔（秒）
    option retry_interval '10'      # 失败重试间隔（秒）
    option relogin_hour   '4'       # 每日重新登录时间（0-23，-1禁用）
    option log_max        '500'     # 日志最大行数
    option debug          '0'       # 调试日志开关

    # 以下为运行时自动维护（参数持久化），用户不应手动修改
    option last_host      ''        # 上次 portal 服务器地址
    option last_bras      ''        # 上次 bras
    option last_clientip   ''       # 上次客户端 IP
    option last_clientmac  ''       # 上次客户端 MAC
    option last_paip       ''       # 上次 portal auth IP
    option last_vlan       ''       # 上次 VLAN
```

---

## 9. 已知问题与解决方案

### 9.1 代理工具劫持（passwall / clash）

**问题**：passwall 等透明代理通过 nftables/iptables 劫持路由器 OUTPUT 链，portal-login 的 curl 被送进代理通道，session 过期时代理也出不去，导致超时。

**当前方案**：
- `--noproxy '*'` 绕 HTTP 层代理（对 iptables REDIRECT 无效）
- probe 超时后用纯 IP 备用探测 + portal 内网直连 fallback
- 建议用户在代理工具中关闭"路由器本身走代理"

**曾尝试但失败的方案**：
- nftables raw 优先级 notrack：passwall 使用 TPROXY（不依赖 conntrack），notrack 无效
- passwall 直连列表：添加 IP 后仍被劫持

### 9.2 busybox ash 嵌套函数

**问题**：早期版本在 `load_cfg()` 中定义嵌套函数 `_g()`，部分 busybox 版本下 `_g()` 无法正确捕获外部变量。

**解决**：v1.2-20 起改为直接调用 `uci -q get`，不使用嵌套函数。

### 9.3 daemon 重复启动

**问题**：`wan` 和 `wan6` 的 ifup 事件各触发一次 hotplug，导致 daemon 被 procd 重启两次。

**解决**：hotplug 只响应 `wan`（不含 `wan6`），并加 60 秒防抖锁文件。

### 9.4 首次运行无缓存参数

**问题**：首次安装后如果 curl 被代理劫持或 AC 行为异常，拿不到 302 参数，无法 fallback。

**解决**：日志提示用户手动执行 `portal-login login`（此时代理未启动或可临时关闭），获取参数后持久化到 UCI，后续自动恢复。

---

## 10. 版本历史

| 版本 | 关键变更 |
|------|---------|
| 1.0 | 初始版本，CGI Web UI |
| 1.1 | 改用 LuCI 原生 JS 界面 + rpcd |
| 1.2 | 多轮迭代修复（1.2-18 ~ 1.2-23） |
| 1.2-19 | 所有 curl 加 `--noproxy '*'`，UCI 持久化 portal 参数 |
| 1.2-20 | 修复 busybox ash 嵌套函数兼容，修复 hotplug 重复触发 |
| 1.2-21 | 重写 probe 逻辑：WAN IP 检测分离超时与断网 |
| 1.2-22 | 添加 nftables bypass（后证实对 TPROXY 无效） |
| 1.2-23 | 移除 bypass 代码，日志重构（汇总策略） |
| 1.3 | 去掉 GUI 探测按钮，精简界面，正式版 |

---

## 11. 构建 ipk

ipk 实际是一个 tar.gz，内含三个文件：

```
debian-binary          # 内容："2.0\n"
control.tar.gz         # 包含 control / postinst / prerm
data.tar.gz            # 实际安装文件
```

### 构建命令

```sh
# 准备目录结构
mkdir -p pkg/data/usr/bin pkg/data/etc/config ...

# 打包 data
cd pkg/data && tar czf ../data.tar.gz . && cd ..

# 打包 control
cd pkg/ctrl && tar czf ../control.tar.gz ./control ./postinst ./prerm && cd ..

# 组装 ipk
tar czf luci-app-portal-login_1.3_all.ipk ./debian-binary ./control.tar.gz ./data.tar.gz
```

### control 文件

```
Package: luci-app-portal-login
Version: 1.3
Depends: libc, curl, libopenssl3, openssl-util, luci-base, rpcd
Architecture: all
Maintainer: portal-login
Section: luci
Description: OpenWrt LuCI 校园网 Portal 自动认证插件
```

---

## 12. 调试指南

### 12.1 开启 debug 模式

```sh
uci set portal_login.main.debug=1
uci commit portal_login
/etc/init.d/portal-login restart
portal-login logs 100
```

### 12.2 手动探测

```sh
# 模拟 probe 看 302 是否正常
curl --noproxy '*' --max-redirs 0 -o /dev/null \
    -w "%{http_code} %{redirect_url}" http://connecttest.com/

# 直连 portal 服务器
curl --noproxy '*' -v http://192.168.199.200/index.html 2>&1 | head -20

# 检查 WAN IP
ip -4 addr show dev eth1

# 检查 portal 参数缓存
uci show portal_login | grep last_
cat /tmp/portal-login.status
```

### 12.3 常见问题排查

| 症状 | 可能原因 | 排查命令 |
|------|---------|---------|
| probe 一直超时 | 代理劫持 / DNS 不通 | `curl --noproxy '*' http://1.1.1.1/` |
| 登录失败 ret=-1 | 密码错误 | 重新设置密码 |
| 登录失败 ret=空 | portal 返回非 JSON | `portal-login login --debug` |
| AES 加密失败 | openssl 未安装 | `opkg install libopenssl3 openssl-util` |
| LuCI 页面不出现 | rpcd 未重载 | `/etc/init.d/rpcd reload` |
| daemon 未运行 | procd 服务未启动 | `/etc/init.d/portal-login start` |
| WAN 无 IP | 光猫/网线问题 | `ip addr show` |

---

## 13. 适配其他学校

如需适配不同校园网 portal，主要修改以下函数：

### 13.1 `_parse_portal_url()`

解析 302 Location URL 中的参数。不同学校的参数名可能不同。

### 13.2 `do_login()`

登录 API 的 URL 路径、POST 参数、返回值格式可能不同。

### 13.3 `encrypt_pass()`

加密方式可能不同（AES-CBC、MD5、Base64 等）。

### 13.4 `detect_key()`

密钥位置和格式可能不同。

### 13.5 probe 判断逻辑

302 Location 中的特征参数（`bras=`、`wlanuserip=` 等）可能不同，需调整 `probe_portal()` 中的 case 匹配。
