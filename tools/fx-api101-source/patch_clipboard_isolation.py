#!/usr/bin/env python3
from pathlib import Path
import hashlib

path = Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source = path.read_text()
base = "fb46869ec48b21592927d39b0ae06143bb53b6c3578f7a15b1eda06d60cfd45f"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != base:
    raise SystemExit(f"unexpected API101 source before clipboard isolation patch: {actual}")

def once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit("clipboard isolation patch anchor mismatch: " + old[:120])
    source = source.replace(old, new, 1)

once("import android.content.ContentResolver;\n",
     "import android.content.ContentResolver;\nimport android.content.ClipData;\n")
once("    private volatile boolean clipboardReadHooksInstalled;\n",
     "    private volatile boolean clipboardReadHooksInstalled;\n"
     "    private volatile boolean clipboardIsolationHooksInstalled;\n"
     "    private final Map<String, ClipData> isolatedClipboard = new ConcurrentHashMap<>();\n")

once(
    "        final boolean clipboardBlockForPackage = privacyEnabled && target.clipboardReadBlock;\n"
    "        final boolean sensorForPackage = privacyEnabled && (target.sensorAccel || target.sensorGyro\n",
    "        final boolean clipboardBlockForPackage = privacyEnabled && target.clipboardReadBlock;\n"
    "        final boolean clipboardIsolateForPackage = privacyEnabled && target.clipboardIsolate && !target.clipboardReadBlock;\n"
    "        final boolean sensorForPackage = privacyEnabled && (target.sensorAccel || target.sensorGyro\n")
once(
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage && !sensorForPackage) return;\n",
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !clipboardIsolateForPackage && !sensorForPackage) return;\n")
once(
    "        if (clipboardBlockForPackage) installClipboardReadBlockHooks(pkg);\n",
    "        if (clipboardBlockForPackage) installClipboardReadBlockHooks(pkg);\n"
    "        if (clipboardIsolateForPackage) installClipboardIsolationHooks(pkg);\n")
once(
    " + \" clipboardReadBlock=\" + clipboardBlockForPackage + \" sensors=\" + sensorForPackage +",
    " + \" clipboardReadBlock=\" + clipboardBlockForPackage + \" clipboardIsolate=\" + clipboardIsolateForPackage + \" sensors=\" + sensorForPackage +")

method = """    /**
     * Keep clipboard writes and reads inside this selected app process. This is
     * intentionally process-local and memory-only; it never writes to the system
     * clipboard. Multi-process apps and clipboard change listeners are not covered.
     */
    private boolean shouldIsolateClipboard() {
        String pkg = currentPackage;
        UnifiedHookConfigParser.Target target = targets.get(pkg);
        return ClipboardIsolationPolicy.shouldIsolate(
                privacyEnabled, processPackages.size(), pkg, target);
    }

    private synchronized boolean installClipboardIsolationHooks(final String pkg) {
        if (clipboardIsolationHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.content.ClipboardManager", false, null);
            for (String name : new String[]{"getPrimaryClip", "getPrimaryClipDescription",
                    "hasPrimaryClip", "getText", "setPrimaryClip", "setText", "clearPrimaryClip"}) {
                try {
                    final Method method;
                    if ("setPrimaryClip".equals(name))
                        method = type.getDeclaredMethod(name, ClipData.class);
                    else if ("setText".equals(name))
                        method = type.getDeclaredMethod(name, CharSequence.class);
                    else
                        method = type.getDeclaredMethod(name);
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                if (!shouldIsolateClipboard()) return chain.proceed();
                                String activePackage = currentPackage;
                                ClipData clip = isolatedClipboard.get(activePackage);
                                switch (name) {
                                    case "getPrimaryClip":
                                        return clip;
                                    case "getPrimaryClipDescription":
                                        return clip == null ? null : clip.getDescription();
                                    case "hasPrimaryClip":
                                        return clip != null;
                                    case "getText":
                                        return clip == null || clip.getItemCount() == 0
                                                ? null : clip.getItemAt(0).getText();
                                    case "setPrimaryClip":
                                        Object value = chain.getArgs().get(0);
                                        if (value instanceof ClipData)
                                            isolatedClipboard.put(activePackage, (ClipData) value);
                                        else
                                            isolatedClipboard.remove(activePackage);
                                        return null;
                                    case "setText":
                                        Object text = chain.getArgs().get(0);
                                        if (text instanceof CharSequence)
                                            isolatedClipboard.put(activePackage,
                                                    ClipData.newPlainText("", (CharSequence) text));
                                        else
                                            isolatedClipboard.remove(activePackage);
                                        return null;
                                    case "clearPrimaryClip":
                                        isolatedClipboard.remove(activePackage);
                                        return null;
                                    default:
                                        return chain.proceed();
                                }
                            });
                    installed++;
                } catch (NoSuchMethodException missing) {
                    logFx(Log.DEBUG, "clipboard isolation API unavailable: " + name);
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "clipboard isolation hook unavailable: " + name);
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "clipboard isolation unavailable; failing open");
            return false;
        }
        clipboardIsolationHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in process-local clipboard isolation hooks installed=" + installed + " for " + pkg);
        return clipboardIsolationHooksInstalled;
    }

"""
once("    /**\n     * Opt-in clipboard read protection. Writes remain untouched; reads are hidden only\n",
     method + "    /**\n     * Opt-in clipboard read protection. Writes remain untouched; reads are hidden only\n")

path.write_text(source)
actual = hashlib.sha256(path.read_bytes()).hexdigest()
print("API101 clipboard isolation patch: PASS", actual)
