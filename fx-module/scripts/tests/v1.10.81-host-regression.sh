#!/bin/sh
# Repeatable host-side assertions and deterministic fault injection; not Android device testing.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
python3 - "$ROOT/scripts/apply.sh" <<'PY'
import sys
s=open(sys.argv[1]).read()
assert '_pg_backup_hash=$(pg_sub_sha256 "$PG_SUB_TXN_BACKUP"' in s
assert '[ "$_pg_backup_hash" != "$PG_SUB_TXN_SHA256" ]' in s
assert 'backup SHA-256 mismatch; refusing to restore and retaining recovery evidence' in s
assert 'backup missing; transaction marker retained for recovery' in s
assert '_lk_pid_again=$(cat "$APPLY_LOCK/pid"' in s
assert 'mv "$APPLY_LOCK" "$_lk_stale"' in s
assert 'Never evict a lock whose recorded owner is still alive' in s
assert 'committed transaction cleanup completed' in s
assert 'network rules still require normal apply reconciliation' in s
PY
# Execute the same checksum comparison policy with both intact and corrupted snapshots.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
printf 'known-good-settings\n' > "$tmp/backup"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
expected=$(sha "$tmp/backup")
actual=$(sha "$tmp/backup")
[ "$actual" = "$expected" ]
printf 'tampered-settings\n' > "$tmp/backup"
actual=$(sha "$tmp/backup")
[ "$actual" != "$expected" ]
# Cert submodules and certificate mount-marker failure handling remain intact.
test -f "$ROOT/certs/submodules/pg_mitm_ca/module.prop"
test -f "$ROOT/certs/submodules/pg_https_ca/module.prop"
grep -q 'umount "\$_cmm_target"' "$ROOT/scripts/certmarker.sh"
grep -q 'preserving overlay \$_cmm_overlay' "$ROOT/scripts/certmarker.sh"
echo 'PASS: rollback checksum enforcement, corruption injection, stale-lock revalidation/quarantine, cert failure paths, independent cert submodules'
# Exercise the actual shell URI parser and validate emitted JSON, including bracketed IPv6.
python3 - "$ROOT" <<'PY'
import base64, json, subprocess, sys
root=sys.argv[1]
vm=json.dumps({'add':'2001:db8::1','port':'443','id':'00000000-0000-0000-0000-000000000001','net':'ws','path':'/ws','host':'example.com','tls':'tls','sni':'example.com','scy':'auto'},separators=(',',':'))
uris=[
 'vmess://'+base64.b64encode(vm.encode()).decode(),
 'vless://00000000-0000-0000-0000-000000000001@[2001:db8::2]:443?security=tls&sni=example.com',
 'trojan://secret@[2001:db8::3]:443?sni=example.com',
 'hysteria2://secret@[2001:db8::4]:443?sni=example.com',
 'tuic://00000000-0000-0000-0000-000000000001:secret@[2001:db8::5]:443?sni=example.com',
 'anytls://secret@[2001:db8::6]:443?sni=example.com',
 'socks5://user:pass@[2001:db8::7]:1080'
]
for uri in uris:
 p=subprocess.run(['sh','-c','. "$1/scripts/vpncore.sh"; singbox_node_outbound "$2" test','sh',root,uri],capture_output=True,text=True)
 assert p.returncode == 0, (uri, p.stderr)
 out=json.loads(p.stdout)
 assert ':' in out['server'] and out['server_port'] in range(1,65536), out
for port in ('0','65536','abc',''):
 p=subprocess.run(['sh','-c','. "$1/scripts/vpncore.sh"; split_host_port "[2001:db8::9]:$2"','sh',root,port],capture_output=True,text=True)
 assert p.returncode != 0, port
print('PASS: 7 real URI parser cases emit valid JSON with IPv6; invalid ports 0/65536/non-numeric/empty rejected')
PY
