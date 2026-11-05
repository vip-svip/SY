package de.privacyguard.adhook.imported.ad;

/**
 * Builds a fixed, fail-closed Root command prefix for FX-owned Yulong scripts.
 * Script names are allowlisted before any command text is constructed.
 */
public final class FxYulongRootModuleCommand {
    private FxYulongRootModuleCommand() { }

    private static boolean isAllowedScript(String name) {
        return "yulong-ad-control.sh".equals(name)
                || "yulong-profiles.sh".equals(name)
                || "yulong-app-whitelist.sh".equals(name);
    }

    public static String prefix(String requiredScript) {
        if (!isAllowedScript(requiredScript)) {
            throw new IllegalArgumentException("Unsupported FX Root module script.");
        }
        return "[ -d '/data' ] && [ ! -L '/data' ] "
                + "&& [ -d '/data/adb' ] && [ ! -L '/data/adb' ] "
                + "&& [ -d '/data/adb/modules' ] && [ ! -L '/data/adb/modules' ] "
                + "&& [ ! -L '/data/adb/modules_update' ] "
                + "&& { [ ! -e '/data/adb/modules_update' ] || [ -d '/data/adb/modules_update' ]; } || exit 71; "
                + "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -d \"$d\" ] && [ ! -L \"$d\" ] "
                + "&& [ -f \"$d/module.prop\" ] && [ ! -L \"$d/module.prop\" ] "
                + "&& grep -qx 'id=privacyguard' \"$d/module.prop\" "
                + "&& grep -qx 'version=1.0.0' \"$d/module.prop\" "
                + "&& [ -d \"$d/scripts\" ] && [ ! -L \"$d/scripts\" ] "
                + "&& [ -f \"$d/scripts/util.sh\" ] && [ ! -L \"$d/scripts/util.sh\" ] "
                + "&& [ -f \"$d/scripts/" + requiredScript + "\" ] "
                + "&& [ ! -L \"$d/scripts/" + requiredScript + "\" ]; then "
                + "MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; ";
    }

    public static String command(String requiredScript, String arguments) {
        return prefix(requiredScript) + "sh \"$MP/scripts/" + requiredScript + "\" "
                + (arguments == null ? "" : arguments);
    }
}
