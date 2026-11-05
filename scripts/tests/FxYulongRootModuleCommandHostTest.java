package de.privacyguard.adhook.imported.ad;

/** Standalone JDK contract test for the allowlisted Yulong Root module command builder. */
public final class FxYulongRootModuleCommandHostTest {
    private static int assertions;

    private static void check(boolean expected, boolean actual, String label) {
        assertions++;
        if (expected != actual) {
            throw new AssertionError(label + ": expected=" + expected + " actual=" + actual);
        }
    }

    private static void reject(String script) {
        try {
            FxYulongRootModuleCommand.prefix(script);
        } catch (IllegalArgumentException expected) {
            assertions++;
            return;
        }
        throw new AssertionError("unapproved Root script was accepted: " + script);
    }

    public static void main(String[] args) {
        String[] scripts = {
                "yulong-ad-control.sh",
                "yulong-profiles.sh",
                "yulong-app-whitelist.sh",
                "yulong-vpn-control.sh"
        };
        for (String script : scripts) {
            String prefix = FxYulongRootModuleCommand.prefix(script);
            check(true, prefix.contains("[ -d '/data' ]") && prefix.contains("[ ! -L '/data' ]"),
                    script + " /data root guard");
            check(true, prefix.contains("[ -d '/data/adb' ]") && prefix.contains("[ ! -L '/data/adb' ]"),
                    script + " /data/adb guard");
            check(true, prefix.contains("[ -d '/data/adb/modules' ]")
                    && prefix.contains("[ ! -L '/data/adb/modules' ]"),
                    script + " modules root guard");
            check(true, prefix.contains("grep -qx 'id=privacyguard'")
                    && prefix.contains("grep -qx 'version=1.0.0'"),
                    script + " exact module identity");
            check(true, prefix.contains("[ -f \"$d/module.prop\" ]")
                    && prefix.contains("[ ! -L \"$d/module.prop\" ]"),
                    script + " module.prop file guard");
            check(true, prefix.contains("[ -d \"$d/scripts\" ]")
                    && prefix.contains("[ ! -L \"$d/scripts\" ]"),
                    script + " scripts directory guard");
            check(true, prefix.contains("[ -f \"$d/scripts/util.sh\" ]")
                    && prefix.contains("[ ! -L \"$d/scripts/util.sh\" ]"),
                    script + " util helper guard");
            check(true, prefix.contains("[ -f \"$d/scripts/" + script + "\" ]")
                    && prefix.contains("[ ! -L \"$d/scripts/" + script + "\" ]"),
                    script + " requested script file guard");
            String command = FxYulongRootModuleCommand.command(script, "list");
            check(true, command.endsWith("sh \"$MP/scripts/" + script + "\" list"),
                    script + " command suffix");
        }
        reject(null);
        reject("");
        reject("../yulong-ad-control.sh");
        reject("yulong-ad-control.sh;id");
        reject("/data/local/tmp/attacker.sh");
        System.out.println("PASS: FX Yulong Root command builder validates module roots, exact version, script payload types and allowlists script names (" + assertions + " assertions)");
    }
}
