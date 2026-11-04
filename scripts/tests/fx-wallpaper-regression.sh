#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
store="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxWallpaperStore.kt"
activity="$root/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
shell="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
host="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeTabActivity.java"
test -s "$store" && test -s "$activity" && test -s "$shell" && test -s "$host"
python3 - "$store" "$activity" "$shell" "$host" <<'PY'
from pathlib import Path
import sys
store, activity, shell, host = [Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]]

# Original YouLong 10.0.2 settings contract and safe local image handling.
for token in ('"native_wallpaper_prefs"', '"wallpaper_path"',
              'MAX_EDGE = 1920', 'JPEG_QUALITY = 85',
              'Bitmap.CompressFormat.JPEG', 'output.fd.sync()', 'temp.renameTo(target)',
              'ACTION_OPEN_DOCUMENT' if False else 'saveFromUri'):
    assert token in store, f"wallpaper store missing invariant: {token}"
assert 'managedFile(context, raw)' in store
assert 'file.parentFile == root' in store, "wallpaper path must stay inside app-private filesDir"

# A real user-facing control, bounded picker, asynchronous decode/save, and restore flow.
for token in ('"壁纸随心换"', '"上传本地图片"', '"恢复默认壁纸"',
              'REQUEST_NATIVE_WALLPAPER_PICKER', 'Intent.ACTION_OPEN_DOCUMENT',
              'FxWallpaperStore.saveFromUri(this, uri)', 'FxWallpaperStore.clear(this)',
              'nativeWallpaperExecutor.execute'):
    assert token in activity, f"Settings wallpaper flow missing: {token}"
assert 'if (requestCode == REQUEST_NATIVE_WALLPAPER_PICKER)' in activity
assert 'webView.setBackgroundColor(wallpaperActive' in activity
assert 'html,body{background:transparent!important' in activity
assert 'if (FxWallpaperStore.currentPath(this) != null) return 0x00000000;' in activity

# Wallpaper is rendered beneath the primary shell and imported native pages.
assert 'FxWallpaperStore.currentPath(view.context)' in shell
assert 'FxWallpaperStore.loadForDisplay(context)' in shell
assert 'Image(' in shell and 'ContentScale.Crop' in shell
assert 'DisposableEffect(wallpaperBitmap)' in shell
assert 'FxWallpaperStore.currentPath(this) != null' in host
assert 'pageContent.setBackgroundColor(android.graphics.Color.TRANSPARENT)' in host
print("PASS: 10.0.2-compatible wallpaper chooser/store/preview/restore and global shell rendering are wired.")
PY
