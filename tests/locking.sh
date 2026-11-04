#!/bin/sh
# Uses real flock; run on the router, no network or production files touched.
cd "$(dirname "$0")/.." || exit 1
root=$(mktemp -d /tmp/portal-lock-tests.XXXXXX) || exit 1
trap 'rm -rf "$root"' EXIT
sed '$d' src/usr/bin/portal-login > "$root/core"
. "$root/core"
LOCK_FILE="$root/transaction"
LOG_FILE="$root/log"
_acquire_lock || exit 1
if (exec 9>&-; _acquire_lock); then echo 'FAIL concurrent transaction accepted'; exit 1; fi
echo 'PASS concurrent transaction rejected'
_release_lock
if ! (exec 9>&-; _acquire_lock); then echo 'FAIL lock not released'; exit 1; fi
echo 'PASS descriptor-close releases lock'
_acquire_lock || exit 1
before=$(ls -i "$LOCK_FILE" | awk '{print $1}')
_release_lock
after=$(ls -i "$LOCK_FILE" | awk '{print $1}')
[ "$before" = "$after" ] || { echo 'FAIL lock inode changed'; exit 1; }
echo 'PASS release preserves lock inode'
(
    exec 9>&-
    _acquire_lock || exit 1
    echo ready > "$root/ready"
    exec sleep 30
) &
child=$!
attempt=0
while [ ! -f "$root/ready" ] && [ "$attempt" -lt 10 ]; do sleep 1; attempt=$((attempt+1)); done
[ -f "$root/ready" ] || { kill "$child"; exit 1; }
kill -TERM "$child"
wait "$child" 2>/dev/null || true
_acquire_lock || { echo 'FAIL terminated process left stale lock'; exit 1; }
_release_lock
echo 'PASS process termination releases lock'
echo 'RESULT 4 passed, 0 failed'
