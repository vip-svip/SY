#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
store="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxWallpaperStore.kt"
shell="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
activity="$root/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
test -s "$store" && test -s "$shell" && test -s "$activity"
python3 - "$store" "$shell" "$activity" <<'PY'
from pathlib import Path
import sys
store = Path(sys.argv[1]).read_text(encoding="utf-8")
shell = Path(sys.argv[2]).read_text(encoding="utf-8")
activity = Path(sys.argv[3]).read_text(encoding="utf-8")

# Match the confirmed YouLong 10.0.2 storage contract and bounded image format.
assert 'private const val PREFS = "native_wallpaper_prefs"' in store
assert 'private const val KEY_PATH = "wallpaper_path"' in store
assert 'private const val MAX_EDGE = 1920' in store
assert 'private const val JPEG_QUALITY = 85' in store
assert 'Bitmap.CompressFormat.JPEG, JPEG_QUALITY' in store
assert 'context.filesDir' in store and 'renameTo(target)' in store
assert 'fun clear(context: Context)' in store

# Wallpaper is loaded off the main thread and rendered below the shared native UI.
assert 'FxWallpaperStore.currentPath(view.context)' in shell
assert 'FxWallpaperStore.loadForDisplay(context)' in shell
assert 'withContext(Dispatchers.IO)' in shell
assert 'Image(' in shell and 'ContentScale.Crop' in shell

# Settings exposes upload/restore, and Android's document picker is the only source.
assert 'section("壁纸与背景")' in activity
assert '"壁纸随心换"' in activity
assert '"上传本地图片"' in activity
assert '"恢复默认壁纸"' in activity
assert 'Intent.ACTION_OPEN_DOCUMENT' in activity
assert 'REQUEST_NATIVE_WALLPAPER_PICKER' in activity
assert 'FxWallpaperStore.saveFromUri(this, uri)' in activity
assert 'FxWallpaperStore.clear(this)' in activity
assert 'if (FxWallpaperStore.currentPath(this) != null) return 0x00000000;' in activity
print("PASS: 10.0.2-compatible wallpaper storage, Settings picker/reset, and shared native wallpaper renderer.")
PY
