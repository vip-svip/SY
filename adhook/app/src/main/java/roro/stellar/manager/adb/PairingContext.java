package roro.stellar.manager.adb;

import java.util.Arrays;

/**
 * JNI boundary for the original Stellar ADB SPAKE2 pairing context.
 *
 * Keep this fully-qualified class name and native method descriptors aligned
 * with libadb.so's JNI_OnLoad registration table. The protocol/client layer is
 * intentionally separate; constructing this class alone does not pair ADB.
 */
public final class PairingContext implements AutoCloseable {
    private static final boolean NATIVE_AVAILABLE;

    static {
        boolean loaded;
        try {
            System.loadLibrary("adb");
            loaded = true;
        } catch (LinkageError | SecurityException unavailable) {
            loaded = false;
        }
        NATIVE_AVAILABLE = loaded;
    }

    private long nativePtr;
    private final byte[] msg;

    private PairingContext(long pointer) {
        this(pointer, true);
    }

    /** Cleanup-only holder; it must not ask a partially-created context for nativeMsg. */
    private PairingContext(long pointer, boolean readInitialMessage) {
        if (pointer == 0L) {
            throw new IllegalArgumentException("libadb returned an empty pairing context");
        }
        nativePtr = pointer;
        if (!readInitialMessage) {
            msg = new byte[0];
            return;
        }
        byte[] initialMessage = nativeMsg(pointer);
        if (initialMessage == null || initialMessage.length == 0) {
            nativePtr = 0L;
            throw new IllegalStateException("libadb did not produce the initial SPAKE2 message");
        }
        msg = initialMessage.clone();
        Arrays.fill(initialMessage, (byte) 0);
    }

    /**
     * Create the original client-side SPAKE2 context from the pairing code.
     * Returns null when the native ABI is unavailable or initialization fails.
     */
    public static PairingContext create(byte[] pairingCode) {
        if (!NATIVE_AVAILABLE || pairingCode == null || pairingCode.length == 0
                || pairingCode.length > 128) {
            return null;
        }
        byte[] secret = pairingCode.clone();
        long pointer = 0L;
        try {
            pointer = nativeConstructor(true, secret);
            if (pointer == 0L) return null;
            return new PairingContext(pointer);
        } catch (RuntimeException | LinkageError failure) {
            if (pointer != 0L) {
                try {
                    new PairingContext(pointer, false).destroy();
                } catch (RuntimeException | LinkageError ignored) {
                    // Native cleanup is best-effort after a failed initialization.
                }
            }
            return null;
        } finally {
            Arrays.fill(secret, (byte) 0);
        }
    }

    public static boolean isNativeAvailable() {
        return NATIVE_AVAILABLE;
    }

    private static native long nativeConstructor(boolean isClient, byte[] password);
    private native byte[] nativeDecrypt(long pointer, byte[] payload);
    private native void nativeDestroy(long pointer);
    private native byte[] nativeEncrypt(long pointer, byte[] payload);
    private native boolean nativeInitCipher(long pointer, byte[] peerMessage);
    private native byte[] nativeMsg(long pointer);

    public synchronized byte[] getMsg() {
        return msg.clone();
    }

    public synchronized boolean initCipher(byte[] peerMessage) {
        if (nativePtr == 0L || peerMessage == null || peerMessage.length == 0
                || peerMessage.length > 64 * 1024) {
            return false;
        }
        return nativeInitCipher(nativePtr, peerMessage);
    }

    public synchronized byte[] encrypt(byte[] payload) {
        if (nativePtr == 0L || payload == null || payload.length > 1024 * 1024) return null;
        return nativeEncrypt(nativePtr, payload);
    }

    public synchronized byte[] decrypt(byte[] payload) {
        if (nativePtr == 0L || payload == null || payload.length > 1024 * 1024) return null;
        return nativeDecrypt(nativePtr, payload);
    }

    /** Idempotent cleanup; native pointers must never be destroyed twice. */
    public synchronized void destroy() {
        long pointer = nativePtr;
        if (pointer == 0L) return;
        nativePtr = 0L;
        Arrays.fill(msg, (byte) 0);
        nativeDestroy(pointer);
    }

    @Override
    public void close() {
        destroy();
    }
}
