package com.babyte.breakpad;

import com.babyte.breakpad.callback.NativeCrashCallback;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

/** Host-JVM check for the exact original JNI class/method/callback descriptor. */
public final class DiaBreakpadJniContractHostTest {
    public static void main(String[] args) throws Exception {
        Method nativeMethod = BaByteBreakpad.class.getDeclaredMethod(
                "initBreakpadNative", String.class, NativeCrashCallback.class);
        if (!Modifier.isStatic(nativeMethod.getModifiers())
                || !Modifier.isNative(nativeMethod.getModifiers())) {
            throw new AssertionError("initBreakpadNative must remain a static native method");
        }
        Method callback = NativeCrashCallback.class.getMethod(
                "onCrash", String.class, String.class, String.class, String.class);
        if (callback.getReturnType() != void.class) {
            throw new AssertionError("Breakpad callback must return void");
        }
        if (!BaByteBreakpad.class.getName().equals("com.babyte.breakpad.BaByteBreakpad")) {
            throw new AssertionError("JNI class path changed");
        }
        System.out.println("PASS: original Dia Breakpad JNI descriptor");
    }
}
