#!/bin/sh
# Offline regression tests. Network calls and persistent writes are mocked.
set -u
cd "$(dirname "$0")/.." || exit 1
TEST_ROOT=$(mktemp -d /tmp/portal-probe-tests.XXXXXX) || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT
sed '$d' src/usr/bin/portal-login > "$TEST_ROOT/core"
. "$TEST_ROOT/core"
STATUS_FILE="$TEST_ROOT/status"
LOG_FILE="$TEST_ROOT/log"
log_d() { :; }; log_i() { :; }; log_w() { :; }
_get_wan_ip() { [ "$scenario" != nowan ] && echo 10.23.45.67; }
_wan_route_ready() { [ "$scenario" != noroute ]; }
_network_prepare() { NET_MODE=system; return 0; }
_network_resolve() { echo 203.0.113.10; }
_parse_portal_url() { return 0; }
curl() {
    local endpoint=""
    for endpoint in "$@"; do :; done
    case "$scenario:$endpoint" in
        online:*) echo '204 ' ;;
        portal:*) echo '302 http://192.168.199.200/index.html?bras=mlyx&clientip=10.23.45.67' ;;
        backup:*hicloud*) echo '204 ' ;;
        third:*miui*) echo '500 ' ;;
        third:*hicloud*) echo '000 ' ;;
        third:*vivo*) echo '302 http://192.168.199.200/index.html?bras=mlyx&clientip=10.23.45.67' ;;
        redirect:*) echo '302 https://unrelated.example/' ;;
        error:*) echo '503 ' ;;
        *) echo '000 ' ;;
    esac
}
failed=0
for item in online:1 portal:0 backup:1 third:0 timeout:3 redirect:3 error:3 nowan:2 noroute:4; do
    scenario="${item%:*}"; expected="${item#*:}"
    probe_portal; actual=$?
    if [ "$actual" = "$expected" ]; then echo "PASS $scenario";
    else echo "FAIL $scenario expected=$expected actual=$actual"; failed=1; fi
done
exit "$failed"
