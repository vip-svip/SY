package roro.stellar.manager.adb;

/** Storage contract used by the original Stellar ADB private-key vault. */
public interface AdbKeyStore {
    byte[] get();
    void put(byte[] encryptedKey);
}
