#!/system/bin/sh
set -eu
ROOT=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
GEN="$ROOT/scripts/gen_xposed_conf.sh"
UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
STATUS="$ROOT/scripts/status.sh"
for key in sensor_accel sensor_gyro sensor_light sensor_magnet sensor_pressure sensor_prox sensor_rate_limit; do
  grep -q "key == \"$key\"" "$GEN" || { echo "FAIL: publisher missing $key"; exit 1; }
  grep -Fq "\"$key\"" "$UI" || { echo "FAIL: UI missing $key"; exit 1; }
done
grep -q 'sensor_rate_limit=%s' "$GEN" || { echo 'FAIL: publisher output missing sensor_rate_limit'; exit 1; }
grep -q 'sensor_rate_limit=1' "$STATUS" || { echo 'FAIL: privacy target count omits sensor_rate_limit'; exit 1; }
grep -Fq "row.append(',').append(k).append('=')" "$UI" || { echo 'FAIL: UI save serialization missing sensor_rate_limit'; exit 1; }
echo 'PASS: per-app sensor flags are represented in publisher, UI, and status surfaces'
