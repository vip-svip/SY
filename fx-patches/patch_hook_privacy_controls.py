#!/usr/bin/env python3
"""Wire existing API-101 camera/location/mic/MediaStore privacy controls end-to-end."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
generator = root / "scripts/gen_xposed_conf.sh"
regression = root / "scripts/tests/v1.0.0-lsposed-remote-file-config-regression.sh"
mic_regression = root / "scripts/tests/v1.0.0-lsposed-audiorecord-mic-silence-regression.sh"
# Per-app Hook controls are native APK UI, not the module WebUI.
native_ui = Path(__file__).resolve().parent.parent / "adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
for path in (generator, regression, mic_regression, native_ui):
    if not path.is_file():
        raise SystemExit("missing required FX source: " + str(path))

def once(path, old, new, *, allow_missing=True):
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count == 0 and allow_missing:
        print(f"{path}: legacy anchor already evolved; deferring to end-to-end regression checks")
        return
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one source anchor, got {count}: {old[:90]!r}")
    path.write_text(source.replace(old, new), encoding="utf-8")

# The published 1.0.0 archive may already contain the complete migration.
# Treat that state as success; do not replay exact-text edits against a newer
# generator/UI and fail merely because their old anchors have disappeared.
gen_text = generator.read_text(encoding="utf-8")
native_ui_text = native_ui.read_text(encoding="utf-8")
reg_text = regression.read_text(encoding="utf-8")
mic_text = mic_regression.read_text(encoding="utf-8")
already_complete = (
    'else if (key == "camera_access_block") camera_access=val' in gen_text
    and 'camera_access_block=%s' in gen_text
    and 'media_store_query_block=%s' in gen_text
    and all(name in native_ui_text for name in (
        "camera_access_block", "location_access_block",
        "mic_access_block", "media_store_query_block"
    ))
    and all(marker in native_ui_text for marker in (
        'toggle("限制摄像头访问", "camera_access_block"',
        'toggle("限制位置访问", "location_access_block"',
        'toggle("阻止录音启动（会影响录音功能）", "mic_access_block"',
        'toggle("清理媒体查询元数据", "media_store_query_block"'
    ))
    and "camera_access_block=1" in reg_text
    and "media_store_query_block=1" in reg_text
    and "unsupported developer-hook fields leaked into the runtime schema" in reg_text
    and "sed -n '/private void installAudioRecordSilenceHooks/,/private boolean isMicrophoneSilenceAuthorized/p'" in mic_text
)
if already_complete:
    print("FX API-101 privacy controls are already fully wired; skipping obsolete exact-text migrations.")
    raise SystemExit(0)

# Root-side Remote Files publisher: do not discard fields already supported by
# the API-101 parser/runtime/serializer.
once(generator,
'''notification_permission_hide=0; clipboard_isolate=0; mic_silence=0
          rules=""''',
'''notification_permission_hide=0; clipboard_isolate=0; mic_silence=0
          camera_access=0; location_access=0; mic_access=0; media_store_query=0
          rules=""''', allow_missing=True)
once(generator,
'''else if (key == "mic_silence") mic_silence=val
            else { valid=0; break }''',
'''else if (key == "mic_silence") mic_silence=val
            else if (key == "camera_access_block") camera_access=val
            else if (key == "location_access_block") location_access=val
            else if (key == "mic_access_block") mic_access=val
            else if (key == "media_store_query_block") media_store_query=val
            else { valid=0; break }''', allow_missing=True)
once(generator,
'''(!(splash+feed+overlay+member+privacy+exif+clipboard+clipboard_isolate+sensor_accel+sensor_gyro+sensor_light+sensor_magnet+sensor_pressure+sensor_prox+sensor_rate_limit+wifi_scan+notification_listen+notification_permission_hide+mic_silence) && rules == "")) next
          printf "%s,ads_splash=%s,ads_feed=%s,ads_overlay=%s,member_diag=%s,privacy=%s,exif_strip=%s,clipboard_read_block=%s,clipboard_isolate=%s,sensor_accel=%s,sensor_gyro=%s,sensor_light=%s,sensor_magnet=%s,sensor_pressure=%s,sensor_prox=%s,sensor_rate_limit=%s,wifi_scan_block=%s,notification_listen_block=%s,notification_permission_hide=%s,mic_silence=%s", pkg,splash,feed,overlay,member,privacy,exif,clipboard,clipboard_isolate,sensor_accel,sensor_gyro,sensor_light,sensor_magnet,sensor_pressure,sensor_prox,sensor_rate_limit,wifi_scan,notification_listen,notification_permission_hide,mic_silence''',
'''(!(splash+feed+overlay+member+privacy+exif+clipboard+clipboard_isolate+sensor_accel+sensor_gyro+sensor_light+sensor_magnet+sensor_pressure+sensor_prox+sensor_rate_limit+wifi_scan+notification_listen+notification_permission_hide+mic_silence+camera_access+location_access+mic_access+media_store_query) && rules == "")) next
          printf "%s,ads_splash=%s,ads_feed=%s,ads_overlay=%s,member_diag=%s,privacy=%s,exif_strip=%s,clipboard_read_block=%s,clipboard_isolate=%s,sensor_accel=%s,sensor_gyro=%s,sensor_light=%s,sensor_magnet=%s,sensor_pressure=%s,sensor_prox=%s,sensor_rate_limit=%s,wifi_scan_block=%s,notification_listen_block=%s,notification_permission_hide=%s,mic_silence=%s,camera_access_block=%s,location_access_block=%s,mic_access_block=%s,media_store_query_block=%s", pkg,splash,feed,overlay,member,privacy,exif,clipboard,clipboard_isolate,sensor_accel,sensor_gyro,sensor_light,sensor_magnet,sensor_pressure,sensor_prox,sensor_rate_limit,wifi_scan,notification_listen,notification_permission_hide,mic_silence,camera_access,location_access,mic_access,media_store_query''', allow_missing=True)

# App-scoped controls are rendered and persisted by the native Hook APK UI.
# Do not inject them into the unrelated module WebUI.

# Exercise the full UI -> settings -> Remote Files -> API-101 parser chain.
once(regression,
'''com.clipiso.app,splash=0,feed=0,overlay=0,member_diag=0,privacy=0,clipboard_isolate=1|Clipboard isolation|1
bad package''',
'''com.clipiso.app,splash=0,feed=0,overlay=0,member_diag=0,privacy=0,clipboard_isolate=1|Clipboard isolation|1
com.sensitive.app,splash=0,feed=0,overlay=0,member_diag=0,privacy=0,camera_access_block=1,location_access_block=1,mic_access_block=1,media_store_query_block=1|Explicit privacy denials|1
bad package''')
once(regression,
'''  grep -q '^com.clipiso.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=0,clipboard_read_block=0,clipboard_isolate=1,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0$' "$OUT" || fail "clipboard isolation target missing or not translated for user $uid"''',
'''  grep -q '^com.clipiso.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=0,clipboard_read_block=0,clipboard_isolate=1,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "clipboard isolation target missing or not translated for user $uid"
  grep -q '^com.sensitive.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=0,clipboard_read_block=0,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=1,location_access_block=1,mic_access_block=1,media_store_query_block=1$' "$OUT" || fail "camera/location/microphone/MediaStore controls missing from Remote Files"''')
# Existing exact expectations need explicit defaults for the new fields.
src = regression.read_text(encoding="utf-8")
src = src.replace(",mic_silence=0$", ",mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$")
regression.write_text(src, encoding="utf-8")
parser_old = '''    if (!result.adsEnabled || result.targets.size() != 8 || !result.isMemberDiagnosticsEnabledFor("com.example.app") || !result.targets.get("com.privacy.app").privacy) {'''
parser_new = '''    UnifiedHookConfigParser.Target sensitive = result.targets.get("com.sensitive.app");
    if (!result.adsEnabled || result.targets.size() != 9 || !result.isMemberDiagnosticsEnabledFor("com.example.app")
        || !result.targets.get("com.privacy.app").privacy || sensitive == null
        || !sensitive.cameraAccessBlock || !sensitive.locationAccessBlock
        || !sensitive.microphoneAccessBlock || !sensitive.mediaStoreQueryBlock) {'''
regression_text = regression.read_text(encoding="utf-8")
if parser_old in regression_text:
    regression.write_text(regression_text.replace(parser_old, parser_new, 1), encoding="utf-8")
else:
    print("Legacy parser assertion has already evolved in the release source; skipped obsolete exact rewrite.")

# Keep AudioRecord post-read silence distinct from the separate explicit
# microphone-access denial feature, which legitimately hooks startRecording.
once(mic_regression,
'''if grep -q 'startRecording' "$HOOK"; then echo 'unexpected startRecording interception' >&2; exit 1; fi''',
'''if sed -n '/private void installAudioRecordSilenceHooks/,/private boolean isMicrophoneSilenceAuthorized/p' "$HOOK" | grep -q 'startRecording'; then echo 'unexpected startRecording interception in silence hook' >&2; exit 1; fi''')

# Fail with a precise postcondition if an evolved source did not already provide
# the API-101 controls; missing legacy anchors alone are not evidence of success.
gen_final = generator.read_text(encoding="utf-8")
native_ui_final = native_ui.read_text(encoding="utf-8")
reg_final = regression.read_text(encoding="utf-8")
required_generator = (
    "camera_access_block", "location_access_block",
    "mic_access_block", "media_store_query_block"
)
required_ui = required_generator
missing = [name for name in required_generator if name not in gen_final]
missing += [name for name in required_ui if name not in native_ui_final]
for label, feature in (
    ("限制摄像头访问", "camera_access_block"),
    ("限制位置访问", "location_access_block"),
    ("阻止录音启动（会影响录音功能）", "mic_access_block"),
    ("清理媒体查询元数据", "media_store_query_block"),
):
    if 'toggle("' + label + '", "' + feature + '"' not in native_ui_final:
        missing.append(feature + " native UI toggle")
    if '"' + feature + '"' not in native_ui_final:
        missing.append(feature + " native config serializer")
if missing:
    raise SystemExit("API-101 privacy migration incomplete; missing fields: " + ", ".join(sorted(set(missing))))
if "com.sensitive.app" not in reg_final or "media_store_query_block=1" not in reg_final:
    raise SystemExit("API-101 privacy migration lacks end-to-end Remote Files regression coverage")

print("FX API-101 privacy controls wired through UI and Remote Files publisher")
