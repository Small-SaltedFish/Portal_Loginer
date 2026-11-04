#!/bin/sh
# Upgrade legacy 1.3 packages that disable autostart and do not declare conffiles.
set -eu
[ "$(id -u)" = 0 ] || { echo '请以 root 运行'; exit 1; }
allow_downgrade=0
if [ "${1:-}" = --allow-downgrade ]; then allow_downgrade=1; shift; fi
[ "$#" = 1 ] && [ -f "$1" ] || { echo "用法: sh $0 [--allow-downgrade] /path/package.ipk"; exit 64; }
package=$(readlink -f "$1")
control=$(tar -xzOf "$package" ./control.tar.gz | tar -xzOf - ./control)
package_name=$(printf '%s\n' "$control" | sed -n 's/^Package: //p')
expected_version=$(printf '%s\n' "$control" | sed -n 's/^Version: //p')
[ "$package_name" = luci-app-portal-login ] && [ -n "$expected_version" ] || { echo '不是本插件的有效安装包' >&2; exit 64; }
backup=$(mktemp -d /root/portal-login-upgrade.XXXXXX)
chmod 700 "$backup"
was_enabled=0; was_running=0
if [ -x /etc/init.d/portal-login ]; then
    if /etc/init.d/portal-login enabled; then was_enabled=1; fi
    if /etc/init.d/portal-login running; then was_running=1; fi
fi
[ ! -f /etc/config/portal_login ] || cp -p /etc/config/portal_login "$backup/portal_login"
printf '%s\n' "$was_enabled" > "$backup/enabled"
printf '%s\n' "$was_running" > "$backup/running"
echo "升级前备份: $backup（包含账号配置，仅 root 可读）"
install_ok=0
if [ "$allow_downgrade" = 1 ]; then
    if opkg --force-downgrade install "$package"; then install_ok=1; fi
else
    if opkg install "$package"; then install_ok=1; fi
fi
if [ "$install_ok" != 1 ]; then
    if [ -f "$backup/portal_login" ]; then cp -p "$backup/portal_login" /etc/config/portal_login; fi
    if [ "$was_enabled" = 1 ]; then /etc/init.d/portal-login enable || true;
    else /etc/init.d/portal-login disable || true; fi
    echo "安装失败，保留备份供恢复: $backup" >&2
    exit 1
fi
installed_version=$(opkg status luci-app-portal-login | sed -n 's/^Version: //p')
if [ "$installed_version" != "$expected_version" ]; then
    echo "安装器未切换到目标版本 $expected_version，当前仍是 $installed_version；未宣告升级成功" >&2
    exit 1
fi
if [ -f "$backup/portal_login" ]; then
    cp -p "$backup/portal_login" /etc/config/portal_login
    chmod 600 /etc/config/portal_login
fi
if [ "$was_enabled" = 1 ]; then /etc/init.d/portal-login enable;
else /etc/init.d/portal-login disable; fi
if [ "$was_running" = 1 ]; then /etc/init.d/portal-login start; fi
echo '升级完成，配置、自启动和原先运行状态已恢复。'
