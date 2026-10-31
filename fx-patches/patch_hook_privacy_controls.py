#!/usr/bin/env python3
"""Wire existing API-101 camera/location/mic/MediaStore privacy controls end-to-end."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
generator = root / "scripts/gen_xposed_conf.sh"
regression = root / "scripts/tests/v1.0.0-lsposed-remote-file-config-regression.sh"
ui = root / "webroot/index.html"
for path in (generator, regression, ui):
    if not path.is_file():
        raise SystemExit("missing required FX source: " + str(path))

def once(path, old, new):
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one source anchor, got {count}: {old[:90]!r}")
    path.write_text(source.replace(old, new), encoding="utf-8")

# Root-side Remote Files publisher: do not discard fields already supported by
# the API-101 parser/runtime/serializer.
once(generator,
'''notification_permission_hide=0; clipboard_isolate=0; mic_silence=0
          rules=""''',
'''notification_permission_hide=0; clipboard_isolate=0; mic_silence=0
          camera_access=0; location_access=0; mic_access=0; media_store_query=0
          rules=""''')
once(generator,
'''else if (key == "mic_silence") mic_silence=val
            else { valid=0; break }''',
'''else if (key == "mic_silence") mic_silence=val
            else if (key == "camera_access_block") camera_access=val
            else if (key == "location_access_block") location_access=val
            else if (key == "mic_access_block") mic_access=val
            else if (key == "media_store_query_block") media_store_query=val
            else { valid=0; break }''')
once(generator,
'''(!(splash+feed+overlay+member+privacy+exif+clipboard+clipboard_isolate+sensor_accel+sensor_gyro+sensor_light+sensor_magnet+sensor_pressure+sensor_prox+sensor_rate_limit+wifi_scan+notification_listen+notification_permission_hide+mic_silence) && rules == "")) next
          printf "%s,ads_splash=%s,ads_feed=%s,ads_overlay=%s,member_diag=%s,privacy=%s,exif_strip=%s,clipboard_read_block=%s,clipboard_isolate=%s,sensor_accel=%s,sensor_gyro=%s,sensor_light=%s,sensor_magnet=%s,sensor_pressure=%s,sensor_prox=%s,sensor_rate_limit=%s,wifi_scan_block=%s,notification_listen_block=%s,notification_permission_hide=%s,mic_silence=%s", pkg,splash,feed,overlay,member,privacy,exif,clipboard,clipboard_isolate,sensor_accel,sensor_gyro,sensor_light,sensor_magnet,sensor_pressure,sensor_prox,sensor_rate_limit,wifi_scan,notification_listen,notification_permission_hide,mic_silence''',
'''(!(splash+feed+overlay+member+privacy+exif+clipboard+clipboard_isolate+sensor_accel+sensor_gyro+sensor_light+sensor_magnet+sensor_pressure+sensor_prox+sensor_rate_limit+wifi_scan+notification_listen+notification_permission_hide+mic_silence+camera_access+location_access+mic_access+media_store_query) && rules == "")) next
          printf "%s,ads_splash=%s,ads_feed=%s,ads_overlay=%s,member_diag=%s,privacy=%s,exif_strip=%s,clipboard_read_block=%s,clipboard_isolate=%s,sensor_accel=%s,sensor_gyro=%s,sensor_light=%s,sensor_magnet=%s,sensor_pressure=%s,sensor_prox=%s,sensor_rate_limit=%s,wifi_scan_block=%s,notification_listen_block=%s,notification_permission_hide=%s,mic_silence=%s,camera_access_block=%s,location_access_block=%s,mic_access_block=%s,media_store_query_block=%s", pkg,splash,feed,overlay,member,privacy,exif,clipboard,clipboard_isolate,sensor_accel,sensor_gyro,sensor_light,sensor_magnet,sensor_pressure,sensor_prox,sensor_rate_limit,wifi_scan,notification_listen,notification_permission_hide,mic_silence,camera_access,location_access,mic_access,media_store_query''')

# FX UI model/import/editor/validation/save path.
once(ui,
'''notification_permission_hide_block:false,mic_silence:false,rules:''',
'''notification_permission_hide_block:false,mic_silence:false,camera_access_block:false,location_access_block:false,mic_access_block:false,media_store_query_block:false,rules:''')
once(ui,
'''notification_permission_hide_block','mic_silence'].indexOf(k)>=0''',
'''notification_permission_hide_block','mic_silence','camera_access_block','location_access_block','mic_access_block','media_store_query_block'].indexOf(k)>=0''')
once(ui,
'''['mic_silence','AudioRecord 录音静音（仅已覆盖的 API；不等同系统麦克风权限关闭）']];''',
'''['mic_silence','AudioRecord 录音静音（仅已覆盖的 API；不等同系统麦克风权限关闭）'],['camera_access_block','阻止摄像头访问（Camera/Camera2）'],['location_access_block','阻止位置读取与更新（LocationManager）'],['mic_access_block','阻止麦克风录音启动（AudioRecord/MediaRecorder）'],['media_store_query_block','阻止读取 MediaStore 媒体列表']];''')
once(ui,
'''&&!item.notification_permission_hide_block&&!item.mic_silence){item.splash=true''',
'''&&!item.notification_permission_hide_block&&!item.mic_silence&&!item.camera_access_block&&!item.location_access_block&&!item.mic_access_block&&!item.media_store_query_block){item.splash=true''')
once(ui,
'''notification_permission_hide_block:false,mic_silence:false,selected:false''',
'''notification_permission_hide_block:false,mic_silence:false,camera_access_block:false,location_access_block:false,mic_access_block:false,media_store_query_block:false,selected:false''')
once(ui,
'''notification_permission_hide_block','mic_silence'].every(function(k''',
'''notification_permission_hide_block','mic_silence','camera_access_block','location_access_block','mic_access_block','media_store_query_block'].every(function(k''')
once(ui,
'''&&!t.notification_permission_hide_block&&!t.mic_silence)throw new Error''',
'''&&!t.notification_permission_hide_block&&!t.mic_silence&&!t.camera_access_block&&!t.location_access_block&&!t.mic_access_block&&!t.media_store_query_block)throw new Error''')
once(ui,
'''',mic_silence='+(t.mic_silence?1:0)+(String(t.rules||'').trim()?''',
'''',mic_silence='+(t.mic_silence?1:0)+',camera_access_block='+(t.camera_access_block?1:0)+',location_access_block='+(t.location_access_block?1:0)+',mic_access_block='+(t.mic_access_block?1:0)+',media_store_query_block='+(t.media_store_query_block?1:0)+(String(t.rules||'').trim()?''')

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
let src = regression.read_text(encoding="utf-8")
src = src.replace(",mic_silence=0$", ",mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$")
regression.write_text(src, encoding="utf-8")
print("FX API-101 privacy controls wired through UI and Remote Files publisher")
