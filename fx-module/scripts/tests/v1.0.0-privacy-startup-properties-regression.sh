#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
CONF="$ROOT/scripts/default.conf"
EARLY="$ROOT/post-fs-data.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
# Bootloader property spoof is opt-in because changing verified-boot properties can
# break device-integrity checks and cannot alter hardware-backed attestation.
grep -q '^hide_bl_status=0' "$CONF" || fail 'bootloader spoof must default off'
grep -Fq 'data-key="hide_bl_status"' "$HTML" || fail 'bootloader property switch missing'
grep -Fq '不能改变硬件 Key Attestation' "$HTML" || fail 'hardware attestation limitation missing'
grep -Fq 'if [ "$(get hide_bl_status 0)" = "1" ]; then' "$EARLY" || fail 'bootloader property backend missing'
# Property randomization is an early-boot action and must not expose a fake editor.
grep -q '^props_random=0' "$CONF" || fail 'property randomization must default off'
grep -Fq 'if [ "$(get props_random 0)" = "1" ]; then' "$EARLY" || fail 'property randomization backend missing'
grep -Fq 'data-key="props_random"' "$HTML" || fail 'property randomization switch missing'
grep -Fq '开机时随机化序列号与构建时间属性' "$HTML" || fail 'randomized properties scope must be explicit'
if grep -Fq 'data-misc-edit="props"' "$HTML"; then fail 'unimplemented property-randomization editor must not be clickable'; fi
grep -Fq "var rebootOnly=['hide_bl_status','props_random','boot_time_spoof'].indexOf(k)>=0" "$HTML" || fail 'reboot-only behavior must be communicated'
echo 'PASS: startup property privacy switches match post-fs-data backends, default safely, and disclose reboot/attestation limits'
