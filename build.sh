#!/bin/sh
# build.sh — 从 src/ 目录构建 ipk 安装包
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
VERSION=$(grep 'readonly VERSION=' "$SCRIPT_DIR/src/usr/bin/portal-login" | head -1 | cut -d'"' -f2)
PKG_NAME="luci-app-portal-login_${VERSION}_all.ipk"
BUILD_DIR="/tmp/portal-login-build-$$"

echo "构建 $PKG_NAME ..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/data" "$BUILD_DIR/ctrl"

# 复制源文件到 data（保持目录结构）
cd "$SCRIPT_DIR/src"
find . -type f | while read f; do
    mkdir -p "$BUILD_DIR/data/$(dirname "$f")"
    cp "$f" "$BUILD_DIR/data/$f"
done

chmod 755 "$BUILD_DIR/data/usr/bin/portal-login"
chmod 755 "$BUILD_DIR/data/usr/libexec/rpcd/portal-login"
chmod 755 "$BUILD_DIR/data/etc/init.d/portal-login"
chmod 755 "$BUILD_DIR/data/etc/hotplug.d/iface/99-portal-login"

# control 文件
cat > "$BUILD_DIR/ctrl/control" <<EOF
Package: luci-app-portal-login
Version: $VERSION
Depends: libc, curl, libopenssl3, openssl-util, luci-base, rpcd
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
/etc/init.d/rpcd reload 2>/dev/null
exit 0
POSTINST
chmod 755 "$BUILD_DIR/ctrl/postinst"

# prerm
cat > "$BUILD_DIR/ctrl/prerm" <<'PRERM'
#!/bin/sh
[ -z "$IPKG_INSTROOT" ] || exit 0
/etc/init.d/portal-login stop 2>/dev/null
/etc/init.d/portal-login disable 2>/dev/null
exit 0
PRERM
chmod 755 "$BUILD_DIR/ctrl/prerm"

# debian-binary
echo "2.0" > "$BUILD_DIR/debian-binary"

# 打包
cd "$BUILD_DIR/data" && tar czf "$BUILD_DIR/data.tar.gz" .
cd "$BUILD_DIR/ctrl" && tar czf "$BUILD_DIR/control.tar.gz" ./control ./postinst ./prerm
cd "$BUILD_DIR"
tar czf "$SCRIPT_DIR/$PKG_NAME" ./debian-binary ./control.tar.gz ./data.tar.gz

rm -rf "$BUILD_DIR"
echo "构建完成: $PKG_NAME"
