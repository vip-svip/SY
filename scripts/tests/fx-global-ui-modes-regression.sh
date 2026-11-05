#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
mode="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxUiMode.kt"
panel="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxDesignModePanel.kt"
shell="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
tokens="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxComposeSkinTokens.kt"
activity="$root/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
host="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeTabActivity.java"
skin="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeSkin.java"
harmony_tokens="$root/adhook/app/src/main/java/de/privacyguard/adhook/HarmonySkinTokens.java"
cupertino_tokens="$root/adhook/app/src/main/java/de/privacyguard/adhook/CupertinoSkinTokens.java"
harmony_renderer="$root/adhook/app/src/main/java/de/privacyguard/adhook/HarmonySkinRenderer.java"
cupertino_renderer="$root/adhook/app/src/main/java/de/privacyguard/adhook/CupertinoSkinRenderer.java"
native_skin_test="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxNativeSkinPaletteTest.kt"
for f in "$mode" "$panel" "$shell" "$tokens" "$activity" "$host" "$skin" "$harmony_tokens" "$cupertino_tokens" "$harmony_renderer" "$cupertino_renderer" "$native_skin_test"; do
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
grep -Fq 'tokens.useLiquidTabsRenderer' "$shell" || { echo "FAIL: liquid renderer is not selected by the skin token set"; exit 1; }
grep -Fq 'fxComposeShellTokens(' "$shell" || { echo "FAIL: shared shell does not resolve the active skin tokens"; exit 1; }
grep -Fq 'tokens.barBorder' "$shell" || { echo "FAIL: per-skin shell border token is not applied"; exit 1; }
grep -Fq '"huawei".equals(uiMode)' "$activity" || { echo "FAIL: HUAWEI native page palette missing"; exit 1; }
grep -Fq '"ios".equals(uiMode)' "$activity" || { echo "FAIL: iOS native page palette missing"; exit 1; }
for token in FxClassicComposeTokens FxLiquidComposeTokens FxMiuixComposeTokens FxHarmonyComposeTokens FxCupertinoComposeTokens; do
  grep -Fq "internal object $token" "$tokens" || { echo "FAIL: missing independent skin token set $token"; exit 1; }
done
grep -Fq 'pageBackground = Color(HarmonySkinTokens.HarmonyColorTokens.BACKGROUND)' "$tokens" || { echo "FAIL: HUAWEI Compose renderer is not using the shared Harmony color tokens"; exit 1; }
grep -Fq 'pageBackground = Color(CupertinoSkinTokens.CupertinoColorTokens.BACKGROUND)' "$tokens" || { echo "FAIL: iOS Compose renderer is not using the shared Cupertino color tokens"; exit 1; }
grep -Fq 'barCornerRadiusDp = HarmonySkinTokens.HarmonyShapeTokens.NAV_BAR_RADIUS_DP' "$tokens" || { echo "FAIL: HUAWEI Compose renderer is not using Harmony shape tokens"; exit 1; }
grep -Fq 'tabBarHeightDp = HarmonySkinTokens.HarmonySpacingTokens.NAV_HEIGHT_DP' "$tokens" || { echo "FAIL: HUAWEI Compose renderer is not using Harmony spacing tokens"; exit 1; }
grep -Fq 'labelSizeSp = HarmonySkinTokens.HarmonyTypographyTokens.TAB_LABEL_SP.toInt()' "$tokens" || { echo "FAIL: HUAWEI Compose renderer is not using Harmony typography tokens"; exit 1; }
grep -Fq 'barCornerRadiusDp = CupertinoSkinTokens.CupertinoShapeTokens.NAV_BAR_RADIUS_DP' "$tokens" || { echo "FAIL: iOS Compose renderer is not using Cupertino shape tokens"; exit 1; }
grep -Fq 'tabBarHeightDp = CupertinoSkinTokens.CupertinoSpacingTokens.NAV_HEIGHT_DP' "$tokens" || { echo "FAIL: iOS Compose renderer is not using Cupertino spacing tokens"; exit 1; }
grep -Fq 'labelSizeSp = CupertinoSkinTokens.CupertinoTypographyTokens.TAB_LABEL_SP.toInt()' "$tokens" || { echo "FAIL: iOS Compose renderer is not using Cupertino typography tokens"; exit 1; }
grep -Fq 'tabBarHeightDp = 60' "$tokens" || { echo "FAIL: Classic tab geometry missing"; exit 1; }
grep -Fq 'tabBarHeightDp = 68' "$tokens" || { echo "FAIL: Miuix tab geometry missing"; exit 1; }
grep -Fq 'NAV_BAR_RADIUS_DP = 18' "$harmony_tokens" || { echo "FAIL: Harmony navigation geometry token missing"; exit 1; }
grep -Fq 'NAV_HEIGHT_DP = 72' "$harmony_tokens" || { echo "FAIL: Harmony tab-bar height token missing"; exit 1; }
grep -Fq 'NAV_BAR_RADIUS_DP = 24' "$cupertino_tokens" || { echo "FAIL: Cupertino navigation geometry token missing"; exit 1; }
grep -Fq 'NAV_HEIGHT_DP = 76' "$cupertino_tokens" || { echo "FAIL: Cupertino tab-bar height token missing"; exit 1; }
grep -Fq 'harmonyRendererUsesItsOwnCardActionAndFormTokens' "$native_skin_test" || { echo "FAIL: Harmony palette unit test missing"; exit 1; }
grep -Fq 'cupertinoRendererUsesItsOwnCardActionAndFormTokens' "$native_skin_test" || { echo "FAIL: Cupertino palette unit test missing"; exit 1; }
grep -Fq 'harmonyAndCupertinoGeometryAndInputsRemainDistinct' "$native_skin_test" || { echo "FAIL: cross-Skin distinction unit test missing"; exit 1; }
grep -Fq 'HarmonyShapeTokens.CARD_RADIUS_DP' "$harmony_renderer" || { echo "FAIL: Harmony native card renderer must use its dedicated card radius"; exit 1; }
grep -Fq 'CupertinoShapeTokens.CARD_RADIUS_DP' "$cupertino_renderer" || { echo "FAIL: Cupertino native card renderer must use its dedicated card radius"; exit 1; }
grep -Fq 'p.cardCornerRadiusDp - 4) * density' "$skin" || { echo "FAIL: native neutral cards must use card radius rather than action radius"; exit 1; }
grep -Fq 'palette.cornerRadiusDp * density' "$skin" || { echo "FAIL: native action buttons must retain the independent action radius"; exit 1; }
grep -Fq 'return HarmonySkinRenderer.palette();' "$skin" || { echo "FAIL: Android Views do not use the Harmony renderer"; exit 1; }
grep -Fq 'return CupertinoSkinRenderer.palette();' "$skin" || { echo "FAIL: Android Views do not use the Cupertino renderer"; exit 1; }
grep -Fq 'HarmonySkinRenderer.applyTaggedComponent(activity, view)' "$skin" || { echo "FAIL: Harmony component renderer is not in the shared native Skin walk"; exit 1; }
grep -Fq 'CupertinoSkinRenderer.applyTaggedComponent(activity, view)' "$skin" || { echo "FAIL: Cupertino component renderer is not in the shared native Skin walk"; exit 1; }
grep -Fq 'FxNativeSkin.shouldPreserveSemanticAction(action)' "$harmony_renderer" || { echo "FAIL: Harmony renderer may recolor semantic actions"; exit 1; }
grep -Fq 'FxNativeSkin.shouldPreserveSemanticAction(action)' "$cupertino_renderer" || { echo "FAIL: Cupertino renderer may recolor semantic actions"; exit 1; }
for role in 't.setTag("fx-title:" + size)' 'button.setTag("fx-action-row")' 'card.setTag("fx-card")' 'card.setTag("fx-setting-card")' 't.setTag("fx-section:" + s)'; do
  grep -Fq "$role" "$activity" || { echo "FAIL: shared native component role missing: $role"; exit 1; }
done
for role in 'role.startsWith("fx-title:")' 'role.startsWith("fx-section:")' '"fx-card".equals(role)' '"fx-action-row".equals(role)'; do
  grep -Fq "$role" "$harmony_renderer" || { echo "FAIL: Harmony component role renderer missing: $role"; exit 1; }
  grep -Fq "$role" "$cupertino_renderer" || { echo "FAIL: Cupertino component role renderer missing: $role"; exit 1; }
done
for token in 'CARD_SURFACE' 'CARD_STROKE' 'ROW_RIPPLE' 'SECTION_RADIUS_DP' 'PAGE_TITLE_SP' 'SECTION_TITLE_SP' 'CARD_TITLE_SP' 'ROW_MIN_HEIGHT_DP'; do
  grep -Fq "$token" "$harmony_tokens" || { echo "FAIL: Harmony component token missing: $token"; exit 1; }
  grep -Fq "$token" "$cupertino_tokens" || { echo "FAIL: Cupertino component token missing: $token"; exit 1; }
done
grep -Fq 'applyTextInputSkin(activity, (EditText) view, mode, palette)' "$skin" || { echo "FAIL: EditText controls must use skin hint tokens"; exit 1; }
grep -Fq 'applySpinnerSkin(activity, (Spinner) view, mode, palette)' "$skin" || { echo "FAIL: Spinner controls must use skin selection tokens"; exit 1; }
grep -Fq 'control.setHintTextColor(palette.secondaryText)' "$skin" || { echo "FAIL: EditText placeholder color is not skin-aware"; exit 1; }
grep -Fq 'palette.inputBorder' "$skin" || { echo "FAIL: focused/unfocused form border token is missing"; exit 1; }
grep -Fq 'INPUT_BORDER = 0xffb7cce5' "$harmony_tokens" || { echo "FAIL: Harmony form border token missing"; exit 1; }
grep -Fq 'INPUT_BORDER = 0xffc6c6cc' "$cupertino_tokens" || { echo "FAIL: Cupertino form border token missing"; exit 1; }
[[ "$(grep -Fc 'static final int INPUT_BORDER' "$harmony_tokens")" -eq 1 ]] || { echo "FAIL: Harmony INPUT_BORDER must be declared exactly once"; exit 1; }
[[ "$(grep -Fc 'static final int INPUT_BORDER' "$cupertino_tokens")" -eq 1 ]] || { echo "FAIL: Cupertino INPUT_BORDER must be declared exactly once"; exit 1; }
[[ "$(grep -Fc 'static final int INPUT_MIN_HEIGHT_DP' "$harmony_tokens")" -eq 1 ]] || { echo "FAIL: Harmony INPUT_MIN_HEIGHT_DP must be declared exactly once"; exit 1; }
[[ "$(grep -Fc 'static final int INPUT_MIN_HEIGHT_DP' "$cupertino_tokens")" -eq 1 ]] || { echo "FAIL: Cupertino INPUT_MIN_HEIGHT_DP must be declared exactly once"; exit 1; }
python3 - "$harmony_tokens" "$cupertino_tokens" <<'PY'
from collections import Counter
from pathlib import Path
import re
import sys

for filename in sys.argv[1:]:
    source = Path(filename).read_text(encoding="utf-8")
    names = re.findall(r"static\s+final\s+\w+\s+(\w+)\s*=", source)
    duplicates = [name for name, count in Counter(names).items() if count > 1]
    assert not duplicates, f"{filename}: duplicate Skin token declarations: {duplicates}"
print("PASS: Harmony and Cupertino token names are unique; duplicate Java constants cannot break compilation.")
PY
grep -Fq 'control.setMinimumHeight(Math.max(control.getMinimumHeight()' "$skin" || { echo "FAIL: native form controls lack minimum touch height"; exit 1; }

grep -Fq 'webView.setVisibility(View.VISIBLE)' "$activity" || { echo "FAIL: ClassicWebCompat WebView not mounted"; exit 1; }
grep -Fq 'navigateWebPage(webPageForBottomTab(index))' "$activity" || { echo "FAIL: ClassicWebCompat tab routing missing"; exit 1; }
grep -Fq 'FxUiMode.read(this).getStorageId()' "$activity"
grep -Fq 'FxUiMode.write(MainActivity.this' "$activity"
grep -Fq 'applyWebUiMode();' "$activity"
grep -Fq 'FxNativeSkin.watch(this, pageContent);' "$host" || { echo "FAIL: imported native screens do not receive shared Skin tokens"; exit 1; }
grep -Fq 'FxNativeSkin.watch(this, pageContent);' "$activity" || { echo "FAIL: MainActivity native pages do not receive shared Skin tokens"; exit 1; }
grep -Fq 'pageContent.post(() -> {' "$activity" || { echo "FAIL: MainActivity Skin pass does not run after dynamic page construction"; exit 1; }
grep -Fq 'pageContent.getParent() != null' "$activity" || { echo "FAIL: deferred Skin pass does not check that the page is still mounted"; exit 1; }
for token in \
  'HarmonySkinTokens.HarmonyColorTokens.BACKGROUND' \
  'CupertinoSkinTokens.CupertinoColorTokens.BACKGROUND' \
  'HarmonySkinTokens.HarmonyColorTokens.SURFACE' \
  'CupertinoSkinTokens.CupertinoColorTokens.SURFACE' \
  'HarmonySkinTokens.HarmonyColorTokens.PRIMARY_TEXT' \
  'CupertinoSkinTokens.CupertinoColorTokens.PRIMARY_TEXT' \
  'HarmonySkinTokens.HarmonyShapeTokens.CARD_RADIUS_DP' \
  'CupertinoSkinTokens.CupertinoShapeTokens.CARD_RADIUS_DP' \
  'HarmonySkinTokens.HarmonyColorTokens.SURFACE_VARIANT' \
  'CupertinoSkinTokens.CupertinoColorTokens.SURFACE_VARIANT'; do
  grep -Fq "$token" "$activity" || { echo "FAIL: MainActivity card/section renderer does not use shared Skin token $token"; exit 1; }
done
for token in 'case HUAWEI_HARMONY_STYLE:' 'case IOS_CUPERTINO_STYLE:' '0xfff0f3f7' '0xff17212b' 'wallpaperActive ? 0x00000000'; do
  grep -Fq "$token" "$skin" || { echo "FAIL: shared native Skin adapter missing $token"; exit 1; }
done
python3 - "$skin" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("private static void apply(Activity activity")
end = source.index("private static boolean isKnownPageBackground", start)
apply = source[start:end]
assert "isKnownPageBackground(rootBackground, palette, rootColor)" in apply
assert "pageContent.setBackgroundColor(rootColor)" in apply
helper = source[source.index("private static boolean isKnownPageBackground"):source.index("private static Palette palette")]
assert "if (!(background instanceof ColorDrawable)) return false;" in helper
assert "background == null" in helper
assert "color == palette.background" in helper
print("PASS: Skin adapter only rewrites known neutral ColorDrawable roots; custom GradientDrawable/selector/ripple roots remain untouched.")
PY
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
assert "background instanceof GradientDrawable" in transform
assert "ColorStateList fill = ((GradientDrawable) background).getColor()" in transform
assert "if (fill != null) legacyBackgroundColor = fill.getDefaultColor()" in transform
assert "replacementBackgroundDrawable(" in transform and "legacyBackgroundColor, palette, wallpaperActive, density" in transform
helper = source[source.index("private static Drawable replacementBackgroundDrawable"):source.index("private static Integer replacementText")]
assert "case 0xfff0f3f7:" in helper and "case 0xffffffff:" in helper
assert "case 0xffe9eef3:" in helper and "case 0xffe5e5ea:" in helper
assert "roundedSurface(p.surface," in helper and "roundedSurface(p.surfaceVariant," in helper
assert "Math.max(10, p.cardCornerRadiusDp - 4) * density" in helper
assert "Math.max(8, p.cardCornerRadiusDp - 8) * density" in helper
assert "surface.setCornerRadius(radiusPx)" in helper
assert "surface.setStroke(1, strokeColor)" in helper
assert helper.index("default:") > helper.index("case 0xffe3e8ee:"), "unknown custom backgrounds must fall through untouched"
assert "return null;" in helper, "unknown/custom background tokens must remain untouched"
print("PASS: known neutral ColorDrawable and solid GradientDrawable cards receive five-skin surfaces; gradients, selectors, ripples and unknown drawables remain intact.")
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
python3 - "$harmony_tokens" "$cupertino_tokens" "$skin" <<'PY'
from collections import Counter
from pathlib import Path
import re
import sys

for name in sys.argv[1:3]:
    source = Path(name).read_text(encoding="utf-8")
    fields = re.findall(r"static final (?:int|float|long|boolean|String)\\s+(\\w+)\\s*=", source)
    duplicates = [key for key, count in Counter(fields).items() if count > 1]
    assert not duplicates, f"{name}: duplicate Java token fields: {duplicates}"

skin = Path(sys.argv[3]).read_text(encoding="utf-8")
assert "int inputBorder, int cardCornerRadiusDp, float buttonTextSizeSp" in skin
assert "this.cardCornerRadiusDp = cardCornerRadiusDp;" in skin
assert "static boolean shouldPreserveSemanticAction(Button button)" in skin
print("PASS: Harmony/Cupertino token declarations are unique and native Skin palette constructor fields are wired.")
PY
echo "PASS: five global UI modes share persistence, shell rendering, and live tokens on MainActivity and imported pages."
