#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PROJECT="$ROOT/adhook/build.gradle"
APP="$ROOT/adhook/app/build.gradle"
PROPERTIES="$ROOT/adhook/gradle.properties"
WORKFLOW="$ROOT/.github/workflows/build-fx-adhook.yml"
PACKAGE_WORKFLOW="$ROOT/.github/workflows/build-fx-kernelsu.yml"
for file in "$PROJECT" "$APP" "$PROPERTIES" "$WORKFLOW" "$PACKAGE_WORKFLOW"; do
  [ -s "$file" ] || { echo "FAIL: missing Android build toolchain file: $file" >&2; exit 1; }
done
python3 - "$PROJECT" "$APP" "$PROPERTIES" "$WORKFLOW" "$ROOT" <<'PY'
from pathlib import Path
import sys
project, app, props, workflow, package_workflow = [Path(p).read_text(encoding="utf-8") for p in sys.argv[1:6]]
root = Path(sys.argv[5])
manifest = (root / "adhook/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
merger = (root / "fx-patches/merge_hook_single_apk.py").read_text(encoding="utf-8")
assert "com.android.application' version '9.1.1'" in project, "AGP must support Android API 37"
assert "org.jetbrains.kotlin.android' version '2.4.21'" in project
assert "org.jetbrains.kotlin.plugin.compose' version '2.4.21'" in project
assert "compileSdk 37" in app, "libXposed 102 requires compileSdk 37"
assert "minSdk 28" in app and "targetSdk 34" in app, "SDK floor/target must remain minSdk 28 / targetSdk 34"
assert "<uses-sdk" not in manifest, "AGP 9 main manifest must not declare SDK levels"
assert 'manifest_root.remove(uses_sdk)' in merger, "manifest merger must strip inherited <uses-sdk> nodes"
assert 'uses_sdk.set(ANDROID + "minSdkVersion"' not in merger, "manifest merger must not rewrite SDK levels"
assert 'g = g.replace("minSdk 28", "minSdk 27")' not in merger, "manifest merger must not silently downgrade minSdk"
assert "jvmTarget = '17'" in app
assert "android.builtInKotlin=false" in props and "android.newDsl=false" in props, \
    "retain the existing Kotlin 2.4.21 / legacy DSL compatibility while upgrading AGP"
assert "gradle-version: '9.3.1'" in workflow, "AGP 9.1.1 requires Gradle 9.3.1"
assert "platforms;android-37" in workflow and "build-tools;36.0.0" in workflow
assert "$SDK_ROOT/build-tools/36.0.0/apksigner" in workflow
assert "$SDK_ROOT/build-tools/36.0.0/aapt" in workflow
assert "gradle-version: '8.13'" not in workflow and "compileSdk 36" not in app and "gradle-version: '8.13'" not in package_workflow
assert "platforms;android-36" not in package_workflow and "build-tools;34.0.0" not in package_workflow
print("PASS: AGP 9.1.1 / Gradle 9.3.1 / Android API 37 matches libXposed 102")
PY
