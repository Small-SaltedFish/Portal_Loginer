#!/bin/sh
# Run on OpenWrt with its real jshn/jsonfilter/uci; all mutable state is isolated.
# jshn.sh 的变量管理不兼容 nounset；按 rpcd 的正常 shell 环境运行。
cd "$(dirname "$0")/.." || exit 1
TEST_ROOT=$(mktemp -d /tmp/portal-login-rpc-tests.XXXXXX) || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir "$TEST_ROOT/config"
printf "config portal-login 'main'\n option user 'before'\n option pass 'fixture-secret'\n" > "$TEST_ROOT/config/portal_login"
set -- test
. ./src/usr/libexec/rpcd/portal-login >/dev/null
STATUS_FILE="$TEST_ROOT/status"
LOG_FILE="$TEST_ROOT/log"
PID_FILE="$TEST_ROOT/pid"
INIT_SCRIPT="$TEST_ROOT/init"
TEST_INIT_ACTIONS="$TEST_ROOT/init-actions"
export TEST_INIT_ACTIONS
printf '#!/bin/sh\nprintf "%%s\\n" "$1" >> "$TEST_INIT_ACTIONS"\n' > "$INIT_SCRIPT"
command chmod 755 "$INIT_SCRIPT"
uci() { command uci -c "$TEST_ROOT/config" "$@"; }
chmod() { case "${2:-}" in /etc/config/portal_login) return 0 ;; *) command chmod "$@" ;; esac; }
passed=0; failed=0
expect() {
    local label="$1" expected="$2" actual
    shift 2
    "$@"; actual=$?
    if [ "$actual" = "$expected" ]; then echo "PASS $label"; passed=$((passed+1));
    else echo "FAIL $label: expected=$expected actual=$actual"; failed=$((failed+1)); fi
}
printf 'STATE=LOGGED_IN\nLOGIN_TS=broken\nFAIL_COUNT=not-a-number\nERROR=quotes " tab\t backslash\\\n' > "$STATUS_FILE"
before=$(sha256sum "$STATUS_FILE")
result=$(method_get_status)
after=$(sha256sum "$STATUS_FILE")
expect 'status/read-only' 0 test "$before" = "$after"
expect 'status/missing-daemon' 0 test "$(printf '%s' "$result" | jsonfilter -e '@.state')" = STOPPED
expect 'status/safe-empty-number' 0 test "$(printf '%s' "$result" | jsonfilter -e '@.login_ts')" = 0
expect 'status/safe-fail-count' 0 test "$(printf '%s' "$result" | jsonfilter -e '@.fail_count')" = 0
expect 'status/escaped-controls' 0 test "$(printf '%s' "$result" | jsonfilter -e '@.error')" = "$(st_get ERROR)"
read -r fixture_up fixture_rest < /proc/uptime
fixture_up=${fixture_up%%.*}
fixture_delta=1
[ "$fixture_up" -lt 5 ] || fixture_delta=5
printf 'LOGIN_UPTIME=%s\n' "$((fixture_up-fixture_delta))" >> "$STATUS_FILE"
result=$(method_get_status)
uptime_result=$(printf '%s' "$result" | jsonfilter -e '@.uptime')
expect 'status/monotonic-uptime' 0 test "${uptime_result%:*}" = '00:00'
printf 'line "quotes"\ttab\\literal\nsecond\n' > "$LOG_FILE"
result=$(printf '{"lines":20}' | method_get_logs)
expect 'logs/json-serialization' 0 test "$(printf '%s' "$result" | jsonfilter -e '@.lines')" = "$(cat "$LOG_FILE")"
result=$(printf '{"user":"after","retry_interval":0}' | method_set_config)
expect 'config/invalid-result' 0 test "$(printf '%s' "$result" | jsonfilter -e '@.result')" = error
expect 'config/no-partial-write' 0 test "$(uci_get user)" = before
result=$(printf '{"user":"after","pass":"","retry_interval":3,"check_interval":30,"relogin_hour":-1,"log_max":500,"enabled":1,"debug":0}' | method_set_config)
expect 'config/save-success' 0 test "$(printf '%s' "$result" | jsonfilter -e '@.result')" = ok
expect 'config/commit-applied' 0 test "$(uci_get user)" = after
expect 'config/preserve-password' 0 test "$(uci_get pass)" = fixture-secret
expect 'config/autostart-synchronized' 0 grep -qx enable "$TEST_INIT_ACTIONS"
result=$(printf '{"user":"bad\nname"}' | method_set_config)
expect 'config/reject-controls' 0 test "$(printf '%s' "$result" | jsonfilter -e '@.result')" = error
result=$(printf '{"retry_interval":[]}' | method_set_config)
expect 'config/reject-array' 0 test "$(printf '%s' "$result" | jsonfilter -e '@.result')" = error
result=$(printf '{"action":"bad\"action"}' | method_do_action)
expect 'action/unknown-valid-json' 0 test "$(printf '%s' "$result" | jsonfilter -e '@.result')" = error
echo "RESULT $passed passed, $failed failed"
[ "$failed" = 0 ]
