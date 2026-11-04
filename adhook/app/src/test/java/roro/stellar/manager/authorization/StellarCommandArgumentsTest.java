package roro.stellar.manager.authorization;

import org.junit.Test;
import static org.junit.Assert.*;

public class StellarCommandArgumentsTest {
    @Test
    public void acceptsKnownOperationsAndQuotesEveryArgumentIndependently() {
        assertTrue(StellarCommandArguments.buildScriptCommand("list").endsWith(" 'list'"));
        assertTrue(StellarCommandArguments.buildScriptCommand(
                "pkg-set 'com.example.app' 1").endsWith(" 'pkg-set' 'com.example.app' '1'"));
        assertTrue(StellarCommandArguments.buildScriptCommand(
                "scope-set 'com.example.app' SHELL_ID_COMMAND 1")
                .endsWith(" 'scope-set' 'com.example.app' 'SHELL_ID_COMMAND' '1'"));
        assertTrue(StellarCommandArguments.buildScriptCommand(
                "run 'com.example.app' SHELL_ID_COMMAND 'id -u'")
                .endsWith(" 'run' 'com.example.app' 'SHELL_ID_COMMAND' 'id -u'"));
    }

    @Test
    public void acceptsKnownPermissionAppOpsAndSecureSettingShapes() {
        assertTrue(StellarCommandArguments.buildScriptCommand(
                "permission 'com.example.app' grant 'android.permission.CAMERA'").contains("'permission'"));
        assertTrue(StellarCommandArguments.buildScriptCommand(
                "appops 'com.example.app' 'CAMERA' 'allow'").contains("'appops'"));
        assertTrue(StellarCommandArguments.buildScriptCommand(
                "secure-setting 'com.example.app' 'screensaver_enabled' '1'").contains("'secure-setting'"));
        assertTrue(StellarCommandArguments.buildScriptCommand(
                "always-set 'com.example.app' 'id -u' 1").contains("'always-set'"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsCommandSeparatorInjection() {
        StellarCommandArguments.buildScriptCommand("list; id");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsInjectionAfterValidPackageMutation() {
        StellarCommandArguments.buildScriptCommand("pkg-set 'com.example.app' 1; id");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsCommandSubstitutionInsideQuotedCommand() {
        StellarCommandArguments.buildScriptCommand("run 'com.example.app' SHELL_ID_COMMAND '$(id)'");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsEmbeddedShellOperatorInsideQuotedCommand() {
        StellarCommandArguments.buildScriptCommand("run 'com.example.app' SHELL_ID_COMMAND 'id -u; id'");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsUnquotedExtraCommandAfterQuotedToken() {
        StellarCommandArguments.buildScriptCommand("run 'com.example.app' SHELL_ID_COMMAND 'id -u' && id");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsUnsupportedCommandName() {
        StellarCommandArguments.buildScriptCommand("sh -c 'id'");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsPrivilegedScopeForReadOnlyRun() {
        StellarCommandArguments.buildScriptCommand(
                "run 'com.example.app' RUNTIME_PERMISSION_MANAGE 'id -u'");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsEnablingTerminalCommandScope() {
        StellarCommandArguments.buildScriptCommand(
                "scope-set 'com.example.app' TERMINAL_COMMAND 1");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsWrongArity() {
        StellarCommandArguments.buildScriptCommand("list extra");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsControlCharacters() {
        StellarCommandArguments.buildScriptCommand("list\nid");
    }
}
