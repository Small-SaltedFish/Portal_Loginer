# luci-app-portal-login

OpenWrt 校园网 Portal 自动认证插件 — 纯 Shell 实现，LuCI 原生界面

测试于沈阳建筑大学(SJZU)的中国移动登录门户。

<img width="612" height="525" alt="image" src="https://github.com/user-attachments/assets/cfb6e855-da6a-4d42-aa8a-24d3eff77ee0" />

适用于 DHCP 接入校园网光猫的路由器场景，自动完成 Portal 登录并持续保持在线。

## 特性

- **全自动**：开机自动认证，session 过期自动重连，每日定时重登录
- **零依赖运行时**：纯 POSIX Shell，仅需 `curl` + `openssl`，无 Python/Node/Lua
- **动态参数**：所有 portal 参数（host/bras/ip/mac/vlan）从 302 重定向实时解析，无需硬编码
- **AES 密钥自适应**：自动从 portal JS 文件检测密钥变更
- **LuCI 原生面板**：状态监控、一键操作、配置管理、实时日志
- **断线恢复**：WAN IP 检测 + portal 直连 fallback + UCI 持久化参数，多重保障
- **Clash/passwall 兼容**：WAN 侧认证与 LAN 侧代理完全独立，零冲突

## 适用环境

| 项目 | 说明 |
|------|------|
| 场景 | 路由器 WAN 口接校园网光猫（DHCP 模式） |
| 固件 | OpenWrt / KWrt / ImmortalWrt 等 |
| 架构 | 任意（纯 Shell，架构无关） |
| 测试设备 | Cudy TR3000 (aarch64, KWrt) |

## 安装

### 依赖

```sh
opkg update
opkg install curl libopenssl
```

### 安装插件

```sh
# 上传 ipk 到路由器
scp luci-app-portal-login_1.3_all.ipk root@192.168.1.1:/tmp/

# SSH 安装
ssh root@192.168.1.1
opkg install /tmp/luci-app-portal-login_1.3_all.ipk
```

### 配置

进入 LuCI 面板：**服务 → Portal 自动登录**

1. 填写校园网账号和密码
2. 点击「保存配置」
3. 点击「启动」

其余参数（探测 URL、AES 密钥、检测间隔等）均有默认值，一般无需修改。

## 工作原理

```
路由器上电 → WAN DHCP 获得 IP
    ↓
portal-login 守护进程启动
    ↓
探测: GET http://connecttest.com/
    ↓
AC 拦截 → 302 → http://192.168.x.x/index.html?bras=hn&clientip=...
    ↓
解析全部参数 → AES-128-ECB 加密密码
    ↓
POST /api/login.php → POST /api/ack_auth.php → 认证完成
    ↓
每 30 秒探测在线状态
每天凌晨 4 点强制重新登录（防 session 过期）
```

### 断线自动恢复

```
探测超时 (curl 000)
  ├─ WAN 无 IP → 等待网络恢复
  └─ WAN 有 IP → session 可能过期
       ├─ 备用 IP 探测 (1.1.1.1) → 获取新 302 参数
       └─ 直连 portal 内网 IP → 用缓存参数重新登录
```

## 命令行

```sh
portal-login status         # 查看状态
portal-login probe          # 探测 portal 参数
portal-login login          # 单次登录
portal-login relogin        # 强制重登录
portal-login logs 50        # 查看日志
portal-login test-encrypt   # 测试 AES 加密
/etc/init.d/portal-login restart  # 重启守护进程
```

## 文件结构

```
/usr/bin/portal-login                             # 主程序 (760行)
/usr/libexec/rpcd/portal-login                    # rpcd 接口 (LuCI ↔ 后端)
/etc/init.d/portal-login                          # procd 服务
/etc/hotplug.d/iface/99-portal-login              # WAN ifup 触发器
/etc/config/portal_login                          # UCI 配置
/usr/share/luci/menu.d/luci-app-portal-login.json # LuCI 菜单注册
/usr/share/rpcd/acl.d/luci-app-portal-login.json  # rpcd 权限
/www/luci-static/resources/view/portal-login.js   # LuCI 前端界面
```

## 与代理工具共存

| | portal-login | Clash / passwall |
|--|--|--|
| 作用层 | WAN 侧认证 | LAN 侧代理分流 |
| 监听端口 | 无（纯客户端） | 7890 等 |
| 冲突 | 无 | 无 |

> **注意**：如果代理工具开启了"路由器本身走代理"，portal-login 的 curl 可能被劫持导致超时。建议关闭路由器本身的代理，或在代理工具中将 portal 相关 IP 加入直连列表。若采用国内外分流（如Clash国内流量不进入内核），可以考虑使用 http://connect.rom.miui.com/generate_204 等国内验证连通性url。

## 卸载

```sh
opkg remove luci-app-portal-login
```

## 许可证

Apache 2.0 License

## 致谢

本项目针对特定校园网 Portal 认证系统开发，认证流程可能因学校不同而有差异。如需适配其他学校的 portal，主要修改 `_parse_portal_url()` 和 `do_login()` 函数。
