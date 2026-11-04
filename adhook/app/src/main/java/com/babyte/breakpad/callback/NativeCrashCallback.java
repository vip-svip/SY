package com.babyte.breakpad.callback;

/** Exact four-String callback descriptor used by Dia 23.11's original JNI library. */
public interface NativeCrashCallback {
    void onCrash(String minidumpPath, String nativeInfo,
                 String nativeThreadTrack, String crashThreadName);
}
