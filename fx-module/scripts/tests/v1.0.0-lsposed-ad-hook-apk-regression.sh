#!/bin/sh
# Verify the bundled LSPosed APK is non-empty, signed/container-valid, and contains the expected entrypoint/rules.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
APK="$ROOT/optional/FXUnifiedHook.apk"
HASH="$APK.sha256"
INFO="$ROOT/optional/FXUnifiedHook-BUILD-INFO.txt"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$APK" ] || fail "FXAdHook APK missing"
[ "$(wc -c < "$APK" | tr -d ' ')" -gt 10000 ] || fail "FXAdHook APK unexpectedly small"
command -v unzip >/dev/null 2>&1 || fail "unzip required for package test"
unzip -t "$APK" >/dev/null 2>&1 || fail "APK archive corrupt"
unzip -p "$APK" META-INF/xposed/java_init.list 2>/dev/null | grep -qx 'de.privacyguard.adhook.AdVisibilityHook' || fail "modern LSPosed entrypoint missing"
unzip -p "$APK" META-INF/xposed/module.prop 2>/dev/null | grep -q '^minApiVersion=101$' || fail "modern API metadata missing"
unzip -p "$APK" META-INF/xposed/module.prop 2>/dev/null | grep -q '^staticScope=false$' || fail "user-managed scope must remain enabled"
unzip -p "$APK" assets/xposed_init 2>/dev/null | grep -qx 'de.privacyguard.hook.MainHook' || fail "copied legacy MainHook entrypoint missing"
unzip -p "$APK" META-INF/xposed/java_init.list 2>/dev/null | grep -qx 'de.privacyguard.adhook.AdVisibilityHook' || fail "modern ad Hook entrypoint missing"
[ -s "$ROOT/adhook/app/src/main/java/de/privacyguard/hook/MainHook.java" ] || fail "copied MainHook source missing"
[ "$(wc -c < "$ROOT/adhook/app/src/main/java/de/privacyguard/hook/MainHook.java" | tr -d ' ')" -ge 90000 ] || fail "copied MainHook source truncated"
DEXSTR=$(for dex in $(unzip -Z1 "$APK" | grep -E '^classes([0-9]+)?[.]dex$'); do unzip -p "$APK" "$dex" 2>/dev/null | strings || true; done)
DEXSTR_FILE=$(mktemp)
printf '%s\n' "$DEXSTR" > "$DEXSTR_FILE"
trap 'rm -f "$DEXSTR_FILE"' EXIT
grep -Fq 'inspectDynamicallyLoadedMemberClass(candidate)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "unified APK DEX discovery path missing from source"
grep -Fq '领取金币' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "rewarded-ad Chinese UI evidence missing from source"
grep -Fq '看视频领' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "rewarded-video Chinese UI evidence missing from source"
grep -Fq '看广告领' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "rewarded-ad Chinese UI evidence missing from source"
grep -Fq '激励视频' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "rewarded-video Chinese marker missing from source"
grep -Fq '广告奖励' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "ad reward Chinese marker missing from source"
for token in installClipboardIsolationHooks clipboardIsolationEnabled setPrimaryClip AdVisibilityHook UnifiedHookConfigParser PrivacyIdentifier privacy_enabled isPrivacyEnabledFor hook_ads_enabled member_diag splash_ad BillingResult Purchase showAsDropDown showAtLocation openRemoteFile fx-hook-targets.conf Remote Files installDynamicAdChildHooks scheduleAddedViewCheck "dynamic ad child observers installed" addView "billing responseCode" "billing purchaseState" "billing purchaseAcknowledged" "billing purchaseAutoRenewing" "billing clientReady" "read-only billing diagnostics installed=" "member runtime discovery installed" "member discovery candidate=" "member DEX candidate scan finished" startBoundedMemberDexScan splitSourceDirs apkFilesScanned  inspectMemberViewTree REWARDED_FLOW_MARKERS MAX_REWARDED_AD_EVIDENCE memberMethodsHooked memberClassesInspected MAX_AUTO_MEMBER_METHOD_HOOKS MAX_DYNAMIC_MEMBER_CLASSES MEMBER_STATE_FIELD_MARKERS hasMemberStateField hasMemberStateType observeLoadedMemberClass loaderHooks= installDynamicMemberClassDiscovery inspectDynamicallyLoadedMemberClass obfuscated-status-candidate member-field-candidate member-interface-candidate "dynamic member class discovery installed" installReadOnlyMemberCandidateHook "auto member candidate hooks installed=" "member state observation" "mode=read-only" isRewardedFlowEvidence containsRewardedUiSignal      recordRewardedAdEvidence preserve-reward-flow "rewarded-ad lifecycle candidate=" "action=observe-only; reward callback/server validation unchanged" resourceName com.huawei.hms.ads com.miui.zeus.mimo.sdk com.heytap.msp.mobad.api com.vivo.mobilead com.hihonor.adsdk; do
  grep -Fq "$token" "$DEXSTR_FILE" || fail "compiled hook marker missing: $token"
done
[ -s "$HASH" ] || fail "APK sha file missing"
ACTUAL=$(sha256sum "$APK" | awk '{print $1}')
EXPECTED=$(awk 'NR==1 {print $1}' "$HASH")
[ "$ACTUAL" = "$EXPECTED" ] || fail "bundled APK sha mismatch"
grep -Eq '^(Build variant: debug-signed APK|Build/signing mode: (debug-signed|release-signed))' "$INFO" || fail "build provenance note missing or signing mode undocumented"
grep -Fq 'Dual entrypoints: legacy Xposed API 93+ and modern libxposed API 101' "$INFO"
grep -q 'versionCode: 10000' "$INFO" || fail "submodule versionCode must stay aligned to fixed 1.0.0"
unzip -p "$APK" AndroidManifest.xml >/dev/null 2>&1 || fail "unified APK manifest missing"
[ ! -e "$ROOT/optional/PrivacyGuardHook.apk" ] || fail "split legacy APK should not be packaged"
[ -s "$ROOT/scripts/install_adhook_app.sh" ] || fail "ordinary-app installer missing"
[ ! -d "$ROOT/system/priv-app/FXAdHook" ] || fail "FXUnifiedHook must not require system overlay mount"
grep -q 'ordinary application' "$INFO" || fail "ordinary-app deployment not documented"
echo "PASS: FX unified Hook APK archive, entrypoint, features, checksum, and ordinary-app deployment"
