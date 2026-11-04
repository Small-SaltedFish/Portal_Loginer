#!/bin/sh
# build.sh — 从 src/ 目录构建 ipk 安装包
set -e
# 调用者可能用 umask 077 保护配置备份；包内共享目录必须始终可遍历。
umask 022

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
VERSION=$(grep 'readonly VERSION=' "$SCRIPT_DIR/src/usr/bin/portal-login" | head -1 | cut -d'"' -f2)
PKG_NAME="luci-app-portal-login_${VERSION}_all.ipk"
BUILD_DIR=$(mktemp -d /tmp/portal-login-build.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
trap 'exit 1' INT TERM

echo "构建 $PKG_NAME ..."

mkdir -p "$BUILD_DIR/data" "$BUILD_DIR/ctrl"

# 复制源文件到 data（保持目录结构）
cd "$SCRIPT_DIR/src"
find . -type f | while read f; do
    mkdir -p "$BUILD_DIR/data/$(dirname "$f")"
    cp "$f" "$BUILD_DIR/data/$f"
done

chmod 755 "$BUILD_DIR/data/usr/bin/portal-login"
chmod 755 "$BUILD_DIR/data/usr/libexec/rpcd/portal-login"
chmod 755 "$BUILD_DIR/data/usr/libexec/portal-login-net"
chmod 755 "$BUILD_DIR/data/etc/init.d/portal-login"
chmod 755 "$BUILD_DIR/data/etc/hotplug.d/iface/99-portal-login"
chmod 600 "$BUILD_DIR/data/etc/config/portal_login"

# 让 opkg 在升级时保护现场配置（包括账号和密码）。
printf '/etc/config/portal_login\n' > "$BUILD_DIR/ctrl/conffiles"

# control 文件
cat > "$BUILD_DIR/ctrl/control" <<EOF
Package: luci-app-portal-login
Version: $VERSION
Depends: libc, busybox, curl, libopenssl3, openssl-util, luci-base, rpcd, jsonfilter, jshn
Architecture: all
Maintainer: portal-login
Section: luci
Description: OpenWrt LuCI 校园网 Portal 自动认证插件
EOF

# postinst
cat > "$BUILD_DIR/ctrl/postinst" <<'POSTINST'
#!/bin/sh
[ -z "$IPKG_INSTROOT" ] || exit 0
chmod 755 /usr/bin/portal-login 2>/dev/null
chmod 755 /usr/libexec/rpcd/portal-login 2>/dev/null
chmod 600 /etc/config/portal_login 2>/dev/null
# 旧包 prerm 在 upgrade 时也会 disable；preinst 已记录升级前开关。
if [ -f /var/run/portal-login-upgrade.enabled ]; then
    /etc/init.d/portal-login enable 2>/dev/null
    rm -f /var/run/portal-login-upgrade.enabled
elif [ "$1" != configure ]; then
    : # 离线镜像由首次启动处理，不在此擅自启用服务。
fi
/etc/init.d/rpcd reload 2>/dev/null
exit 0
POSTINST
chmod 755 "$BUILD_DIR/ctrl/postinst"

cat > "$BUILD_DIR/ctrl/preinst" <<'PREINST'
#!/bin/sh
[ -z "$IPKG_INSTROOT" ] || exit 0
rm -f /var/run/portal-login-upgrade.enabled
if [ -x /etc/init.d/portal-login ] && /etc/init.d/portal-login enabled; then
    touch /var/run/portal-login-upgrade.enabled
fi
exit 0
PREINST
chmod 755 "$BUILD_DIR/ctrl/preinst"

# prerm
cat > "$BUILD_DIR/ctrl/prerm" <<'PRERM'
#!/bin/sh
[ -z "$IPKG_INSTROOT" ] || exit 0
/etc/init.d/portal-login stop 2>/dev/null
[ "$1" = upgrade ] || /etc/init.d/portal-login disable 2>/dev/null
exit 0
PRERM
chmod 755 "$BUILD_DIR/ctrl/prerm"

# debian-binary
echo "2.0" > "$BUILD_DIR/debian-binary"

# 打包
find "$BUILD_DIR/data" -type d -exec chmod 755 {} \;
cd "$BUILD_DIR/data" && tar czf "$BUILD_DIR/data.tar.gz" .
cd "$BUILD_DIR/ctrl" && tar czf "$BUILD_DIR/control.tar.gz" ./control ./preinst ./postinst ./prerm ./conffiles
cd "$BUILD_DIR"
tar czf "$SCRIPT_DIR/$PKG_NAME" ./debian-binary ./control.tar.gz ./data.tar.gz

rm -rf "$BUILD_DIR"
trap - EXIT
echo "构建完成: $PKG_NAME"
