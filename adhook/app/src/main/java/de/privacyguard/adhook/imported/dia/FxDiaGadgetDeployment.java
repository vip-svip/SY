package de.privacyguard.adhook.imported.dia;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.nio.file.Files;
import java.nio.charset.StandardCharsets;

/**
 * Root-assisted, package-scoped deployment of an official Frida Gadget into a
 * debuggable user application's nativeLibraryDir. The APK itself is never
 * rewritten or re-signed. A marker is committed last so the LSPosed target hook
 * will not load a partially installed library/config pair.
 */
public final class FxDiaGadgetDeployment {
    public static final String GADGET_NAME = "libalertclose.so";
    public static final String CONFIG_NAME = "libalertclose.config.so";
    public static final String MARKER_NAME = "libalertclose.fx-target";
    public static final String MARKER_SCHEMA = "FX-DIA-FRIDA-GADGET-1";

    private FxDiaGadgetDeployment() {}

    public static String targetNativeLibraryDir(Context context, String packageName) throws Exception {
        if (!validPackage(packageName)) throw new IllegalArgumentException("目标包名无效。");
        ApplicationInfo info = context.getPackageManager().getApplicationInfo(packageName, 0);
        if ((info.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0
                || (info.flags & ApplicationInfo.FLAG_SYSTEM) != 0) {
            throw new IllegalArgumentException("仅允许部署到用户安装的 debuggable 应用。");
        }
        if (info.nativeLibraryDir == null || info.nativeLibraryDir.trim().isEmpty()) {
            throw new IllegalArgumentException("目标应用没有可用的 nativeLibraryDir。");
        }
        File raw = new File(info.nativeLibraryDir);
        if (Files.isSymbolicLink(raw.toPath())) {
            throw new IllegalArgumentException("目标应用 nativeLibraryDir 是符号链接，拒绝部署。");
        }
        File canonical = raw.getCanonicalFile();
        String path = canonical.getPath();
        if (!path.startsWith("/data/app/") || !canonical.isDirectory()) {
            throw new IllegalArgumentException("目标 nativeLibraryDir 不在受支持的 /data/app 路径中。");
        }
        return path;
    }

    public static String validateSources(Context context, String packageName,
                                         String libraryPath, String configPath,
                                         int expectedPort) {
        try {
            targetNativeLibraryDir(context, packageName);
            File library = safeRegularFile(libraryPath, 150L * 1024L * 1024L);
            File config = safeRegularFile(configPath, 16L * 1024L);
            if (library == null || config == null) {
                return "Gadget 动态库或配置文件不存在、不可读、是符号链接或大小超限。";
            }
            if (!matchesElfAbi(library, targetNativeLibraryDir(context, packageName))) {
                return "Gadget ELF ABI 与目标应用的 nativeLibraryDir 架构不匹配。";
            }
            byte[] configBytes = new byte[(int) config.length()];
            try (FileInputStream input = new FileInputStream(config)) {
                int offset = 0;
                while (offset < configBytes.length) {
                    int count = input.read(configBytes, offset, configBytes.length - offset);
                    if (count < 0) return "Gadget 配置文件读取不完整。";
                    offset += count;
                }
            }
            JSONObject root = new JSONObject(new String(configBytes, StandardCharsets.UTF_8));
            JSONObject interaction = root.optJSONObject("interaction");
            if (interaction == null || !"listen".equals(interaction.optString("type"))
                    || !"127.0.0.1".equals(interaction.optString("address"))
                    || interaction.optInt("port", -1) != expectedPort
                    || expectedPort == 27042
                    || !("wait".equals(interaction.optString("on_load"))
                         || "resume".equals(interaction.optString("on_load")))) {
                return "Gadget 配置必须匹配当前端口，并使用 127.0.0.1 Listen 和 WAIT/RESUME。";
            }
            return null;
        } catch (PackageManager.NameNotFoundException missing) {
            return "目标应用已卸载。";
        } catch (Exception error) {
            return "Gadget 部署预检失败：" + error.getClass().getSimpleName();
        }
    }

    private static File safeRegularFile(String path, long maximumBytes) throws Exception {
        if (path == null || !path.startsWith("/") || path.contains("..")
                || !path.matches("/[A-Za-z0-9_./-]+")) return null;
        File raw = new File(path);
        if (Files.isSymbolicLink(raw.toPath())) return null;
        File file = raw.getCanonicalFile();
        if (!file.isFile() || !file.canRead() || file.length() <= 0
                || file.length() > maximumBytes) return null;
        return file;
    }

    private static boolean matchesElfAbi(File library, String nativeDir) throws Exception {
        byte[] header = new byte[20];
        try (FileInputStream input = new FileInputStream(library)) {
            int offset = 0;
            while (offset < header.length) {
                int count = input.read(header, offset, header.length - offset);
                if (count < 0) return false;
                offset += count;
            }
        }
        if (header[0] != 0x7f || header[1] != 'E' || header[2] != 'L' || header[3] != 'F'
                || header[5] != 1) return false; // ELF, little-endian only.
        int elfClass = header[4] & 0xff;
        int machine = (header[18] & 0xff) | ((header[19] & 0xff) << 8);
        String lower = nativeDir.toLowerCase(java.util.Locale.ROOT);
        if (lower.endsWith("/arm64") || lower.endsWith("/arm64-v8a")) return elfClass == 2 && machine == 183;
        if (lower.endsWith("/arm") || lower.endsWith("/armeabi-v7a")) return elfClass == 1 && machine == 40;
        if (lower.endsWith("/x86_64")) return elfClass == 2 && machine == 62;
        if (lower.endsWith("/x86")) return elfClass == 1 && machine == 3;
        return false;
    }

    private static boolean validPackage(String pkg) {
        return pkg != null && pkg.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+");
    }

    private static String q(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }

    public static String buildDeployCommand(String library, String config,
                                            String nativeDir, String packageName,
                                            int port) {
        StringBuilder c = new StringBuilder();
        c.append("set -eu\numask 077\n");
        c.append("src=").append(q(library)).append("\n");
        c.append("cfg=").append(q(config)).append("\n");
        c.append("dest=").append(q(nativeDir)).append("\n");
        c.append("pkg=").append(q(packageName)).append("\n");
        c.append("port=").append(port).append("\n");
        c.append("gadget=").append(q(GADGET_NAME)).append("\nconf=").append(q(CONFIG_NAME))
                .append("\nmarker=").append(q(MARKER_NAME)).append("\n");
        c.append("[ -f \"$src\" ] && [ ! -L \"$src\" ] && [ -s \"$src\" ]\n");
        c.append("[ -f \"$cfg\" ] && [ ! -L \"$cfg\" ] && [ -s \"$cfg\" ]\n");
        c.append("[ -d \"$dest\" ] && [ ! -L \"$dest\" ]\n");
        c.append("case \"$dest\" in /data/app/*) ;; *) echo FX_GADGET_BAD_NATIVE_DIR; exit 31;; esac\n");
        c.append("lock=\"$dest/.fx-dia-gadget.deploy.lock\"; [ ! -L \"$lock\" ] || exit 32\n");
        c.append("mkdir \"$lock\" 2>/dev/null || { echo FX_GADGET_DEPLOY_BUSY; exit 33; }\n");
        c.append("stage=; backup=; committed=0; old_g=0; old_c=0; old_m=0; new_g=0; new_c=0; new_m=0\n");
        c.append("cleanup(){ rc=$?; if [ \"$committed\" != 1 ]; then\n");
        c.append("  [ \"$new_m\" != 1 ] || rm -f \"$dest/$marker\"; [ \"$new_c\" != 1 ] || rm -f \"$dest/$conf\"; [ \"$new_g\" != 1 ] || rm -f \"$dest/$gadget\";\n");
        c.append("  [ \"$old_g\" != 1 ] || mv \"$backup/$gadget\" \"$dest/$gadget\" 2>/dev/null || :;\n");
        c.append("  [ \"$old_c\" != 1 ] || mv \"$backup/$conf\" \"$dest/$conf\" 2>/dev/null || :;\n");
        c.append("  [ \"$old_m\" != 1 ] || mv \"$backup/$marker\" \"$dest/$marker\" 2>/dev/null || :;\nfi\n");
        c.append("  [ -z \"$stage\" ] || rm -rf \"$stage\"; rmdir \"$lock\" 2>/dev/null || :; return \"$rc\"; }\n");
        c.append("trap cleanup 0; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM\n");
        c.append("owner=$(stat -c '%u:%g' \"$dest\"); case \"$owner\" in *[!0-9:]*|:*|0:*|*:0) echo FX_GADGET_BAD_OWNER; exit 34;; esac\n");
        c.append("stage=$(mktemp -d \"$dest/.fx-dia-gadget-deploy.XXXXXX\"); [ -d \"$stage\" ] && [ ! -L \"$stage\" ]; backup=\"$stage/backup\"; mkdir \"$backup\"\n");
        c.append("if [ -e \"$dest/$gadget\" ] || [ -e \"$dest/$conf\" ] || [ -e \"$dest/$marker\" ] || [ -L \"$dest/$gadget\" ] || [ -L \"$dest/$conf\" ] || [ -L \"$dest/$marker\" ]; then\n");
        c.append("  [ -f \"$dest/$marker\" ] && [ ! -L \"$dest/$marker\" ] && [ -f \"$dest/$gadget\" ] && [ ! -L \"$dest/$gadget\" ] && [ -f \"$dest/$conf\" ] && [ ! -L \"$dest/$conf\" ] || { echo FX_GADGET_EXISTING_FILE_CONFLICT; exit 35; }\n");
        c.append("  grep -Fxq 'schema=").append(MARKER_SCHEMA).append("' \"$dest/$marker\" && grep -Fxq \"package=$pkg\" \"$dest/$marker\" || { echo FX_GADGET_EXISTING_MARKER_CONFLICT; exit 36; }\n");
        c.append("  old_l=$(sed -n 's/^library_sha256=//p' \"$dest/$marker\" | head -1); old_c=$(sed -n 's/^config_sha256=//p' \"$dest/$marker\" | head -1)\n");
        c.append("  [ -n \"$old_l\" ] && [ -n \"$old_c\" ] && [ \"$(sha256sum \"$dest/$gadget\" | awk '{print $1}')\" = \"$old_l\" ] && [ \"$(sha256sum \"$dest/$conf\" | awk '{print $1}')\" = \"$old_c\" ] || { echo FX_GADGET_EXISTING_HASH_CONFLICT; exit 37; }\n");
        c.append("  mv \"$dest/$gadget\" \"$backup/$gadget\"; old_g=1; mv \"$dest/$conf\" \"$backup/$conf\"; old_c=1; mv \"$dest/$marker\" \"$backup/$marker\"; old_m=1\nfi\n");
        c.append("cp \"$src\" \"$stage/$gadget\"; cp \"$cfg\" \"$stage/$conf\"\n");
        c.append("libhash=$(sha256sum \"$stage/$gadget\" | awk '{print $1}'); confhash=$(sha256sum \"$stage/$conf\" | awk '{print $1}')\n");
        c.append("printf 'schema=%s\\npackage=%s\\nprocesses=*\\nlibrary_sha256=%s\\nconfig_sha256=%s\\nport=%s\\n' ")
                .append(q(MARKER_SCHEMA)).append(" \"$pkg\" \"$libhash\" \"$confhash\" \"$port\" > \"$stage/$marker\"\n");
        c.append("chown \"$owner\" \"$stage/$gadget\" \"$stage/$conf\" \"$stage/$marker\"; chmod 0755 \"$stage/$gadget\"; chmod 0644 \"$stage/$conf\" \"$stage/$marker\"\n");
        c.append("if command -v restorecon >/dev/null 2>&1; then restorecon \"$stage/$gadget\" \"$stage/$conf\" \"$stage/$marker\" 2>/dev/null || :; fi\n");
        c.append("mv \"$stage/$gadget\" \"$dest/$gadget\"; new_g=1\n");
        c.append("mv \"$stage/$conf\" \"$dest/$conf\"; new_c=1\n");
        c.append("mv \"$stage/$marker\" \"$dest/$marker\"; new_m=1\n");
        public static String buildRemoveCommand(String nativeDir, String packageName) {
        StringBuilder c = new StringBuilder();
        c.append("set -eu\n");
        c.append("dest=").append(q(nativeDir)).append("\npkg=").append(q(packageName)).append("\n");
        c.append("gadget=").append(q(GADGET_NAME)).append("\nconf=").append(q(CONFIG_NAME))
                .append("\nmarker=").append(q(MARKER_NAME)).append("\n");
        c.append("[ -d \"$dest\" ] && [ ! -L \"$dest\" ]\n");
        c.append("lock=\"$dest/.fx-dia-gadget.deploy.lock\"; [ ! -L \"$lock\" ] || exit 32; mkdir \"$lock\" 2>/dev/null || { echo FX_GADGET_DEPLOY_BUSY; exit 33; }\n");
        c.append("stage=; cleanup(){ rc=$?; if [ -n \"$stage\" ] && [ -d \"$stage\" ]; then\n");
        c.append("  [ ! -e \"$stage/$marker\" ] || mv \"$stage/$marker\" \"$dest/$marker\" 2>/dev/null || :;\n");
        c.append("  [ ! -e \"$stage/$conf\" ] || mv \"$stage/$conf\" \"$dest/$conf\" 2>/dev/null || :;\n");
        c.append("  [ ! -e \"$stage/$gadget\" ] || mv \"$stage/$gadget\" \"$dest/$gadget\" 2>/dev/null || :;\n");
        c.append("  rm -rf \"$stage\"; fi; rmdir \"$lock\" 2>/dev/null || :; return \"$rc\"; }\n");
        c.append("trap cleanup 0; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM\n");
        c.append("stage=$(mktemp -d \"$dest/.fx-dia-gadget-remove.XXXXXX\"); [ -d \"$stage\" ] && [ ! -L \"$stage\" ]\n");
        c.append("[ -f \"$dest/$marker\" ] && [ ! -L \"$dest/$marker\" ] || { echo FX_GADGET_NOT_DEPLOYED; exit 0; }\n");
        c.append("grep -Fxq 'schema=").append(MARKER_SCHEMA).append("' \"$dest/$marker\" && grep -Fxq \"package=$pkg\" \"$dest/$marker\" || { echo FX_GADGET_MARKER_CONFLICT; exit 38; }\n");
        c.append("[ -f \"$dest/$gadget\" ] && [ ! -L \"$dest/$gadget\" ] && [ -f \"$dest/$conf\" ] && [ ! -L \"$dest/$conf\" ] || { echo FX_GADGET_FILE_CONFLICT; exit 39; }\n");
        c.append("old_l=$(sed -n 's/^library_sha256=//p' \"$dest/$marker\" | head -1); old_c=$(sed -n 's/^config_sha256=//p' \"$dest/$marker\" | head -1)\n");
        c.append("[ -n \"$old_l\" ] && [ -n \"$old_c\" ] && [ \"$(sha256sum \"$dest/$gadget\" | awk '{print $1}')\" = \"$old_l\" ] && [ \"$(sha256sum \"$dest/$conf\" | awk '{print $1}')\" = \"$old_c\" ] || { echo FX_GADGET_HASH_CONFLICT; exit 40; }\n");
        c.append("mv \"$dest/$marker\" \"$stage/$marker\"; mv \"$dest/$conf\" \"$stage/$conf\"; mv \"$dest/$gadget\" \"$stage/$gadget\"; rm -rf \"$stage\"; stage=; trap - 0 HUP INT TERM; rmdir \"$lock\"; echo FX_GADGET_REMOVED\n");
        return c.toString();
    }"$stage\"; stage=; trap - 0 HUP INT TERM; rmdir \"$lock\"; echo FX_GADGET_REMOVED\n");
        return c.toString();
    }
}
