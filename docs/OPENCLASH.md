# 与 OpenClash 共存：探针独立直连配置

## 先分清三个概念

- **探针**是检测地址：主探针加两个备用，共三个，按顺序检查。
- **出网路径**只有当前实际使用的一条，不需要在面板选择多个“通道”。
- **兼容设置**使探针绕过 OpenClash，检查校园网本身，不受代理节点故障影响。

没有安装 OpenClash 时，不需要本页任何规则，PortalLogin 直接使用系统网络。停止 OpenClash 并撤除其代理规则后，也不应阻止正常直连。
安装并启用 OpenClash，尤其要开启“路由本机代理”时，完成以下配套设置。

本页按目标设备已验证的 **OpenClash + firewall4/nftables + Fake-IP 非 TUN + dnsmasq 转发**说明。
原生来源规则的实现覆盖其他传输模式，但其他固件、DNS 劫持方式和传输模式须检查实际规则后再宣称验证通过。

## 为什么不能只写 DIRECT

Mihomo 的 DOMAIN/DIRECT 是进入核心后的分流规则，全局模式不会按普通 rule 模式执行这些规则。
PortalLogin 还必须在核心启动中、代理出口失败时工作，因此要在进入核心前绕过。
`curl --noproxy '*'` 只禁用显式代理，不能单独绕过防火墙透明代理。

本方案只使用 OpenClash 自带的来源流量控制、第二 DNS 和 WAN 绕过地址，不修改订阅、模板、内核二进制或其启动脚本。

## 第一步：设置三个探针的独立 DNS

LuCI：**服务 → OpenClash → 插件设置 → DNS 设置**。

1. 本地 DNS 劫持使用 **Dnsmasq 转发**（`enable_redirect_dns=1`）。本方案依赖 dnsmasq 的域名专用解析，不能直接照搬到“防火墙重定向到核心 DNS”的方式。
2. 开启 **第二 DNS 服务器 / Enable Specify DNS Server**。
3. 指定服务器填写 `223.5.5.5`。如果原本已经设置其他专用上游，先记录原值，按现场验证结果决定，不要覆盖其他业务的 DNS。
4. 在对应的自定义域名列表中，每行添加一个域名，保留已有内容：

```text
connect.rom.miui.com
connectivitycheck.platform.hicloud.com
wifi.vivo.com.cn
```

列表文件是 `/etc/openclash/custom/openclash_custom_domain_dns.list`。
这些域名应返回真实 IP，不应返回 `198.18.0.0/16` Fake-IP。不要把所有浏览域名加进这个列表。

**主探针设置仍有效。** 更换主探针域名时，先将新域名加入此列表并应用 OpenClash 设置，再在 PortalLogin 保存新 URL。
未加入时 PortalLogin 会说明原因并拒绝保存，保留原设置；华为、vivo 两个备用不被主探针设置替换。
自定义地址必须在正常联网时返回 HTTP 204，普通返回 200 的网页不能替代。

## 第二步：保护这个 DNS 上游本身

LuCI：**服务 → OpenClash → 插件设置 → 黑白名单**。

找到 **不走代理的 WAN IP / WAN Bypassed Host List**（`wan_ac_black_ips`），**追加** `223.5.5.5`，保留已有条目。
这是解析器访问专用 DNS 的恢复出口；否则本机代理可能把 dnsmasq 的查询再次送进核心，形成依赖循环。
如果选用其他专用 DNS，绕过条目也必须匹配实际服务器，并重新验证。

第二 DNS 在此使用传统 DNS 端口。它是三个运维域名的明确例外，不能称为“所有 DNS 都加密”。普通浏览域名仍使用各自的 OpenClash 加密 DNS 策略。

## 第三步：添加一条原生来源流量绕过规则

LuCI：**服务 → OpenClash → 插件设置页面底部 → 来源流量访问控制 / Lan Traffic Access List**。
它是页面底部的独立列表，不在订阅规则编辑器中。

添加一行，按下表填写：

| 字段 | 填写值 | 作用 |
|---|---|---|
| 备注 | `PortalLogin_Direct_42` | 插件据此识别配套规则，大小写一致 |
| 启用 | 开启 | 生成原生防火墙规则 |
| 内部地址 / src_ip | 留空 | 不固定 WAN 地址，适应 DHCP 换址 |
| 内部端口 / src_port | `0-65535` | 不依赖 curl 临时源端口 |
| 协议 / proto | TCP+UDP / `both` | 覆盖相应的 OUTPUT 代理链 |
| 地址族 / family | IPv4 / `ipv4` | PortalLogin 探针固定使用 IPv4 |
| 接口 / interface | 留空 | 本机发出的请求不能误写成入接口匹配 |
| 用户 / user | root / UID `0` | 仅本机 root 进程，不让 LAN 设备匹配 |
| DSCP / dscp | `42` | 仅匹配本插件专门标记的请求 |
| 目标 / target | RETURN / `return` | 进入核心之前直接绕过 |

**用户和 DSCP 两个条件必须都保留。** 不要为了方便只设置 root 然后把所有路由器请求绕过；也不要把所有端口加入 WAN 绕过端口列表。
其他 root 程序如主动使用同一 DSCP，也会命中；这是一项流量选择机制，不是权限隔离边界。

若页面没有 UID/DSCP 字段，该 OpenClash 版本不适合直接照此配置。不要删除匹配条件后扩大规则范围；先检查版本及对应原生功能。

保存并应用 OpenClash 设置，检查启动日志没有规则添加错误。

## 第四步：启用 PortalLogin 的请求标记

需要 **curl ≥8.9.0**，并支持 `--ip-tos`。TOS=168 对应 DSCP=42、ECN=0。
在路由器 SSH 或 LuCI 终端执行：

```sh
uci set portal_login.main.direct_tos='168'
uci commit portal_login
/etc/init.d/portal-login restart
```

这个数字与第三步配套，不是一个待测速的代理线路选项，所以不在普通设置页增加选择框。
不熟悉终端时可以请管理路由器的人完成这三行配置；不要把账号密码写进命令或截图。
此后可以开启 OpenClash 的 **插件设置 → 流量控制 → 路由本机代理**，并重新应用设置。

PortalLogin 设置页仅在检测到 OpenClash 时显示共存提醒及本文链接。运行时缺少配套绕过规则时，状态会明确显示未确认，不借代理出口伪装校园网探测。

## 第五步：验证

先保持校园账号在线，避免把两个不同故障混在一起。

1. 普通状态下三个探针应返回 204，PortalLogin 没有重复认证。
2. 重启 PortalLogin，应重新检查网络，不主动校园登出。
3. 本机代理开启时，分别验证 rule、global、direct。将代理出口临时设为不可用前，准备手机热点及明确的回退步骤。
4. 确认代理请求失败而探针仍 204，原生绕过规则计数增长，之后恢复原模式和策略组。
5. 最后再由用户手动注销校园登录，观察真实认证跳转与一次自动恢复。

熟悉终端的管理员可只读查看：

```sh
nft list chain inet fw4 openclash_output
nft list chain inet fw4 openclash_mangle_output
```

已验证的非 TUN 例子中，应看到包含 `meta skuid 0`、`ip dscp 0x2a`、`return` 和备注 `PortalLogin_Direct_42` 的规则；0x2a 即十进制 42。实际链名随模式变化。
不能只凭节点列表的延迟标记或某次界面“登录成功”代替网络验证。

## 撤销或卸载 OpenClash

没有安装 OpenClash 时，插件自动使用系统网络，不需要配置另一条“通道”。
若保留 OpenClash 但要撤销这项集成：先关闭路由本机代理，再禁用本页添加的来源规则；仅删除本次追加且其他业务不需要的 DNS 域名与上游绕过条目，然后清除标记并重启 PortalLogin：

```sh
uci -q delete portal_login.main.direct_tos
uci commit portal_login
/etc/init.d/portal-login restart
```

保留其他业务原有设置。撤销后仍要验证 Fake-IP、DNS 和实际出口，不能假定关闭本机代理会同时移除全部 DNS 依赖。

## 权威参考

- [OpenClash 用户指南入口](https://raw.githubusercontent.com/vernesong/OpenClash/dev/.github/skills/openclash-user-guide/SKILL.md)
- [DNS 设置 §9.1、WAN 绕过地址 §9.2.6](https://raw.githubusercontent.com/vernesong/OpenClash/dev/.github/skills/openclash-user-guide/09-settings-dns-ac-ipv6.md)
- [来源流量控制 §10.3](https://raw.githubusercontent.com/vernesong/OpenClash/dev/.github/skills/openclash-user-guide/10-settings-geo-misc-src.md)
- [防火墙与本机 DNS 行为 §6.2–6.3](https://raw.githubusercontent.com/vernesong/OpenClash/dev/.github/skills/openclash-user-guide/06-firewall-options-dnsmasq.md)
- [curl --ip-tos](https://curl.se/docs/manpage.html#--ip-tos)
