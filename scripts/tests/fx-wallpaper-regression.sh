#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
store="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxWallpaperStore.kt"
shell="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
activity="$root/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
test -s "$store" && test -s "$shell" && test -s "$activity"
python3 - "$store" "$shell" "$activity" "$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeSkin.java" "$root/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeTabActivity.java" <<'PY'
from pathlib import Path
import sys
store = Path(sys.argv[1]).read_text(encoding="utf-8")
shell = Path(sys.argv[2]).read_text(encoding="utf-8")
activity = Path(sys.argv[3]).read_text(encoding="utf-8")
skin = Path(sys.argv[4]).read_text(encoding="utf-8")
host = Path(sys.argv[5]).read_text(encoding="utf-8")

# Match the confirmed YouLong 10.0.2 storage contract and bounded image format.
assert 'private const val PREFS = "native_wallpaper_prefs"' in store
assert 'private const val KEY_PATH = "wallpaper_path"' in store
assert 'private const val MAX_EDGE = 1920' in store
assert 'private const val JPEG_QUALITY = 85' in store
assert 'Bitmap.CompressFormat.JPEG, JPEG_QUALITY' in store
assert 'context.filesDir' in store and 'renameTo(target)' in store
assert 'fun clear(context: Context)' in store
# Bound the decode memory before the final 1920px scale-down.
assert 'sampleSizeFor(sourceWidth, sourceHeight, MAX_EDGE)' in store
assert 'MAX_SOURCE_PIXELS' in store

# Wallpaper is loaded off the main thread and rendered below the shared native UI.
assert 'FxWallpaperStore.currentPath(view.context)' in shell
assert 'FxWallpaperStore.loadForDisplay(context)' in shell
assert 'withContext(Dispatchers.IO)' in shell
assert 'Image(' in shell and 'ContentScale.Crop' in shell
assert 'DisposableEffect(wallpaperBitmap)' in shell and 'bitmap.recycle()' in shell
assert shell.index('wallpaperImage?.let') < shell.index('AndroidView(')

# Both old WebUI and migrated native Activities must expose the same wallpaper.
assert 'webView.setBackgroundColor(wallpaperActive' in activity
assert 'html,body{background:transparent!important;background-color:transparent!important}' in activity
assert 'FxNativeSkin.watch(this, pageContent);' in host
# MainActivity also builds native pages dynamically after base() and must apply the same palette.
mount_start = activity.index("private void mountNativeShell(View pageContent)")
mount_end = activity.index("private void handleNativeTabSelection(", mount_start)
assert "FxNativeSkin.watch(this, pageContent);" in activity[mount_start:mount_end]
assert "addOnGlobalLayoutListener" in skin
assert "pageContent.post(() -> {" in activity[mount_start:mount_end]
assert "pageContent.getParent() != null" in activity[mount_start:mount_end]
assert 'wallpaperActive ? 0x00000000 : palette.background' in skin
for background in ('case 0xfff7f8fa:', 'case 0xfff4f6f8:', 'case 0xfff0f3f7:'):
    assert background in skin
for page in (
    'imported/ad/FxYulongAdActivity.java',
    'imported/ad/FxYulongAdGeneralActivity.java',
    'imported/ad/FxYulongAdSummaryActivity.java',
    'imported/shield/FxYulongShieldActivity.java',
    'imported/dia/FxDiaGlobalSettingsActivity.java',
):
    source = Path('adhook/app/src/main/java/de/privacyguard/adhook') / page
    page_text = source.read_text(encoding='utf-8')
    assert 'extends de.privacyguard.adhook.FxNativeTabActivity' in page_text
    assert 'setContentViewWithNativeTabs(' in page_text

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
print("PASS: 10.0.2-compatible wallpaper storage, bounded import decode, Classic WebUI transparency, and shared native wallpaper renderer across migrated Ad/Shield/Dia Activities.")
PY
