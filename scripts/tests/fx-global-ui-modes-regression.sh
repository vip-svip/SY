#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
mode="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxUiMode.kt"
panel="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxDesignModePanel.kt"
shell="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
activity="$root/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
host="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeTabActivity.java"
skin="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeSkin.java"
for f in "$mode" "$panel" "$shell" "$activity" "$host" "$skin"; do
  test -s "$f" || { echo "FAIL: missing UI mode source $f"; exit 1; }
done
for token in CLASSIC_WEB_COMPAT FX_LIQUID_NATIVE MIUIX_STYLE HUAWEI_HARMONY_STYLE IOS_CUPERTINO_STYLE classic glass miuix huawei ios; do
  grep -Fq "$token" "$mode" || { echo "FAIL: mode model missing $token"; exit 1; }
done
for token in FxUiMode.CLASSIC_WEB_COMPAT FxUiMode.FX_LIQUID_NATIVE FxUiMode.MIUIX_STYLE FxUiMode.HUAWEI_HARMONY_STYLE FxUiMode.IOS_CUPERTINO_STYLE; do
  grep -Fq "$token" "$panel" || { echo "FAIL: settings panel missing $token"; exit 1; }
done
grep -Fq 'LiquidBottomTabs(' "$shell" || { echo "FAIL: liquid renderer missing"; exit 1; }
grep -Fq 'MiuixTheme(' "$shell" || { echo "FAIL: Miuix renderer missing"; exit 1; }
grep -Fq 'mode == "glass"' "$shell" || { echo "FAIL: liquid mode branch missing"; exit 1; }
grep -Fq 'mode == "miuix"' "$shell" || { echo "FAIL: Miuix mode branch missing"; exit 1; }
grep -Fq '"classic" ->' "$shell" || { echo "FAIL: classic mode branch missing"; exit 1; }
grep -Fq '"huawei".equals(uiMode)' "$activity" || { echo "FAIL: HUAWEI native page palette missing"; exit 1; }
grep -Fq '"ios".equals(uiMode)' "$activity" || { echo "FAIL: iOS native page palette missing"; exit 1; }
grep -Fq '"huawei" -> Color(0xFFF1F5FA)' "$shell" || { echo "FAIL: HUAWEI Harmony shell palette missing"; exit 1; }
grep -Fq '"ios" -> Color(0xFFF2F2F7)' "$shell" || { echo "FAIL: iOS Cupertino shell palette missing"; exit 1; }
grep -Fq 'webView.setVisibility(View.VISIBLE)' "$activity" || { echo "FAIL: ClassicWebCompat WebView not mounted"; exit 1; }
grep -Fq 'navigateWebPage(webPageForBottomTab(index))' "$activity" || { echo "FAIL: ClassicWebCompat tab routing missing"; exit 1; }
grep -Fq 'FxUiMode.read(this).getStorageId()' "$activity"
grep -Fq 'FxUiMode.write(MainActivity.this' "$activity"
grep -Fq 'applyWebUiMode();' "$activity"
grep -Fq 'FxNativeSkin.watch(this, pageContent);' "$host" || { echo "FAIL: imported native screens do not receive shared Skin tokens"; exit 1; }
grep -Fq 'FxNativeSkin.watch(this, pageContent);' "$activity" || { echo "FAIL: MainActivity native pages do not receive shared Skin tokens"; exit 1; }
grep -Fq 'pageContent.post(() -> {' "$activity" || { echo "FAIL: MainActivity Skin pass does not run after dynamic page construction"; exit 1; }
grep -Fq 'pageContent.getParent() != null' "$activity" || { echo "FAIL: deferred Skin pass does not check that the page is still mounted"; exit 1; }
for token in 'case HUAWEI_HARMONY_STYLE:' 'case IOS_CUPERTINO_STYLE:' '0xfff0f3f7' '0xff17212b' 'wallpaperActive ? 0x00000000'; do
  grep -Fq "$token" "$skin" || { echo "FAIL: shared native Skin adapter missing $token"; exit 1; }
done
python3 - "$skin" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
switch = source.index("if (view instanceof Switch)")
choice = source.index("else if (view instanceof android.widget.CompoundButton)", switch)
button = source.index("else if (view instanceof Button)", choice)
assert switch < choice < button, "Switch/CompoundButton must be dispatched before generic Button"
assert "control.setThumbTintList" in source and "control.setTrackTintList" in source
assert "control.setButtonTintList" in source
print("PASS: Switch and CheckBox/RadioButton tint adapters are reachable before generic Button styling.")
PY
python3 - "$skin" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    "case 0xff697681:", "case 0xff536170:", "case 0xff263443:",
    "case 0xff155a9c:", "return p.accent;"
):
    assert token in source, f"five-skin text palette token missing: {token}"
# Semantic alert colors must remain untouched by the neutral text remapper.
replacement = source[source.index("private static Integer replacementText"):source.index("\n    }\n}", source.index("private static Integer replacementText"))]
for alert in ("0xff9b2c2c", "0xffa32620", "0xffa12d2d",
              "0xfffff6e8", "0xff7a4b13", "0xff79552b",
              "0xff237347", "0xff24734a"):
    assert alert not in replacement, f"alert/success color should not be remapped: {alert}"
print("PASS: primary, secondary and accent text tokens map across all five skins while alert colors remain semantic.")
PY

python3 - "$skin" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("private static void applyButtonSkin")
end = source.index("private static boolean isSemanticActionBackground", start)
button_skin = source[start:end]
assert "isSemanticActionColor(button.getCurrentTextColor())" in button_skin
assert "isSemanticActionBackground(button.getBackground())" in button_skin
assert button_skin.index("isSemanticActionColor") < button_skin.index("BUTTON_SKINS")
semantic = source[source.index("private static boolean isSemanticActionColor"):source.index("private static void applySwitchSkin")]
for color in ("0xff9b2c2c", "0xffa32620", "0xffa12d2d",
              "0xfffff6e8", "0xff7a4b13", "0xff79552b",
              "0xff237347", "0xff24734a"):
    assert color in semantic, f"semantic action color missing from preservation guard: {color}"
print("PASS: semantic destructive/warning/success buttons bypass generic accent recoloring.")
PY

python3 - "$skin" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
transform = source[source.index("private static void transformKnownLegacyTokens"):source.index("private static void applyButtonSkin")]
assert "background instanceof ColorDrawable" in transform
assert "replacementBackgroundDrawable(oldColor, palette, wallpaperActive, density)" in transform
helper = source[source.index("private static Drawable replacementBackgroundDrawable"):source.index("private static Integer replacementText")]
assert "case 0xfff0f3f7:" in helper and "case 0xffffffff:" in helper
assert "case 0xffe9eef3:" in helper and "case 0xffe5e5ea:" in helper
assert "roundedSurface(p.surface," in helper and "roundedSurface(p.surfaceVariant," in helper
assert "p.cornerRadiusDp - 4) * density" in helper
assert "p.cornerRadiusDp - 8) * density" in helper
assert "surface.setCornerRadius(radiusPx)" in helper
assert "return null;" in helper, "unknown/custom background tokens must remain untouched"
print("PASS: known neutral cards receive density-scaled five-skin radii while custom drawables remain intact.")
PY
grep -Fq 'addOnGlobalLayoutListener' "$skin" || { echo "FAIL: dynamic native pages are not re-skinned after layout"; exit 1; }
grep -Fq 'addOnAttachStateChangeListener' "$skin" || { echo "FAIL: Skin observer is not attached to the live page root"; exit 1; }
grep -Fq 'removeOnGlobalLayoutListener(layoutListener)' "$skin" || { echo "FAIL: Skin observer is not removed when page detaches"; exit 1; }
grep -Fq 'private static final WeakHashMap<View, Boolean> WATCHED' "$skin" || { echo "FAIL: Skin observer deduplication is missing"; exit 1; }
grep -Fq 'WATCHED.containsKey(pageContent)' "$skin" || { echo "FAIL: re-mounted pages can register duplicate Skin observers"; exit 1; }
grep -Fq 'activity.isDestroyed()' "$skin" || { echo "FAIL: Skin observer does not stop for destroyed Activities"; exit 1; }
grep -Fq 'applyButtonSkin(activity, (Button) view, mode, palette)' "$skin" || { echo "FAIL: native buttons do not receive Skin tokens"; exit 1; }
grep -Fq 'new RippleDrawable(' "$skin" || { echo "FAIL: native buttons lack mode-aware ripple surfaces"; exit 1; }
grep -Fq 'applySwitchSkin(activity, (Switch) view, mode, palette)' "$skin" || { echo "FAIL: native switches do not receive Skin tokens"; exit 1; }
grep -Fq 'setThumbTintList(' "$skin" && grep -Fq 'setTrackTintList(' "$skin" || { echo "FAIL: native switches lack selected/off Skin colors"; exit 1; }
grep -Fq 'applyChoiceControlSkin(' "$skin" || { echo "FAIL: radio/choice controls do not receive Skin tokens"; exit 1; }
! grep -Fq 'control.setBackgroundColor(android.graphics.Color.TRANSPARENT)' "$skin" || { echo "FAIL: switch Skin pass must not erase card/row surfaces"; exit 1; }
# Run adjacent UI fixtures here as well: a Skin-only source change must not
# leave the targeted workflow with an unmapped source path, and these tests
# explicitly distinguish source-only checkout from Release-staged resources.
bash "$root/scripts/tests/fx-wallpaper-regression.sh"
sh "$root/scripts/tests/fx-native-vpn-api-regression.sh"
sh "$root/scripts/tests/fx-vpn-transparent-toggle-regression.sh"
sh "$root/scripts/tests/v1.0.0-fxhook-capture-privacy-wiring-regression.sh"
sh "$root/scripts/tests/vpncore-default-node-fallback-regression.sh"
echo "PASS: five global UI modes share persistence, shell rendering, and live tokens on MainActivity and imported pages."
