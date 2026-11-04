package de.privacyguard.hook;

import android.content.pm.ApplicationInfo;
import android.util.Log;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/** Modern-libXposed-safe, per-package/process Frida Gadget loader. */
public final class DiaFridaGadgetLoader {
    private static final String TAG = "FX-Dia-Frida";
    private static final String GADGET_NAME = "libalertclose.so";
    private static final String CONFIG_NAME = "libalertclose.config.so";
    private static final String MARKER_NAME = "libalertclose.fx-target";
    private static final String MARKER_SCHEMA = "FX-DIA-FRIDA-GADGET-1";
    private static final Set<String> HOOKED_PROCESSES =
            java.util.Collections.synchronizedSet(new HashSet<String>());

    private DiaFridaGadgetLoader() {}

    public static void loadForPackage(ApplicationInfo info, String expectedPackage,
                                      String expectedProcess) {
        if (info == null || expectedPackage == null || expectedPackage.isEmpty()
                || expectedProcess == null || expectedProcess.isEmpty()
                || !expectedPackage.equals(info.packageName)) return;
        String processKey = expectedPackage + "|" + expectedProcess;
        if (HOOKED_PROCESSES.contains(processKey)) return;
        try {
            if ((info.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0
                    || (info.flags & ApplicationInfo.FLAG_SYSTEM) != 0) return;
            String nativeLibraryPath = info.nativeLibraryDir;
            if (nativeLibraryPath == null || nativeLibraryPath.trim().isEmpty()
                    || !nativeLibraryPath.startsWith("/data/app/")
                    || nativeLibraryPath.contains("..")) {
                log(Log.WARN, "skip " + expectedPackage + ": nativeLibraryDir is outside /data/app");
                return;
            }
            File rawNativeDir = new File(nativeLibraryPath);
            if (!rawNativeDir.isAbsolute() || hasSymlinkComponent(rawNativeDir)) {
                log(Log.WARN, "skip " + expectedPackage + ": nativeLibraryDir contains a symlink");
                return;
            }
            File nativeDir = rawNativeDir.getCanonicalFile();
            String canonicalNativePath = nativeDir.getPath();
            if (!nativeDir.isDirectory() || !canonicalNativePath.startsWith("/data/app/")
                    || canonicalNativePath.contains("/../")) {
                log(Log.WARN, "skip " + expectedPackage + ": canonical nativeLibraryDir is unsafe");
                return;
            }
            File marker = child(nativeDir, MARKER_NAME);
            if (marker == null || !marker.isFile() || !marker.canRead()) return;
            Map<String, String> record = readMarker(marker);
            String markerProcesses = record.get("processes");
            String markerPort = record.get("port");
            if (!MARKER_SCHEMA.equals(record.get("schema"))
                    || !expectedPackage.equals(record.get("package"))
                    || markerProcesses == null || markerProcesses.length() > 2048
                    || markerPort == null || !markerPort.matches("[0-9]{4,5}")
                    || !matchesProcess(markerProcesses, expectedProcess)) {
                log(Log.WARN, "skip " + expectedPackage + ": target marker does not match this process");
                return;
            }
            File gadget = child(nativeDir, GADGET_NAME);
            File config = child(nativeDir, CONFIG_NAME);
            if (gadget == null || config == null || !gadget.isFile() || !gadget.canRead()
                    || !config.isFile() || !config.canRead()) {
                log(Log.WARN, "skip " + expectedPackage + ": Gadget library/config missing or unsafe");
                return;
            }
            String libraryHash = sha256(gadget);
            String configHash = sha256(config);
            if (!constantEquals(record.get("library_sha256"), libraryHash)
                    || !constantEquals(record.get("config_sha256"), configHash)) {
                log(Log.WARN, "skip " + expectedPackage + ": Gadget library/config hash mismatch");
                return;
            }
            int configPort = validateConfig(config);
            if (!Integer.toString(configPort).equals(markerPort)) {
                log(Log.WARN, "skip " + expectedPackage + ": marker/config port mismatch");
                return;
            }
            if (!HOOKED_PROCESSES.add(processKey)) return;
            try {
                System.load(gadget.getAbsolutePath());
                log(Log.INFO, "Gadget loaded for " + expectedPackage + " process="
                        + expectedProcess + " port=" + markerPort);
            } catch (Throwable loadError) {
                HOOKED_PROCESSES.remove(processKey);
                log(Log.ERROR, "Gadget load failed for " + expectedPackage + ": " + loadError);
            }
        } catch (Throwable error) {
            log(Log.ERROR, "target loader failed for " + expectedPackage + ": " + error);
        }
    }

    private static boolean hasSymlinkComponent(File path) {
        File current = path.getAbsoluteFile();
        while (current != null) {
            if (Files.isSymbolicLink(current.toPath())) return true;
            current = current.getParentFile();
        }
        return false;
    }

    private static File child(File parent, String name) throws Exception {
        if (parent == null || name == null || name.contains("/") || name.contains("\\")) return null;
        File candidate = new File(parent, name);
        if (Files.isSymbolicLink(candidate.toPath())) return null;
        File canonical = candidate.getCanonicalFile();
        return parent.getCanonicalFile().equals(canonical.getParentFile()) ? canonical : null;
    }

    private static Map<String, String> readMarker(File marker) throws Exception {
        if (marker.length() <= 0 || marker.length() > 4096)
            throw new IllegalStateException("target marker size is invalid");
        Map<String, String> values = new HashMap<>();
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(new FileInputStream(marker), StandardCharsets.UTF_8))) {
            String line;
            int lines = 0;
            while ((line = reader.readLine()) != null) {
                if (++lines > 32) throw new IllegalStateException("too many target marker lines");
                if (line.isEmpty()) continue;
                int equals = line.indexOf('=');
                if (equals <= 0 || equals == line.length() - 1)
                    throw new IllegalStateException("malformed target marker line");
                String key = line.substring(0, equals);
                String value = line.substring(equals + 1);
                if (values.put(key, value) != null)
                    throw new IllegalStateException("duplicate target marker key");
            }
        }
        return values;
    }

    private static boolean matchesProcess(String allowed, String process) {
        return allowed != null && !allowed.isEmpty() && process != null && allowed.equals(process);
    }

    private static String sha256(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[16384];
            int count;
            long total = 0;
            while ((count = input.read(buffer)) != -1) {
                total += count;
                if (total > 150L * 1024L * 1024L)
                    throw new IllegalStateException("Gadget file exceeds 150 MiB");
                digest.update(buffer, 0, count);
            }
        }
        StringBuilder out = new StringBuilder(64);
        for (byte value : digest.digest()) out.append(String.format("%02x", value & 0xff));
        return out.toString();
    }

    private static int validateConfig(File file) throws Exception {
        if (file.length() <= 0 || file.length() > 16 * 1024)
            throw new IllegalStateException("Gadget config size is invalid");
        byte[] bytes = new byte[(int) file.length()];
        try (FileInputStream input = new FileInputStream(file)) {
            int offset = 0;
            while (offset < bytes.length) {
                int count = input.read(bytes, offset, bytes.length - offset);
                if (count < 0) throw new IllegalStateException("short Gadget config read");
                offset += count;
            }
        }
        JSONObject root = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
        JSONObject interaction = root.optJSONObject("interaction");
        if (interaction == null || !"listen".equals(interaction.optString("type"))
                || !"127.0.0.1".equals(interaction.optString("address")))
            throw new IllegalStateException("Gadget config must use a loopback Listen interaction");
        int port = interaction.optInt("port", -1);
        String onLoad = interaction.optString("on_load");
        if (port < 1024 || port > 65535 || port == 27042
                || !("wait".equals(onLoad) || "resume".equals(onLoad)))
            throw new IllegalStateException("Gadget config port/on_load is invalid");
        return port;
    }

    private static boolean constantEquals(String expected, String actual) {
        if (expected == null || actual == null || expected.length() != actual.length()) return false;
        int diff = 0;
        for (int i = 0; i < expected.length(); i++) diff |= expected.charAt(i) ^ actual.charAt(i);
        return diff == 0;
    }

    private static void log(int priority, String message) {
        Log.println(priority, TAG, message);
    }
}
