package com.babyte.breakpad;

import com.babyte.breakpad.callback.NativeCrashCallback;

/** Java descriptor adapter for Dia 23.11's original libbreakpad.so JNI export. */
public final class BaByteBreakpad {
    public static final BaByteBreakpad INSTANCE = new BaByteBreakpad();
    private static final boolean LIBRARY_LOADED;

    static {
        boolean loaded;
        try {
            System.loadLibrary("breakpad");
            loaded = true;
        } catch (UnsatisfiedLinkError | SecurityException unavailable) {
            loaded = false;
        }
        LIBRARY_LOADED = loaded;
    }

    private BaByteBreakpad() { }

    public static boolean isLibraryLoaded() {
        return LIBRARY_LOADED;
    }

    public void initBreakpad(String minidumpDirectory, NativeCrashCallback callback) {
        if (!LIBRARY_LOADED) throw new UnsatisfiedLinkError("Dia libbreakpad.so is unavailable for this ABI");
        if (minidumpDirectory == null || callback == null) {
            throw new IllegalArgumentException("minidump directory and callback are required");
        }
        initBreakpadNative(minidumpDirectory, callback);
    }

    private static final native void initBreakpadNative(String minidumpDirectory,
                                                         NativeCrashCallback callback);
}
