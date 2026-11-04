#!/bin/sh
# Isolated behavioral tests: no real UCI, network, authentication, or service changes.
set -u
cd "$(dirname "$0")/.." || exit 1
TEST_ROOT=$(mktemp -d /tmp/portal-login-tests.XXXXXX) || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT
sed '$d' src/usr/bin/portal-login > "$TEST_ROOT/core"
. "$TEST_ROOT/core"
STATUS_FILE="$TEST_ROOT/status"
LOG_FILE="$TEST_ROOT/log"
PID_FILE="$TEST_ROOT/pid"
LOCK_FILE="$TEST_ROOT/lock"
COOKIE_FILE="$TEST_ROOT/cookies"
CFG_USER=test-user
CFG_PASS=test-pass
scenario=online
wan_up=true
wan_address=10.23.45.67
route_ready=1
api_calls="$TEST_ROOT/api"
passed=0
failed=0
log_i() { :; }; log_d() { :; }; log_w() { :; }; log_e() { :; }
_save_params_uci() { :; }
uci() { return 1; }
encrypt_pass() { printf '%s\n' encrypted-fixture; }
_network_prepare() { NET_MODE=system; return 0; }
_network_resolve() { echo 203.0.113.10; }
# On OpenWrt, use the actual jsonfilter parser. Windows Git Bash uses Node for fixtures.
if ! command -v jsonfilter >/dev/null 2>&1; then
    jsonfilter() { node tests/jsonfilter.cjs "$@"; }
fi
ubus() {
    printf '{"up":%s,"l3_device":"wan-fixture","ipv4-address":[{"address":"%s"}]}\n' "$wan_up" "$wan_address"
}
ip() {
    [ "$route_ready" = 1 ] || return 1
    printf '%s\n' '223.5.5.5 via 10.23.0.1 dev wan-fixture src 10.23.45.67'
}
curl() {
    local endpoint=""
    for endpoint in "$@"; do :; done
    case "$endpoint" in
        */api/login.php\?*)
            echo login >> "$api_calls"
            case "$scenario" in
                transport) return 28 ;;
                malformed) echo '<html>error</html>' ;;
                password) echo '{"ret": -1, "msg": "bad password"}' ;;
                *) echo '{ "ret" : 0 }' ;;
            esac
            return ;;
        */api/ack_auth.php\?*)
            echo ack >> "$api_calls"
            case "$scenario" in
                ackfail|ackfail-online) echo '{"ret":1}' ;;
                acktimeout) return 28 ;;
                *) echo '{"ret":0}' ;;
            esac
            return ;;
        *192.168.199.200/index.html*) return 0 ;;
    esac
    case "$scenario" in
        online|ackfail-online) echo '204 ' ;;
        timeout204) echo '204 '; return 28 ;;
        timeout|acktimeout|pending|ackfail) echo '000 '; return 28 ;;
        http200) echo '200 ' ;;
        unrelated) echo '302 https://example.org/?bras=phish&clientip=10.23.45.67' ;;
        wrongip) echo '302 http://192.168.199.200/index.html?bras=hn&clientip=10.23.45.1' ;;
        portal301) echo '301 http://192.168.199.200/index.html?bras=hn&clientip=10.23.45.67' ;;
        portal302) echo '302 http://192.168.199.200/index.html?bras=hn&clientip=10.23.45.67' ;;
        *) echo '503 ' ;;
    esac
}
expect() {
    local label="$1" expected="$2" actual
    shift 2
    "$@"; actual=$?
    if [ "$actual" = "$expected" ]; then
        echo "PASS $label"; passed=$((passed+1))
    else
        echo "FAIL $label: expected=$expected actual=$actual"; failed=$((failed+1))
    fi
}
for item in online:1 timeout204:3 timeout:3 http200:3 unrelated:3 wrongip:3 portal301:0 portal302:0; do
    scenario=${item%:*}
    expect "probe/$scenario" "${item#*:}" probe_portal
done
wan_up=false
expect 'cold-boot/no-netifd-address' 2 probe_portal
wan_up=true; route_ready=0
expect 'cold-boot/address-without-route' 4 probe_portal
route_ready=1
for item in online:0 pending:2 ackfail:1 acktimeout:1 ackfail-online:0 malformed:1 password:1 transport:1; do
    scenario=${item%:*}
    P_HOST=http://192.168.199.200; P_BRAS=hn; P_CLIENTIP=$wan_address
    P_WLANUSERIP=$wan_address; P_CLIENTMAC=aa:bb:cc:dd:ee:ff
    : > "$api_calls"
    expect "login/$scenario" "${item#*:}" do_login
    case "$scenario" in
        online|ackfail-online) expect "state/$scenario" 0 test "$(st_get STATE)" = LOGGED_IN ;;
        pending) expect 'state/pending' 0 test "$(st_get STATE)" = VERIFYING ;;
        *) expect "state/$scenario" 0 test "$(st_get STATE)" = FAILED ;;
    esac
done
P_CLIENTIP=10.23.45.1
: > "$api_calls"
expect 'DHCP-change/reject-old-parameters' 1 do_login
expect 'DHCP-change/no-auth-request' 0 test ! -s "$api_calls"
st_set ERROR 'literal & backslash\ "quote"'
expect 'status/literal-characters' 0 test "$(st_get ERROR)" = 'literal & backslash\ "quote"'
CFG_RETRY_INTERVAL=08
expect 'config/reject-octal-like-number' 1 validate_cfg
CFG_RETRY_INTERVAL=3
expect 'config/valid' 0 validate_cfg
echo "RESULT $passed passed, $failed failed"
[ "$failed" = 0 ]
