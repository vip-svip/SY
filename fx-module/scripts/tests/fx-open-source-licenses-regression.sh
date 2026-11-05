#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APP="$ROOT/adhook/app/src/main"
JAVA="$APP/java/de/privacyguard/adhook"
ACTIVITY="$JAVA/FxOpenSourceLicensesActivity.java"
MAIN="$JAVA/MainActivity.java"
MANIFEST="$APP/AndroidManifest.xml"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$ACTIVITY" ] && [ -s "$MAIN" ] && [ -s "$MANIFEST" ] || fail "open-source license page sources missing"
for name in THIRD_PARTY_NOTICES.txt GKD-XA-GPL-3.0.txt Capsule-LICENSE.txt Kyant-AndroidLiquidGlass-LICENSE.txt MaterialKolor-MIT-LICENSE.txt Miuix-LICENSE.txt; do
  [ -s "$APP/assets/licenses/$name" ] || fail "bundled license asset missing: $name"
  grep -Fq "$name" "$ACTIVITY" || fail "license asset is not exposed by the native viewer: $name"
done
grep -Fq 'FxOpenSourceLicensesActivity.class' "$MAIN" || fail "Settings does not navigate to the native license viewer"
python3 - "$MANIFEST" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
ns = "{http://schemas.android.com/apk/res/android}"
app = root.find("application")
activity = next((x for x in app.findall("activity")
                 if x.attrib.get(ns + "name") == ".FxOpenSourceLicensesActivity"), None)
assert activity is not None, "license viewer Activity not registered"
assert activity.attrib.get(ns + "exported") == "false", "license viewer must not be exported"
PY
grep -Fq 'getAssets().open("licenses/" + file)' "$ACTIVITY" || fail "license viewer does not read APK-bundled text"
grep -Fq 'GKD-XA v1.4.8 选择器 · GPL-3.0' "$ACTIVITY" || fail "GKD GPL license is not labeled in the Settings license viewer"
grep -Fq 'GNU General Public License' "$APP/assets/licenses/GKD-XA-GPL-3.0.txt" || fail "full GKD GPL-3.0 text is missing"
grep -Fq '8a6ce935da11671dac7e1a7595416ec99ee07436' "$APP/assets/licenses/THIRD_PARTY_NOTICES.txt" || fail "GKD selector source pin is missing from third-party notices"
grep -Fq 'MAX_LICENSE_BYTES = 48 * 1024' "$ACTIVITY" || fail "license reader must retain a bounded input size"
grep -Fq 'new ArrayBlockingQueue<>(2)' "$ACTIVITY" || fail "license reader must use a bounded background queue"
grep -Fq "} catch (Exception failure) {" "$ACTIVITY" || fail "license reader must handle recoverable read errors"
! grep -Fq "} catch (Throwable failure) {" "$ACTIVITY" || fail "license reader must not swallow fatal VM errors"
grep -Fq 'worker.shutdownNow()' "$ACTIVITY" || fail "license reader worker must stop with Activity lifecycle"
echo "PASS: bundled open-source notices are reachable from Settings and read with bounded native I/O"
