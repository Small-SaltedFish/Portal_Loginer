#!/bin/sh
# Installation metadata, tested even when the caller's umask is restrictive.
set -e
cd "$(dirname "$0")/.."
root=$(mktemp -d /tmp/portal-package-tests.XXXXXX)
trap 'rm -rf "$root"' EXIT
(umask 077; sh build.sh)
version=$(sed -n 's/^readonly VERSION="\([^"]*\)"/\1/p' src/usr/bin/portal-login)
tar -xzf "luci-app-portal-login_${version}_all.ipk" -C "$root"
mkdir "$root/data" "$root/control"
tar -xzf "$root/data.tar.gz" -C "$root/data"
tar -xzf "$root/control.tar.gz" -C "$root/control"
for path in . etc etc/config etc/init.d usr usr/bin usr/libexec usr/libexec/rpcd usr/share www www/luci-static/resources/view; do
    mode=$(stat -c '%a' "$root/data/$path")
    [ "$mode" = 755 ] || { echo "FAIL directory permission $path=$mode"; exit 1; }
done
echo 'PASS all shared package directories remain 755 under umask 077'
[ "$(stat -c '%a' "$root/data/etc/config/portal_login")" = 600 ]
echo 'PASS credential configuration remains 600'
grep -qx '/etc/config/portal_login' "$root/control/conffiles"
echo 'PASS conffiles protects configuration'
for path in usr/bin/portal-login usr/libexec/rpcd/portal-login etc/init.d/portal-login etc/hotplug.d/iface/99-portal-login; do
    [ "$(stat -c '%a' "$root/data/$path")" = 755 ]
    sh -n "$root/data/$path"
done
echo 'PASS executable modes and package shell syntax'
echo 'RESULT 4 passed, 0 failed'
