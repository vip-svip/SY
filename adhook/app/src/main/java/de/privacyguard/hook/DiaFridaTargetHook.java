package de.privacyguard.hook;

import android.app.Application;
import android.content.Context;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/** Legacy LSPosed adapter; the modern libXposed entry calls DiaFridaGadgetLoader directly. */
public final class DiaFridaTargetHook implements IXposedHookLoadPackage {
    private static final String SELF_PACKAGE = "de.privacyguard.adhook";

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpp) {
        if (lpp == null || lpp.packageName == null || lpp.packageName.isEmpty()
                || SELF_PACKAGE.equals(lpp.packageName)) return;
        final String expectedPackage = lpp.packageName;
        final String expectedProcess = lpp.processName == null ? expectedPackage : lpp.processName;
        try {
            XposedHelpers.findAndHookMethod(Application.class, "attach", Context.class,
                    new XC_MethodHook() {
                        @Override protected void beforeHookedMethod(MethodHookParam param) {
                            if (param.args == null || param.args.length == 0
                                    || !(param.args[0] instanceof Context)) return;
                            Context context = (Context) param.args[0];
                            DiaFridaGadgetLoader.loadForPackage(
                                    context.getApplicationInfo(), expectedPackage, expectedProcess);
                        }
                    });
        } catch (Throwable hookError) {
            android.util.Log.e("FX-Dia-Frida", "legacy attach hook failed for " + expectedPackage, hookError);
        }
    }
}
