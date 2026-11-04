#!/bin/sh
# Network-adapter tests. No sockets, credentials, firewall changes or UCI writes.
cd "$(dirname "$0")/.." || exit 1
root=$(mktemp -d /tmp/portal-network-tests.XXXXXX) || exit 1
trap 'rm -rf "$root"' EXIT
sed '$d' src/usr/bin/portal-login > "$root/core"
. "$root/core"
NET_HELPER="$root/helper"
: > "$NET_HELPER"
passed=0; failed=0
expect() {
    local label="$1" expected="$2" actual
    shift 2; "$@"; actual=$?
    if [ "$actual" = "$expected" ]; then echo "PASS $label"; passed=$((passed+1));
    else echo "FAIL $label expected=$expected actual=$actual"; failed=$((failed+1)); fi
}
oc=0; firewall=owner; helper=ok
_has_openclash() { [ "$oc" = 1 ]; }
nft() {
    if [ "$6" = nat_output ]; then
        case "$firewall" in
            dns-only) echo 'meta skgid != 65534 redirect to :53 comment "OpenClash Router DNS Hijack"' ;;
            dns-broken) echo 'redirect to :53 comment "OpenClash Router DNS Hijack"' ;;
        esac
        return 0
    fi
    case "$firewall" in
        owner) echo 'meta skgid 65534 counter packets 1 bytes 60 return' ;;
        markonly) echo 'tcp sport 0-65535 meta skuid 0 ip dscp 0x2a return comment "PortalLogin_Direct_42"' ;;
        stopped|fw3|dns-only|dns-broken) return 1 ;;
    esac
}
iptables() {
    [ "$4" != OUTPUT ] || return 1
    [ "$firewall" = fw3 ] && echo '-A openclash_output -m owner --gid-owner 65534 -j RETURN'
}
ruby() { [ "$helper" = ok ]; }
expect 'no OpenClash works without its configuration' 0 _network_prepare
expect 'no OpenClash uses system network' 0 test "$NET_MODE" = system
oc=1
expect 'existing nft owner exemption detected automatically' 0 _network_prepare
expect 'owner worker selected without DSCP rule' 0 test "$NET_MODE" = openclash-owner
helper=broken
expect 'helper failure is explicit' 1 _network_prepare
helper=ok; firewall=markonly
expect 'old site-specific DSCP rule is not proof of isolation' 1 _network_prepare
firewall=stopped
expect 'stopped OpenClash uses normal network' 0 _network_prepare
expect 'stopped OpenClash mode' 0 test "$NET_MODE" = system
firewall=fw3
expect 'iptables owner exemption detected' 0 _network_prepare
expect 'iptables uses same worker' 0 test "$NET_MODE" = openclash-owner
firewall=dns-only
expect 'DNS-only interception selects isolated worker' 0 _network_prepare
expect 'DNS-only mode' 0 test "$NET_MODE" = openclash-owner
firewall=dns-broken
expect 'DNS without owner exemption is rejected' 1 _network_prepare

dns_case=normal
_network_dns_servers() { printf '%s\n' 192.0.2.53 192.0.2.54; }
ip() { echo '192.0.2.53 dev eth0 src 10.0.0.2'; }
_network_run() {
    local operation="$1" last
    shift
    if [ "$operation" = curl ]; then printf '%s\n' "$@" > "$root/curl-arguments"; return 0; fi
    for last in "$@"; do :; done
    echo "lookup $*" >> "$root/lookups"
    case "$dns_case:$last" in
        fake-first:192.0.2.53) printf 'Server: resolver\nAddress: 192.0.2.53#53\nName: custom.example\nAddress: 198.18.1.2\n' ;;
        timeout-first:192.0.2.53) return 124 ;;
        server-only:*) printf 'Server: resolver\nAddress: 192.0.2.53#53\n' ;;
        malformed:*) printf 'Name: custom.example\nAddress: 999.1.2.3\n' ;;
        fake-only:*) printf 'Name: custom.example\nAddress: 198.19.1.2\n' ;;
        ipv6-only:*) printf 'Name: custom.example\nAddress: 2001:db8::1\n' ;;
        *) printf 'Server: resolver\nAddress: 192.0.2.53#53\nName: custom.example\nAddress: 203.0.113.10\n' ;;
    esac
}
answer=$(_network_resolve custom.example)
expect 'DNS server address is not mistaken for answer' 0 test "$answer" = 203.0.113.10
dns_case=fake-first
answer=$(_network_resolve custom.example)
expect 'Fake-IP answer rejected and next DNS used' 0 test "$answer" = 203.0.113.10
dns_case=timeout-first
answer=$(_network_resolve custom.example)
expect 'DNS timeout falls back' 0 test "$answer" = 203.0.113.10
for dns_case in server-only malformed fake-only ipv6-only; do
    expect "reject $dns_case DNS response" 1 _network_resolve custom.example
done
dns_case=normal; oc=0
expect 'custom probe needs no OpenClash domain registration' 0 _direct_curl -s https://custom.example:8443/generate_204
expect 'curl uses resolved real IP with correct port' 0 grep -qx 'custom.example:8443:203.0.113.10' "$root/curl-arguments"
expect 'curl explicit proxies disabled' 0 grep -qx -- '--noproxy' "$root/curl-arguments"
expect 'TLS verification remains enabled' 1 grep -Ex -- '-k|--insecure' "$root/curl-arguments"
: > "$root/lookups"
expect 'literal portal IP does not need DNS' 0 _direct_curl -s http://192.168.1.2/index.html
expect 'literal IP sends no DNS request' 0 test ! -s "$root/lookups"
echo "RESULT $passed passed, $failed failed"
[ "$failed" = 0 ]
