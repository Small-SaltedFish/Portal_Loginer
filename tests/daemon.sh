#!/bin/sh
# Deterministic cold-start state-machine test, with isolated files and mocked I/O.
cd "$(dirname "$0")/.." || exit 1
test_root=$(mktemp -d /tmp/portal-daemon-tests.XXXXXX) || exit 1
trap 'rm -rf "$test_root"' EXIT
sed '$d' src/usr/bin/portal-login > "$test_root/core"
. "$test_root/core"
STATUS_FILE="$test_root/status"; LOG_FILE="$test_root/log"
LOCK_FILE="$test_root/lock"; PID_FILE="$test_root/pid"; COOKIE_FILE="$test_root/cookie"
CFG_RELOGIN_HOUR=-1
clock=100; wall_offset=0; step=0; phase=noip; auth_count=0
_up_seconds() { echo "$clock"; }
flock() { return 0; } # This suite tests transitions; locking.sh checks real flock separately.
log_i() { :; }; log_w() { :; }; log_e() { :; }; log_d() { :; }
_restore_params_uci() { :; }
network_diagnostics() { :; }
_refresh_wan_params() { P_CLIENTIP=10.23.45.67; st_set P_CLIENTIP "$P_CLIENTIP"; }
date() {
    case "$1" in +%s) echo "$((clock+wall_offset))" ;; *) command date "$@" ;; esac
}
_get_wan_ip() { [ "$phase" != noip ] && echo 10.23.45.67; }
_wan_route_ready() { [ "$phase" != noroute ]; }
probe_portal() {
    case "$phase" in noip) return 2 ;; online) return 1 ;; *) return 0 ;; esac
}
detect_key() { :; }
do_login() { auth_count=$((auth_count+1)); _set_state LOGGED_IN; return 0; }
fail() { echo "FAIL $1"; exit 1; }
_sleep() {
    _release_lock
    step=$((step+1)); clock=$((clock+$1))
    case "$step" in
        1) [ "$(st_get STATE)" = OFFLINE ] && [ "$auth_count" = 0 ] || fail noip
           echo 'PASS no DHCP address does not authenticate'; phase=noroute ;;
        2) [ "$(st_get STATE)" = WAIT_NETWORK ] && [ "$auth_count" = 0 ] || fail noroute
           echo 'PASS address without route waits'; phase=unstable; wall_offset=3600 ;;
        3|4|5) [ "$(st_get STATE)" = WAIT_NETWORK ] && [ "$auth_count" = 0 ] || fail settling ;;
        6) [ "$(st_get STATE)" = LOGGED_IN ] && [ "$auth_count" = 1 ] || fail firstlogin
           echo 'PASS stable address and route authenticate once despite clock correction'; phase=online ;;
        7) [ "$(st_get STATE)" = LOGGED_IN ] && [ "$auth_count" = 1 ] || fail duplicate
           echo 'PASS online cycle does not repeat authentication'
           echo 'RESULT 4 passed, 0 failed'; exit 0 ;;
        *) fail unexpected-cycle ;;
    esac
}
run_daemon
